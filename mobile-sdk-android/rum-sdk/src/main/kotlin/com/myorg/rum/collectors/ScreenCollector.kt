package com.myorg.rum.collectors

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import com.myorg.rum.EventBuffer
import com.myorg.rum.models.ConnectionContext
import com.myorg.rum.models.DeviceContext
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent

/**
 * 화면 전환 수집기.
 *
 * Application.ActivityLifecycleCallbacks 를 등록하여
 * onActivityResumed 시 화면 뷰 이벤트를 기록한다.
 * 직전 화면과의 전환 소요 시간도 payload 에 포함한다.
 *
 * - event_type: "navigation"
 * - event_name: "screen_view" | "screen_transition"
 */
class ScreenCollector(
    private val app: Application,
    private val buffer: EventBuffer,
    private val sessionProvider: () -> String,
    private val userProvider: () -> String,
    private val deviceId: String,
    private val appVersion: String,
    private val deviceContextProvider: () -> DeviceContext,
    private val connectionContextProvider: () -> ConnectionContext
) : Application.ActivityLifecycleCallbacks {

    private val tag = "RumScreenCollector"

    @Volatile var currentScreenName: String = ""
        private set

    private var previousScreenName: String = ""
    private var screenStartTimeMs: Long = 0L

    /** 화면 수집을 시작한다. */
    fun start() {
        app.registerActivityLifecycleCallbacks(this)
        Log.d(tag, "화면 수집기 시작됨")
    }

    /** 화면 수집을 중지한다. */
    fun stop() {
        app.unregisterActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) {
        val screenName = activity.javaClass.simpleName
        val now = System.currentTimeMillis()

        previousScreenName = currentScreenName
        currentScreenName = screenName

        val context = RumContext(
            screenName = screenName,
            device = deviceContextProvider(),
            connection = connectionContextProvider()
        )

        // 첫 화면이면 screen_view, 이후 전환이면 screen_transition 도 추가
        val eventName = if (previousScreenName.isEmpty()) "screen_view" else "screen_transition"
        val payload = mutableMapOf<String, Any>(
            "screen_name" to screenName
        )
        if (previousScreenName.isNotEmpty()) {
            payload["previous_screen"] = previousScreenName
            if (screenStartTimeMs > 0) {
                payload["transition_duration_ms"] = now - screenStartTimeMs
            }
        }

        buffer.add(
            RumEvent(
                sessionId = sessionProvider(),
                userId = userProvider(),
                deviceId = deviceId,
                timestamp = now,
                appVersion = appVersion,
                eventType = "navigation",
                eventName = eventName,
                payload = payload,
                context = context
            )
        )

        screenStartTimeMs = now
    }

    // 나머지 콜백은 사용하지 않음
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
