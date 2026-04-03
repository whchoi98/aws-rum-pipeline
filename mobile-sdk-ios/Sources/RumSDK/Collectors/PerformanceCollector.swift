import Foundation

// MARK: - PerformanceCollector
/// 앱 시작 시간을 측정하는 수집기.
///
/// 프로세스 시작 시각(`processStartTime`)부터 첫 번째
/// `viewDidAppear` 시각까지의 경과 시간을 밀리초 단위로 기록한다.
///
/// 평가 기준:
/// - good            : < 1000 ms
/// - needs-improvement: 1000 ~ 2000 ms
/// - poor            : > 2000 ms
///
/// - event_type: "performance"
/// - event_name: "app_start"
/// - payload: value (ms, Int), rating (String)
public final class PerformanceCollector {

    // MARK: - Properties

    private let onEvent: (RumEvent) -> Void
    private let sessionId: String
    private let userId: String
    private let deviceId: String
    private let appVersion: String
    private let deviceInfo: DeviceInfo

    /// 앱 시작 이벤트가 이미 전송되었는지 여부 (한 번만 전송)
    private var didReportAppStart = false

    // MARK: - Init

    /// - Parameters:
    ///   - sessionId: 현재 세션 ID
    ///   - userId: 현재 사용자 ID
    ///   - deviceId: 디바이스 고유 ID
    ///   - appVersion: 앱 버전 문자열
    ///   - deviceInfo: 디바이스 환경 정보 공급자
    ///   - onEvent: 성능 이벤트 생성 시 호출되는 콜백
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

    /// ScreenCollector의 첫 화면 표시 시점에 호출하여 앱 시작 이벤트를 기록한다.
    /// 두 번째 이후 호출은 무시된다.
    public func recordAppStart() {
        guard !didReportAppStart else { return }
        didReportAppStart = true

        let startMs  = processStartMilliseconds()
        let nowMs    = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsed  = Int(nowMs - startMs)
        let rating   = appStartRating(ms: elapsed)

        let event = RumEvent(
            sessionId:  sessionId,
            userId:     userId,
            deviceId:   deviceId,
            timestamp:  nowMs,
            appVersion: appVersion,
            eventType:  .performance,
            eventName:  .appStart,
            payload: [
                "value":  AnyCodable(elapsed),
                "rating": AnyCodable(rating)
            ],
            context: RumContext(
                device:     deviceInfo.deviceInfoModel(),
                connection: deviceInfo.connectionInfoModel()
            )
        )
        onEvent(event)
    }

    // MARK: - Private

    /// 프로세스 시작 시각을 Unix 밀리초로 반환한다.
    /// `kinfo_proc.kp_proc.p_un.__p_starttime` 을 사용하며,
    /// 조회 실패 시 현재 시각을 반환한다.
    private func processStartMilliseconds() -> Int64 {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info        = kinfo_proc()
        var size        = MemoryLayout<kinfo_proc>.size

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else {
            return Int64(Date().timeIntervalSince1970 * 1000)
        }

        let startTimeSec = Int64(info.kp_proc.p_un.__p_starttime.tv_sec)
        let startTimeUsec = Int64(info.kp_proc.p_un.__p_starttime.tv_usec)
        return startTimeSec * 1000 + startTimeUsec / 1000
    }

    /// 앱 시작 시간에 따른 품질 등급을 반환한다.
    private func appStartRating(ms: Int) -> String {
        switch ms {
        case ..<1000:
            return "good"
        case 1000..<2000:
            return "needs-improvement"
        default:
            return "poor"
        }
    }
}
