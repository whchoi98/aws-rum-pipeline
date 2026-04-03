import UIKit
import Network

// MARK: - DeviceInfo
/// 디바이스 모델명, OS 버전, 네트워크 연결 정보를 제공하는 유틸리티 클래스.
///
/// `NWPathMonitor` 를 사용하여 현재 연결 유형(wifi/cellular/none)을 추적한다.
public final class DeviceInfo {

    // MARK: - Properties

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.rum.sdk.DeviceInfo.monitor")
    private var currentPath: NWPath?

    // MARK: - Init

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Public API

    /// 현재 디바이스 정보를 `RumDeviceInfo` 모델로 반환한다.
    public func deviceInfoModel() -> RumDeviceInfo {
        RumDeviceInfo(
            os:      "iOS \(UIDevice.current.systemVersion)",
            browser: "Safari",
            model:   deviceModel()
        )
    }

    /// 현재 네트워크 연결 정보를 `RumConnectionInfo` 모델로 반환한다.
    public func connectionInfoModel() -> RumConnectionInfo {
        RumConnectionInfo(
            type: connectionType(),
            rtt:  0  // iOS에서는 RTT를 직접 측정하지 않음 (0으로 설정)
        )
    }

    // MARK: - Private

    /// 디바이스 모델명을 반환한다 (예: "iPhone15,2").
    /// 마케팅 이름으로의 변환은 별도 매핑 테이블 없이는 불가하므로 식별자를 그대로 사용한다.
    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(bitPattern: value)))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    /// 현재 네트워크 연결 유형 문자열을 반환한다.
    private func connectionType() -> String {
        guard let path = currentPath else { return "unknown" }
        if path.usesInterfaceType(.wifi)     { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.status == .unsatisfied       { return "none" }
        return "unknown"
    }
}
