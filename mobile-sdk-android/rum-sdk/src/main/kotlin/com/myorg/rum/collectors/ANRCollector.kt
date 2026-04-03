package com.myorg.rum.collectors

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.myorg.rum.EventBuffer
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * ANR(Application Not Responding) 감지 수집기.
 *
 * 메인 스레드 워치독 패턴:
 * 1. 백그라운드 루프에서 메인 핸들러에 Runnable 을 post 한다.
 * 2. 5초 이내에 실행되지 않으면 ANR 로 판단한다.
 * 3. 메인 스레드 스택 트레이스를 캡처해 이벤트로 기록한다.
 *
 * - event_type: "error"
 * - event_name: "anr"
 */
class ANRCollector(
    private val buffer: EventBuffer,
    private val sessionProvider: () -> String,
    private val userProvider: () -> String,
    private val deviceId: String,
    private val appVersion: String,
    private val contextProvider: () -> RumContext,
    private val anrThresholdMs: Long = 5_000L
) {
    private val tag = "RumANRCollector"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var watchdogJob: Job? = null

    /** ANR 워치독을 시작한다. */
    fun start() {
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            while (isActive) {
                var executed = false
                mainHandler.post { executed = true }
                delay(anrThresholdMs)
                if (!executed) {
                    reportAnr()
                }
                // 다음 체크 전 짧은 대기
                delay(1_000L)
            }
        }
        Log.d(tag, "ANR 워치독 시작됨 (임계값 ${anrThresholdMs}ms)")
    }

    /** ANR 워치독을 중지한다. */
    fun stop() {
        watchdogJob?.cancel()
        watchdogJob = null
    }

    private fun reportAnr() {
        val mainThread = Looper.getMainLooper().thread
        val stackTrace = mainThread.stackTrace
            .joinToString("\n") { "  at ${it.className}.${it.methodName}(${it.fileName}:${it.lineNumber})" }

        val event = RumEvent(
            sessionId = sessionProvider(),
            userId = userProvider(),
            deviceId = deviceId,
            timestamp = System.currentTimeMillis(),
            appVersion = appVersion,
            eventType = "error",
            eventName = "anr",
            payload = mapOf(
                "threshold_ms" to anrThresholdMs,
                "thread_name" to mainThread.name,
                "stack_trace" to stackTrace
            ),
            context = contextProvider()
        )
        buffer.add(event)
        Log.w(tag, "ANR 감지됨 — 이벤트 기록")
    }
}
