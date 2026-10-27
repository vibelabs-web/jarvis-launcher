import Combine
import Foundation

/// 녹음 중 파형 표시용 소리 크기 기록. 파형 뷰만 다시 그리도록 AppModel과 분리한다.
@MainActor
final class MicMeter: ObservableObject {
    static let count = 24  // 칩 줄 한 줄 안에 들어가는 폭(B21)
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: MicMeter.count)
    @Published private(set) var startedAt: Date?
    /// 최근 2초 동안 소리가 거의 없었는지(마이크가 안 들어오는지 알리기 위함)
    @Published private(set) var silent = false
    private var lastLoud = Date()

    func start() {
        levels = Array(repeating: 0, count: Self.count)
        startedAt = Date()
        lastLoud = Date()
        silent = false
    }

    func stop() { startedAt = nil; silent = false }

    func push(_ level: Float) {
        guard startedAt != nil else { return }
        levels.removeFirst()
        levels.append(level)
        if level > 0.15 { lastLoud = Date() }
        let quiet = Date().timeIntervalSince(lastLoud) > 2
        if quiet != silent { silent = quiet }
    }
}
