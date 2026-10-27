import Foundation

public enum GuardFailure: Error, Equatable, LocalizedError {
    case terminalGone
    case incarnationChanged
    case pathChanged(String)
    case hostChanged(String)
    case notClaude
    case notWritable
    case screen(String)
    case lookupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .terminalGone: return "대상 터미널이 더 이상 없습니다"
        case .incarnationChanged: return "터미널 프로세스가 바뀌었습니다(재시작됨). 대상을 다시 확인해 주세요"
        case .pathChanged(let p): return "대상 터미널의 폴더가 바뀌었습니다: \(p)"
        case .hostChanged(let h): return "대상 터미널의 호스트가 바뀌었습니다: \(h)"
        case .notClaude: return "대상 터미널에서 Claude Code가 실행 중이 아닙니다"
        case .notWritable: return "대상 터미널에 입력할 수 없습니다(연결 끊김/분리)"
        case .screen(let s): return "Claude가 입력을 받을 수 없는 상태입니다: \(s)"
        case .lookupFailed(let m): return "전송 전 재확인 실패: \(m)"
        }
    }
}

/// 전송 직전 재검증(PRD 5.5 절대 규칙, FR-08). 하나라도 어긋나면 보내지 않는다.
public enum SendGuard {
    public static func validate(expected: TargetSnapshot, current: TerminalCandidate, screen: [String],
                                canonicalize: (String) -> String = PathTools.canonical) -> GuardFailure? {
        if let e = expected.incarnationId, current.incarnationId != e { return .incarnationChanged }
        guard let path = current.worktreePath else { return .pathChanged("알 수 없음") }
        let cp = canonicalize(path)
        if cp != expected.canonicalPath { return .pathChanged(cp) }
        guard let host = current.executionHostId, host == expected.hostId, host == "local" else {
            return .hostChanged(current.executionHostId ?? "알 수 없음")
        }
        guard current.isClaude || ScreenClassifier.looksLikeClaude(screen) else { return .notClaude }
        guard current.connected == true, current.writable == true else { return .notWritable }
        switch ScreenClassifier.classify(screen) {
        case .ready: return nil
        case .dialog(let d): return .screen("화면에 대화상자/질문이 떠 있습니다 — \(d)")
        case .notClaude: return .notClaude
        case .unknown: return .screen("화면 상태를 판정하지 못했습니다")
        }
    }
}

public enum DeliveryOutcome: Equatable, Sendable {
    /// Claude 턴 시작까지 관찰됨 → "터미널에 전달됨"
    case delivered(requestId: String?)
    /// 입력은 수락됐지만 제출 관찰 실패, 또는 응답 누락/타임아웃 → 자동 재전송 금지
    case unknown(requestId: String?, reason: String)
    /// 전송 전 차단(전송 0회)
    case blocked(GuardFailure)
    case failed(String)
    /// 같은 프로젝트로 이미 전송 중
    case rejectedDuplicate

    public var label: String {
        switch self {
        case .delivered: return "터미널에 전달됨"
        case .unknown: return "전송 여부 불명"
        case .blocked: return "전송 차단"
        case .failed: return "실패"
        case .rejectedDuplicate: return "이미 전송 중"
        }
    }

    public static func from(receipt: SendReceipt) -> DeliveryOutcome {
        if receipt.stages.contains("turn_started") { return .delivered(requestId: receipt.requestId) }
        if receipt.accepted {
            return .unknown(requestId: receipt.requestId, reason: "입력은 수락됐지만 Claude의 처리 시작을 확인하지 못했습니다")
        }
        return .failed("Orca가 입력을 수락하지 않았습니다")
    }
}

/// 재검증 → 직렬 1회 전송 → 결과 기록. 자동 재시도 없음.
public actor DispatchCoordinator {
    private let orca: OrcaAdapter
    private var inFlight: Set<UUID> = []
    public private(set) var sendCount = 0
    public var waitSubmitSeconds = 5

    public init(orca: OrcaAdapter) { self.orca = orca }

    public func dispatch(text: String, to target: TargetSnapshot, retryRequestId: String? = nil) async -> DeliveryOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failed("보낼 내용이 비어 있습니다") }
        guard !inFlight.contains(target.projectID) else { return .rejectedDuplicate }
        inFlight.insert(target.projectID)
        defer { inFlight.remove(target.projectID) }

        let current: TerminalCandidate
        let screen: [String]
        do {
            current = try await orca.showTerminal(handle: target.handle)
            screen = try await orca.readScreen(handle: target.handle)
        } catch let e as OrcaError {
            if case .commandFailed = e { return .blocked(.terminalGone) }
            return .blocked(.lookupFailed(e.localizedDescription))
        } catch {
            return .blocked(.lookupFailed(error.localizedDescription))
        }
        if let failure = SendGuard.validate(expected: target, current: current, screen: screen) {
            return .blocked(failure)
        }

        sendCount += 1
        do {
            let receipt = try await orca.send(handle: target.handle, text: text,
                                              waitSubmitSeconds: waitSubmitSeconds, retryRequestId: retryRequestId)
            return DeliveryOutcome.from(receipt: receipt)
        } catch OrcaError.timedOut {
            return .unknown(requestId: retryRequestId, reason: "응답 시간 초과 — 화면을 확인한 뒤 수동으로 판단해 주세요")
        } catch {
            return .unknown(requestId: retryRequestId, reason: "전송 응답 오류: \(error.localizedDescription)")
        }
    }
}
