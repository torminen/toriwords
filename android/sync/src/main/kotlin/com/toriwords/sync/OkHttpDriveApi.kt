package com.toriwords.sync

import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.time.Instant
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** OAuth access tokens for Drive. [refresh] drops the cached token and asks for a new one silently. */
interface TokenProvider {
    suspend fun token(): String
    suspend fun refresh(): String
}

/**
 * Drive REST v3 over OkHttp, `appDataFolder` only. Bodies passed to [create] / [updateMedia] are already gzipped by the
 * caller and are sent as-is with `application/gzip`. Every failure surfaces as a [DriveError].
 */
class OkHttpDriveApi(
    private val client: OkHttpClient,
    private val tokens: TokenProvider,
    private val baseUrl: HttpUrl = "https://www.googleapis.com/".toHttpUrl(),
) : DriveApi {

    override suspend fun about(): DriveUser {
        val user = call<AboutDto>(get("drive/v3/about") { addQueryParameter("fields", "user(permissionId,displayName,emailAddress)") }).user
        return DriveUser(user.permissionId, user.displayName, user.emailAddress)
    }

    override suspend fun getStartPageToken(): String =
        call<StartPageTokenDto>(get("drive/v3/changes/startPageToken")).startPageToken

    override suspend fun changesList(pageToken: String): DrivePage<DriveChange> {
        val page = call<ChangesDto>(get("drive/v3/changes") {
            addQueryParameter("spaces", APP_DATA)
            addQueryParameter("pageToken", pageToken)
            addQueryParameter("pageSize", PAGE_SIZE)
            addQueryParameter("fields", "nextPageToken,newStartPageToken,changes(fileId,removed,file($FILE_FIELDS))")
        }, changes = true)
        return DrivePage(page.changes.map { DriveChange(it.fileId, it.removed, it.file?.toDomain()) }, page.nextPageToken, page.newStartPageToken)
    }

    override suspend fun filesList(pageToken: String?): DrivePage<DriveFile> {
        val page = call<FilesDto>(get("drive/v3/files") {
            addQueryParameter("spaces", APP_DATA)
            addQueryParameter("pageSize", PAGE_SIZE)
            addQueryParameter("fields", "nextPageToken,files($FILE_FIELDS)")
            if (pageToken != null) addQueryParameter("pageToken", pageToken)
        })
        return DrivePage(page.files.map { it.toDomain() }, page.nextPageToken, null)
    }

    override suspend fun download(fileId: String): ByteArray =
        execute(get("drive/v3/files/$fileId") { addQueryParameter("alt", "media") }) { it.body.bytes() }

    override suspend fun create(name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile {
        val metadata = buildJsonObject {
            put("name", name)
            put("mimeType", GZIP.toString())
            put("parents", JsonArray(listOf(JsonPrimitive(APP_DATA))))
            put("appProperties", JsonObject(appProperties.mapValues { JsonPrimitive(it.value) }))
        }
        val body = MultipartBody.Builder().setType(MULTIPART_RELATED)
            .addPart(metadata.toString().toRequestBody(JSON_TYPE))
            .addPart(bytes.toRequestBody(GZIP))
            .build()
        return call<FileDto>(upload("upload/drive/v3/files", "multipart").post(body)).toDomain()
    }

    override suspend fun updateMedia(fileId: String, bytes: ByteArray): DriveFile =
        call<FileDto>(upload("upload/drive/v3/files/$fileId", "media").patch(bytes.toRequestBody(GZIP))).toDomain()

    override suspend fun delete(fileId: String) {
        execute(Request.Builder().url(baseUrl.resolve("drive/v3/files/$fileId")!!).delete()) { }
    }

    private fun get(path: String, query: HttpUrl.Builder.() -> Unit = {}): Request.Builder =
        Request.Builder().url(baseUrl.resolve(path)!!.newBuilder().apply(query).build())

    private fun upload(path: String, type: String): Request.Builder = Request.Builder().url(
        baseUrl.resolve(path)!!.newBuilder()
            .addQueryParameter("uploadType", type)
            .addQueryParameter("fields", FILE_FIELDS)
            .build(),
    )

    private suspend inline fun <reified T> call(request: Request.Builder, changes: Boolean = false): T =
        execute(request, changes) { json.decodeFromString<T>(it.body.string()) }

    /** Sends with a bearer token; one silent re-authorization on 401. [read] runs only on 2xx. */
    private suspend fun <T> execute(request: Request.Builder, changes: Boolean = false, read: (Response) -> T): T {
        var token = tokens.token()
        var retriedAuth = false
        while (true) {
            val response = try {
                client.newCall(request.header("Authorization", "Bearer $token").build()).await()
            } catch (_: IOException) {
                throw DriveError.Network
            }
            response.use {
                if (it.isSuccessful) {
                    return try { read(it) } catch (_: IOException) { throw DriveError.Network }
                }
                if (it.code == 401 && !retriedAuth) {
                    retriedAuth = true
                    token = tokens.refresh()
                } else {
                    throw mapError(it, changes)
                }
            }
        }
    }

    private fun mapError(response: Response, changes: Boolean): DriveError {
        val error = runCatching { json.decodeFromString<ErrorEnvelope>(response.body.string()).error }.getOrNull()
        val reasons = error?.errors.orEmpty().map { it.reason }
        return when (val code = response.code) {
            401 -> DriveError.NotAuthenticated
            403 if "storageQuotaExceeded" in reasons -> DriveError.QuotaExceeded
            403 if reasons.any { it == "rateLimitExceeded" || it == "userRateLimitExceeded" } -> DriveError.RateLimited(retryAfterMs(response))
            429 -> DriveError.RateLimited(retryAfterMs(response))
            410 -> DriveError.TokenExpired
            400 if changes && isInvalidPageToken(error) -> DriveError.TokenExpired
            404 -> DriveError.NotFound
            413 -> DriveError.TooLarge
            in 500..599 -> DriveError.Network
            else -> DriveError.Other(code, error?.message)
        }
    }

    private fun isInvalidPageToken(error: ErrorDto?): Boolean =
        error != null && (error.errors.any { it.location == "pageToken" } || error.message?.contains("pageToken", ignoreCase = true) == true)

    /** `Retry-After` in seconds; the HTTP-date form is rare on Google APIs and treated as absent. */
    private fun retryAfterMs(response: Response): Long? = response.header("Retry-After")?.trim()?.toLongOrNull()?.times(1000)

    private companion object {
        const val APP_DATA = "appDataFolder"
        const val PAGE_SIZE = "1000"
        const val FILE_FIELDS = "id,name,appProperties,createdTime,modifiedTime,trashed"
        val GZIP = "application/gzip".toMediaType()
        val JSON_TYPE = "application/json; charset=UTF-8".toMediaType()
        val MULTIPART_RELATED = "multipart/related".toMediaType()
        val json = Json { ignoreUnknownKeys = true }
    }
}

private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onResponse(call: Call, response: Response) = cont.resume(response) { _, r, _ -> r.close() }
        override fun onFailure(call: Call, e: IOException) = cont.resumeWithException(e)
    })
}

