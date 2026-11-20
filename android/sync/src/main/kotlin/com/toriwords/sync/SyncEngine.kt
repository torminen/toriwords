package com.toriwords.sync

import com.toriwords.store.SyncStateKey
import com.toriwords.store.ToriStore
import com.toriwords.store.activateDrive
import com.toriwords.store.backUpAgain
import com.toriwords.store.markDriveDeleted
import com.toriwords.store.pendingRecordCount
import com.toriwords.store.recoverClockAhead
import com.toriwords.store.setSyncState
import com.toriwords.store.syncState
import com.toriwords.store.thisDeviceId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import java.security.MessageDigest
import kotlin.random.Random

/** Network backoff: 5 s, 10 s, 20 s … 15 min, ±20 % jitter (same as iOS `Backoff`). */
object Backoff {
    fun delayMs(attempt: Int, jitter: Double): Long {
        val base = minOf(5_000.0 * Math.pow(2.0, minOf(attempt, 20).toDouble()), 900_000.0)
        return (base * (0.8 + 0.4 * jitter.coerceIn(0.0, 1.0))).toLong()
    }
}

/**
 * One sync at a time against the Drive `appDataFolder` (port of iOS `SyncEngine`, doc 38 §11.2): identity rule,
 * `generation.json`, fetch, push, purge, compaction. Drive never merges; this client merges every record.
 * Triggers arriving while a cycle runs coalesce into one re-run.
 */
