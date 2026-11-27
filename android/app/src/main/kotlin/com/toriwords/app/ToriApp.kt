package com.toriwords.app

import android.app.Application
import android.os.Build
import android.util.Log
import com.toriwords.store.ToriStore
import com.toriwords.store.launch
import com.toriwords.sync.DriveApi
import com.toriwords.sync.DriveAuthorizer
import com.toriwords.sync.DriveTokenGate
import com.toriwords.sync.OkHttpDriveApi
import com.toriwords.sync.SyncController
import com.toriwords.sync.SyncEngine
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.File

/** Manual DI: one instance of each long-lived component per process. */
class ToriApp : Application() {
    /** Work that must outlive a screen (turn on, delete, sync cycles). */
    val appScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, e -> Log.w("Toriwords", "sync action failed", e) },
    )

    val store: ToriStore by lazy { ToriStore.open(this) }
    val authorizer: DriveAuthorizer by lazy { DriveAuthorizer(this) }
    val driveApi: DriveApi by lazy { OkHttpDriveApi(OkHttpClient(), authorizer) }
    val tokenGate: DriveTokenGate by lazy { DriveTokenGate(authorizer, driveApi, store) }
    val syncEngine: SyncEngine by lazy {
        SyncEngine(store, tokenGate, appScope, api = driveApi, appVersion = appVersion())
    }
    val syncController: SyncController get() = syncEngine
    val syncTriggers: SyncTriggers by lazy { SyncTriggers(this, syncController, appScope) }

    /** Completes once the store is launched and the engine status reflects storage; workers await it. */
    val ready = CompletableDeferred<Unit>()

    override fun onCreate() {
        super.onCreate()
        store.onLocalChange = { syncTriggers.onLocalChange() }
        appScope.launch {
            store.launch(File(noBackupFilesDir, "device-marker"), Build.MODEL ?: "Android")
            syncEngine.start()
            ready.complete(Unit)
            // Triggers observe the engine status, so they start once it reflects storage.
            withContext(Dispatchers.Main) { syncTriggers.start() }
        }
    }

    private fun appVersion(): String =
        runCatching { packageManager.getPackageInfo(packageName, 0).versionName }.getOrNull() ?: "0"
}
