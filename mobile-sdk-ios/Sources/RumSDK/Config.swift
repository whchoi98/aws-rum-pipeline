import Foundation

// MARK: - RumConfig
/// RUM SDK 초기화에 필요한 설정값 컨테이너.
/// `RumSDK.shared.configure(config:)` 호출 시 전달한다.
public struct RumConfig {
    /// 이벤트를 전송할 API 엔드포인트 (예: "https://api.example.com")
    public let endpoint: String

    /// API Gateway에서 요구하는 인증 키 (x-api-key 헤더)
    public let apiKey: String

    /// 앱 버전 문자열 (예: "2.1.0")
    public let appVersion: String

    /// 이벤트 샘플링 비율 (0.0 ~ 1.0, 기본값 1.0 = 100% 수집)
    public let sampleRate: Double

    /// 버퍼에 쌓인 이벤트를 주기적으로 플러시하는 간격 (초, 기본값 30)
    public let flushInterval: TimeInterval

    /// 한 번에 전송할 최대 이벤트 수 (기본값 10)
    public let maxBatchSize: Int

    /// - Parameters:
    ///   - endpoint: 수집 API 엔드포인트 URL 문자열
    ///   - apiKey: API 인증 키
    ///   - appVersion: 앱 버전 (CFBundleShortVersionString 등)
    ///   - sampleRate: 샘플링 비율 (기본값 1.0)
    ///   - flushInterval: 플러시 주기(초, 기본값 30)
    ///   - maxBatchSize: 배치 최대 크기 (기본값 10)
    public init(
        endpoint: String,
        apiKey: String,
        appVersion: String,
        sampleRate: Double = 1.0,
        flushInterval: TimeInterval = 30,
        maxBatchSize: Int = 10
    ) {
        self.endpoint      = endpoint
        self.apiKey        = apiKey
        self.appVersion    = appVersion
        self.sampleRate    = min(max(sampleRate, 0.0), 1.0)
        self.flushInterval = flushInterval
        self.maxBatchSize  = maxBatchSize
    }
}
