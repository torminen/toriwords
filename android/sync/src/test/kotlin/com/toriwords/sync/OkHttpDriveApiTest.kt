package com.toriwords.sync

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import mockwebserver3.SocketEffect
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.util.concurrent.TimeUnit

class OkHttpDriveApiTest {
    private val server = MockWebServer()
    private val tokens = FakeTokens()
    private lateinit var api: OkHttpDriveApi

    @Before fun setUp() {
        server.start()
        val client = OkHttpClient.Builder().readTimeout(2, TimeUnit.SECONDS).build()
        api = OkHttpDriveApi(client, tokens, server.url("/"))
    }

    @After fun tearDown() = server.close()

    // Request shapes

    @Test fun aboutRequestsUserFieldsAndParsesUser() = runBlocking {
        respond(200, """{"user":{"permissionId":"0123","displayName":"Ann","emailAddress":"ann@example.com","kind":"drive#user"}}""")
        assertEquals(DriveUser("0123", "Ann", "ann@example.com"), api.about())
        val r = take()
        assertEquals("GET", r.method)
        assertEquals("/drive/v3/about", r.url.encodedPath)
        assertEquals("user(permissionId,displayName,emailAddress)", r.url.queryParameter("fields"))
        assertEquals("Bearer t1", r.headers["Authorization"])
    }

    @Test fun aboutToleratesMissingNameAndEmail() = runBlocking {
        respond(200, """{"user":{"permissionId":"0123"}}""")
        assertEquals(DriveUser("0123", null, null), api.about())
    }

    @Test fun startPageToken() = runBlocking {
        respond(200, """{"kind":"drive#startPageToken","startPageToken":"42"}""")
        assertEquals("42", api.getStartPageToken())
        assertEquals("/drive/v3/changes/startPageToken", take().url.encodedPath)
    }

    @Test fun changesListRequestAndParsing() = runBlocking {
        respond(200, """{"nextPageToken":"p2","changes":[
            {"fileId":"f1","removed":false,"file":{"id":"f1","name":"b-d-1.json.gz","appProperties":{"kind":"batch","seq":"1"},
             "createdTime":"2026-11-20T10:00:00.000Z","modifiedTime":"2026-11-20T10:00:01.500Z","trashed":false}},
            {"fileId":"f2","removed":true}]}""")
        val page = api.changesList("p1")
        assertEquals("p2", page.nextPageToken)
        assertNull(page.newStartPageToken)
        assertEquals(
            listOf(
                DriveChange("f1", false, DriveFile("f1", "b-d-1.json.gz", mapOf("kind" to "batch", "seq" to "1"),
                    ms("2026-11-20T10:00:00Z"), ms("2026-11-20T10:00:01.500Z"), false)),
                DriveChange("f2", true, null),
            ),
            page.items,
        )
        val url = take().url
        assertEquals("/drive/v3/changes", url.encodedPath)
        assertEquals("appDataFolder", url.queryParameter("spaces"))
        assertEquals("p1", url.queryParameter("pageToken"))
        assertEquals(
            "nextPageToken,newStartPageToken,changes(fileId,removed,file(id,name,appProperties,createdTime,modifiedTime,trashed))",
            url.queryParameter("fields"),
        )
    }

    @Test fun changesListLastPageCarriesNewStartPageToken() = runBlocking {
        respond(200, """{"newStartPageToken":"p9","changes":[]}""")
        val page = api.changesList("p8")
        assertEquals(DrivePage(emptyList<DriveChange>(), null, "p9"), page)
    }

    @Test fun filesListFirstAndNextPage() = runBlocking {
        respond(200, """{"nextPageToken":"n2","files":[{"id":"g","name":"generation.json","createdTime":"2026-11-20T09:00:00Z",
            "modifiedTime":"2026-11-20T09:00:00Z","trashed":true}]}""")
        respond(200, """{"files":[]}""")
        val first = api.filesList(null)
        assertEquals(listOf(DriveFile("g", "generation.json", emptyMap(), ms("2026-11-20T09:00:00Z"), ms("2026-11-20T09:00:00Z"), true)), first.items)
        assertEquals("n2", first.nextPageToken)
        api.filesList("n2")

        val firstUrl = take().url
        assertEquals("/drive/v3/files", firstUrl.encodedPath)
        assertEquals("appDataFolder", firstUrl.queryParameter("spaces"))
        assertEquals("nextPageToken,files(id,name,appProperties,createdTime,modifiedTime,trashed)", firstUrl.queryParameter("fields"))
        assertNull(firstUrl.queryParameter("pageToken"))
        assertEquals("n2", take().url.queryParameter("pageToken"))
    }

