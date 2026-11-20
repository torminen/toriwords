package com.toriwords.sync

import com.toriwords.store.SyncStateKey
import com.toriwords.store.ToriStore
import com.toriwords.store.syncState
import java.security.MessageDigest

/** `driveAccount`: lowercase hex SHA-256 of the Drive `permissionId`, the only account identity ever persisted. */
fun driveAccountId(permissionId: String): String =
    MessageDigest.getInstance("SHA-256").digest(permissionId.toByteArray()).joinToString("") { "%02x".format(it) }

/**
 * Silent authorization check before a sync cycle (outside Turn on / Back up again).
 * Needs the consent sheet, or the token belongs to another account than the stored `driveAccount` → [AuthResult.NeedsResolution];
 * the caller decides what that means for status (foreground: access removed; background: unchanged).
 * Drive errors from `about` propagate as [DriveError].
 */
class DriveTokenGate(
    private val authorizer: DriveAuthorizer,
    private val api: DriveApi,
    private val storedAccount: suspend () -> String?,
) : TokenGate {
    constructor(authorizer: DriveAuthorizer, api: DriveApi, store: ToriStore) :
        this(authorizer, api, { store.syncState(SyncStateKey.DRIVE_ACCOUNT) })

    override suspend fun ensureAuthorized(foreground: Boolean): AuthResult {
        if (authorizer.authorize() is DriveAuthorization.NeedsConsent) return AuthResult.NeedsResolution
        val user = api.about()
        if (driveAccountId(user.permissionId) != storedAccount()) return AuthResult.NeedsResolution
        return AuthResult.Ok
    }
}
