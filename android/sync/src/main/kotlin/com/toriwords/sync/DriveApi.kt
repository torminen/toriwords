package com.toriwords.sync

data class DriveFile(val id: String, val name: String, val appProperties: Map<String, String>,
                     val createdTime: Long, val modifiedTime: Long, val trashed: Boolean)
data class DrivePage<T>(val items: List<T>, val nextPageToken: String?, val newStartPageToken: String?)
data class DriveChange(val fileId: String, val removed: Boolean, val file: DriveFile?)
data class DriveUser(val permissionId: String, val displayName: String?, val emailAddress: String?)
sealed class DriveError(message: String? = null) : Exception(message) {
  object Network : DriveError(); data class RateLimited(val retryAfterMs: Long?) : DriveError()
  object QuotaExceeded : DriveError(); object NotAuthenticated : DriveError()
  object TokenExpired : DriveError() /* 410 / invalid pageToken ONLY; a 401 persisting after the silent re-auth is NotAuthenticated */; object TooLarge : DriveError(); object NotFound : DriveError()
  data class Other(val code: Int, val detail: String?) : DriveError(detail)
}
interface DriveApi {
  suspend fun about(): DriveUser
  suspend fun getStartPageToken(): String
  suspend fun changesList(pageToken: String): DrivePage<DriveChange>
  suspend fun filesList(pageToken: String?): DrivePage<DriveFile>
  suspend fun download(fileId: String): ByteArray
  suspend fun create(name: String, appProperties: Map<String, String>, bytes: ByteArray): DriveFile
  suspend fun updateMedia(fileId: String, bytes: ByteArray): DriveFile
  suspend fun delete(fileId: String)
}
