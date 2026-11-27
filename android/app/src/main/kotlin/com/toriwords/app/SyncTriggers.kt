package com.toriwords.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.toriwords.sync.SyncController
import com.toriwords.sync.SyncPhase
import com.toriwords.sync.SyncTrigger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

/** Triggers are no-ops while sync is off, unavailable or Drive data was deleted. */
val SyncPhase.triggersActive: Boolean
    get() = this != SyncPhase.Off && this != SyncPhase.NotAvailable && this != SyncPhase.DriveDeleted

/** Automatic sync triggers: app foreground, local changes, periodic background work, network back after a failure. */
class SyncTriggers(context: Context, private val controller: SyncController, private val scope: CoroutineScope) {
    private val work = WorkManager.getInstance(context)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    /** Call once from `Application.onCreate` (main thread). */
    fun start() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) syncIfActive(SyncTrigger.Foreground, foreground = true)
        })
        connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (controller.status.value.phase == SyncPhase.WaitingForNetwork) syncIfActive(SyncTrigger.Network, foreground = false)
            }
        })
        scope.launch {
            controller.status.map { it.phase }.distinctUntilChanged().collect(::schedule)
        }
    }

    /** ~5 s after the last local change. */
    fun onLocalChange() {
        if (!controller.status.value.phase.triggersActive) return
        work.enqueueUniqueWork(DEBOUNCED, ExistingWorkPolicy.REPLACE, oneTime(SyncTrigger.Debounced, delaySeconds = 5))
    }

    private fun syncIfActive(trigger: SyncTrigger, foreground: Boolean) {
        scope.launch { if (controller.status.value.phase.triggersActive) controller.sync(trigger, foreground) }
    }

    private fun schedule(phase: SyncPhase) {
        if (phase.triggersActive) {
            val periodic = PeriodicWorkRequestBuilder<SyncWorker>(4, TimeUnit.HOURS, 1, TimeUnit.HOURS)
                .setConstraints(CONNECTED)
                .setInputData(workDataOf(SyncWorker.TRIGGER to SyncTrigger.Periodic.name))
                .build()
            work.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, periodic)
        } else {
            work.cancelUniqueWork(PERIODIC)
        }
        // Fallback for when the process dies before the network callback fires.
        if (phase == SyncPhase.WaitingForNetwork) work.enqueueUniqueWork(RETRY, ExistingWorkPolicy.KEEP, oneTime(SyncTrigger.Network))
    }

    private fun oneTime(trigger: SyncTrigger, delaySeconds: Long = 0) = OneTimeWorkRequestBuilder<SyncWorker>()
        .setConstraints(CONNECTED)
        .setInitialDelay(delaySeconds, TimeUnit.SECONDS)
        .setInputData(workDataOf(SyncWorker.TRIGGER to trigger.name))
        .build()

    private companion object {
        const val DEBOUNCED = "sync-debounced"
        const val PERIODIC = "sync-periodic"
        const val RETRY = "sync-retry"
        val CONNECTED = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
    }
}

/** One background sync cycle. Still waiting for network afterwards → WorkManager's exponential backoff. */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as ToriApp
        app.ready.await()
        val controller = app.syncController
        if (!controller.status.value.phase.triggersActive) return Result.success()
        val trigger = inputData.getString(TRIGGER)?.let(SyncTrigger::valueOf) ?: SyncTrigger.Periodic
        controller.sync(trigger, foreground = false)
        return if (controller.status.value.phase == SyncPhase.WaitingForNetwork) Result.retry() else Result.success()
    }

    companion object {
        const val TRIGGER = "trigger"
    }
}
