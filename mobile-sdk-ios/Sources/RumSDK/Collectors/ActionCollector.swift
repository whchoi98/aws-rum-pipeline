import UIKit
import ObjectiveC

// MARK: - ActionCollector
/// UIApplication.sendEvent 스위즐링으로 탭(터치) 이벤트를 수집하는 수집기.
///
/// UITouchPhaseBegan 단계의 터치만 기록하여 중복 이벤트를 방지한다.
/// - event_type: "action"
/// - event_name: "tap"
/// - payload: target_class (터치된 뷰 클래스명), accessibility_label (접근성 레이블)
public final class ActionCollector {

    // MARK: - Singleton reference for swizzled method access

    private static weak var current: ActionCollector?

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
    ///   - onEvent: 탭 이벤트 생성 시 호출되는 콜백
    public init(
        sessionId: String,
        userId: String,
        deviceId: String,
        appVersion: String,
        deviceInfo: DeviceInfo,
        onEvent: @escaping (RumEvent) -> Void
    ) {
        self.sessionId  = sessionId
        self.userId     = userId
        self.deviceId   = deviceId
        self.appVersion = appVersion
        self.deviceInfo = deviceInfo
        self.onEvent    = onEvent
    }

    // MARK: - Public API

    /// sendEvent 스위즐링을 설치한다. SDK 초기화 직후 한 번만 호출해야 한다.
    public func start() {
        ActionCollector.current = self
        ActionCollector.swizzleSendEvent()
    }

    // MARK: - Swizzling

    /// `UIApplication.sendEvent(_:)` 를 한 번만 스위즐링한다.
    private static let swizzleSendEvent: () -> Void = {
        let original = #selector(UIApplication.sendEvent(_:))
        let swizzled = #selector(UIApplication.rum_sendEvent(_:))

        guard
            let originalMethod = class_getInstanceMethod(UIApplication.self, original),
            let swizzledMethod = class_getInstanceMethod(UIApplication.self, swizzled)
        else { return }

        let added = class_addMethod(
            UIApplication.self,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        if added {
            class_replaceMethod(
                UIApplication.self,
                swizzled,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // MARK: - Internal callback from swizzled method

    /// 스위즐된 `sendEvent` 에서 터치 시작 이벤트를 처리한다.
    fileprivate static func handleEvent(_ event: UIEvent) {
        guard
            let collector = ActionCollector.current,
            event.type == .touches
        else { return }

        for touch in event.allTouches ?? [] {
            guard touch.phase == .began else { continue }
            let targetClass       = String(describing: type(of: touch.view as Any))
            let accessibilityLabel = (touch.view as? UIView)?.accessibilityLabel ?? ""
            collector.record(targetClass: targetClass, accessibilityLabel: accessibilityLabel)
        }
    }

    // MARK: - Private

    private func record(targetClass: String, accessibilityLabel: String) {
        let event = RumEvent(
            sessionId:  sessionId,
            userId:     userId,
            deviceId:   deviceId,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: appVersion,
            eventType:  .action,
            eventName:  .tap,
            payload: [
                "target_class":       AnyCodable(targetClass),
                "accessibility_label": AnyCodable(accessibilityLabel)
            ],
            context: RumContext(
                device:     deviceInfo.deviceInfoModel(),
                connection: deviceInfo.connectionInfoModel()
            )
        )
        onEvent(event)
    }
}

// MARK: - UIApplication Extension (Swizzled Method)

extension UIApplication {
    /// 스위즐링 대상 메서드 — 런타임에 원본 `sendEvent(_:)` 와 교체된다.
    @objc func rum_sendEvent(_ event: UIEvent) {
        // 스위즐링 후 이 호출은 원본 sendEvent 를 실행한다
        rum_sendEvent(event)
        ActionCollector.handleEvent(event)
    }
}
