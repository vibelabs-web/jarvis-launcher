import AppKit
import AVFoundation
import Combine
import JARVISCore

/// 한 화면 컴포저 상태(ChatGPT 입력창 방식). 입력창 아래 칩으로 프로젝트(@)·스킬(/)을 고른다.
/// UI는 이 모델만 보고, CLI는 JARVISCore 어댑터를 통해서만 부른다.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case compose, recording, transcribing, sending, creating }
    enum MenuStatus { case ready, attention, offline }

    struct StatusLine: Equatable {
        enum Kind { case ok, info, warn, error }
        var text: String
        var kind: Kind
        var canRetry = false
        var canOpenOrca = false
        var confirmInferredSkill = false
        var canRevertDictation = false
    }

    /// 칩 위로 펼치는 목록의 한 줄
    struct ListItem: Identifiable, Equatable {
        enum Action: Equatable {
            case project(UUID, handle: String?)
            case pairTerminal(TerminalCandidate)
            case newProject
            case skill(String)
        }
        let id: String
        let title: String
        let subtitle: String
        let badge: String
        let enabled: Bool
        let action: Action
    }

    // MARK: 입력
    @Published var phase: Phase = .compose
    @Published var session = ComposerSession()
    /// 커서 위치. 화면에 그리지 않으므로 발행하지 않는다(커서가 움직일 때마다 전체를 다시 그리지 않도록)
    var caretUTF16: Int?
    /// 모델이 텍스트를 바꾼 뒤 입력창에 적용할 커서 위치
    @Published var pendingCaret: Int?
    @Published var focusTick = 0
    /// 입력창 크게 보기(⌘E). 긴 정리본을 패널 안에서 읽기 위함
    @Published var inputExpanded = false

    // MARK: 칩
    @Published var selectedProjectID: UUID?
    /// 같은 폴더에 Claude가 여러 개일 때 고른 터미널
    @Published var selectedHandle: String?
    /// 칩을 앱이 채운 경우의 이유("추천", "지난 대상"). nil이면 작가님이 직접 고른 것.
    @Published var softSelection: String?
    @Published var newProjectMode = false
    @Published var selectedSkillID: String?
    @Published var skills: [SkillEntry] = []

    // MARK: 칩 위 목록
    @Published var listKind: TriggerKind?
    @Published var listQuery = ""
    @Published var highlight = 0
    /// 스킬 목록에서 입력한 철자에 맞는 줄이 없음
    @Published var listNoMatch = false
    /// 입력 중 트리거로 연 경우의 토큰(선택하면 지운다)
    var activeTrigger: ActiveTrigger?

    // MARK: 결과 한 줄
    @Published var status: StatusLine?
    var lastDelivery: (target: TargetSnapshot, text: String, requestId: String?)?
    var inferredConfirmed = false

    // MARK: 연결
    @Published var prefs: Preferences
    @Published var projects: [ProjectRecord]
    @Published var connection: [UUID: ConnectionState] = [:]
    @Published var lastList: TerminalListResult?
    @Published var orcaProblem: String?
    @Published var lastRefresh: Date?
    @Published var menuStatus: MenuStatus = .offline
    @Published var statusLabel = "준비"
    @Published var hotkeyProblem: String?

    // MARK: 새 프로젝트 카드
    @Published var meta: MetaPrompt?
    @Published var composingMeta = false
    @Published var newName = ""
    @Published var metaText = ""
    @Published var creation: CreationCheckpoint?
    @Published var creationMessage: String?
    @Published var creationCanResume = false
    @Published var creationDelivered = false

    var onRequestHide: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// 전체 보기 창 열기·닫기(⌘⇧E). PanelController가 연결한다
    var onOpenFullView: (() -> Void)?
    var onCloseFullView: (() -> Void)?
    var onHotkeyChanged: ((HotkeySetting) -> Void)?

    let stores: AppStores
    private var recorder: MicRecorder?
    /// 녹음 중 파형
    let meter = MicMeter()
    /// 마지막 받아쓰기의 (정리본, 받아쓴 원문). '원문으로 되돌리기'용
    var lastDictation: (structured: String, transcript: String)?
    private var llmEngine: LlamaServerLLM?
    private var dispatcher: DispatchCoordinator?
    private var suggestTask: Task<Void, Never>?
    private var statusClearTask: Task<Void, Never>?

    init(stores: AppStores = AppStores()) {
        self.stores = stores
        prefs = stores.preferences.load() ?? Preferences()
        projects = stores.projects.load() ?? []
        if let pending = stores.creations.load()?.last(where: { $0.currentStep != .done }) {
            creation = pending
            creationCanResume = true
        }
    }

    // MARK: 높이 (PanelController가 관찰)

    var showNewProjectCard: Bool { newProjectMode && (meta != nil || composingMeta || creation != nil) }

    static let inputHeight: CGFloat = 150
    static let expandedInputHeight: CGFloat = 480

    func toggleExpanded() {
        inputExpanded.toggle()
        Diagnostics.log("panel.expand \(inputExpanded)")
        focusTick += 1
    }

    /// 전체 보기 창에서 고친 글. 트리거 목록(@·/)은 패널 전용이라 열지 않는다.
    func fullViewTextChanged(_ text: String, caret: Int) {
        session.original = text
        caretUTF16 = caret
        if listKind != nil { activeTrigger = nil; closeList() }
        if status?.kind == .ok { status = nil }
    }

    var panelHeight: CGFloat {
        var h: CGFloat = 214
        if targetSummary != nil { h += 20 }
        if let s = status { h += s.canRetry || s.confirmInferredSkill || s.canRevertDictation ? 34 : 24 }
        if listKind != nil { h += min(CGFloat(max(listItems.count, 1)), 6) * 40 + 30 }
        if inputExpanded { h += Self.expandedInputHeight - Self.inputHeight }
        if showNewProjectCard { h += 360 }
        return h
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
        guard prefs.useLLM, let (server, model) = llmPaths else { return nil }
        if let e = llmEngine, e.serverPath == server, e.modelPath == model { return e }
        llmEngine = LlamaServerLLM(serverPath: server, modelPath: model)
        return llmEngine
    }

    /// 설정에 경로가 있으면 그것을, 비어 있으면 `scripts/fetch-models.sh`가 받아 두는 프로젝트의 `.local-models`를 쓴다.
    /// (설정이 비어 있어 앱이 모델을 못 찾고 업무 정리·LLM 추천을 조용히 건너뛰던 결함, B20)
    var llmPaths: (server: String, model: String)? {
        let fm = FileManager.default
        var server = (prefs.llamaServerPath as NSString).expandingTildeInPath
        var model = (prefs.llmModelPath as NSString).expandingTildeInPath
        if server.isEmpty || model.isEmpty {
            // 개발 실행: build/JARVISLauncher.app 의 두 단계 위가 프로젝트 폴더. 데이터 폴더(.local-data)의 위도 본다.
            let roots = [Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent(),
                         stores.directory.deletingLastPathComponent()]
            for root in roots {
                let dir = root.appendingPathComponent(".local-models")
                let s = dir.appendingPathComponent("llama-b11606/llama-b11606/llama-server").path
                let m = dir.appendingPathComponent("Qwen3-1.7B-Q4_K_M.gguf").path
                if fm.isExecutableFile(atPath: s), fm.fileExists(atPath: m) {
                    if server.isEmpty { server = s }
                    if model.isEmpty { model = m }
                    break
                }
            }
        }
        guard fm.isExecutableFile(atPath: server), fm.fileExists(atPath: model) else { return nil }
        return (server, model)
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
        if selectedProjectID == nil, !newProjectMode, let last = prefs.lastProjectID, projects.contains(where: { $0.id == last }) {
            selectedProjectID = last
            softSelection = "지난 대상"
        }
        focusTick += 1
        Task {
            await refreshOrca()
            if skills.isEmpty { await loadSkills() }
        }
    }

    func panelDidHide() {
        if phase == .recording { cancelRecording() }
        closeList()
    }

    /// Esc: 목록 → 새 프로젝트 카드(진행 전이면) → 패널 순으로 닫는다. 입력은 남긴다.
    func escape() {
        if listKind != nil { closeList(); return }
        if phase == .recording { cancelRecording(); return }
        if showNewProjectCard && phase != .creating && creation?.folderPath == nil {
            meta = nil
            return
        }
        onRequestHide?()
    }

    // MARK: 입력 변화·트리거

    func textChanged(_ text: String, caret: Int) {
        session.original = text
        caretUTF16 = caret
        if let t = TriggerParser.active(in: text, caretUTF16: caret) {
            activeTrigger = t
            if listKind != t.kind { listKind = t.kind; setHighlight(0) }
            if listQuery != t.query { listQuery = t.query; followQuery() }
            if t.kind == .skill && skills.isEmpty { Task { await loadSkills() } }
        } else if activeTrigger != nil {
            activeTrigger = nil
            closeList()
        }
        if status?.kind == .ok { status = nil }
        scheduleSuggestion()
    }

    /// 검색어가 바뀌면: 프로젝트는 걸러진 목록의 맨 위, 스킬은 목록을 그대로 두고 가장 잘 맞는 줄로 이동
    private func followQuery() {
        guard listKind == .skill else { setHighlight(0); return }
        let best = SkillSearch.bestIndex(in: skills, query: listQuery)
        if listNoMatch != (best == nil && !listQuery.isEmpty) { listNoMatch.toggle() }
        if let best { setHighlight(best) } else if listQuery.isEmpty { setHighlight(0) }
        Diagnostics.log("list.follow kind=skill queryLen=\(listQuery.count) index=\(best.map(String.init) ?? "none") of=\(skills.count)")
    }

    /// 같은 값이면 발행하지 않는다(불필요한 다시 그리기 방지)
    private func setHighlight(_ h: Int) { if highlight != h { highlight = h } }

    func caretMoved(_ caret: Int) {
        caretUTF16 = caret
        if activeTrigger != nil, TriggerParser.active(in: session.original, caretUTF16: caret) == nil {
            activeTrigger = nil
            closeList()
        }
    }

    /// 칩을 누르면 커서 자리에 `@`·`/`를 넣어, 이어서 치는 철자가 곧바로 검색어가 되게 한다.
    func openList(_ kind: TriggerKind) {
        if listKind == kind {
            // 다시 누르면 닫는다. 검색어 없이 넣어 둔 기호만 있으면 함께 지운다.
            if let t = activeTrigger, t.query.isEmpty {
                let (text, caret) = TriggerParser.removing(t, from: session.original)
                session.original = text
                pendingCaret = caret
            }
            activeTrigger = nil
            closeList()
            focusTick += 1
            return
        }
        let ns = session.original as NSString
        let caret = min(caretUTF16 ?? ns.length, ns.length)
        let needsSpace = caret > 0 && !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: caret - 1)) ?? " ")
        let insert = (needsSpace ? " " : "") + (kind == .project ? "@" : "/")
        let text = ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: insert)
        let newCaret = caret + (insert as NSString).length
        session.original = text
        caretUTF16 = newCaret
        pendingCaret = newCaret
        activeTrigger = TriggerParser.active(in: text, caretUTF16: newCaret)
        listKind = kind
        listQuery = ""
        setHighlight(0)
        listNoMatch = false
        if kind == .skill && skills.isEmpty { Task { await loadSkills() } }
        if kind == .project { Task { await refreshOrca() } }
        focusTick += 1
    }

    func closeList() {
        if listNoMatch { listNoMatch = false }
        if listKind != nil { listKind = nil }
        if !listQuery.isEmpty { listQuery = "" }
        setHighlight(0)
    }

    func moveHighlight(_ delta: Int) {
        let n = listItems.count
        guard n > 0 else { return }
        setHighlight((highlight + delta + n) % n)
    }

    func chooseHighlighted() {
        let items = listItems
        guard items.indices.contains(highlight) else { return }
        choose(items[highlight])
    }

    func choose(_ item: ListItem) {
        guard item.enabled else { return }
        if let t = activeTrigger {
            let (text, caret) = TriggerParser.removing(t, from: session.original)
            session.original = text
            pendingCaret = caret
            activeTrigger = nil
        }
        switch item.action {
        case .project(let id, let handle):
            selectProject(id, handle: handle)
        case .pairTerminal(let t):
            if let id = pair(t) { selectProject(id, handle: nil) }
        case .newProject:
            newProjectMode = true
            selectedProjectID = nil
            selectedHandle = nil
            softSelection = nil
            meta = nil
        case .skill(let id):
            selectedSkillID = id
            inferredConfirmed = false
            if let s = selectedSkill, s.availability == .inferred {
                setStatus("'\(s.invocation)'는 Orca 목록에만 있는 스킬입니다. 보낼 때 한 번 더 확인합니다", .info)
            }
        }
        closeList()
        focusTick += 1
    }

    func selectProject(_ id: UUID, handle: String?) {
        selectedProjectID = id
        selectedHandle = handle
        softSelection = nil
        newProjectMode = false
        meta = nil
        Task { await loadSkills() }
    }

    func clearProject() {
        selectedProjectID = nil
        selectedHandle = nil
        softSelection = nil
        newProjectMode = false
        meta = nil
    }

    func clearSkill() { selectedSkillID = nil; inferredConfirmed = false }

    /// 칩이 비어 있거나 앱이 채운 칩이면, 입력이 멈춘 뒤 규칙으로 대상을 추천한다(작가님이 고른 칩은 바꾸지 않음).
    private func scheduleSuggestion() {
        suggestTask?.cancel()
        guard (selectedProjectID == nil && !newProjectMode) || softSelection != nil else { return }
        let text = session.original
        let cands = projects.map(RouteCandidate.init)
        suggestTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let d = IntentRouter.ruleRoute(text: text, candidates: cands) else { return }
            switch d.intent {
            case .existingProject:
                if let id = d.suggested, self.connection[id]?.terminal != nil, id != self.selectedProjectID {
                    self.selectedProjectID = id
                    self.selectedHandle = nil
                    self.newProjectMode = false
                    self.softSelection = "추천"
                }
            case .newProject:
                if !self.newProjectMode {
                    self.newProjectMode = true
                    self.selectedProjectID = nil
                    self.softSelection = "추천"
                }
            default: break
            }
        }
    }

    // MARK: 칩 위 목록 항목

    var listItems: [ListItem] {
        let q = listQuery.lowercased()
        // 한글 자판 상태로 친 @검색어도 영문 키 위치로 함께 찾는다
        let qs = [q, HangulKeys.toQwerty(q)].compactMap { $0 }
        func match(_ parts: String...) -> Bool { q.isEmpty || parts.contains { p in qs.contains { p.lowercased().contains($0) } } }
        switch listKind {
        case .project:
            var items: [ListItem] = []
            for p in projects.sorted(by: { $0.alias < $1.alias }) {
                let state = connection[p.id] ?? .unknown(reason: "조회 전")
                if case .needsConfirmation(let cands, _) = state {
                    for t in cands where match(p.alias, p.folderName, t.title ?? "") {
                        items.append(ListItem(id: "p-\(p.id)-\(t.handle)", title: p.alias,
                                              subtitle: "\(t.title ?? String(t.handle.prefix(13))) · 같은 폴더에 세션 여러 개 — 이 터미널",
                                              badge: "직접 선택", enabled: true, action: .project(p.id, handle: t.handle)))
                    }
                    continue
                }
                guard match(p.alias, p.folderName, state.terminal?.title ?? "", p.note) else { continue }
                items.append(ListItem(id: "p-\(p.id)", title: p.alias,
                                      subtitle: [state.terminal?.title, shortPath(p.canonicalPath)].compactMap { $0 }.joined(separator: " · "),
                                      badge: state.label, enabled: true, action: .project(p.id, handle: nil)))
            }
            let paired = Set(projects.map { "\($0.hostId)|\($0.canonicalPath)" })
            if let list = lastList {
                for row in SessionRegistry.pairableCandidates(list) where row.pairable {
                    let t = row.terminal
                    guard let path = t.worktreePath, !paired.contains("\(t.executionHostId ?? "")|\(PathTools.canonical(path))"),
                          match(t.folderName, t.title ?? "") else { continue }
                    items.append(ListItem(id: "t-\(t.handle)", title: t.folderName,
                                          subtitle: "\(t.title ?? "Orca 터미널") · \(shortPath(path))",
                                          badge: t.orphaned == true ? "연결하기 · 탭 분리" : "연결하기", enabled: true, action: .pairTerminal(t)))
                }
            }
            if match("새 프로젝트", "new") {
                items.append(ListItem(id: "new", title: "＋ 새 프로젝트", subtitle: "폴더를 만들고 Claude를 플랜 모드로 시작",
                                      badge: "", enabled: true, action: .newProject))
            }
            return items
        case .skill:
            return skills.map { s in
                ListItem(id: "s-\(s.id)", title: s.invocation, subtitle: s.description.isEmpty ? s.note : s.description,
                         badge: "\(s.source.rawValue) · \(s.availability.rawValue)", enabled: s.callable, action: .skill(s.id))
            }
        case nil:
            return []
        }
    }

    func shortPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        let t = p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
        let comps = t.split(separator: "/")
        return comps.count > 3 ? "…/" + comps.suffix(2).joined(separator: "/") : t
    }

    // MARK: 선택된 대상

    var selectedProject: ProjectRecord? { projects.first { $0.id == selectedProjectID } }
    var selectedSkill: SkillEntry? { skills.first { $0.id == selectedSkillID } }

    /// 확인용 대상(이것과 전송 직전 재조회 결과를 대조한다)
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

    /// 입력창 아래 한 줄 요약(경로 · 호스트 · 터미널) — PRD 4.3
    var targetSummary: String? {
        if newProjectMode {
            return prefs.defaultParentFolder.isEmpty ? "새 프로젝트 · 설정에서 기본 상위 폴더를 먼저 지정해 주세요"
                : "새 프로젝트 · \(shortPath(prefs.defaultParentFolder))/… · 새 Orca 터미널 · Claude 플랜 모드"
        }
        guard let p = selectedProject else { return nil }
        let host = p.hostId == "local" ? "이 Mac" : p.hostId
        if let (_, t) = currentTarget {
            return "\(shortPath(p.canonicalPath)) · \(host) · Claude \"\(t.title ?? String(t.handle.prefix(13)))\"\(t.orphaned == true ? " · 탭 분리" : "")"
        }
        let state = connection[p.id] ?? .unknown(reason: "조회 전")
        switch state {
        case .needsConfirmation(_, let r): return "\(shortPath(p.canonicalPath)) · \(r) — @에서 터미널을 골라 주세요"
        case .offline(let r), .unknown(let r): return "\(shortPath(p.canonicalPath)) · \(state.label): \(r)"
        case .connected: return nil
        }
    }

    var canSubmit: Bool {
        guard phase == .compose else { return false }
        if newProjectMode { return session.canProceed && !showNewProjectCard }
        return session.canProceed || selectedSkillID != nil
    }

    // MARK: 전송 (⌘↵)

    func submit() {
        guard canSubmit else { return }
        closeList()
        if newProjectMode {
            Task { await composeNewProject() }
            return
        }
        guard selectedProjectID != nil else {
            recommendThenWait()
            return
        }
        guard let (target, _) = currentTarget else {
            setStatus(targetSummary ?? "보낼 수 있는 대상이 아닙니다", .warn)
            openList(.project)
            return
        }
        if let s = selectedSkill, s.availability == .inferred, !inferredConfirmed {
            var line = StatusLine(text: "'\(s.invocation)'가 이 세션에서 쓸 수 있는지 확인되지 않았습니다(/skills로 확인 후 진행)", kind: .warn)
            line.confirmInferredSkill = true
            status = line
            return
        }
        send(text: ComposerSession.outgoing(text: session.original, skillInvocation: selectedSkill?.invocation), to: target)
    }

    func confirmInferredAndSend() {
        inferredConfirmed = true
        status = nil
        submit()
    }

    /// 칩이 비었을 때: 추천만 하고 보내지 않는다. 한 번 더 ⌘↵를 눌러야 전송된다.
    private func recommendThenWait() {
        phase = .sending
        statusLabel = "대상 추천 중"
        let text = session.original
        let cands = projects.map(RouteCandidate.init)
        let engine = llm
        Task {
            await refreshOrca()
            let d = await IntentRouter.route(text: text, candidates: cands, llm: engine)
            phase = .compose
            updateMenuStatus()
            Diagnostics.log("route intent=\(d.intent.rawValue) source=\(d.source) needsSelection=\(d.needsUserSelection)")
            if d.intent == .newProject {
                newProjectMode = true
                softSelection = "추천"
                setStatus("새 프로젝트로 보입니다. 맞으면 ⌘↵로 계속하세요", .info)
            } else if d.intent == .existingProject, let id = d.suggested, connection[id]?.terminal != nil {
                selectedProjectID = id
                softSelection = "추천"
                setStatus("추천: \(selectedProject?.alias ?? "") — \(d.reason). 맞으면 ⌘↵로 보냅니다", .info)
            } else {
                setStatus("보낼 프로젝트를 골라 주세요 (\(d.reason))", .info)
                openList(.project)
            }
            focusTick += 1
        }
    }

    private func send(text: String, to target: TargetSnapshot, retryRequestId: String? = nil) {
        guard let d = dispatchCoordinator() else { setStatus("Orca CLI를 찾지 못했습니다", .error); return }
        phase = .sending
        statusLabel = "전송 중"
        Task {
            let out = await d.dispatch(text: text, to: target, retryRequestId: retryRequestId)
            phase = .compose
            Diagnostics.log("dispatch outcome=\(out.label) chars=\(text.count)")
            recordSend(text: text, target: target, outcome: out)
            switch out {
            case .delivered(let rid):
                lastDelivery = (target, text, rid)
                prefs.lastProjectID = target.projectID
                savePrefs()
                let name = projects.first { $0.id == target.projectID }?.alias ?? ""
                if prefs.clearInputAfterSend { session = ComposerSession(); pendingCaret = 0 }
                selectedSkillID = nil
                softSelection = nil
                setStatus("\(name)에 전달됨 · \(Date().formatted(date: .omitted, time: .shortened))", .ok, autoClear: 6)
                statusLabel = "전송 확인"
            case .unknown(let rid, let reason):
                lastDelivery = (target, text, rid)
                var line = StatusLine(text: "전송 여부 불명: \(reason) — 자동으로 다시 보내지 않습니다", kind: .warn)
                line.canRetry = rid != nil
                line.canOpenOrca = true
                status = line
                statusLabel = "재확인 필요"
            case .blocked(let g):
                setStatus("보내지 않았습니다: \(g.localizedDescription)", .warn)
                await refreshOrca()
            case .failed(let m):
                setStatus("실패: \(m)", .error)
            case .rejectedDuplicate:
                setStatus("이미 전송 중입니다", .info)
            }
            focusTick += 1
        }
    }

    // MARK: 프롬프트 기록 (ADR-8)

    /// 훅이 쓰는 것과 같은 DB. 훅 기록과 같은 글로 짝지어 받아쓴 원문·프로젝트를 붙인다.
    lazy var promptLog: PromptLog? = try? PromptLog(url: stores.directory.appendingPathComponent("prompts.sqlite"))

    private func recordSend(text: String, target: TargetSnapshot, outcome: DeliveryOutcome) {
        let label: String
        switch outcome {
        case .delivered: label = "delivered"
        case .unknown: label = "unknown"
        default: return  // 보내지 않은 것은 기록하지 않는다
        }
        // 보낸 글에 받아쓴 원문이 들어 있을 때만(정리본 끝에 붙는다) 원문으로 함께 남긴다
        let transcript = lastDictation.flatMap { text.contains($0.transcript) ? $0.transcript : nil }
        let project = projects.first { $0.id == target.projectID }?.alias ?? PromptLog.projectName(cwd: target.canonicalPath)
        do {
            try promptLog?.recordLauncherSend(text: text, transcript: transcript, project: project,
                                              skill: selectedSkill?.invocation, outcome: label)
        } catch {
            Diagnostics.log("promptlog.send failed \(error.localizedDescription)")
        }
        if case .delivered = outcome { lastDictation = nil }
    }

    /// 상태 불명 뒤 사용자가 화면을 확인하고 누르는 수동 재시도. 같은 requestId로만 재개한다.
    func manualRetry() {
        guard let last = lastDelivery, let rid = last.requestId else { return }
        status = nil
        send(text: last.text, to: last.target, retryRequestId: rid)
    }

    func openInOrca() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Orca.app")) }

    func setStatus(_ text: String, _ kind: StatusLine.Kind, autoClear: Double? = nil) {
        let line = StatusLine(text: text, kind: kind)
        status = line
        statusClearTask?.cancel()
        if let secs = autoClear {
            statusClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                if !Task.isCancelled, self?.status == line { self?.status = nil }
            }
        }
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
        if connection.values.contains(where: { if case .needsConfirmation = $0 { return true }; return false }) {
            menuStatus = .attention; statusLabel = "재확인 필요"
        } else {
            menuStatus = .ready; statusLabel = "준비"
        }
    }

    /// 터미널을 프로젝트로 페어링한다. 핸들이 아니라 경로·호스트·worktree를 저장한다.
    @discardableResult
    func pair(_ t: TerminalCandidate) -> UUID? {
        guard let path = t.worktreePath, let host = t.executionHostId else { return nil }
        let canonical = PathTools.canonical(path)
        if let existing = projects.first(where: { $0.canonicalPath == canonical && $0.hostId == host }) { return existing.id }
        let p = ProjectRecord(alias: (canonical as NSString).lastPathComponent, canonicalPath: canonical,
                              worktreeId: t.worktreeId, hostId: host, lastRuntimeHandle: t.handle, lastSeenAt: Date())
        projects.append(p)
        saveProjects()
        if let list = lastList { connection[p.id] = SessionRegistry.resolve(project: p, list: list) }
        Diagnostics.log("pair added")
        Task { await refreshOrca() }
        return p.id
    }

    func unpair(_ id: UUID) {
        projects.removeAll { $0.id == id }
        connection[id] = nil
        if selectedProjectID == id { clearProject() }
        if prefs.lastProjectID == id { prefs.lastProjectID = nil; savePrefs() }
        saveProjects()
    }

    // MARK: 스킬 (FR-10)

    func loadSkills() async {
        let orcaSkills = (try? await orca?.installedSkills()) ?? []
        skills = SkillSearch.displayOrder(SkillCatalog.discover(roots: .init(), projectPath: selectedProject?.canonicalPath, orcaSkills: orcaSkills))
        if listKind == .skill && !listQuery.isEmpty { followQuery() }
        if let id = selectedSkillID, !skills.contains(where: { $0.id == id }) { selectedSkillID = nil }
    }

    // MARK: 받아쓰기 (FR-03)

    func toggleRecording() {
        if phase == .recording { stopRecordingAndTranscribe() } else { startRecording() }
    }

    /// 권한 대화상자가 떠 있는 동안 버튼을 또 눌러도 녹음이 겹쳐 시작되지 않게 막는다(B18)
    private var micStarting = false

    func startRecording() {
        guard phase == .compose, !micStarting, recorder == nil else { return }
        if let e = recognizer.check() { setStatus(e.localizedDescription + " — 텍스트로 입력할 수 있습니다", .warn); return }
        micStarting = true
        let before = MicRecorder.permissionLabel
        if before == "아직 묻지 않음" {
            setStatus("마이크 권한 창에서 '허용'을 눌러 주세요. 창이 안 보이면 다른 창 뒤에 있을 수 있습니다", .info)
        }
        Task {
            defer { micStarting = false }
            let granted = await MicRecorder.requestPermission()
            Diagnostics.log("mic.permission before=\(before) granted=\(granted)")
            guard phase == .compose, recorder == nil else { return }
            guard granted else {
                setStatus("마이크 권한이 없어 받아쓰기를 할 수 없습니다. 시스템 설정 > 개인정보 보호 > 마이크에서 허용할 수 있고, 텍스트 입력은 그대로 쓸 수 있습니다", .warn)
                return
            }
            do {
                let r = try MicRecorder(directory: stores.directory.appendingPathComponent("tmp-audio", isDirectory: true))
                let meter = self.meter
                r.onLevel = { level in Task { @MainActor in meter.push(level) } }
                meter.start()
                try r.start()
                recorder = r
                phase = .recording
                statusLabel = "녹음 중"
                if status?.kind == .info { status = nil }
                Diagnostics.log("mic.recording started")
            } catch {
                setStatus("녹음을 시작하지 못했습니다: \(error.localizedDescription)", .error)
            }
        }
    }

    func cancelRecording() {
        meter.stop()
        recorder?.cancel()
        recorder = nil
        phase = .compose
        updateMenuStatus()
    }

    func stopRecordingAndTranscribe() {
        guard let r = recorder else { phase = .compose; return }
        recorder = nil
        let wav = r.stop()
        meter.stop()
        phase = .transcribing
        statusLabel = "음성 변환 중"
        let rec = recognizer
        let started = Date()
        let caret = caretUTF16
        Task {
            defer { try? FileManager.default.removeItem(at: wav) }  // 음성 파일은 즉시 삭제(PRD 5.3)
            do {
                let text = try await rec.transcribe(wav: wav)
                let before = (session.original as NSString).length
                session.insertTranscript(text, atUTF16: caret)
                // 넣은 글자 뒤로 커서를 옮긴다(B15: 예전에는 커서 위치를 받지 못해 항상 끝에 붙였다)
                let after = (session.original as NSString).length
                pendingCaret = min((caret ?? before) + (after - before), after)
                Diagnostics.log(String(format: "stt.done seconds=%.2f chars=%d", Date().timeIntervalSince(started), text.count))
                if prefs.structureDictation { await structureDictation(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                scheduleSuggestion()
            } catch {
                setStatus(error.localizedDescription + " — 텍스트로 입력할 수 있습니다", .warn)
                Diagnostics.log("stt.failed \(error.localizedDescription)")
            }
            phase = .compose
            updateMenuStatus()
            focusTick += 1
        }
    }

    /// 받아쓴 말을 업무 지시(목표·할 일·조건)로 정리해 입력창의 받아쓴 부분을 바꾼다. 보내지는 않는다.
    private func structureDictation(_ transcript: String) async {
        lastDictation = nil
        guard let (engine, engineName) = structureEngine else {
            Diagnostics.log("dictation.structure skipped reason=no-engine engine=\(prefs.structureEngine)")
            setStatus(prefs.structureEngine == "claude"
                      ? "받아쓴 그대로 넣었습니다(claude CLI를 찾지 못해 업무 정리를 하지 않음)"
                      : "받아쓴 그대로 넣었습니다(로컬 모델이 없어 업무 정리를 하지 않음)", .warn)
            return
        }
        statusLabel = "업무로 정리 중"
        setStatus("받아쓴 말을 할 일로 정리하는 중… (\(engineName))", .info)
        let started = Date()
        let t = await TaskStructurer.structure(transcript: transcript, llm: engine)
        let secs = Date().timeIntervalSince(started)
        guard let t else {
            Diagnostics.log(String(format: "dictation.structure ok=false engine=%@ seconds=%.2f", engineName, secs))
            setStatus("업무 정리에 실패해 받아쓴 그대로 두었습니다. 고친 뒤 ⌘↵로 보내세요", .warn)
            return
        }
        let structured = t.text()
        let ns = session.original as NSString
        let r = ns.range(of: transcript, options: .backwards)
        guard r.location != NSNotFound else { status = nil; return }  // 그사이 직접 고쳤으면 건드리지 않는다
        session.original = ns.replacingCharacters(in: r, with: structured)
        pendingCaret = r.location + (structured as NSString).length
        lastDictation = (structured, transcript)
        Diagnostics.log(String(format: "dictation.structure ok=true engine=%@ seconds=%.2f actions=%d warnings=%d", engineName, secs, t.actions.count, t.warnings.count))
        var line = StatusLine(text: t.warnings.isEmpty
                              ? "할 일 \(t.actions.count)개로 정리했습니다. 확인·수정 후 ⌘↵로 보내세요"
                              : "정리본 확인 필요: " + t.warnings.joined(separator: " · "),
                              kind: t.warnings.isEmpty ? .info : .warn)
        line.canRevertDictation = true
        statusClearTask?.cancel()
        status = line
    }

    /// 정리 엔진. 기본은 claude -p(Haiku 5.5). 받아쓴 말이 외부로 전송되는 것은 작가님 결정(ADR-7).
    var structureEngine: (LocalLLM, String)? {
        if prefs.structureEngine == "claude" {
            guard let cli = ClaudeCLILLM.locate() else { return nil }
            // 빈 전용 폴더에서 실행해 프로젝트의 CLAUDE.md·저장소 정보가 섞이지 않게 한다
            let wd = stores.directory.appendingPathComponent("claude-structurer", isDirectory: true)
            return (ClaudeCLILLM(cliPath: cli, workDir: wd), "Haiku 5.5")
        }
        return llm.map { ($0, "로컬 모델") }
    }

    func revertDictation() {
        guard let d = lastDictation else { return }
        let ns = session.original as NSString
        let r = ns.range(of: d.structured, options: .backwards)
        guard r.location != NSNotFound else {
            setStatus("정리본을 이미 고쳐서 되돌릴 수 없습니다", .warn, autoClear: 4)
            return
        }
        session.original = ns.replacingCharacters(in: r, with: d.transcript)
        pendingCaret = r.location + (d.transcript as NSString).length
        lastDictation = nil
        setStatus("받아쓴 원문으로 되돌렸습니다", .info, autoClear: 4)
    }

    // MARK: 새 프로젝트 카드 (FR-07·09)

    func composeNewProject() async {
        composingMeta = true
        let m = await PromptComposer.compose(original: session.original, llm: llm)
        meta = m
        metaText = m.markdown()
        newName = m.nameSuggestions.first ?? PromptComposer.suggestName(from: session.original)
        if creation?.folderPath == nil { creation = nil; creationCanResume = false }
        creationMessage = nil
        creationDelivered = false
        composingMeta = false
    }

    var newFolderPlan: Result<URL, FolderError> { FolderSafety.plan(parent: prefs.defaultParentFolder, name: newName) }

    func startCreation() {
        guard let o = orca, let d = dispatchCoordinator() else { setStatus("Orca CLI를 찾지 못했습니다", .error); return }
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
            phase = .compose
            switch result {
            case .completed(let project, _):
                if !projects.contains(where: { $0.canonicalPath == project.canonicalPath && $0.hostId == project.hostId }) {
                    projects.append(project)
                    saveProjects()
                }
                creationCanResume = false
                creationDelivered = true
                prefs.lastProjectID = projects.first { $0.canonicalPath == project.canonicalPath }?.id
                savePrefs()
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

    /// 새 프로젝트를 마치고 일반 입력으로 돌아간다. 만든 프로젝트를 칩으로 남긴다.
    func finishNewProject() {
        let created = prefs.lastProjectID
        session = ComposerSession()
        pendingCaret = 0
        meta = nil
        creation = nil
        creationDelivered = false
        creationMessage = nil
        newProjectMode = false
        if let id = created, projects.contains(where: { $0.id == id }) { selectedProjectID = id; softSelection = nil }
        setStatus("새 프로젝트에 메타 프롬프트를 전달했습니다", .ok, autoClear: 6)
        focusTick += 1
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
}
