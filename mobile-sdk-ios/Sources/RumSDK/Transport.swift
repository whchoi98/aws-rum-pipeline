import Foundation

// MARK: - TransportError
/// Transport 레이어에서 발생할 수 있는 오류 타입
public enum TransportError: Error {
    /// HTTP 4xx 클라이언트 에러 (재시도 불필요)
    case clientError(Int)
    /// HTTP 5xx 서버 에러 (재시도 대상)
    case serverError(Int)
    /// 네트워크 레이어 오류
    case networkError(Error)
    /// 이벤트 직렬화(JSON 인코딩) 실패
    case encodingError(Error)
}

// MARK: - Transport
/// URLSession 기반 HTTP POST 전송 객체.
/// - 엔드포인트: `{endpoint}/v1/events`
/// - 헤더: Content-Type: application/json, x-api-key: {apiKey}
/// - 5xx 응답 시 지수 백오프(1s → 2s → 4s) 최대 3회 재시도
/// - 4xx 응답 시 즉시 실패 처리 (재시도 없음)
public final class Transport {

    // MARK: - Properties

    private let config: RumConfig
    private let session: URLSession

    /// 재시도 지연 간격(초) — 테스트에서 주입 가능
    var retryDelays: [TimeInterval] = [1, 2, 4]

    // MARK: - Init

    /// - Parameters:
    ///   - config: SDK 설정 (endpoint, apiKey 포함)
    ///   - session: URLSession (기본값: .shared, 테스트 시 mock 주입 가능)
    public init(config: RumConfig, session: URLSession = .shared) {
        self.config  = config
        self.session = session
    }

    // MARK: - Public API

    /// 이벤트 배열을 JSON 배열로 직렬화하여 POST 전송한다.
    /// 5xx 에러 시 최대 3회 재시도(지수 백오프)하며, 4xx는 즉시 콜백한다.
    ///
    /// - Parameters:
    ///   - events: 전송할 RUM 이벤트 배열
    ///   - completion: 성공/실패 콜백
    public func send(events: [RumEvent], completion: @escaping (Result<Void, TransportError>) -> Void) {
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(events)
        } catch {
            completion(.failure(.encodingError(error)))
            return
        }

        guard let url = buildURL() else {
            completion(.failure(.networkError(URLError(.badURL))))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.httpBody    = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")

        attemptSend(request: request, attemptsLeft: retryDelays.count + 1, delayIndex: 0, completion: completion)
    }

    // MARK: - Private

    private func buildURL() -> URL? {
        var base = config.endpoint
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: "\(base)/v1/events")
    }

    private func attemptSend(
        request: URLRequest,
        attemptsLeft: Int,
        delayIndex: Int,
        completion: @escaping (Result<Void, TransportError>) -> Void
    ) {
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }

            if let error {
                // 네트워크 에러는 재시도 대상
                if attemptsLeft > 1 {
                    self.scheduleRetry(
                        request: request,
                        attemptsLeft: attemptsLeft - 1,
                        delayIndex: delayIndex,
                        completion: completion
                    )
                } else {
                    completion(.failure(.networkError(error)))
                }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.networkError(URLError(.badServerResponse))))
                return
            }

            switch http.statusCode {
            case 200...299:
                completion(.success(()))
            case 400...499:
                // 4xx: 클라이언트 에러 — 재시도하지 않음
                completion(.failure(.clientError(http.statusCode)))
            case 500...599:
                // 5xx: 서버 에러 — 재시도
                if attemptsLeft > 1 {
                    self.scheduleRetry(
                        request: request,
                        attemptsLeft: attemptsLeft - 1,
                        delayIndex: delayIndex,
                        completion: completion
                    )
                } else {
                    completion(.failure(.serverError(http.statusCode)))
                }
            default:
                completion(.failure(.serverError(http.statusCode)))
            }
        }.resume()
    }

    private func scheduleRetry(
        request: URLRequest,
        attemptsLeft: Int,
        delayIndex: Int,
        completion: @escaping (Result<Void, TransportError>) -> Void
    ) {
        let delay = delayIndex < retryDelays.count ? retryDelays[delayIndex] : retryDelays.last ?? 4
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.attemptSend(
                request: request,
                attemptsLeft: attemptsLeft,
                delayIndex: delayIndex + 1,
                completion: completion
            )
        }
    }
}
