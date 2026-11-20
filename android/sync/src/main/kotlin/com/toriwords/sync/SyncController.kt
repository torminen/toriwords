package com.toriwords.sync

enum class SyncTrigger { Foreground, Debounced, Periodic, Network, SyncNow, TurnOn, BackUpAgain }
enum class SyncPhase { Off, NotAvailable, Idle, Syncing, WaitingForNetwork, QuotaFull, ClockWarning, AccessRemoved, DriveDeleted }
data class SyncStatus(val phase: SyncPhase, val lastSyncAt: Long?, val accountLabel: String?,
                      val firstDownload: Pair<Int, Int>?, /* applied, total files */ val pendingCount: Int)
interface SyncController {
  val status: kotlinx.coroutines.flow.StateFlow<SyncStatus>
  suspend fun sync(trigger: SyncTrigger, foreground: Boolean)
  suspend fun turnOn(api: DriveApi)          // runs identity rule, account switch if hash differs, then sync(TurnOn)
  suspend fun turnOff()
  suspend fun deleteDriveData(): Boolean     // false = offline, nothing changed
  suspend fun backUpAgain()
}
