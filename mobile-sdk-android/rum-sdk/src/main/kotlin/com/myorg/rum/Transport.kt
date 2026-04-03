package com.myorg.rum

import android.util.Log
import com.myorg.rum.models.RumEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * HTTP 전송 레이어.
 *
 * - POST {endpoint}/v1/events
 * - 헤더: Content-Type: application/json, x-api-key: {apiKey}
 * - 5xx 오류 시 지수 백오프 재시도 (1s → 2s → 4s, 최대 3회)
 * - 4xx 오류는 재시도하지 않음
 * - Dispatchers.IO 에서 실행
 */
class Transport(private val config: Config) {

    private val tag = "RumTransport"

    /**
     * 이벤트 배치를 서버로 전송한다.
     * @return 전송 성공 여부
     */
    open suspend fun send(events: List<RumEvent>): Boolean = withContext(Dispatchers.IO) {
        if (events.isEmpty()) return@withContext true

        val url = "${config.endpoint}/v1/events"
        val body = buildBody(events)

        var attempt = 0
        val maxAttempts = 3
        val baseDelayMs = 1_000L

        while (attempt < maxAttempts) {
            val result = runCatching { postRequest(url, body) }
            when {
                result.isSuccess -> {
                    val code = result.getOrThrow()
                    when {
                        code in 200..299 -> {
                            if (config.debug) Log.d(tag, "전송 성공 (${events.size}건, HTTP $code)")
                            return@withContext true
                        }
                        code in 400..499 -> {
                            // 4xx: 클라이언트 오류 — 재시도 없음
                            Log.w(tag, "전송 실패 (4xx $code) — 재시도 안함")
                            return@withContext false
                        }
                        else -> {
                            // 5xx: 서버 오류 — 재시도
                            Log.w(tag, "서버 오류 $code, 재시도 ${attempt + 1}/$maxAttempts")
                        }
                    }
                }
                else -> {
                    Log.w(tag, "네트워크 오류: ${result.exceptionOrNull()?.message}, 재시도 ${attempt + 1}/$maxAttempts")
                }
            }

            attempt++
            if (attempt < maxAttempts) {
                val delay = baseDelayMs * (1L shl (attempt - 1)) // 1s, 2s, 4s
                kotlinx.coroutines.delay(delay)
            }
        }

        Log.e(tag, "최대 재시도 초과 — 전송 포기 (${events.size}건)")
        false
    }

    /** HTTP POST 요청 수행. 응답 코드를 반환한다. */
    private fun postRequest(urlStr: String, body: String): Int {
        val connection = (URL(urlStr).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("x-api-key", config.apiKey)
        }
        try {
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                writer.write(body)
                writer.flush()
            }
            return connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    /** 이벤트 목록을 JSON 배열 문자열로 직렬화한다. */
    private fun buildBody(events: List<RumEvent>): String {
        val array = JSONArray()
        events.forEach { array.put(it.toJson()) }
        return array.toString()
    }
}
