package com.toriwords.app

import com.toriwords.sync.DriveApi
import com.toriwords.sync.DriveChange
import com.toriwords.sync.DriveFile
import com.toriwords.sync.DrivePage
import com.toriwords.sync.DriveUser
import com.toriwords.sync.SyncController
import com.toriwords.sync.SyncPhase
import com.toriwords.sync.SyncStatus
import com.toriwords.sync.SyncTrigger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DriveSyncViewModelTest {
    private val dispatcher = UnconfinedTestDispatcher()
    private val actions = TestScope(dispatcher)
    private val controller = FakeController()
    private val revoked = mutableListOf<String?>()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun vm(driveAvailable: Boolean = true) = DriveSyncViewModel(
        controller, FakeApi, driveAvailable, actions, revokeAccess = { revoked += it }, now = { NOW },
    )

    private fun DriveSyncViewModel.ui() = state.value

    // State → UI

    @Test fun offShowsTurnOn() {
        controller.phase(SyncPhase.Off)
        assertEquals(DriveSyncUiState(DriveSyncMode.Off), vm().ui())
    }

    @Test fun noPlayServicesIsNotAvailableWhateverTheStatus() {
        controller.phase(SyncPhase.Off)
        assertEquals(DriveSyncMode.NotAvailable, vm(driveAvailable = false).ui().mode)
        controller.phase(SyncPhase.NotAvailable)
        assertEquals(DriveSyncMode.NotAvailable, vm().ui().mode)
    }

    @Test fun onIdleShowsAccountMinutesAgoAndEnabledSyncNow() {
        controller.status.value = SyncStatus(SyncPhase.Idle, NOW - 3 * 60_000 - 5_000, "ann@example.com", null, 0)
        val ui = vm().ui()
        assertEquals(DriveSyncMode.On, ui.mode)
        assertEquals("ann@example.com", ui.account)
        assertEquals(DriveSyncStatusLine.Synced, ui.status)
        assertEquals(3L, ui.syncedMinutesAgo)
        assertTrue(ui.syncNowEnabled)
    }

    @Test fun onNeverSyncedHasBlankStatusAndAccount() {
        controller.phase(SyncPhase.Idle)
        val ui = vm().ui()
        assertNull(ui.status)
        assertNull(ui.account)
    }

    @Test fun syncingDisablesSyncNowAndShowsFirstDownload() {
        controller.status.value = SyncStatus(SyncPhase.Syncing, null, "a", 3 to 10, 0)
        val ui = vm().ui()
        assertEquals(DriveSyncStatusLine.Syncing, ui.status)
        assertEquals(3 to 10, ui.firstDownload)
        assertFalse(ui.syncNowEnabled)
    }

    @Test fun onStatusLines() {
        val vm = vm()
        mapOf(
            SyncPhase.WaitingForNetwork to DriveSyncStatusLine.WaitingForNetwork,
            SyncPhase.QuotaFull to DriveSyncStatusLine.StorageFull,
            SyncPhase.ClockWarning to DriveSyncStatusLine.CheckDeviceTime,
        ).forEach { (phase, line) ->
            controller.phase(phase)
            assertEquals(DriveSyncMode.On, vm.ui().mode)
            assertEquals(line, vm.ui().status)
            assertTrue(vm.ui().syncNowEnabled)
        }
    }

    @Test fun driveDeletedShowsBackUpAgainAndDisablesSyncNow() {
        controller.phase(SyncPhase.DriveDeleted)
        val ui = vm().ui()
        assertEquals(DriveSyncMode.DriveDeleted, ui.mode)
        assertEquals(DriveSyncStatusLine.DriveDeleted, ui.status)
        assertFalse(ui.syncNowEnabled)
    }

    @Test fun accessRemovedShowsTurnOnAgain() {
        controller.phase(SyncPhase.AccessRemoved)
        assertEquals(DriveSyncUiState(DriveSyncMode.AccessRemoved, status = DriveSyncStatusLine.AccessRemoved), vm().ui())
    }

    @Test fun followsStatusUpdates() {
        val vm = vm()
        controller.phase(SyncPhase.Off)
        assertEquals(DriveSyncMode.Off, vm.ui().mode)
        controller.phase(SyncPhase.Syncing)
        assertEquals(DriveSyncMode.On, vm.ui().mode)
    }

    // Actions and dialogs

    @Test fun authorizedTurnsOnWithTheDriveApi() {
        vm().onAuthorized()
        assertSame(FakeApi, controller.turnedOnWith)
    }

    @Test fun syncNowIsAForegroundSyncNow() {
        vm().onSyncNow()
        assertEquals(listOf(SyncTrigger.SyncNow to true), controller.syncs)
    }

    @Test fun backUpAgain() {
        vm().onBackUpAgain()
        assertEquals(1, controller.backUps)
    }

    @Test fun turnOffDialogCancelChangesNothing() {
        controller.phase(SyncPhase.Idle)
        val vm = vm()
        vm.onTurnOffClicked()
        assertEquals(DriveSyncDialog.TurnOff, vm.ui().dialog)
        vm.onDialogDismissed()
        assertNull(vm.ui().dialog)
        assertEquals(0, controller.turnOffs)
    }

    @Test fun turnOffConfirmedTurnsOffAndRevokesTheShownAccount() {
        controller.status.value = SyncStatus(SyncPhase.Idle, null, "ann@example.com", null, 0)
        val vm = vm()
        vm.onTurnOffClicked()
        vm.onTurnOffConfirmed()
        assertNull(vm.ui().dialog)
        assertEquals(1, controller.turnOffs)
        assertEquals(listOf<String?>("ann@example.com"), revoked)
        assertEquals(DriveSyncMode.Off, vm.ui().mode)
    }

    @Test fun deleteDialogCancelChangesNothing() {
        controller.phase(SyncPhase.Idle)
        val vm = vm()
        vm.onDeleteClicked()
        assertEquals(DriveSyncDialog.DeleteDriveData, vm.ui().dialog)
        vm.onDialogDismissed()
        assertNull(vm.ui().dialog)
        assertEquals(0, controller.deletes)
    }

    @Test fun deleteConfirmedOnline() {
        controller.phase(SyncPhase.Idle)
        val vm = vm()
        vm.onDeleteClicked()
        vm.onDeleteConfirmed()
        assertEquals(1, controller.deletes)
        assertNull(vm.ui().dialog)
        assertEquals(DriveSyncMode.DriveDeleted, vm.ui().mode)
    }

    @Test fun deleteConfirmedOfflineShowsNoInternetThenOkCloses() {
        controller.phase(SyncPhase.Idle)
        controller.online = false
        val vm = vm()
        vm.onDeleteClicked()
        vm.onDeleteConfirmed()
        assertEquals(DriveSyncDialog.Offline, vm.ui().dialog)
        assertEquals(DriveSyncMode.On, vm.ui().mode)
        vm.onDialogDismissed()
        assertNull(vm.ui().dialog)
    }

    private class FakeController : SyncController {
        override val status = MutableStateFlow(SyncStatus(SyncPhase.Off, null, null, null, 0))
        val syncs = mutableListOf<Pair<SyncTrigger, Boolean>>()
        var turnedOnWith: DriveApi? = null
        var turnOffs = 0
        var deletes = 0
        var backUps = 0
        var online = true

        fun phase(phase: SyncPhase) { status.value = status.value.copy(phase = phase) }

        override suspend fun sync(trigger: SyncTrigger, foreground: Boolean) { syncs += trigger to foreground }
        override suspend fun turnOn(api: DriveApi) { turnedOnWith = api }
        override suspend fun turnOff() { turnOffs++; status.value = SyncStatus(SyncPhase.Off, null, null, null, 0) }
        override suspend fun deleteDriveData(): Boolean {
            deletes++
            if (online) phase(SyncPhase.DriveDeleted)
            return online
        }
        override suspend fun backUpAgain() { backUps++ }
    }

    private object FakeApi : DriveApi {
        override suspend fun about() = DriveUser("p", null, null)
        override suspend fun getStartPageToken() = error("unused")
        override suspend fun changesList(pageToken: String): DrivePage<DriveChange> = error("unused")
        override suspend fun filesList(pageToken: String?): DrivePage<DriveFile> = error("unused")
        override suspend fun download(fileId: String): ByteArray = error("unused")
        override suspend fun create(name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile = error("unused")
        override suspend fun updateMedia(fileId: String, bytes: ByteArray): DriveFile = error("unused")
        override suspend fun delete(fileId: String) = error("unused")
    }

    private companion object {
        const val NOW = 1_800_000_000_000L
    }
}
