package com.toriwords.app

import android.app.Application
import android.util.Log
import com.toriwords.store.ToriStore
import com.toriwords.sync.DriveApi
import com.toriwords.sync.DriveAuthorizer
import com.toriwords.sync.DriveTokenGate
import com.toriwords.sync.OkHttpDriveApi
import com.toriwords.sync.SyncController
import com.toriwords.sync.SyncPhase
import com.toriwords.sync.SyncStatus
import com.toriwords.sync.SyncTrigger
import com.toriwords.sync.TokenGate
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import okhttp3.OkHttpClient

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
    val syncController: SyncController by lazy { createSyncController(store, tokenGate, authorizer.isAvailable()) }
    val syncTriggers: SyncTriggers by lazy { SyncTriggers(this, syncController, appScope) }

    override fun onCreate() {
        super.onCreate()
        syncTriggers.start()
    }
}

// TODO(step5): return SyncEngine(store, tokenGate, …) from step 3; the placeholder below only moves between phases.
@Suppress("UNUSED_PARAMETER")
fun createSyncController(store: ToriStore, tokenGate: TokenGate, driveAvailable: Boolean): SyncController =
    PlaceholderSyncController(driveAvailable)

// TODO(step5): delete with the factory above.
private class PlaceholderSyncController(driveAvailable: Boolean) : SyncController {
    private val state = MutableStateFlow(
        SyncStatus(if (driveAvailable) SyncPhase.Off else SyncPhase.NotAvailable, null, null, null, 0),
    )
    override val status: StateFlow<SyncStatus> = state.asStateFlow()

    override suspend fun sync(trigger: SyncTrigger, foreground: Boolean) =
        state.update { it.copy(phase = SyncPhase.Idle, lastSyncAt = System.currentTimeMillis()) }

    override suspend fun turnOn(api: DriveApi) {
        val user = runCatching { api.about() }.getOrNull()
        state.update { it.copy(accountLabel = user?.let { u -> u.emailAddress ?: u.displayName }) }
        sync(SyncTrigger.TurnOn, foreground = true)
    }

    override suspend fun turnOff() = state.update { SyncStatus(SyncPhase.Off, null, null, null, 0) }
    override suspend fun deleteDriveData(): Boolean = true.also { state.update { it.copy(phase = SyncPhase.DriveDeleted) } }
    override suspend fun backUpAgain() = sync(SyncTrigger.BackUpAgain, foreground = true)
}
