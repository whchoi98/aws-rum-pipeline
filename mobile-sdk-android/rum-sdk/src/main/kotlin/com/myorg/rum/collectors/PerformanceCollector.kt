package com.myorg.rum.collectors

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.util.Log
import com.myorg.rum.EventBuffer
import com.myorg.rum.models.ConnectionContext
import com.myorg.rum.models.DeviceContext
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent

/**
 * 앱 성능 수집기.
 *
 * 앱 시작 시간을 측정한다:
 * - Process.getStartElapsedRealtime() : 프로세스 시작 시점 (elapsedRealtime 기준)
 * - 첫 번째 onActivityResumed() 시각: 사용자가 첫 화면을 볼 수 있는 시점
 *
 * payload.rating 기준:
 * - good  : < 1000ms
 * - needs_improvement : < 2500ms
 * - poor  : >= 2500ms
 *
 * - event_type: "performance"
 * - event_name: "app_start"
 */
class PerformanceCollector(
    private val app: Application,
    private val buffer: EventBuffer,
    private val sessionProvider: () -> String,
    private val userProvider: () -> String,
    private val deviceId: String,
    private val appVersion: String,
    private val deviceContextProvider: () -> DeviceContext,
    private val connectionContextProvider: () -> ConnectionContext
) : Application.ActivityLifecycleCallbacks {

    private val tag = "RumPerfCollector"
    private var appStartReported = false

    /** 성능 수집을 시작한다. */
    fun start() {
        app.registerActivityLifecycleCallbacks(this)
        Log.d(tag, "성능 수집기 시작됨")
    }

    /** 성능 수집을 중지한다. */
    fun stop() {
        app.unregisterActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) {
        if (appStartReported) return
        appStartReported = true

        // 프로세스 시작부터 현재까지의 경과 시간
        val processStartElapsed = Process.getStartElapsedRealtime()
        val nowElapsed = SystemClock.elapsedRealtime()
        val durationMs = nowElapsed - processStartElapsed

        val rating = when {
            durationMs < 1_000  -> "good"
            durationMs < 2_500  -> "needs_improvement"
            else                -> "poor"
        }

        val event = RumEvent(
            sessionId = sessionProvider(),
            userId = userProvider(),
            deviceId = deviceId,
            timestamp = System.currentTimeMillis(),
            appVersion = appVersion,
            eventType = "performance",
            eventName = "app_start",
            payload = mapOf(
                "value" to durationMs,
                "rating" to rating
            ),
            context = RumContext(
                screenName = activity.javaClass.simpleName,
                device = deviceContextProvider(),
                connection = connectionContextProvider()
            )
        )
        buffer.add(event)
        Log.d(tag, "앱 시작 시간: ${durationMs}ms ($rating)")
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
