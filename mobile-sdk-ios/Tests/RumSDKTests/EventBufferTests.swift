import XCTest
@testable import RumSDK

// MARK: - MockTransport
/// 테스트용 Transport 대역(mock) — 실제 네트워크 호출 없이 결과를 제어한다.
final class MockTransport: Transport {

    var sentBatches: [[RumEvent]] = []
    var resultToReturn: Result<Void, TransportError> = .success(())
    var sendCallCount = 0

    override func send(events: [RumEvent], completion: @escaping (Result<Void, TransportError>) -> Void) {
        sendCallCount += 1
        sentBatches.append(events)
        completion(resultToReturn)
    }
}

// MARK: - EventBufferTests

/// EventBuffer 동작을 검증하는 단위 테스트 모음
final class EventBufferTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(maxBatchSize: Int = 10, flushInterval: TimeInterval = 60) -> RumConfig {
        RumConfig(
            endpoint:      "https://example.com",
            apiKey:        "test-key",
            appVersion:    "1.0.0",
            sampleRate:    1.0,
            flushInterval: flushInterval,
            maxBatchSize:  maxBatchSize
        )
    }

    private func makeEvent(name: RumEventName = .tap) -> RumEvent {
        RumEvent(
            sessionId:  UUID().uuidString,
            userId:     "anonymous",
            deviceId:   UUID().uuidString,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: "1.0.0",
            eventType:  .action,
            eventName:  name,
            context:    RumContext(
                device:     RumDeviceInfo(os: "iOS 17", browser: "Safari", model: "iPhone15,2"),
                connection: RumConnectionInfo(type: "wifi")
            )
        )
    }

    // MARK: - Test 1: 배치 크기 도달 시 자동 플러시

    /// maxBatchSize개 이벤트를 추가하면 자동으로 transport.send 가 호출된다.
    func testFlushOnBatchSizeReached() {
        let transport = MockTransport(config: makeConfig(maxBatchSize: 3), session: .shared)
        let buffer    = EventBuffer(config: makeConfig(maxBatchSize: 3), transport: transport)

        buffer.add(makeEvent())
        buffer.add(makeEvent())
        buffer.add(makeEvent())  // 3번째 — flush 트리거

        let expectation = XCTestExpectation(description: "flush called")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if transport.sendCallCount >= 1 {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2)
        XCTAssertGreaterThanOrEqual(transport.sendCallCount, 1)
    }

    // MARK: - Test 2: 수동 flushSync 호출

    /// `flushSync()` 를 호출하면 버퍼의 이벤트가 즉시 전송되고 버퍼가 비워진다.
    func testFlushSyncSendsAllEvents() {
        let transport = MockTransport(config: makeConfig(), session: .shared)
        let buffer    = EventBuffer(config: makeConfig(maxBatchSize: 100), transport: transport)

        buffer.add(makeEvent())
        buffer.add(makeEvent())
        buffer.add(makeEvent())

        buffer.flushSync()

        XCTAssertEqual(transport.sendCallCount, 1)
        XCTAssertEqual(transport.sentBatches.first?.count, 3)
        XCTAssertEqual(buffer.count, 0)
    }

    // MARK: - Test 3: 버퍼 오버플로우 — 최대 500개 유지

    /// 500개 초과 이벤트를 추가하면 가장 오래된 이벤트가 삭제되어 500개를 초과하지 않는다.
    func testBufferCapCappedAt500() {
        // flushInterval을 매우 크게 설정하여 타이머 플러시 방지
        // maxBatchSize도 크게 설정하여 배치 플러시 방지
        let config    = RumConfig(
            endpoint: "https://example.com",
            apiKey: "key",
            appVersion: "1.0.0",
            sampleRate: 1.0,
            flushInterval: 9999,
            maxBatchSize: 9999
        )
        let transport = MockTransport(config: config, session: .shared)
        let buffer    = EventBuffer(config: config, transport: transport)

        // 510개 추가 — 플러시 없이 500개 상한 유지 확인
        for _ in 0..<510 {
            buffer.add(makeEvent())
        }

        // 배리어 큐 작업 완료 대기
        let expectation = XCTestExpectation(description: "barrier settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        XCTAssertLessThanOrEqual(buffer.count, 500)
    }

    // MARK: - Test 4: 전송 실패 시 이벤트 재-큐잉

    /// transport 가 실패를 반환하면 이벤트가 버퍼에 재삽입된다.
    func testRequeueOnFailure() {
        let config    = RumConfig(
            endpoint: "https://example.com",
            apiKey: "key",
            appVersion: "1.0.0",
            sampleRate: 1.0,
            flushInterval: 9999,
            maxBatchSize: 2
        )
        let transport = MockTransport(config: config, session: .shared)
        transport.resultToReturn = .failure(.serverError(500))
        let buffer = EventBuffer(config: config, transport: transport)

        buffer.add(makeEvent())
        buffer.add(makeEvent())  // 배치 크기 도달 → flush → 실패 → 재-큐잉

        let expectation = XCTestExpectation(description: "requeue settled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        // 실패 후 이벤트가 재-큐잉 되어 버퍼가 비어있지 않아야 한다
        XCTAssertGreaterThan(buffer.count, 0)
    }

    // MARK: - Test 5: flushSync 이후 버퍼가 비어 있음

    /// `flushSync()` 호출 후 이벤트가 없으면 transport는 호출되지 않는다.
    func testFlushSyncEmptyBuffer() {
        let transport = MockTransport(config: makeConfig(), session: .shared)
        let buffer    = EventBuffer(config: makeConfig(), transport: transport)

        buffer.flushSync()

        XCTAssertEqual(transport.sendCallCount, 0, "빈 버퍼에서 flushSync는 transport를 호출하지 않아야 한다")
        XCTAssertEqual(buffer.count, 0)
    }

    // MARK: - Test 6: 배치 분할 전송

    /// maxBatchSize=2, 5개 이벤트 추가 시 여러 배치로 나누어 전송된다.
    func testBatchSplitting() {
        let config = RumConfig(
            endpoint: "https://example.com",
            apiKey: "key",
            appVersion: "1.0.0",
            sampleRate: 1.0,
            flushInterval: 9999,
            maxBatchSize: 2
        )
        let transport = MockTransport(config: config, session: .shared)
        let buffer    = EventBuffer(config: config, transport: transport)

        for _ in 0..<5 {
            buffer.add(makeEvent())
        }

        let expectation = XCTestExpectation(description: "batches sent")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)

        // 최소 2회 이상 전송 호출 (5개 / 배치2 = 최소 2배치)
        XCTAssertGreaterThanOrEqual(transport.sendCallCount, 2)
    }
}
