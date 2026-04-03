import UIKit

// MARK: - RumSDK
/// iOS RUM SDK 진입점 싱글턴.
///
/// 사용 예시:
/// ```swift
/// let config = RumConfig(endpoint: "https://api.example.com",
///                        apiKey: "your-api-key",
///                        appVersion: "1.0.0")
/// RumSDK.shared.configure(config: config)
/// ```
public final class RumSDK {

    // MARK: - Singleton

    /// 전역 공유 인스턴스
    public static let shared = RumSDK()
    private init() {}

    // MARK: - Private State

    private var config: RumConfig?
    private var buffer: EventBuffer?
    private var transport: Transport?
    private var deviceInfo: DeviceInfo?

    // Collectors
    private var crashCollector:      CrashCollector?
    private var screenCollector:     ScreenCollector?
    private var performanceCollector: PerformanceCollector?
    private var actionCollector:     ActionCollector?

    // Session
    private var sessionId: String = UUID().uuidString
    private var userId:    String = "anonymous"
    private var deviceId:  String = Self.resolveDeviceId()

    private var isConfigured = false

    // MARK: - Configuration

    /// SDK를 초기화하고 모든 수집기를 시작한다.
    /// 앱 실행 직후(AppDelegate/SceneDelegate) 한 번만 호출해야 한다.
    ///
    /// - Parameter config: SDK 설정 객체
    public func configure(config: RumConfig) {
        guard !isConfigured else { return }
        isConfigured = true

        self.config     = config
        let info        = DeviceInfo()
        self.deviceInfo = info
        let xport       = Transport(config: config)
        self.transport  = xport
        let buf         = EventBuffer(config: config, transport: xport)
        self.buffer     = buf

        setupCollectors(config: config, deviceInfo: info, buffer: buf)
        registerBackgroundObservers()
    }

    // MARK: - User Management

    /// 현재 사용자 ID를 설정한다. 로그인/로그아웃 시 호출한다.
    ///
    /// - Parameter userId: 사용자 식별자 (로그아웃 시 "anonymous" 전달)
    public func setUser(userId: String) {
        self.userId    = userId
        self.sessionId = UUID().uuidString // 사용자 변경 시 세션 갱신
    }

    // MARK: - Custom Events

    /// 커스텀 이벤트를 기록한다.
    ///
    /// - Parameters:
    ///   - name: 이벤트 이름 (이미 정의된 `RumEventName` 외 커스텀 이름은 `.fetch` 등으로 래핑 권장)
    ///   - payload: 추가 데이터 딕셔너리
    public func addCustomEvent(name: RumEventName, payload: [String: AnyCodable] = [:]) {
        guard let config, let deviceInfo, let buffer else { return }
        let event = RumEvent(
            sessionId:  sessionId,
            userId:     userId,
            deviceId:   deviceId,
            timestamp:  Int64(Date().timeIntervalSince1970 * 1000),
            appVersion: config.appVersion,
            eventType:  .action,
            eventName:  name,
            payload:    payload,
            context: RumContext(
                device:     deviceInfo.deviceInfoModel(),
                connection: deviceInfo.connectionInfoModel()
            )
        )
        enqueue(event)
        _ = buffer  // suppress unused warning
    }

    // MARK: - Internal: Enqueue

    /// 샘플링 비율 적용 후 버퍼에 이벤트를 추가한다.
    func enqueue(_ event: RumEvent) {
        guard let config, let buffer else { return }
        guard Double.random(in: 0..<1) < config.sampleRate else { return }
        buffer.add(event)
    }

    // MARK: - Private: Collectors Setup

    private func setupCollectors(config: RumConfig, deviceInfo: DeviceInfo, buffer: EventBuffer) {
        let sid = sessionId
        let uid = userId
        let did = deviceId
        let ver = config.appVersion

        // Crash Collector
        let crash = CrashCollector(
            sessionId:  sid,
            userId:     uid,
            deviceId:   did,
            appVersion: ver,
            deviceInfo: deviceInfo
        ) { [weak self] event in self?.enqueue(event) }
        crash.start()
        crashCollector = crash

        // Performance Collector
        let perf = PerformanceCollector(
            sessionId:  sid,
            userId:     uid,
            deviceId:   did,
            appVersion: ver,
            deviceInfo: deviceInfo
        ) { [weak self] event in self?.enqueue(event) }
        performanceCollector = perf

        // Screen Collector (첫 화면 표시 시 앱 시작 시간도 기록)
        let screen = ScreenCollector(
            sessionId:  sid,
            userId:     uid,
            deviceId:   did,
            appVersion: ver,
            deviceInfo: deviceInfo
        ) { [weak self] event in
            self?.enqueue(event)
            self?.performanceCollector?.recordAppStart()
        }
        screen.start()
        screenCollector = screen

        // Action Collector
        let action = ActionCollector(
            sessionId:  sid,
            userId:     uid,
            deviceId:   did,
            appVersion: ver,
            deviceInfo: deviceInfo
        ) { [weak self] event in self?.enqueue(event) }
        action.start()
        actionCollector = action
    }

    // MARK: - Private: Background Flush

    private func registerBackgroundObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object:  nil,
            queue:   nil
        ) { [weak self] _ in self?.buffer?.flushSync() }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object:  nil,
            queue:   nil
        ) { [weak self] _ in self?.buffer?.flushSync() }
    }

    // MARK: - Private: Device ID Persistence

    /// UserDefaults에서 디바이스 ID를 불러오거나 새로 생성한다.
    private static func resolveDeviceId() -> String {
        let key = "com.rum.sdk.device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}
