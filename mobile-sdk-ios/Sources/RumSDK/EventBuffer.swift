import Foundation

// MARK: - EventBuffer
/// 스레드-세이프 이벤트 큐.
/// 배치 크기 도달 또는 타이머 만료 시 자동 플러시하며,
/// 전송 실패 시 이벤트를 재-큐잉한다. 최대 500개까지 보관한다.
public final class EventBuffer {

    // MARK: - Constants

    /// 버퍼에 보관할 수 있는 최대 이벤트 수
    private static let maxCapacity = 500

    // MARK: - Properties

    private var events: [RumEvent] = []
    private let queue = DispatchQueue(label: "com.rum.sdk.EventBuffer", attributes: .concurrent)
    private var flushTimer: DispatchSourceTimer?
    private let config: RumConfig
    private let transport: Transport

    // MARK: - Init

    /// - Parameters:
    ///   - config: SDK 설정 (배치 크기, 플러시 주기 포함)
    ///   - transport: 네트워크 전송 객체
    public init(config: RumConfig, transport: Transport) {
        self.config    = config
        self.transport = transport
        startFlushTimer()
    }

    deinit {
        flushTimer?.cancel()
    }

    // MARK: - Public API

    /// 이벤트를 버퍼에 추가한다.
    /// 버퍼가 최대 용량에 도달한 경우 가장 오래된 이벤트를 삭제하고 추가한다.
    /// 배치 크기 초과 시 비동기 플러시를 트리거한다.
    public func add(_ event: RumEvent) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if self.events.count >= Self.maxCapacity {
                self.events.removeFirst()
            }
            self.events.append(event)
            if self.events.count >= self.config.maxBatchSize {
                self.flush()
            }
        }
    }

    /// 버퍼를 비우고 비동기로 전송한다. (타이머·배치 트리거 사용)
    public func flush() {
        queue.async(flags: .barrier) { [weak self] in
            self?.performFlush()
        }
    }

    /// 앱이 백그라운드/종료될 때 동기적으로 즉시 전송한다.
    /// 최대 3초 대기 후 타임아웃한다.
    public func flushSync() {
        let semaphore = DispatchSemaphore(value: 0)
        queue.async(flags: .barrier) { [weak self] in
            guard let self, !self.events.isEmpty else {
                semaphore.signal()
                return
            }
            let batch = self.events
            self.events.removeAll()
            self.transport.send(events: batch) { result in
                if case .failure = result {
                    // 종료 직전이므로 재-큐잉하지 않음
                }
                semaphore.signal()
            }
        }
        semaphore.wait(timeout: .now() + 3)
    }

    // MARK: - Internal

    /// 현재 버퍼 이벤트 수 (테스트용)
    var count: Int {
        queue.sync { events.count }
    }

    // MARK: - Private

    private func performFlush() {
        guard !events.isEmpty else { return }
        let batch = events.prefix(config.maxBatchSize).map { $0 }
        events.removeFirst(min(batch.count, events.count))

        transport.send(events: batch) { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                // 전송 실패 시 이벤트를 큐 앞에 재삽입
                self.queue.async(flags: .barrier) {
                    let space = Self.maxCapacity - self.events.count
                    let requeue = Array(batch.prefix(space))
                    self.events.insert(contentsOf: requeue, at: 0)
                }
            }
        }
    }

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + config.flushInterval,
                       repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in
            self?.performFlush()
        }
        timer.resume()
        flushTimer = timer
    }
}
