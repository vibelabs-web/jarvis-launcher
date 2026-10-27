import AppKit
import AVFoundation
import Combine
import JARVISCore

/// 패널 상태 머신(PRD 4.7). UI는 이 모델만 보고, CLI는 JARVISCore 어댑터를 통해서만 부른다.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case compose
        case recording
        case transcribing
        case classifying
        case reviewExisting
        case reviewNew
        case creating
        case reviewSkill
        case sending
        case result
    }

    enum MenuStatus { case ready, attention, offline }

    // MARK: 상태
    @Published var phase: Phase = .compose { didSet { onPanelHeightChange?(panelHeight) } }
    @Published var session = ComposerSession()
    @Published var notice: String?          // 패널 하단 안내(오류 포함)
    @Published var cursorUTF16: Int?

    @Published var prefs: Preferences
    @Published var projects: [ProjectRecord]
    @Published var connection: [UUID: ConnectionState] = [:]
    @Published var lastList: TerminalListResult?
    @Published var orcaProblem: String?
    @Published var lastRefresh: Date?
    @Published var menuStatus: MenuStatus = .offline
    @Published var statusLabel = "준비"
    @Published var hotkeyProblem: String?

    // 기존 프로젝트 확인 단계
    @Published var decision: RouteDecision?
    @Published var selectedProjectID: UUID?
    /// 같은 폴더에 Claude가 여러 개일 때 사용자가 직접 고른 터미널
    @Published var selectedHandle: String?
    @Published var reviewText = ""
    @Published var outcome: DeliveryOutcome?
    @Published var lastDelivery: (target: TargetSnapshot, text: String, requestId: String?)?

    // 새 프로젝트
    @Published var meta: MetaPrompt?
    @Published var newName = ""
    @Published var metaText = ""
    @Published var creation: CreationCheckpoint?
    @Published var creationMessage: String?
    @Published var creationCanResume = false

    // 스킬
    @Published var skills: [SkillEntry] = []
    @Published var skillFilter = ""
    @Published var selectedSkillID: String?
    @Published var skillArgs = ""

    // 패널 콜백
    var onPanelHeightChange: ((CGFloat) -> Void)?
    var onRequestHide: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHotkeyChanged: ((HotkeySetting) -> Void)?

    let stores: AppStores
    private var recorder: MicRecorder?
    private var llmEngine: LlamaServerLLM?
    private var dispatcher: DispatchCoordinator?

    init(stores: AppStores = AppStores()) {
        self.stores = stores
        prefs = stores.preferences.load() ?? Preferences()
        projects = stores.projects.load() ?? []
        if let pending = stores.creations.load()?.last(where: { $0.currentStep != .done }) {
            creation = pending
            creationCanResume = true
        }
    }

    var panelHeight: CGFloat {
        switch phase {
        case .compose, .recording, .transcribing, .classifying: return 300
        case .result: return 280
        case .reviewNew, .creating: return 640
        case .reviewExisting, .reviewSkill, .sending: return 560
        }
    }

    // MARK: 의존 객체

    var orca: OrcaAdapter? {
        guard let url = OrcaCLIAdapter.locate(configured: prefs.orcaPath) else { return nil }
        return OrcaCLIAdapter(executable: url)
    }

    func dispatchCoordinator() -> DispatchCoordinator? {
        if let d = dispatcher { return d }
        guard let o = orca else { return nil }
        dispatcher = DispatchCoordinator(orca: o)
        return dispatcher
    }

    var llm: LocalLLM? {
        guard prefs.useLLM, FileManager.default.isExecutableFile(atPath: (prefs.llamaServerPath as NSString).expandingTildeInPath),
              FileManager.default.fileExists(atPath: (prefs.llmModelPath as NSString).expandingTildeInPath) else { return nil }
        if let e = llmEngine, e.serverPath == (prefs.llamaServerPath as NSString).expandingTildeInPath,
           e.modelPath == (prefs.llmModelPath as NSString).expandingTildeInPath { return e }
        llmEngine = LlamaServerLLM(serverPath: prefs.llamaServerPath, modelPath: prefs.llmModelPath)
        return llmEngine
    }

    var recognizer: WhisperCLIRecognizer { WhisperCLIRecognizer(cliPath: prefs.whisperCLIPath, modelPath: prefs.whisperModelPath) }

    func savePrefs() {
        try? stores.preferences.save(prefs)
        dispatcher = nil
    }

    func saveProjects() { try? stores.projects.save(projects) }

    func shutdown() async { await llmEngine?.stop() }

    // MARK: 패널

    func panelDidShow() {
        notice = nil
        Task { await refreshOrca() }
    }

    func panelDidHide() {
        if phase == .recording { cancelRecording() }
    }

    func escape() {
        if phase == .recording { cancelRecording() }
        onRequestHide?()
    }

    /// 원문은 남기고 처음 단계로(뒤로 가기)
    func backToCompose() {
        session.back()
        phase = .compose
        notice = nil
        outcome = nil
    }

    /// 완료 후 새 요청
    func reset(clear: Bool) {
        if clear { session = ComposerSession() }
        decision = nil; selectedProjectID = nil; selectedHandle = nil; reviewText = ""
        outcome = nil; meta = nil; metaText = ""; newName = ""; selectedSkillID = nil; skillArgs = ""
        notice = nil
        phase = .compose
    }

    // MARK: Orca 조회·재연결 (FR-04·05)

    func refreshOrca() async {
        guard let orca else {
            orcaProblem = "Orca CLI를 찾지 못했습니다. 설정 > 진단에서 경로를 확인해 주세요"
            connection = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, .unknown(reason: "Orca CLI 없음")) })
            updateMenuStatus()
            return
        }
        do {
            let raw = try await orca.listTerminals()
            // Orca가 agentIdentity를 비워 보내는 Claude 세션이 있어 화면으로 보강한다(B14)
            let list = await SessionRegistry.enrichWithScreens(raw) { h in try? await orca.readScreen(handle: h) }
            lastList = list
            orcaProblem = nil
            lastRefresh = Date()
            var states: [UUID: ConnectionState] = [:]
            for i in projects.indices {
                let s = SessionRegistry.resolve(project: projects[i], list: list)
                states[projects[i].id] = s
                if let t = s.terminal {
                    projects[i].lastRuntimeHandle = t.handle
                    projects[i].lastSeenAt = Date()
                }
            }
            connection = states
            saveProjects()
            Diagnostics.log("orca.refresh terminals=\(list.terminals.count) claudeByOrca=\(list.terminals.filter { $0.agentIdentity == "claude" }.count) claudeByScreen=\(list.terminals.filter { $0.screenDetectedClaude == true }.count) projects=\(projects.count) connected=\(states.values.filter { $0.terminal != nil }.count)")
        } catch {
            orcaProblem = error.localizedDescription
            connection = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, .unknown(reason: error.localizedDescription)) })
            Diagnostics.log("orca.refresh failed \(error.localizedDescription)")
        }
        updateMenuStatus()
    }

    func updateMenuStatus() {
        if orcaProblem != nil { menuStatus = .offline; statusLabel = "연결 끊김"; return }
        let states = Array(connection.values)
        if states.contains(where: { if case .needsConfirmation = $0 { return true }; return false }) {
            menuStatus = .attention; statusLabel = "재확인 필요"
        } else {
            menuStatus = .ready; statusLabel = "준비"
        }
    }

    /// 설정에서 터미널을 프로젝트로 페어링한다. 핸들이 아니라 경로·호스트·worktree를 저장한다.
    func pair(_ t: TerminalCandidate) {
        guard let path = t.worktreePath, let host = t.executionHostId else { return }
        let canonical = PathTools.canonical(path)
        if projects.contains(where: { $0.canonicalPath == canonical && $0.hostId == host }) { return }
        projects.append(ProjectRecord(alias: (canonical as NSString).lastPathComponent, canonicalPath: canonical,
                                      worktreeId: t.worktreeId, hostId: host, lastRuntimeHandle: t.handle, lastSeenAt: Date()))
        saveProjects()
        Task { await refreshOrca() }
    }

    func unpair(_ id: UUID) {
        projects.removeAll { $0.id == id }
        connection[id] = nil
        saveProjects()
    }

    // MARK: 받아쓰기 (FR-03)

    func toggleRecording() {
        if phase == .recording { stopRecordingAndTranscribe() } else { startRecording() }
    }

    func startRecording() {
        if let e = recognizer.check() { notice = e.localizedDescription + " — 텍스트로 입력할 수 있습니다"; return }
        Task {
            let before = MicRecorder.permissionLabel
            let granted = await MicRecorder.requestPermission()
            Diagnostics.log("mic.permission before=\(before) granted=\(granted)")
            guard granted else {
                notice = "마이크 권한이 없어 받아쓰기를 할 수 없습니다. 시스템 설정 > 개인정보 보호 > 마이크에서 허용할 수 있고, 텍스트 입력은 그대로 쓸 수 있습니다"
                return
            }
            do {
                let dir = stores.directory.appendingPathComponent("tmp-audio", isDirectory: true)
                let r = try MicRecorder(directory: dir)
                try r.start()
                recorder = r
                phase = .recording
                statusLabel = "녹음 중"
                Diagnostics.log("mic.recording started")
                notice = nil
            } catch {
                notice = "녹음을 시작하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func cancelRecording() {
        recorder?.cancel()
        recorder = nil
        phase = .compose
        updateMenuStatus()
    }

    func stopRecordingAndTranscribe() {
        guard let r = recorder else { phase = .compose; return }
        recorder = nil
        let wav = r.stop()
        phase = .transcribing
        statusLabel = "음성 변환 중"
        let rec = recognizer
        let started = Date()
        Task {
            defer { try? FileManager.default.removeItem(at: wav) }  // 음성 파일은 즉시 삭제(PRD 5.3)
            do {
                let text = try await rec.transcribe(wav: wav)
                session.insertTranscript(text, atUTF16: cursorUTF16)
                notice = nil
                Diagnostics.log(String(format: "stt.done seconds=%.2f chars=%d", Date().timeIntervalSince(started), text.count))
            } catch {
                notice = error.localizedDescription + " — 텍스트로 입력할 수 있습니다"
                Diagnostics.log("stt.failed \(error.localizedDescription)")
            }
            if phase == .transcribing { phase = .compose }
            updateMenuStatus()
        }
    }

    // MARK: 분류 (FR-06)

    func proceed() {
        guard session.canProceed, phase == .compose else { return }
        phase = .classifying
        let text = session.original
        let candidates = projects.map(RouteCandidate.init)
        let engine = llm
        Task {
            await refreshOrca()
            let d = await IntentRouter.route(text: text, candidates: candidates, llm: engine)
            decision = d
            Diagnostics.log("route intent=\(d.intent.rawValue) source=\(d.source) needsSelection=\(d.needsUserSelection)")
            switch d.intent {
            case .newProject: await enterNewProject()
            case .skill: enterSkill()
            case .existingProject, .unknown: enterExisting(suggested: d.suggested)
            }
        }
    }

    func switchIntent(_ intent: RequestIntent) {
        outcome = nil
        notice = nil
        switch intent {
        case .newProject: Task { await enterNewProject() }
        case .skill: enterSkill()
        default: enterExisting(suggested: nil)
        }
    }

    // MARK: 기존 프로젝트 → 확인 → 1회 전송 (FR-08)

    func enterExisting(suggested: UUID?) {
        reviewText = session.beginReview()
        // 추천 대상이 "연결됨"일 때만 미리 선택한다. 모호하면 비워 두고 사용자가 고른다.
        if let s = suggested, connection[s]?.terminal != nil { selectedProjectID = s } else { selectedProjectID = nil }
        selectedHandle = nil
        outcome = nil
        phase = .reviewExisting
    }

    var selectedProject: ProjectRecord? { projects.first { $0.id == selectedProjectID } }

    /// 확인 화면에 보이는 그 대상. 이것과 전송 직전 재조회 결과를 대조한다.
    var currentTarget: (TargetSnapshot, TerminalCandidate)? {
        guard let p = selectedProject, let state = connection[p.id] else { return nil }
        switch state {
        case .connected(let t): return (TargetSnapshot(project: p, terminal: t), t)
        case .needsConfirmation(let cands, _):
            guard let h = selectedHandle, let t = cands.first(where: { $0.handle == h }) else { return nil }
            return (TargetSnapshot(project: p, terminal: t), t)
        default: return nil
        }
    }

    func sendExisting() {
        guard phase == .reviewExisting, let (target, _) = currentTarget else { return }
        let text = reviewText
        session.finalText = text
        send(text: text, to: target)
    }

    private func send(text: String, to target: TargetSnapshot, retryRequestId: String? = nil) {
        guard let d = dispatchCoordinator() else { notice = "Orca CLI를 찾지 못했습니다"; return }
        let previous = phase
        phase = .sending
        statusLabel = "전송 중"
        Task {
            let out = await d.dispatch(text: text, to: target, retryRequestId: retryRequestId)
            outcome = out
            Diagnostics.log("dispatch outcome=\(out.label) chars=\(text.count)")
            switch out {
            case .delivered(let rid):
                lastDelivery = (target, text, rid)
                statusLabel = "전송 확인"
                phase = .result
            case .unknown(let rid, _):
                lastDelivery = (target, text, rid)
                statusLabel = "재확인 필요"
                phase = .result
            case .blocked, .failed, .rejectedDuplicate:
                phase = previous
                await refreshOrca()
            }
        }
    }

    /// 상태 불명 뒤 사용자가 화면을 확인하고 누르는 수동 재시도. 같은 requestId로만 재개한다.
    func manualRetry() {
        guard let last = lastDelivery, let rid = last.requestId else { return }
        send(text: last.text, to: last.target, retryRequestId: rid)
    }

    func openInOrca() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app"))
    }

    // MARK: 새 프로젝트 (FR-07·09)

    func enterNewProject() async {
        phase = .classifying
        let m = await PromptComposer.compose(original: session.original, llm: llm)
        meta = m
        metaText = m.markdown()
        newName = m.nameSuggestions.first ?? PromptComposer.suggestName(from: session.original)
        creation = nil
        creationMessage = nil
        creationCanResume = false
        phase = .reviewNew
    }

    var newFolderPlan: Result<URL, FolderError> { FolderSafety.plan(parent: prefs.defaultParentFolder, name: newName) }

    func startCreation() {
        guard let o = orca, let d = dispatchCoordinator() else { notice = "Orca CLI를 찾지 못했습니다"; return }
        var cp: CreationCheckpoint
        if let existing = creation, creationCanResume {
            cp = existing
        } else {
            guard case .success = newFolderPlan else { return }
            cp = CreationCheckpoint(parent: prefs.defaultParentFolder, name: newName)
        }
        let prompt = metaText
        phase = .creating
        creationMessage = nil
        let coordinator = ProjectCreationCoordinator(orca: o, dispatcher: d)
        Task {
            let (final, result) = await coordinator.run(cp, prompt: prompt) { snapshot in
                Task { @MainActor in
                    self.creation = snapshot
                    self.persistCreation(snapshot)
                }
            }
            creation = final
            persistCreation(final)
            switch result {
            case .completed(let project, let out):
                if !projects.contains(where: { $0.canonicalPath == project.canonicalPath && $0.hostId == project.hostId }) {
                    projects.append(project)
                    saveProjects()
                }
                outcome = out
                creationCanResume = false
                creationMessage = nil
                statusLabel = "전송 확인"
                Diagnostics.log("create.completed")
            case .stopped(let step, let msg, let canResume):
                creationMessage = "\(step.label) 단계에서 멈춤: \(msg)"
                creationCanResume = canResume
                Diagnostics.log("create.stopped step=\(step.rawValue) resume=\(canResume)")
            }
            await refreshOrca()
        }
    }

    /// FR-09: Git 초기화는 사용자가 이 버튼으로 따로 승인할 때만 한다.
    func approveGitInitAndResume() {
        guard var cp = creation, cp.needsGitInit == true else { return }
        cp.gitInitApproved = true
        creation = cp
        creationCanResume = true
        Diagnostics.log("create.gitInitApproved")
        startCreation()
    }

    private func persistCreation(_ cp: CreationCheckpoint) {
        var all = stores.creations.load() ?? []
        all.removeAll { $0.id == cp.id }
        all.append(cp)
        try? stores.creations.save(Array(all.suffix(20)))
    }

    // MARK: 스킬 (FR-10)

    func enterSkill() {
        Task {
            let orcaSkills = (try? await orca?.installedSkills()) ?? []
            skills = SkillCatalog.discover(roots: .init(), projectPath: selectedProject?.canonicalPath, orcaSkills: orcaSkills)
        }
        let trimmed = session.original.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            skillFilter = String(trimmed.dropFirst().split(separator: " ").first ?? "")
        }
        if selectedProjectID == nil || connection[selectedProjectID!]?.terminal == nil { selectedProjectID = nil }
        phase = .reviewSkill
    }

    var filteredSkills: [SkillEntry] {
        let f = skillFilter.lowercased()
        return f.isEmpty ? skills : skills.filter { $0.name.lowercased().contains(f) || $0.description.lowercased().contains(f) }
    }

    var selectedSkill: SkillEntry? { skills.first { $0.id == selectedSkillID } }

    var skillInvocation: String {
        guard let s = selectedSkill else { return "" }
        let a = skillArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? s.invocation : "\(s.invocation) \(a)"
    }

    func sendSkill() {
        guard let s = selectedSkill, s.callable, let (target, _) = currentTarget else { return }
        send(text: skillInvocation, to: target)
    }

    func refreshSkillsForProject() {
        Task {
            let orcaSkills = (try? await orca?.installedSkills()) ?? []
            skills = SkillCatalog.discover(roots: .init(), projectPath: selectedProject?.canonicalPath, orcaSkills: orcaSkills)
        }
    }
}