class SyncEngine(
    private val store: ToriStore,
    private val tokenGate: TokenGate,
    /** Retries after network errors and rate limits run here. */
    private val scope: CoroutineScope,
    private var api: DriveApi? = null,
    private val appVersion: String,
    private val now: () -> Long = System::currentTimeMillis,
    private val sleep: suspend (Long) -> Unit = { delay(it) },
    private val jitter: () -> Double = { Random.nextDouble() },
    private val newGeneration: () -> String = { java.util.UUID.randomUUID().toString() },
    /** Envelopes per applied chunk (one Room transaction each). */
    private val applyChunk: Int = 400,
    /** After each completed cycle: vocab index, widget, reminders. */
    private val onCycleFinished: suspend () -> Unit = {},
) : SyncController {
    private val _status = MutableStateFlow(SyncStatus(SyncPhase.Off, null, null, null, 0))
    override val status: StateFlow<SyncStatus> = _status

    private val running = Mutex()
    @Volatile private var rerun: Pair<SyncTrigger, Boolean>? = null
    /** Bumped by resets; a cycle started under an older epoch stops at its next suspension. */
    @Volatile private var epoch = 0
    private var backoffAttempt = 0
    private var retryJob: Job? = null

    /** The state from storage alone. Call once after `ToriStore.launch`. */
    suspend fun start() {
        val lastSyncAt = store.syncState(SyncStateKey.LAST_SYNC_AT)?.toLongOrNull()
        val phase = when {
            store.syncState(SyncStateKey.DRIVE_ACCOUNT) == null -> SyncPhase.Off
            store.syncState(SyncStateKey.DRIVE_DELETED) != null -> SyncPhase.DriveDeleted
            else -> SyncPhase.Idle
        }
        _status.update { it.copy(phase = phase, lastSyncAt = lastSyncAt, pendingCount = store.pendingRecordCount()) }
    }

    override suspend fun sync(trigger: SyncTrigger, foreground: Boolean) {
        if (!running.tryLock()) {
            val queued = rerun
            rerun = trigger to (foreground || queued?.second == true)
            return
        }
        try {
            var next: Pair<SyncTrigger, Boolean>? = trigger to foreground
            while (next != null) {
                rerun = null
                cycle(next.second)
                next = rerun
            }
        } finally {
            running.unlock()
        }
    }

    override suspend fun turnOn(api: DriveApi) {
        epoch++
        retryJob?.cancel()
        this.api = api
        try {
            val user = api.about()
            val account = accountHash(user)
            // An explicit Turn-on is the only place an account switch (silent merge into that Drive) happens.
            if (store.syncState(SyncStateKey.DRIVE_ACCOUNT) != account) store.activateDrive(account)
            _status.update { it.copy(accountLabel = user.displayName ?: user.emailAddress) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return handle(e)
        }
        sync(SyncTrigger.TurnOn, foreground = true)
    }

    override suspend fun turnOff() {
        epoch++
        retryJob?.cancel()
        api = null
        store.setSyncState(mapOf(SyncStateKey.DRIVE_ACCOUNT to null))
        _status.update { it.copy(phase = SyncPhase.Off, accountLabel = null, firstDownload = null) }
    }

    override suspend fun deleteDriveData(): Boolean {
        val api = api ?: return false
        epoch++ // a suspended cycle must not mark records saved or show "Synced" afterwards
        retryJob?.cancel()
        try {
            cloud(api, check = {}).deleteAll()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return false
        }
        epoch++
        retryJob?.cancel()
        store.markDriveDeleted()
        set(SyncPhase.DriveDeleted)
        return true
    }

    override suspend fun backUpAgain() {
        epoch++
        store.backUpAgain()
        sync(SyncTrigger.BackUpAgain, foreground = true)
    }

    // Cycle

    private suspend fun cycle(foreground: Boolean) {
        val started = epoch
        val check = { if (started != epoch) throw Superseded() }
        try {
            val stored = store.syncState(SyncStateKey.DRIVE_ACCOUNT) ?: return set(SyncPhase.Off)
            val api = api ?: return
            if (store.syncState(SyncStateKey.DRIVE_DELETED) != null) return set(SyncPhase.DriveDeleted)
            if (tokenGate.ensureAuthorized(foreground) == AuthResult.NeedsResolution) return needsResolution(foreground)
            check()
            val user = api.about()
            check()
            // A silent token never switches accounts: a different account outside Turn-on needs the user.
            if (accountHash(user) != stored) return needsResolution(foreground)
            if (foreground) _status.update { it.copy(accountLabel = user.displayName ?: user.emailAddress) }
            set(SyncPhase.Syncing)
            store.syncState(SyncStateKey.LAST_SERVER_TIME)?.toLongOrNull()?.let { store.recoverClockAhead(it) }
            val cloud = cloud(api, check)
            cloud.retryPendingDeletes()
            cloud.prepareGeneration()
            cloud.pull()
            cloud.push()
            cloud.purge()
            if (foreground) cloud.compactIfDue()
            check()
            backoffAttempt = 0
            val at = now()
            store.setSyncState(mapOf(SyncStateKey.LAST_SYNC_AT to "$at"))
            _status.update { it.copy(lastSyncAt = at, firstDownload = null) }
            set(if (cloud.clockWarning == true) SyncPhase.ClockWarning else SyncPhase.Idle)
            onCycleFinished()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Superseded) {
        } catch (e: Exception) {
            if (started == epoch) handle(e) // else a reset happened meanwhile; the error is stale
        }
    }

    private suspend fun needsResolution(foreground: Boolean) {
        if (foreground) set(SyncPhase.AccessRemoved)
    }

    private suspend fun handle(e: Exception) {
        when (e) {
            is DriveDeleted -> {
                retryJob?.cancel()
                store.markDriveDeleted()
                set(SyncPhase.DriveDeleted)
            }
            is DriveError.NotAuthenticated -> set(SyncPhase.AccessRemoved)
            is DriveError.QuotaExceeded -> set(SyncPhase.QuotaFull)
            is DriveError.RateLimited -> {
                set(SyncPhase.Idle)
                scheduleRetry(e.retryAfterMs)
            }
            else -> {
                set(SyncPhase.WaitingForNetwork)
                scheduleRetry(null)
            }
        }
    }

    private fun scheduleRetry(afterMs: Long?) {
        val wait = afterMs ?: Backoff.delayMs(backoffAttempt++, jitter())
        retryJob?.cancel()
        retryJob = scope.launch {
            sleep(wait)
            sync(SyncTrigger.Network, foreground = false)
        }
    }

    private suspend fun set(phase: SyncPhase) {
        val pending = store.pendingRecordCount()
        _status.update { it.copy(phase = phase, pendingCount = pending) }
    }

    private suspend fun cloud(api: DriveApi, check: () -> Unit): DriveCloud {
        val node = store.thisDeviceId()?.high ?: error("store not launched")
        return DriveCloud(
            store, api, node.toString(16).padStart(16, '0'), appVersion, applyChunk, now, newGeneration, check,
            onProgress = { p -> _status.update { it.copy(firstDownload = p) } },
        )
    }

    companion object {
        /** `driveAccount`: lowercase hex SHA-256 of the Drive `permissionId`, the only persisted identity. */
        fun accountHash(user: DriveUser): String =
            MessageDigest.getInstance("SHA-256").digest(user.permissionId.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
