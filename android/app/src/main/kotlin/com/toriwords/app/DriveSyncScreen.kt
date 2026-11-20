package com.toriwords.app

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.toriwords.sync.DriveAuthorization
import com.toriwords.sync.DriveAuthorizer
import com.toriwords.sync.DriveError
import kotlinx.coroutines.launch

/**
 * Activity-side Drive authorization: silent grant → [onAuthorized]; otherwise launches the system account picker /
 * consent sheet. Cancel or failure does nothing.
 */
@Composable
fun rememberDriveTurnOn(authorizer: DriveAuthorizer, onAuthorized: () -> Unit): () -> Unit {
    val authorized by rememberUpdatedState(onAuthorized)
    val scope = rememberCoroutineScope()
    val consent = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK && authorizer.resultFromIntent(result.data) != null) authorized()
    }
    return remember(authorizer) {
        {
            scope.launch {
                when (val auth = try { authorizer.authorize() } catch (_: DriveError) { null }) {
                    is DriveAuthorization.Granted -> authorized()
                    is DriveAuthorization.NeedsConsent -> consent.launch(IntentSenderRequest.Builder(auth.intentSender).build())
                    null -> Unit
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DriveSyncScreen(state: DriveSyncUiState, vm: DriveSyncViewModel, onTurnOn: () -> Unit) {
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.drive_sync_title)) }) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when (state.mode) {
                DriveSyncMode.NotAvailable -> Text(stringResource(R.string.drive_sync_not_available))
                DriveSyncMode.Off -> {
                    Text(stringResource(R.string.drive_sync_off_explainer))
                    Button(onClick = onTurnOn) { Text(stringResource(R.string.drive_sync_turn_on)) }
                }
                DriveSyncMode.AccessRemoved -> {
                    StatusRow(state)
                    Button(onClick = onTurnOn) { Text(stringResource(R.string.drive_sync_turn_on)) }
                }
                DriveSyncMode.On, DriveSyncMode.DriveDeleted -> OnContent(state, vm)
            }
        }
    }
    state.dialog?.let { Dialog(it, vm) }
}

@Composable
private fun OnContent(state: DriveSyncUiState, vm: DriveSyncViewModel) {
    ListItem(
        headlineContent = { Text(stringResource(R.string.drive_sync_account)) },
        supportingContent = { Text(state.account.orEmpty()) },
    )
    StatusRow(state)
    state.firstDownload?.let { (applied, total) -> Text(stringResource(R.string.drive_sync_first_download, applied, total)) }
    if (state.mode == DriveSyncMode.DriveDeleted) {
        Button(onClick = vm::onBackUpAgain) { Text(stringResource(R.string.drive_sync_back_up_again)) }
    }
    OutlinedButton(onClick = vm::onSyncNow, enabled = state.syncNowEnabled) { Text(stringResource(R.string.drive_sync_sync_now)) }
    TextButton(onClick = vm::onTurnOffClicked) { Text(stringResource(R.string.drive_sync_turn_off)) }
    if (state.mode == DriveSyncMode.On) {
        TextButton(onClick = vm::onDeleteClicked, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
            Text(stringResource(R.string.drive_sync_delete))
        }
    }
}

@Composable
private fun StatusRow(state: DriveSyncUiState) {
    val text = when (state.status) {
        null -> ""
        DriveSyncStatusLine.Synced -> stringResource(R.string.drive_sync_status_synced, state.syncedMinutesAgo)
        DriveSyncStatusLine.Syncing -> stringResource(R.string.drive_sync_status_syncing)
        DriveSyncStatusLine.WaitingForNetwork -> stringResource(R.string.drive_sync_status_waiting)
        DriveSyncStatusLine.StorageFull -> stringResource(R.string.drive_sync_status_storage_full)
        DriveSyncStatusLine.CheckDeviceTime -> stringResource(R.string.drive_sync_status_check_time)
        DriveSyncStatusLine.DriveDeleted -> stringResource(R.string.drive_sync_status_drive_deleted)
        DriveSyncStatusLine.AccessRemoved -> stringResource(R.string.drive_sync_status_access_removed)
    }
    ListItem(headlineContent = { Text(stringResource(R.string.drive_sync_status)) }, supportingContent = { Text(text) })
}

@Composable
private fun Dialog(dialog: DriveSyncDialog, vm: DriveSyncViewModel) {
    val (title, body, confirm, onConfirm) = when (dialog) {
        DriveSyncDialog.TurnOff -> DialogCopy(R.string.drive_sync_turn_off_title, R.string.drive_sync_turn_off_body, R.string.drive_sync_turn_off_confirm, vm::onTurnOffConfirmed)
        DriveSyncDialog.DeleteDriveData -> DialogCopy(R.string.drive_sync_delete_title, R.string.drive_sync_delete_body, R.string.drive_sync_delete_confirm, vm::onDeleteConfirmed)
        DriveSyncDialog.Offline -> DialogCopy(R.string.drive_sync_offline_title, R.string.drive_sync_offline_body, R.string.ok, vm::onDialogDismissed)
    }
    AlertDialog(
        onDismissRequest = vm::onDialogDismissed,
        title = { Text(stringResource(title)) },
        text = { Text(stringResource(body)) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(confirm)) } },
        dismissButton = if (dialog == DriveSyncDialog.Offline) null else {
            { TextButton(onClick = vm::onDialogDismissed) { Text(stringResource(R.string.cancel)) } }
        },
    )
}

private data class DialogCopy(val title: Int, val body: Int, val confirm: Int, val onConfirm: () -> Unit)
