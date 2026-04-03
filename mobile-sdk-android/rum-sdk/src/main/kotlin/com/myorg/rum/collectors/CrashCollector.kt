package com.myorg.rum.collectors

import android.util.Log
import com.myorg.rum.EventBuffer
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent

/**
 * 미처리 예외(크래시) 수집기.
 *
 * Thread.setDefaultUncaughtExceptionHandler 를 사용해 앱 크래시를 감지한다.
 * 기존 핸들러를 체이닝하여 시스템 동작(ANR 다이얼로그 등)을 유지한다.
 *
 * - event_type: "error"
 * - event_name: "crash"
 * - payload: exception 클래스명, 메시지, 스택 트레이스, 스레드 이름
 */
class CrashCollector(
    private val buffer: EventBuffer,
    private val sessionProvider: () -> String,
    private val userProvider: () -> String,
    private val deviceId: String,
    private val appVersion: String,
    private val screenNameProvider: () -> String,
    private val contextProvider: () -> RumContext
) {
    private val tag = "RumCrashCollector"
    private var previousHandler: Thread.UncaughtExceptionHandler? = null

    /** 크래시 수집을 시작한다. */
    fun start() {
        previousHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            handleCrash(thread, throwable)
        }
        Log.d(tag, "크래시 수집기 시작됨")
    }

    /** 크래시 수집을 중지하고 이전 핸들러를 복원한다. */
    fun stop() {
        Thread.setDefaultUncaughtExceptionHandler(previousHandler)
        previousHandler = null
    }

    private fun handleCrash(thread: Thread, throwable: Throwable) {
        try {
            val stackTrace = throwable.stackTrace
                .joinToString("\n") { "  at ${it.className}.${it.methodName}(${it.fileName}:${it.lineNumber})" }

            val event = RumEvent(
                sessionId = sessionProvider(),
                userId = userProvider(),
                deviceId = deviceId,
                timestamp = System.currentTimeMillis(),
                appVersion = appVersion,
                eventType = "error",
                eventName = "crash",
                payload = mapOf(
                    "exception_type" to (throwable::class.java.name ?: "Unknown"),
                    "message" to (throwable.message ?: ""),
                    "stack_trace" to stackTrace,
                    "thread_name" to thread.name
                ),
                context = contextProvider()
            )
            // flushSync 는 suspend 함수이므로 runBlocking 으로 동기 전송
            buffer.add(event)
            kotlinx.coroutines.runBlocking { buffer.flushSync() }
        } catch (e: Exception) {
            Log.e(tag, "크래시 이벤트 기록 실패", e)
        } finally {
            // 이전 핸들러로 체이닝 — 시스템 크래시 리포트 등 유지
            previousHandler?.uncaughtException(thread, throwable)
        }
    }
}