    @Test fun downloadReturnsRawBytes() = runBlocking {
        server.enqueue(MockResponse.Builder().code(200).setHeader("Content-Type", "application/gzip").body(okio.Buffer().write(GZ)).build())
        assertArrayEquals(GZ, api.download("f1"))
        val url = take().url
        assertEquals("/drive/v3/files/f1", url.encodedPath)
        assertEquals("media", url.queryParameter("alt"))
    }

    @Test fun createIsMultipartIntoAppDataFolderWithGzipMediaUntouched() = runBlocking {
        respond(200, FILE_JSON)
        val file = api.create("b-d-7.json.gz", mapOf("layout" to "1", "kind" to "batch"), GZ)
        assertEquals("f9", file.id)

        val r = take()
        assertEquals("POST", r.method)
        assertEquals("/upload/drive/v3/files", r.url.encodedPath)
        assertEquals("multipart", r.url.queryParameter("uploadType"))
        assertTrue(r.headers["Content-Type"]!!.startsWith("multipart/related"))
        val body = r.body!!.toByteArray()
        val text = String(body, Charsets.ISO_8859_1)
        val metaStart = text.indexOf("{")
        val meta = Json.parseToJsonElement(text.substring(metaStart, text.indexOf("\r\n", metaStart))).jsonObject
        assertEquals("b-d-7.json.gz", meta["name"]!!.jsonPrimitive.content)
        assertEquals("appDataFolder", meta["parents"]!!.jsonArray.single().jsonPrimitive.content)
        assertEquals("batch", meta["appProperties"]!!.jsonObject["kind"]!!.jsonPrimitive.content)
        assertTrue(text.contains("Content-Type: application/gzip"))
        assertTrue("gzip bytes are sent as-is", text.contains(String(GZ, Charsets.ISO_8859_1)))
    }

    @Test fun updateMediaPatchesGzipBody() = runBlocking {
        respond(200, FILE_JSON)
        assertEquals(ms("2026-11-20T10:00:05Z"), api.updateMedia("f9", GZ).modifiedTime)
        val r = take()
        assertEquals("PATCH", r.method)
        assertEquals("/upload/drive/v3/files/f9", r.url.encodedPath)
        assertEquals("media", r.url.queryParameter("uploadType"))
        assertTrue(r.headers["Content-Type"]!!.startsWith("application/gzip"))
        assertArrayEquals(GZ, r.body!!.toByteArray())
    }

    @Test fun deleteByFileId() = runBlocking {
        server.enqueue(MockResponse.Builder().code(204).build())
        api.delete("f9")
        val r = take()
        assertEquals("DELETE", r.method)
        assertEquals("/drive/v3/files/f9", r.url.encodedPath)
    }

    // Error mapping

    @Test fun connectionDropIsNetwork() = runBlocking {
        server.enqueue(MockResponse.Builder().onRequestStart(SocketEffect.CloseSocket()).build())
        expect(DriveError.Network) { api.getStartPageToken() }
    }

    @Test fun timeoutIsNetwork() = runBlocking {
        server.enqueue(MockResponse.Builder().code(200).body("{}").bodyDelay(5, TimeUnit.SECONDS).build())
        expect(DriveError.Network) { api.getStartPageToken() }
    }

    @Test fun serverErrorIsNetwork() = runBlocking {
        respond(503, "")
        expect(DriveError.Network) { api.getStartPageToken() }
    }

    @Test fun rateLimit403WithRetryAfter() = runBlocking {
        server.enqueue(MockResponse.Builder().code(403).setHeader("Retry-After", "7").body(error(403, "rateLimitExceeded")).build())
        expect(DriveError.RateLimited(7_000)) { api.getStartPageToken() }
    }

    @Test fun userRateLimit403WithoutRetryAfter() = runBlocking {
        respond(403, error(403, "userRateLimitExceeded"))
        expect(DriveError.RateLimited(null)) { api.getStartPageToken() }
    }

