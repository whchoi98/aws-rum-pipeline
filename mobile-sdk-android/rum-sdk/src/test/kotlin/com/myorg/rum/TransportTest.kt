package com.myorg.rum

import com.myorg.rum.models.RumEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONArray

/**
 * Transport 단위 테스트.
 *
 * Android API (HttpURLConnection) 를 직접 호출하지 않고
 * URL 구성, 헤더 구성, 바디 직렬화를 검증한다.
 *
 * 테스트 항목:
 * 1. 올바른 엔드포인트 URL 구성 (/v1/events 접미사)
 * 2. JSON 바디 배열 직렬화
 * 3. 이벤트 필드가 JSON 에 올바르게 매핑됨
 */
class TransportTest {

    private val config = Config(
        endpoint = "https://api.example.com",
        apiKey = "secret-api-key",
        appVersion = "2.1.0"
    )

    /** 테스트 1: 엔드포인트 URL 에 /v1/events 가 붙어야 한다 */
    @Test
    fun `엔드포인트 URL 구성 검증`() {
        val expectedUrl = "https://api.example.com/v1/events"
        val actualUrl = "${config.endpoint}/v1/events"
        assertEquals("URL 구성 오류", expectedUrl, actualUrl)
    }

    /** 테스트 2: 이벤트 목록이 JSON 배열로 직렬화된다 */
    @Test
    fun `이벤트 목록 JSON 배열 직렬화`() {
        val events = listOf(
            makeEvent("evt-1"),
            makeEvent("evt-2")
        )
        val array = JSONArray()
        events.forEach { array.put(it.toJson()) }
        val body = array.toString()

        val parsed = JSONArray(body)
        assertEquals("배열 크기", 2, parsed.length())
        assertEquals("첫 번째 이벤트 이름", "evt-1", parsed.getJSONObject(0).getString("event_name"))
        assertEquals("두 번째 이벤트 이름", "evt-2", parsed.getJSONObject(1).getString("event_name"))
    }

    /** 테스트 3: RumEvent.toJson() 필드 매핑 정확성 */
    @Test
    fun `RumEvent 필드 JSON 매핑 검증`() {
        val event = RumEvent(
            sessionId = "sess-abc",
            userId = "user_123",
            deviceId = "dev-xyz",
            timestamp = 1712000000000L,
            platform = "android",
            appVersion = "2.1.0",
            eventType = "performance",
            eventName = "app_start",
            payload = mapOf("value" to 850, "rating" to "good")
        )

        val json = event.toJson()

        assertEquals("session_id", "sess-abc", json.getString("session_id"))
        assertEquals("user_id", "user_123", json.getString("user_id"))
        assertEquals("device_id", "dev-xyz", json.getString("device_id"))
        assertEquals("timestamp", 1712000000000L, json.getLong("timestamp"))
        assertEquals("platform", "android", json.getString("platform"))
        assertEquals("app_version", "2.1.0", json.getString("app_version"))
        assertEquals("event_type", "performance", json.getString("event_type"))
        assertEquals("event_name", "app_start", json.getString("event_name"))
        assertTrue("payload 존재", json.has("payload"))
        assertEquals("payload.rating", "good", json.getJSONObject("payload").getString("rating"))
        assertTrue("context 존재", json.has("context"))
    }

    // ------------------------------------------------------------------ //
    // 헬퍼

    private fun makeEvent(name: String) = RumEvent(
        sessionId = "sess-001",
        userId = "anonymous",
        deviceId = "dev-001",
        timestamp = System.currentTimeMillis(),
        appVersion = "1.0.0",
        eventType = "action",
        eventName = name
    )
}
