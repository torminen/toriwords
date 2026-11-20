package com.toriwords.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.toriwords.sync.DriveApi
import com.toriwords.sync.SyncController
import com.toriwords.sync.SyncPhase
import com.toriwords.sync.SyncStatus
import com.toriwords.sync.SyncTrigger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class DriveSyncMode { NotAvailable, Off, On, DriveDeleted, AccessRemoved }

enum class DriveSyncStatusLine { Synced, Syncing, WaitingForNetwork, StorageFull, CheckDeviceTime, DriveDeleted, AccessRemoved }

enum class DriveSyncDialog { TurnOff, DeleteDriveData, Offline }

data class DriveSyncUiState(
    val mode: DriveSyncMode,
    val account: String? = null,
    /** Null = blank row (on, never synced yet). */
    val status: DriveSyncStatusLine? = null,
    val syncedMinutesAgo: Long = 0,
    /** Applied / total files of the first download. */
    val firstDownload: Pair<Int, Int>? = null,
    val syncNowEnabled: Boolean = false,
    val dialog: DriveSyncDialog? = null,
)

/**
 * Settings → Google Drive sync. State comes only from [SyncController.status]; authorization (the consent sheet) is
 * done by the screen, which calls [onAuthorized] once a grant exists. Actions run in [actions] (an app-wide scope) so a
 * started turn-on or delete survives leaving the screen.
 */
class DriveSyncViewModel(
    private val controller: SyncController,
    private val api: DriveApi,
    private val driveAvailable: Boolean,
    private val actions: CoroutineScope,
    private val revokeAccess: suspend (accountLabel: String?) -> Unit = {},
    private val now: () -> Long = System::currentTimeMillis,
) : ViewModel() {
    private val dialog = MutableStateFlow<DriveSyncDialog?>(null)

    val state: StateFlow<DriveSyncUiState> = combine(controller.status, dialog, ::uiState)
        .stateIn(viewModelScope, SharingStarted.Eagerly, uiState(controller.status.value, null))

    /** Turn on / Turn on again after access was removed: a grant exists now. */
    fun onAuthorized() { actions.launch { controller.turnOn(api) } }

    fun onSyncNow() { actions.launch { controller.sync(SyncTrigger.SyncNow, foreground = true) } }

    fun onBackUpAgain() { actions.launch { controller.backUpAgain() } }

    fun onTurnOffClicked() { dialog.value = DriveSyncDialog.TurnOff }

    fun onTurnOffConfirmed() {
        dialog.value = null
        val label = controller.status.value.accountLabel
        actions.launch {
            controller.turnOff()
            revokeAccess(label)
        }
    }

    fun onDeleteClicked() { dialog.value = DriveSyncDialog.DeleteDriveData }

    fun onDeleteConfirmed() {
        dialog.value = null
        actions.launch { if (!controller.deleteDriveData()) dialog.value = DriveSyncDialog.Offline }
    }

    fun onDialogDismissed() { dialog.value = null }

    private fun uiState(status: SyncStatus, dialog: DriveSyncDialog?): DriveSyncUiState {
        if (!driveAvailable) return DriveSyncUiState(DriveSyncMode.NotAvailable)
        val on = DriveSyncUiState(
            mode = DriveSyncMode.On,
            account = status.accountLabel,
            firstDownload = status.firstDownload,
            syncNowEnabled = status.phase != SyncPhase.Syncing,
            dialog = dialog,
        )
        return when (status.phase) {
            SyncPhase.NotAvailable -> DriveSyncUiState(DriveSyncMode.NotAvailable)
            SyncPhase.Off -> DriveSyncUiState(DriveSyncMode.Off)
            SyncPhase.Idle -> on.copy(
                status = status.lastSyncAt?.let { DriveSyncStatusLine.Synced },
                syncedMinutesAgo = status.lastSyncAt?.let { ((now() - it) / 60_000).coerceAtLeast(0) } ?: 0,
            )
            SyncPhase.Syncing -> on.copy(status = DriveSyncStatusLine.Syncing)
            SyncPhase.WaitingForNetwork -> on.copy(status = DriveSyncStatusLine.WaitingForNetwork)
            SyncPhase.QuotaFull -> on.copy(status = DriveSyncStatusLine.StorageFull)
            SyncPhase.ClockWarning -> on.copy(status = DriveSyncStatusLine.CheckDeviceTime)
            SyncPhase.DriveDeleted -> on.copy(mode = DriveSyncMode.DriveDeleted, status = DriveSyncStatusLine.DriveDeleted, syncNowEnabled = false)
            SyncPhase.AccessRemoved -> DriveSyncUiState(DriveSyncMode.AccessRemoved, status = DriveSyncStatusLine.AccessRemoved)
        }
    }
}
