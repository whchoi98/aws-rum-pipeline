import Foundation

// MARK: - RumEvent
/// Web SDK와 동일한 스키마를 사용하는 RUM 이벤트 모델.
/// 모든 플랫폼(웹/iOS)에서 동일한 JSON 구조를 보장한다.
public struct RumEvent: Codable {
    /// 세션 식별자 (UUID 문자열)
    public let sessionId: String
    /// 사용자 식별자 ("anonymous" 또는 "user_xxx")
    public let userId: String
    /// 디바이스 식별자 (UUID 문자열, 앱 재설치 시 갱신됨)
    public let deviceId: String
    /// 이벤트 발생 시각 (Unix 밀리초, Int64)
    public let timestamp: Int64
    /// 플랫폼 식별자 (항상 "ios")
    public let platform: String
    /// 앱 버전 문자열 (예: "2.1.0")
    public let appVersion: String
    /// 이벤트 종류 (performance | action | error | navigation | resource)
    public let eventType: RumEventType
    /// 이벤트 이름 (app_start | screen_load | frame_drop | crash | oom | screen_view | screen_transition | tap | swipe | scroll | fetch | xhr)
    public let eventName: RumEventName
    /// 이벤트별 추가 데이터 (자유형식 JSON 객체)
    public let payload: [String: AnyCodable]
    /// 이벤트 발생 시점의 컨텍스트 정보
    public let context: RumContext

    enum CodingKeys: String, CodingKey {
        case sessionId   = "session_id"
        case userId      = "user_id"
        case deviceId    = "device_id"
        case timestamp
        case platform
        case appVersion  = "app_version"
        case eventType   = "event_type"
        case eventName   = "event_name"
        case payload
        case context
    }

    public init(
        sessionId: String,
        userId: String,
        deviceId: String,
        timestamp: Int64,
        platform: String = "ios",
        appVersion: String,
        eventType: RumEventType,
        eventName: RumEventName,
        payload: [String: AnyCodable] = [:],
        context: RumContext
    ) {
        self.sessionId  = sessionId
        self.userId     = userId
        self.deviceId   = deviceId
        self.timestamp  = timestamp
        self.platform   = platform
        self.appVersion = appVersion
        self.eventType  = eventType
        self.eventName  = eventName
        self.payload    = payload
        self.context    = context
    }
}

// MARK: - RumEventType
/// Web SDK event_type 열거형 — 웹과 동일한 문자열 raw value 사용
public enum RumEventType: String, Codable {
    case performance
    case action
    case error
    case navigation
    case resource
}

// MARK: - RumEventName
/// Web SDK event_name 열거형 — 웹과 동일한 문자열 raw value 사용
public enum RumEventName: String, Codable {
    case appStart          = "app_start"
    case screenLoad        = "screen_load"
    case frameDrop         = "frame_drop"
    case crash
    case oom
    case screenView        = "screen_view"
    case screenTransition  = "screen_transition"
    case tap
    case swipe
    case scroll
    case fetch
    case xhr
}

// MARK: - RumContext
/// 이벤트 발생 시점의 환경 정보 컨테이너
public struct RumContext: Codable {
    /// URL (웹 호환용 필드, iOS에서는 딥링크 또는 빈 문자열)
    public let url: String
    /// 현재 화면 이름 (ViewController 클래스명 등)
    public let screenName: String
    /// 디바이스 하드웨어/소프트웨어 정보
    public let device: RumDeviceInfo
    /// 네트워크 연결 정보
    public let connection: RumConnectionInfo

    enum CodingKeys: String, CodingKey {
        case url
        case screenName = "screen_name"
        case device
        case connection
    }

    public init(
        url: String = "",
        screenName: String = "",
        device: RumDeviceInfo,
        connection: RumConnectionInfo
    ) {
        self.url        = url
        self.screenName = screenName
        self.device     = device
        self.connection = connection
    }
}

// MARK: - RumDeviceInfo
/// Web SDK context.device 필드와 동일한 구조
public struct RumDeviceInfo: Codable {
    /// OS 버전 문자열 (예: "iOS 17")
    public let os: String
    /// 브라우저 호환 필드 — iOS에서는 "Safari" 또는 "WKWebView"
    public let browser: String
    /// 디바이스 모델명 (예: "iPhone 15")
    public let model: String

    public init(os: String, browser: String, model: String) {
        self.os      = os
        self.browser = browser
        self.model   = model
    }
}

// MARK: - RumConnectionInfo
/// Web SDK context.connection 필드와 동일한 구조
public struct RumConnectionInfo: Codable {
    /// 연결 유형 (wifi | cellular | none | unknown)
    public let type: String
    /// 왕복 시간(ms)
    public let rtt: Int

    public init(type: String, rtt: Int = 0) {
        self.type = type
        self.rtt  = rtt
    }
}

// MARK: - AnyCodable
/// 자유형식 JSON 값을 Codable로 감싸는 타입 지우개(type-eraser).
/// payload 필드에 임의의 키-값 쌍을 넣을 수 있도록 한다.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codable = array.map { AnyCodable($0) }
            try container.encode(codable)
        case let dict as [String: Any]:
            let codable = dict.mapValues { AnyCodable($0) }
            try container.encode(codable)
        default:
            try container.encodeNil()
        }
    }
}