    @Test fun tooManyRequests429() = runBlocking {
        server.enqueue(MockResponse.Builder().code(429).setHeader("Retry-After", "2").build())
        expect(DriveError.RateLimited(2_000)) { api.getStartPageToken() }
    }

    @Test fun storageQuota403() = runBlocking {
        respond(403, error(403, "storageQuotaExceeded"))
        expect(DriveError.QuotaExceeded) { api.create("x", emptyMap(), GZ) }
    }

    @Test fun other403IsOther() = runBlocking {
        respond(403, error(403, "insufficientPermissions", message = "nope"))
        expect(DriveError.Other(403, "nope")) { api.getStartPageToken() }
    }

    @Test fun unauthorizedRefreshesOnceThenSucceeds() = runBlocking {
        respond(401, error(401, "authError"))
        respond(200, """{"startPageToken":"5"}""")
        assertEquals("5", api.getStartPageToken())
        assertEquals("Bearer t1", take().headers["Authorization"])
        assertEquals("Bearer t2", take().headers["Authorization"])
        assertEquals(1, tokens.refreshes)
    }

    @Test fun unauthorizedTwiceIsNotAuthenticated() = runBlocking {
        respond(401, error(401, "authError"))
        respond(401, error(401, "authError"))
        expect(DriveError.NotAuthenticated) { api.getStartPageToken() }
        assertEquals(1, tokens.refreshes)
        assertEquals(2, server.requestCount)
    }

    @Test fun goneOnChangesIsTokenExpired() = runBlocking {
        respond(410, "")
        expect(DriveError.TokenExpired) { api.changesList("old") }
    }

    @Test fun invalidPageTokenOnChangesIsTokenExpired() = runBlocking {
        respond(400, error(400, "invalid", location = "pageToken", message = "Invalid Value"))
        expect(DriveError.TokenExpired) { api.changesList("bad") }
    }

    @Test fun badRequestOnFilesListIsOther() = runBlocking {
        respond(400, error(400, "invalid", location = "pageToken", message = "Invalid Value"))
        expect(DriveError.Other(400, "Invalid Value")) { api.filesList("bad") }
    }

    @Test fun payloadTooLarge() = runBlocking {
        respond(413, "")
        expect(DriveError.TooLarge) { api.create("x", emptyMap(), GZ) }
    }

    @Test fun notFound() = runBlocking {
        respond(404, error(404, "notFound"))
        expect(DriveError.NotFound) { api.download("gone") }
    }

    @Test fun unknownStatusIsOther() = runBlocking {
        respond(409, "not json")
        expect(DriveError.Other(409, null)) { api.delete("f") }
    }

    private fun respond(code: Int, body: String) = server.enqueue(MockResponse.Builder().code(code).body(body).build())

    private fun take(): RecordedRequest = server.takeRequest(1, TimeUnit.SECONDS)!!

    private suspend fun expect(expected: DriveError, block: suspend () -> Unit) {
        try {
            block()
            fail("expected $expected")
        } catch (e: DriveError) {
            assertEquals(expected, e)
        }
    }

    private fun error(code: Int, reason: String, location: String? = null, message: String = "m"): String {
        val loc = location?.let { ""","location":"$it"""" } ?: ""
        return """{"error":{"code":$code,"message":"$message","errors":[{"domain":"global","reason":"$reason"$loc}]}}"""
    }

    private fun ms(rfc3339: String) = Instant.parse(rfc3339).toEpochMilli()

    private class FakeTokens : TokenProvider {
        var refreshes = 0
        private var current = "t1"
        override suspend fun token() = current
        override suspend fun refresh(): String { refreshes++; current = "t2"; return current }
    }

    private companion object {
        val GZ = byteArrayOf(0x1f, 0x8b.toByte(), 8, 0, 1, 2, 3, 0x7f, 0x80.toByte(), 0xff.toByte())
        const val FILE_JSON = """{"id":"f9","name":"b-d-7.json.gz","appProperties":{"layout":"1"},
            "createdTime":"2026-11-20T10:00:05Z","modifiedTime":"2026-11-20T10:00:05Z","trashed":false}"""
    }
}
