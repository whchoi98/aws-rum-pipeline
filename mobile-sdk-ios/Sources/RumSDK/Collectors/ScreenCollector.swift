import UIKit
import ObjectiveC

// MARK: - ScreenCollector
/// UIViewController 스위즐링으로 화면 전환을 탐지하는 수집기.
///
/// `viewDidAppear(_:)` 를 후킹하여 매 화면 전환마다 RUM 이벤트를 생성한다.
/// - event_type: "navigation"
/// - event_name: "screen_view"
/// - payload: screen_name (ViewController 클래스명), transition_time (ms)
public final class ScreenCollector {

    // MARK: - Singleton reference for swizzled method access

    private static weak var current: ScreenCollector?

    // MARK: - Properties

    private let onEvent: (RumEvent) -> Void
    private let sessionId: String
    private let userId: String
    private let deviceId: String
    private let appVersion: String
    private let deviceInfo: DeviceInfo

    /// 이전 화면이 사라진 시각 — screen_transition 시간 측정용
    private var lastDisappearTime: Date?
    /// 마지막으로 기록된 화면 이름
    private(set) var currentScreenName: String = ""

    // MARK: - Init

    /// - Parameters:
    ///   - sessionId: 현재 세션 ID
    ///   - userId: 현재 사용자 ID
    ///   - deviceId: 디바이스 고유 ID
    ///   - appVersion: 앱 버전 문자열
    ///   - deviceInfo: 디바이스 환경 정보 공급자
    ///   - onEvent: 화면 전환 이벤트 생성 시 호출되는 콜백
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

    /// 스위즐링을 설치한다. SDK 초기화 직후 한 번만 호출해야 한다.
    public func start() {
        ScreenCollector.current = self
        ScreenCollector.swizzleViewDidAppear()
    }

    // MARK: - Swizzling

    /// `UIViewController.viewDidAppear(_:)` 를 한 번만 스위즐링한다.
    private static let swizzleViewDidAppear: () -> Void = {
        let original = #selector(UIViewController.viewDidAppear(_:))
        let swizzled = #selector(UIViewController.rum_viewDidAppear(_:))

        guard
            let originalMethod = class_getInstanceMethod(UIViewController.self, original),
            let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzled)
        else { return }

        let added = class_addMethod(
            UIViewController.self,
            original,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        if added {
            class_replaceMethod(
                UIViewController.self,
                swizzled,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    // MARK: - Internal callback from swizzled method

    /// 스위즐된 `viewDidAppear` 에서 호출된다.
    fileprivate static func didAppear(viewController: UIViewController) {
        guard let collector = ScreenCollector.current else { return }
        collector.record(viewController: viewController)
    }

    // MARK: - Private

    private func record(viewController: UIViewController) {
        let screenName = String(describing: type(of: viewController))
        let now        = Date()

        // 이전 화면 전환 소요 시간 계산
        var transitionMs: Int? = nil
        if let last = lastDisappearTime {
            transitionMs = Int(now.timeIntervalSince(last) * 1000)
        }
        lastDisappearTime = now
        currentScreenName = screenName

        let event = buildScreenViewEvent(screenName: screenName, transitionMs: transitionMs)
        onEvent(event)
    }

    private func buildScreenViewEvent(screenName: String, transitionMs: Int?) -> RumEvent {
        var payload: [String: AnyCodable] = [
            "screen_name": AnyCodable(screenName)
        ]
        if let ms = transitionMs {
            payload["transition_time"] = AnyCodable(ms)
        }

        return RumEvent(
            sessionId:  sessionId,
            userId:     userId,
            deviceId:   deviceId,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: appVersion,
            eventType:  .navigation,
            eventName:  .screenView,
            payload:    payload,
            context: RumContext(
                screenName: screenName,
                device:     deviceInfo.deviceInfoModel(),
                connection: deviceInfo.connectionInfoModel()
            )
        )
    }
}

// MARK: - UIViewController Extension (Swizzled Method)

extension UIViewController {
    /// 스위즐링 대상 메서드 — 런타임에 원본 `viewDidAppear(_:)` 와 교체된다.
    @objc func rum_viewDidAppear(_ animated: Bool) {
        // 스위즐링 후 이 호출은 원본 viewDidAppear 를 실행한다
        rum_viewDidAppear(animated)
        ScreenCollector.didAppear(viewController: self)
    }
}
