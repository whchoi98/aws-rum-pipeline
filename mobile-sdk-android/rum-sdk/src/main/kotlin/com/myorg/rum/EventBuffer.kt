package com.myorg.rum

import android.util.Log
import com.myorg.rum.models.RumEvent
import kotlinx.coroutines.*

/**
 * 스레드 안전 이벤트 버퍼.
 *
 * - 이벤트 추가 시 배치 크기 초과 여부 확인 후 자동 플러시
 * - 코루틴 delay 를 이용한 주기적 타이머 플러시
 * - 전송 실패 시 재큐잉 (최대 500건 초과 시 드롭)
 * - 앱 백그라운드 진입 시 flushSync() 동기 플러시
 */
class EventBuffer(
    private val config: Config,
    private val transport: Transport,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
) {
    private val tag = "RumEventBuffer"

    /** 버퍼 최대 크기 */
    private val maxBufferSize = 500

    @Volatile private var buffer: ArrayDeque<RumEvent> = ArrayDeque()
    private val lock = Any()

    private var timerJob: Job? = null

    /** 타이머 플러시 시작 */
    fun startTimer() {
        timerJob?.cancel()
        timerJob = scope.launch {
            while (isActive) {
                delay(config.flushIntervalMs)
                flush()
            }
        }
    }

    /** 타이머 정지 */
    fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    /**
     * 이벤트를 버퍼에 추가한다.
     * 최대 크기 초과 시 가장 오래된 이벤트를 드롭하고 경고 로그를 남긴다.
     * 배치 크기에 도달하면 즉시 플러시를 트리거한다.
     */
    fun add(event: RumEvent) {
        val shouldFlush: Boolean
        synchronized(lock) {
            if (buffer.size >= maxBufferSize) {
                buffer.removeFirst()
                if (config.debug) Log.w(tag, "버퍼 초과 — 가장 오래된 이벤트 드롭")
            }
            buffer.addLast(event)
            shouldFlush = buffer.size >= config.maxBatchSize
        }
        if (shouldFlush) {
            scope.launch { flush() }
        }
    }

    /**
     * 버퍼의 이벤트를 비동기 플러시한다.
     * 전송 실패 시 이벤트를 버퍼 앞쪽에 재큐잉한다.
     */
    suspend fun flush() {
        val batch: List<RumEvent>
        synchronized(lock) {
            if (buffer.isEmpty()) return
            batch = buffer.toList()
            buffer.clear()
        }

        if (config.debug) Log.d(tag, "플러시 시작: ${batch.size}건")

        val success = transport.send(batch)
        if (!success) {
            // 전송 실패 — 버퍼 앞쪽에 재삽입 (오래된 것부터)
            synchronized(lock) {
                val space = maxBufferSize - buffer.size
                val requeue = if (batch.size <= space) batch else batch.takeLast(space)
                requeue.reversed().forEach { buffer.addFirst(it) }
                if (config.debug) Log.w(tag, "재큐잉: ${requeue.size}건")
            }
        }
    }

    /**
     * 동기 플러시 — 앱이 백그라운드로 전환될 때 호출한다.
     * 현재 코루틴 컨텍스트에서 블로킹 없이 suspend 방식으로 실행한다.
     */
    suspend fun flushSync() {
        flush()
    }

    /** 현재 버퍼 크기 (테스트 용도) */
    fun size(): Int = synchronized(lock) { buffer.size }

    /** 버퍼를 완전히 비운다 (테스트 용도) */
    fun clear() = synchronized(lock) { buffer.clear() }
}
