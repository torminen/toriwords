package com.toriwords.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory

/** Single activity; until the rest of the UI lands its start screen is Settings → Google Drive sync. */
class MainActivity : ComponentActivity() {
    private val app get() = application as ToriApp

    private val driveSync: DriveSyncViewModel by viewModels {
        viewModelFactory {
            initializer {
                DriveSyncViewModel(
                    controller = app.syncController,
                    api = app.driveApi,
                    driveAvailable = app.authorizer.isAvailable(),
                    actions = app.appScope,
                    revokeAccess = { email -> app.authorizer.revoke(email) },
                    accountEmail = { app.syncEngine.accountEmail },
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                val state = driveSync.state.collectAsStateWithLifecycle().value
                DriveSyncScreen(state, driveSync, onTurnOn = rememberDriveTurnOn(app.authorizer, driveSync::onAuthorized))
            }
        }
    }
}
