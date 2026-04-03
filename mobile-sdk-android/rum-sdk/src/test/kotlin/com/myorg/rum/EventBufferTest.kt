package com.myorg.rum

import com.myorg.rum.models.RumEvent
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * EventBuffer 단위 테스트.
 *
 * 테스트 항목:
 * 1. 배치 크기 도달 시 자동 플러시
 * 2. 타이머 주기 플러시
 * 3. 500건 초과 시 오래된 이벤트 드롭 (오버플로우)
 * 4. 전송 실패 시 이벤트 재큐잉
 * 5. flushSync() 즉시 플러시
 */
@OptIn(ExperimentalCoroutinesApi::class)
class EventBufferTest {

    private val testDispatcher = StandardTestDispatcher()
    private val testScope = TestScope(testDispatcher)

    private lateinit var config: Config
    private lateinit var fakeTransport: FakeTransport
    private lateinit var buffer: EventBuffer

    @Before
    fun setUp() {
        config = Config(
            endpoint = "https://test.example.com",
            apiKey = "test-key",
            appVersion = "1.0.0",
            flushIntervalMs = 5_000L,
            maxBatchSize = 3
        )
        fakeTransport = FakeTransport(shouldSucceed = true)
        buffer = EventBuffer(config, fakeTransport, testScope)
    }

    /** 테스트 1: 배치 크기(3) 도달 시 자동 플러시 트리거 */
    @Test
    fun `배치 크기 도달 시 자동 플러시`() = testScope.runTest {
        repeat(3) { buffer.add(makeEvent("e$it")) }
        advanceTimeBy(100) // 코루틴 launch 실행 기회 제공
        assertEquals("3건 전송 확인", 3, fakeTransport.sentEvents.size)
        assertEquals("버퍼 비워짐", 0, buffer.size())
    }

    /** 테스트 2: 타이머 주기(5초) 플러시 */
    @Test
    fun `타이머 주기 플러시`() = testScope.runTest {
        buffer.startTimer()
        buffer.add(makeEvent("timer-1"))
        buffer.add(makeEvent("timer-2"))

        // 5초 경과 전에는 아직 플러시 안 됨
        advanceTimeBy(4_999)
        assertEquals("5초 전 — 미전송", 0, fakeTransport.sentEvents.size)

        // 5초 경과 후 플러시
        advanceTimeBy(1_001)
        assertEquals("5초 후 — 2건 전송", 2, fakeTransport.sentEvents.size)

        buffer.stopTimer()
    }

    /** 테스트 3: 500건 초과 시 가장 오래된 이벤트 드롭 */
    @Test
    fun `오버플로우 시 오래된 이벤트 드롭`() = testScope.runTest {
        // 전송 실패 설정으로 버퍼가 쌓이게 함
        val failTransport = FakeTransport(shouldSucceed = false)
        val overflowBuffer = EventBuffer(
            config.copy(maxBatchSize = 1000), // 자동 플러시 비활성화
            failTransport,
            testScope
        )

        // maxBatchSize 를 크게 해 자동 플러시 없이 501건 추가
        val bigConfig = config.copy(maxBatchSize = 1000)
        val bigBuffer = EventBuffer(bigConfig, failTransport, testScope)

        repeat(501) { bigBuffer.add(makeEvent("ev$it")) }

        // 최대 500건 유지 확인
        assertTrue("500건 이하 유지", bigBuffer.size() <= 500)
    }

    /** 테스트 4: 전송 실패 시 이벤트 재큐잉 */
    @Test
    fun `전송 실패 시 재큐잉`() = testScope.runTest {
        val failTransport = FakeTransport(shouldSucceed = false)
        val failBuffer = EventBuffer(config, failTransport, testScope)

        failBuffer.add(makeEvent("retry-1"))
        failBuffer.add(makeEvent("retry-2"))
        failBuffer.flushSync()

        // 전송 실패 후 이벤트가 버퍼에 남아 있어야 함
        assertTrue("전송 실패 후 재큐잉됨", failBuffer.size() > 0)
    }

    /** 테스트 5: flushSync() 즉시 플러시 */
    @Test
    fun `flushSync 즉시 플러시`() = testScope.runTest {
        buffer.add(makeEvent("sync-1"))
        buffer.add(makeEvent("sync-2"))
        assertEquals("플러시 전 2건", 2, buffer.size())

        buffer.flushSync()

        assertEquals("flushSync 후 버퍼 비워짐", 0, buffer.size())
        assertEquals("2건 전송됨", 2, fakeTransport.sentEvents.size)
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

    /** 테스트용 가짜 Transport */
    class FakeTransport(private val shouldSucceed: Boolean) : Transport(
        Config(
            endpoint = "https://test.example.com",
            apiKey = "test-key",
            appVersion = "1.0.0"
        )
    ) {
        val sentEvents = mutableListOf<RumEvent>()

        override suspend fun send(events: List<RumEvent>): Boolean {
            return if (shouldSucceed) {
                sentEvents.addAll(events)
                true
            } else {
                false
            }
        }
    }
}
