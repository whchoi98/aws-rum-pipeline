import XCTest
@testable import RumSDK

// MARK: - MockURLProtocol
/// URLSession 요청을 가로채는 테스트용 URLProtocol.
/// `responseProvider` 클로저에서 원하는 HTTP 응답을 반환한다.
final class MockURLProtocol: URLProtocol {

    static var responseProvider: ((URLRequest) -> (HTTPURLResponse?, Data?, Error?)) = { _ in
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        return (response, Data(), nil)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (response, data, error) = MockURLProtocol.responseProvider(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if let data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - TransportTests

/// Transport 레이어의 URL 구성, 헤더, 재시도 로직을 검증하는 단위 테스트 모음
final class TransportTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(endpoint: String = "https://api.example.com",
                            apiKey: String = "test-api-key") -> RumConfig {
        RumConfig(endpoint: endpoint, apiKey: apiKey, appVersion: "1.0.0")
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeEvent() -> RumEvent {
        RumEvent(
            sessionId:  UUID().uuidString,
            userId:     "anonymous",
            deviceId:   UUID().uuidString,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: "1.0.0",
            eventType:  .action,
            eventName:  .tap,
            context:    RumContext(
                device:     RumDeviceInfo(os: "iOS 17", browser: "Safari", model: "iPhone15,2"),
                connection: RumConnectionInfo(type: "wifi")
            )
        )
    }

    // MARK: - Test 1: URL 구성 — /v1/events 경로 포함 여부

    /// endpoint 에 `/v1/events` 경로가 올바르게 붙는지 검증한다.
    func testURLConstruction() {
        var capturedRequest: URLRequest?

        MockURLProtocol.responseProvider = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (response, Data(), nil)
        }

        let config    = makeConfig(endpoint: "https://api.example.com")
        let transport = Transport(config: config, session: makeMockSession())
        transport.retryDelays = []  // 재시도 비활성화

        let expectation = XCTestExpectation(description: "request sent")
        transport.send(events: [makeEvent()]) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(capturedRequest?.url?.path, "/v1/events")
        XCTAssertEqual(capturedRequest?.url?.host, "api.example.com")
    }

    // MARK: - Test 2: 요청 헤더 검증

    /// Content-Type 및 x-api-key 헤더가 올바르게 설정되는지 검증한다.
    func testRequestHeaders() {
        var capturedRequest: URLRequest?

        MockURLProtocol.responseProvider = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (response, Data(), nil)
        }

        let apiKey    = "super-secret-key"
        let config    = makeConfig(apiKey: apiKey)
        let transport = Transport(config: config, session: makeMockSession())
        transport.retryDelays = []

        let expectation = XCTestExpectation(description: "request sent")
        transport.send(events: [makeEvent()]) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "x-api-key"), apiKey)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
    }

    // MARK: - Test 3: 5xx 응답 시 재시도 로직

    /// 5xx 응답 시 지정된 재시도 횟수만큼 재시도 후 실패를 반환한다.
    func testRetryOn5xxError() {
        var callCount = 0

        MockURLProtocol.responseProvider = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )
            return (response, Data(), nil)
        }

        let config    = makeConfig()
        let transport = Transport(config: config, session: makeMockSession())
        // 재시도 지연을 0으로 설정하여 테스트 속도 향상
        transport.retryDelays = [0.01, 0.01, 0.01]

        var finalResult: Result<Void, TransportError>?
        let expectation = XCTestExpectation(description: "all retries done")

        transport.send(events: [makeEvent()]) { result in
            finalResult = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        // 초기 시도 1회 + 재시도 3회 = 총 4회
        XCTAssertEqual(callCount, 4, "초기 1회 + 재시도 3회 = 총 4회 호출되어야 한다")

        if case .failure(let error) = finalResult,
           case .serverError(let code) = error {
            XCTAssertEqual(code, 503)
        } else {
            XCTFail("5xx 응답은 .failure(.serverError)를 반환해야 한다")
        }
    }

    // MARK: - Test 4: 4xx 응답 시 즉시 실패 (재시도 없음)

    /// 4xx 응답 시 재시도 없이 즉시 `.failure(.clientError)` 를 반환한다.
    func testNoRetryOn4xxError() {
        var callCount = 0

        MockURLProtocol.responseProvider = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )
            return (response, Data(), nil)
        }

        let config    = makeConfig()
        let transport = Transport(config: config, session: makeMockSession())
        transport.retryDelays = [0.01, 0.01, 0.01]

        var finalResult: Result<Void, TransportError>?
        let expectation = XCTestExpectation(description: "4xx no retry")

        transport.send(events: [makeEvent()]) { result in
            finalResult = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(callCount, 1, "4xx 응답은 재시도 없이 1회 호출만 이루어져야 한다")

        if case .failure(let error) = finalResult,
           case .clientError(let code) = error {
            XCTAssertEqual(code, 401)
        } else {
            XCTFail("4xx 응답은 .failure(.clientError)를 반환해야 한다")
        }
    }

    // MARK: - Test 5: 200 응답 시 성공 반환

    /// 200 응답 시 `.success(())` 를 반환하고 1회만 호출된다.
    func testSuccessOn200() {
        var callCount = 0

        MockURLProtocol.responseProvider = { request in
            callCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
            return (response, Data(), nil)
        }

        let config    = makeConfig()
        let transport = Transport(config: config, session: makeMockSession())
        transport.retryDelays = []

        var finalResult: Result<Void, TransportError>?
        let expectation = XCTestExpectation(description: "200 success")

        transport.send(events: [makeEvent()]) { result in
            finalResult = result
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)

        XCTAssertEqual(callCount, 1)
        if case .success = finalResult { } else {
            XCTFail("200 응답은 .success를 반환해야 한다")
        }
    }
}
