import Foundation

public enum CreationStep: String, Codable, CaseIterable, Sendable {
    case folder, orca, terminal, claudeReady, prompt, done

    public var label: String {
        switch self {
        case .folder: return "폴더 생성"
        case .orca: return "Orca 연결"
        case .terminal: return "터미널 생성"
        case .claudeReady: return "Claude 플랜 모드 확인"
        case .prompt: return "프롬프트 전송"
        case .done: return "완료"
        }
    }
}

/// 단계별 체크포인트. 프롬프트 원문은 저장하지 않는다(PRD 5.7·5.9).
public struct CreationCheckpoint: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parent: String
    public var name: String
    public var claudeSessionId: String
    public var folderPath: String?
    public var worktreeRoot: String?
    public var repoId: String?
    public var insideExistingRepo: Bool?
    public var terminalHandle: String?
    public var terminalIncarnation: String?
    public var planModeVerified: Bool
    /// nil = 아직 보내지 않음 / "delivered" / "unknown"
    public var delivery: String?
    public var promptRequestId: String?
    public var lastError: String?
    public var updatedAt: Date

    public init(parent: String, name: String) {
        id = UUID()
        self.parent = parent
        self.name = name
        claudeSessionId = UUID().uuidString.lowercased()
        planModeVerified = false
        updatedAt = Date()
    }

    public var currentStep: CreationStep {
        if folderPath == nil { return .folder }
        if worktreeRoot == nil { return .orca }
        if terminalHandle == nil { return .terminal }
        if !planModeVerified { return .claudeReady }
        if delivery == nil { return .prompt }
        return .done
    }
}

public enum CreationResult: Equatable, Sendable {
    case completed(ProjectRecord, DeliveryOutcome)
    /// 중단. `canResume`이면 같은 체크포인트로 `이어하기`가 가능하다.
    case stopped(CreationStep, String, canResume: Bool)
}

