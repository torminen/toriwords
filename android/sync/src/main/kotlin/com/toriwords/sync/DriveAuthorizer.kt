package com.toriwords.sync

import android.accounts.Account
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Task
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Result of asking Play services for Drive access. [NeedsConsent] carries the system account picker / consent sheet. */
sealed interface DriveAuthorization {
    data class Granted(val accessToken: String) : DriveAuthorization
    class NeedsConsent(val intentSender: IntentSender) : DriveAuthorization
}

/**
 * Drive authorization through `AuthorizationClient` with the `drive.appdata` scope only. Never calls `setAccount`
 * (the user's last grant is used), never persists the account name or email.
 */
class DriveAuthorizer(private val context: Context) : TokenProvider {
    private val client = Identity.getAuthorizationClient(context)
    private val request = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(DRIVE_APPDATA))).build()

    @Volatile private var cachedToken: String? = null

    fun isAvailable(): Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    /** Play services failures (no connection, service error) surface as [DriveError.Network]. */
    suspend fun authorize(): DriveAuthorization {
        val result = try { client.authorize(request).await() } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            throw DriveError.Network
        }
        return toAuthorization(result)
    }

    /** Result of the consent sheet launched from [DriveAuthorization.NeedsConsent]; null when cancelled or failed. */
    fun resultFromIntent(data: Intent?): DriveAuthorization.Granted? =
        runCatching { toAuthorization(client.getAuthorizationResultFromIntent(data)) }.getOrNull() as? DriveAuthorization.Granted

    /** Silent token; a grant that needs the consent sheet is [DriveError.NotAuthenticated] here. */
    override suspend fun token(): String = cachedToken ?: when (val auth = authorize()) {
        is DriveAuthorization.Granted -> auth.accessToken
        is DriveAuthorization.NeedsConsent -> throw DriveError.NotAuthenticated
    }

    override suspend fun refresh(): String {
        cachedToken?.let { stale ->
            cachedToken = null
            runCatching { client.clearToken(ClearTokenRequest.builder().setToken(stale).build()).await() }
        }
        return token()
    }

    /** Best effort: revoking needs the account, which is only known in memory (the email from `about`). */
    suspend fun revoke(email: String?) {
        cachedToken = null
        if (email == null) return
        val revoke = RevokeAccessRequest.builder()
            .setAccount(Account(email, "com.google"))
            .setScopes(listOf(Scope(DRIVE_APPDATA)))
            .build()
        runCatching { client.revokeAccess(revoke).await() }
    }

    private fun toAuthorization(result: AuthorizationResult): DriveAuthorization {
        val token = result.accessToken
        val consent = result.pendingIntent
        return when {
            result.hasResolution() && consent != null -> DriveAuthorization.NeedsConsent(consent.intentSender)
            token != null -> DriveAuthorization.Granted(token).also { cachedToken = token }
            else -> throw DriveError.NotAuthenticated
        }
    }

    companion object {
        const val DRIVE_APPDATA = "https://www.googleapis.com/auth/drive.appdata"
    }
}

internal suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { cont ->
    addOnSuccessListener { cont.resume(it) }
    addOnFailureListener { cont.resumeWithException(it) }
    addOnCanceledListener { cont.cancel() }
}
