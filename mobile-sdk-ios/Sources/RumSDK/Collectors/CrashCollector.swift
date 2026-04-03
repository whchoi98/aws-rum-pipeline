import Foundation

// MARK: - CrashCollector
/// 앱 충돌(크래시)을 탐지하여 RUM 이벤트로 기록하는 수집기.
///
/// 두 가지 메커니즘을 사용한다:
/// 1. `NSSetUncaughtExceptionHandler` — Objective-C 예외 처리
/// 2. `signal()` — SIGABRT, SIGSEGV, SIGBUS 유닉스 시그널 처리
///
/// - event_type: "error"
/// - event_name: "crash"
/// - payload: message (문자열), stack_trace (배열)
public final class CrashCollector {

    // MARK: - Singleton reference (static, for C callback access)

    /// C 핸들러에서 접근하기 위한 전역 약한 참조
    private static weak var current: CrashCollector?

    // MARK: - Properties

    private let onEvent: (RumEvent) -> Void
    private let sessionId: String
    private let userId: String
    private let deviceId: String
    private let appVersion: String
    private let deviceInfo: DeviceInfo

    // MARK: - Init

    /// - Parameters:
    ///   - sessionId: 현재 세션 ID
    ///   - userId: 현재 사용자 ID
    ///   - deviceId: 디바이스 고유 ID
    ///   - appVersion: 앱 버전 문자열
    ///   - deviceInfo: 디바이스 환경 정보 공급자
    ///   - onEvent: 크래시 이벤트 생성 시 호출되는 콜백
    public init(
        sessionId: String,
        userId: String,
        deviceId: String,
        appVersion: String,
        deviceInfo: DeviceInfo,
        onEvent: @escaping (RumEvent) -> Void
    ) {
        self.sessionId   = sessionId
        self.userId      = userId
        self.deviceId    = deviceId
        self.appVersion  = appVersion
        self.deviceInfo  = deviceInfo
        self.onEvent     = onEvent
    }

    // MARK: - Public API

    /// 크래시 핸들러를 등록한다. SDK 초기화 직후 한 번만 호출해야 한다.
    public func start() {
        CrashCollector.current = self
        installExceptionHandler()
        installSignalHandlers()
    }

    // MARK: - Event Building

    /// 크래시 RUM 이벤트를 생성하여 콜백으로 전달한다.
    fileprivate func handleCrash(message: String, stackTrace: [String]) {
        let event = buildCrashEvent(message: message, stackTrace: stackTrace)
        onEvent(event)
    }

    private func buildCrashEvent(message: String, stackTrace: [String]) -> RumEvent {
        RumEvent(
            sessionId:  sessionId,
            userId:     userId,
            deviceId:   deviceId,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: appVersion,
            eventType:  .error,
            eventName:  .crash,
            payload: [
                "message":     AnyCodable(message),
                "stack_trace": AnyCodable(stackTrace)
            ],
            context: RumContext(
                device:     deviceInfo.deviceInfoModel(),
                connection: deviceInfo.connectionInfoModel()
            )
        )
    }

    // MARK: - Private: Exception Handler

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            guard let collector = CrashCollector.current else { return }
            let message    = exception.reason ?? exception.name.rawValue
            let stackTrace = exception.callStackSymbols
            collector.handleCrash(message: message, stackTrace: stackTrace)
        }
    }

    // MARK: - Private: Signal Handlers

    private func installSignalHandlers() {
        let signals = [SIGABRT, SIGSEGV, SIGBUS]
        for sig in signals {
            signal(sig) { signum in
                guard let collector = CrashCollector.current else { return }
                let name       = CrashCollector.signalName(signum)
                let stackTrace = Thread.callStackSymbols
                collector.handleCrash(message: "Signal \(name) (\(signum))", stackTrace: stackTrace)
            }
        }
    }

    private static func signalName(_ signum: Int32) -> String {
        switch signum {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS:  return "SIGBUS"
        default:      return "SIG\(signum)"
        }
    }
}