@Serializable private class AboutDto(val user: UserDto)
@Serializable private class UserDto(val permissionId: String, val displayName: String? = null, val emailAddress: String? = null)
@Serializable private class StartPageTokenDto(val startPageToken: String)
@Serializable private class ChangesDto(val changes: List<ChangeDto> = emptyList(), val nextPageToken: String? = null, val newStartPageToken: String? = null)
@Serializable private class ChangeDto(val fileId: String, val removed: Boolean = false, val file: FileDto? = null)
@Serializable private class FilesDto(val files: List<FileDto> = emptyList(), val nextPageToken: String? = null)

@Serializable
private class FileDto(
    val id: String,
    val name: String = "",
    val appProperties: Map<String, String> = emptyMap(),
    val createdTime: String? = null,
    val modifiedTime: String? = null,
    val trashed: Boolean = false,
) {
    fun toDomain() = DriveFile(id, name, appProperties, millis(createdTime), millis(modifiedTime), trashed)
    private fun millis(rfc3339: String?): Long = rfc3339?.let { Instant.parse(it).toEpochMilli() } ?: 0
}

@Serializable private class ErrorEnvelope(val error: ErrorDto)
@Serializable private class ErrorDto(val code: Int = 0, val message: String? = null, val errors: List<ErrorItemDto> = emptyList())
@Serializable private class ErrorItemDto(val reason: String? = null, val location: String? = null)