/// 새 프로젝트 파이프라인(PRD 5.7). 각 단계는 멱등이어서 재실행해도 폴더·터미널·전송이 중복되지 않는다.
public struct ProjectCreationCoordinator: Sendable {
    public let orca: OrcaAdapter
    public let dispatcher: DispatchCoordinator
    public var readyTimeout: TimeInterval = 60
    public var pollInterval: TimeInterval = 1.5
    /// '준비됐지만 플랜 모드 줄 없음'을 몇 번 연속 봐야 멈출지
    public var planConfirmReads = 4
    public var sleep: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }

    public init(orca: OrcaAdapter, dispatcher: DispatchCoordinator) {
        self.orca = orca
        self.dispatcher = dispatcher
    }

    public static func claudeCommand(folder: String, sessionId: String, name: String) -> String {
        "cd -- \(FolderSafety.shellQuote(folder)) && claude --permission-mode plan --session-id \(sessionId) -n \(FolderSafety.shellQuote(name))"
    }

    public func run(_ start: CreationCheckpoint, prompt: String,
                    onProgress: @Sendable (CreationCheckpoint) -> Void = { _ in }) async -> (CreationCheckpoint, CreationResult) {
        var cp = start
        func stop(_ step: CreationStep, _ msg: String, resume: Bool = true) -> (CreationCheckpoint, CreationResult) {
            cp.lastError = msg
            cp.updatedAt = Date()
            onProgress(cp)
            return (cp, .stopped(step, msg, canResume: resume))
        }
        func advance() { cp.lastError = nil; cp.updatedAt = Date(); onProgress(cp) }

        // 1. 폴더: 이미 만든 폴더는 재사용한다.
        if let existing = cp.folderPath {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: existing, isDirectory: &isDir), isDir.boolValue else {
                return stop(.folder, "이전에 만든 폴더가 사라졌습니다: \(existing)", resume: false)
            }
        } else {
            switch FolderSafety.create(parent: cp.parent, name: cp.name) {
            case .failure(let e): return stop(.folder, e.localizedDescription, resume: false)
            case .success(let url):
                cp.folderPath = PathTools.canonical(url.path)
                advance()
            }
        }
        let folder = cp.folderPath!

        // 2. Orca 등록
        if cp.worktreeRoot == nil {
            do {
                let repo = try await orca.addRepo(path: folder)
                let root = PathTools.canonical(repo.path)
                cp.worktreeRoot = root
                cp.repoId = repo.id
                cp.insideExistingRepo = root != folder
                advance()
            } catch {
                return stop(.orca, "Orca에 폴더를 등록하지 못했습니다: \(error.localizedDescription). Orca에서 폴더를 직접 연 뒤 이어하기를 눌러 주세요")
            }
        }
        let root = cp.worktreeRoot!

        // 3. 터미널: 살아 있는 터미널이 있으면 재사용한다.
        if let handle = cp.terminalHandle {
            if let t = try? await orca.showTerminal(handle: handle), t.orphaned != true, t.connected != false {
                // 재사용
            } else {
                cp.terminalHandle = nil
                cp.terminalIncarnation = nil
                cp.planModeVerified = false
            }
        }
        if cp.terminalHandle == nil {
            if cp.delivery != nil {
                return stop(.terminal, "이전 터미널이 사라졌고 프롬프트 전송 기록이 있어 새로 만들지 않습니다", resume: false)
            }
            do {
                let created = try await orca.createTerminal(
                    worktreePath: root, title: cp.name,
                    command: Self.claudeCommand(folder: folder, sessionId: cp.claudeSessionId, name: cp.name))
                cp.terminalHandle = created.handle
                cp.terminalIncarnation = created.incarnationId
                advance()
            } catch {
                return stop(.terminal, "새 터미널을 만들지 못했습니다: \(error.localizedDescription)")
            }
        }
        let handle = cp.terminalHandle!

        // 4. Claude 플랜 모드 확인. 대화상자에는 자동으로 응답하지 않는다(ADR-6).
        if !cp.planModeVerified {
            let deadline = Date().addingTimeInterval(readyTimeout)
            var lastState: ScreenState = .unknown
            // 프롬프트 줄이 하단 상태줄보다 먼저 그려질 수 있으므로, '준비됐지만 플랜 모드 줄 없음'은
            // 몇 번 더 읽어 본 뒤에 판정한다(1회 관찰된 사례, docs/dev-bug-log.md B7).
            var readyWithoutPlan = 0
            while true {
                let lines = (try? await orca.readScreen(handle: handle)) ?? []
                lastState = ScreenClassifier.classify(lines)
                if case .ready(let plan, _) = lastState {
                    if plan { break }
                    readyWithoutPlan += 1
                    if readyWithoutPlan >= planConfirmReads {
                        return stop(.claudeReady, "Claude는 떴지만 플랜 모드가 확인되지 않았습니다. 전송하지 않았습니다")
                    }
                }
                if case .dialog(let d) = lastState {
                    return stop(.claudeReady, "Claude가 확인을 기다리고 있습니다: \(d). Orca에서 직접 처리한 뒤 이어하기를 눌러 주세요")
                }
                if Date() >= deadline {
                    return stop(.claudeReady, "Claude 준비 상태를 \(Int(readyTimeout))초 안에 확인하지 못했습니다")
                }
                await sleep(pollInterval)
            }
            cp.planModeVerified = true
            advance()
        }

        let project = ProjectRecord(alias: cp.name, canonicalPath: root, worktreeId: cp.repoId.map { "\($0)::\(root)" },
                                    hostId: "local", note: "", createdClaudeSessionId: cp.claudeSessionId,
                                    lastRuntimeHandle: handle, lastSeenAt: Date())

        // 5. 프롬프트 1회 전송. 이미 시도했으면 다시 보내지 않는다.
        if let d = cp.delivery {
            if d == "delivered" { return (cp, .completed(project, .delivered(requestId: cp.promptRequestId))) }
            return stop(.prompt, "이전 전송 결과가 불명입니다. 터미널 화면을 확인해 주세요(자동 재전송 안 함)", resume: false)
        }
        let target = TargetSnapshot(projectID: project.id, handle: handle, incarnationId: cp.terminalIncarnation,
                                    canonicalPath: root, hostId: "local")
        let outcome = await dispatcher.dispatch(text: prompt, to: target)
        switch outcome {
        case .delivered(let rid):
            cp.delivery = "delivered"; cp.promptRequestId = rid; advance()
            return (cp, .completed(project, outcome))
        case .unknown(let rid, let reason):
            cp.delivery = "unknown"; cp.promptRequestId = rid
            return stop(.prompt, reason, resume: false)
        case .blocked(let g):
            return stop(.prompt, g.localizedDescription)
        case .failed(let m):
            return stop(.prompt, m)
        case .rejectedDuplicate:
            return stop(.prompt, "이미 전송 중입니다")
        }
    }
}
