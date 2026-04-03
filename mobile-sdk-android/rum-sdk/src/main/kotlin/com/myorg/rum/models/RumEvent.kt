package com.myorg.rum.models

import org.json.JSONObject

/**
 * RUM 이벤트 데이터 모델.
 * 웹 SDK와 동일한 JSON 스키마를 사용한다.
 */
data class RumEvent(
    /** 세션 UUID */
    val sessionId: String,
    /** 사용자 식별자 (익명: "anonymous", 인증: "user_xxx") */
    val userId: String,
    /** 디바이스 UUID */
    val deviceId: String,
    /** 이벤트 발생 시각 (Unix epoch ms) */
    val timestamp: Long,
    /** 플랫폼 고정값 */
    val platform: String = "android",
    /** 앱 버전 */
    val appVersion: String,
    /** 이벤트 유형: performance | action | error | navigation | resource */
    val eventType: String,
    /** 이벤트 이름 */
    val eventName: String,
    /** 이벤트별 세부 데이터 */
    val payload: Map<String, Any> = emptyMap(),
    /** 공통 컨텍스트 */
    val context: RumContext = RumContext()
) {
    /** JSON 직렬화 */
    fun toJson(): JSONObject {
        return JSONObject().apply {
            put("session_id", sessionId)
            put("user_id", userId)
            put("device_id", deviceId)
            put("timestamp", timestamp)
            put("platform", platform)
            put("app_version", appVersion)
            put("event_type", eventType)
            put("event_name", eventName)
            put("payload", JSONObject(payload))
            put("context", context.toJson())
        }
    }

    companion object {
        /** JSON 역직렬화 */
        fun fromJson(json: JSONObject): RumEvent {
            val ctx = if (json.has("context")) RumContext.fromJson(json.getJSONObject("context"))
                      else RumContext()
            val payloadObj = if (json.has("payload")) json.getJSONObject("payload") else JSONObject()
            val payloadMap = mutableMapOf<String, Any>()
            payloadObj.keys().forEach { key -> payloadMap[key] = payloadObj.get(key) }
            return RumEvent(
                sessionId = json.getString("session_id"),
                userId = json.optString("user_id", "anonymous"),
                deviceId = json.getString("device_id"),
                timestamp = json.getLong("timestamp"),
                platform = json.optString("platform", "android"),
                appVersion = json.optString("app_version", ""),
                eventType = json.getString("event_type"),
                eventName = json.getString("event_name"),
                payload = payloadMap,
                context = ctx
            )
        }
    }
}

/**
 * 이벤트 공통 컨텍스트.
 */
data class RumContext(
    val url: String = "",
    val screenName: String = "",
    val device: DeviceContext = DeviceContext(),
    val connection: ConnectionContext = ConnectionContext()
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("url", url)
        put("screen_name", screenName)
        put("device", device.toJson())
        put("connection", connection.toJson())
    }

    companion object {
        fun fromJson(json: JSONObject): RumContext {
            val deviceJson = if (json.has("device")) json.getJSONObject("device") else JSONObject()
            val connJson = if (json.has("connection")) json.getJSONObject("connection") else JSONObject()
            return RumContext(
                url = json.optString("url", ""),
                screenName = json.optString("screen_name", ""),
                device = DeviceContext.fromJson(deviceJson),
                connection = ConnectionContext.fromJson(connJson)
            )
        }
    }
}

/**
 * 디바이스 정보 컨텍스트.
 */
data class DeviceContext(
    val os: String = "",
    val browser: String = "WebView",
    val model: String = ""
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("os", os)
        put("browser", browser)
        put("model", model)
    }

    companion object {
        fun fromJson(json: JSONObject): DeviceContext = DeviceContext(
            os = json.optString("os", ""),
            browser = json.optString("browser", "WebView"),
            model = json.optString("model", "")
        )
    }
}

/**
 * 네트워크 연결 컨텍스트.
 */
data class ConnectionContext(
    val type: String = "",
    val rtt: Int = 0
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("type", type)
        put("rtt", rtt)
    }

    companion object {
        fun fromJson(json: JSONObject): ConnectionContext = ConnectionContext(
            type = json.optString("type", ""),
            rtt = json.optInt("rtt", 0)
        )
    }
}
