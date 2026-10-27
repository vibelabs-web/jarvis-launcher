import Foundation
import Testing
@testable import JARVISCore

private let cands = [
    RouteCandidate(id: UUID(), alias: "sales-dashboard", folderName: "sales-dashboard", note: "매출 대시보드"),
    RouteCandidate(id: UUID(), alias: "고객관리", folderName: "crm-app", note: "고객 관리 앱"),
]

@Suite("AC-11·12 분류·프롬프트")
struct BrainTests {
    @Test("별칭이 명시되면 규칙으로 추천한다 (AC-11)")
    func ruleAlias() async {
        let d = await IntentRouter.route(text: "고객관리 앱의 검색 필터 수정해줘", candidates: cands, llm: nil)
        #expect(d.intent == .existingProject)
        #expect(d.suggested == cands[1].id)
        #expect(d.source == "rule")
    }

    @Test("새 프로젝트 표현은 new_project")
    func ruleNew() async {
        let d = await IntentRouter.route(text: "새로운 독서 메모 앱을 만들어보자", candidates: cands, llm: nil)
        #expect(d.intent == .newProject)
    }

    @Test("모호하고 LLM이 없으면 수동 선택 (AC-11)")
    func ambiguousNoLLM() async {
        let d = await IntentRouter.route(text: "지난번 그거 고쳐줘", candidates: cands, llm: nil)
        #expect(d.suggested == nil)
        #expect(d.needsUserSelection)
    }

    @Test("LLM이 후보 밖 ID를 내면 버리고 수동 선택 (PRD 5.4)")
    func llmOutsideAllowlist() async {
        let bad = #"{"intent":"existing_project","suggested_project_id":"\#(UUID().uuidString)","candidate_ids":[],"reason":"x","needs_user_selection":false}"#
        let d = await IntentRouter.route(text: "지난번 그거 고쳐줘", candidates: cands, llm: FakeLLM(output: bad))
        #expect(d.suggested == nil)
        #expect(d.source == "fallback")
    }

    @Test("LLM이 손상된 JSON을 내면 수동 선택으로 폴백 (AC-12)")
    func llmBrokenJSON() async {
        let d = await IntentRouter.route(text: "지난번 그거 고쳐줘", candidates: cands, llm: FakeLLM(output: "{intent: existing"))
        #expect(d.source == "fallback")
        #expect(d.needsUserSelection)
    }

    @Test("LLM 정상 추천은 후보 ID로만")
    func llmOK() async {
        let ok = #"{"intent":"existing_project","suggested_project_id":"\#(cands[0].id.uuidString)","candidate_ids":["\#(cands[0].id.uuidString)"],"reason":"매출 언급","needs_user_selection":false}"#
        let d = await IntentRouter.route(text: "그래프 날짜 필터 고쳐줘", candidates: cands, llm: FakeLLM(output: "```json\n\(ok)\n```"))
        #expect(d.suggested == cands[0].id)
        #expect(d.source == "llm")
    }

    @Test("메타 프롬프트는 원문을 그대로 보존하고, 손상된 출력은 템플릿 폴백 (AC-12)")
    func composer() async {
        let original = "독서 메모 앱. ~/notes/books 폴더 읽기, 태그 3개까지. 로그인은 만들지 마."
        let broken = await PromptComposer.compose(original: original, llm: FakeLLM(output: "not json"))
        #expect(broken.source == "template")
        #expect(broken.markdown().contains(original))

        let lossy = #"{"purpose":"독서 메모 앱","scope":["메모"],"done_criteria":[],"constraints":[],"questions":[],"first_step":"계획","names":["Reading Notes!"]}"#
        let m = await PromptComposer.compose(original: original, llm: FakeLLM(output: lossy))
        #expect(m.source == "llm")
        #expect(m.markdown().contains(original))
        #expect(m.nameSuggestions == ["reading-notes"])
        #expect(m.preservationWarnings.contains { $0.contains("~/notes/books") })
        #expect(m.preservationWarnings.contains { $0.contains("3") })
        #expect(m.preservationWarnings.contains { $0.contains("부정") })
    }

    @Test("입력 세션: 뒤로 가기·받아쓰기 삽입에도 원문 유지 (AC-03)")
    func composerSession() {
        var s = ComposerSession()
        #expect(!s.canProceed)
        s.original = "   \n "
        #expect(!s.canProceed)
        s.original = "Fix the ~/dev/app/src/main.swift 파일\n두 번째 줄"
        let snapshot = s.original
        var edited = s.beginReview()
        edited += " (편집)"
        s.finalText = edited
        s.back()
        #expect(s.original == snapshot)
        #expect(s.finalText == nil)
        s.insertTranscript("추가 문장", atUTF16: 3)
        #expect(s.original.hasPrefix("Fix 추가 문장 the"))
        s.original = String(repeating: "가", count: 8_001)
        #expect(s.isOverSoftLimit && s.canProceed)
    }

    @Test("패널은 화면 사용 영역 안에 들어간다 (AC-02)")
    func geometry() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 944), CGRect(x: 1512, y: -200, width: 2560, height: 1415),
                       CGRect(x: 0, y: 0, width: 600, height: 400)]
        for vf in screens {
            let f = PanelGeometry.frame(contentSize: CGSize(width: 680, height: 420), visibleFrame: vf)
            #expect(vf.contains(f), "\(f) ⊄ \(vf)")
        }
    }
}

@Suite("AC-16·18 새 프로젝트")
struct ProjectCreationTests {
    @Test("기존 폴더·상위 탈출·symlink·권한 없음·잘못된 이름은 중단 (AC-16)")
    func folderSafety() throws {
        let parent = TestDirs.fresh("fs")
        try FileManager.default.createDirectory(at: parent.appendingPathComponent("exists"), withIntermediateDirectories: false)
        try "keep".write(to: parent.appendingPathComponent("exists/file.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: parent.appendingPathComponent("link").path, withDestinationPath: "/tmp")

        #expect(FolderSafety.create(parent: parent.path, name: "exists") == .failure(.alreadyExists(parent.appendingPathComponent("exists").path)))
        #expect((try? String(contentsOf: parent.appendingPathComponent("exists/file.txt"), encoding: .utf8)) == "keep")
        #expect(FolderSafety.create(parent: parent.path, name: "link") == .failure(.alreadyExists(parent.appendingPathComponent("link").path)))
        for bad in ["../escape", "..", "a/b", "/abs", "Upper", "", "-x", "한글"] {
            #expect(FolderSafety.create(parent: parent.path, name: bad) == .failure(.invalidName(bad)))
        }
        #expect(!FileManager.default.fileExists(atPath: parent.deletingLastPathComponent().appendingPathComponent("escape").path))

        let ro = parent.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: false)
        chmod(ro.path, 0o555)
        defer { chmod(ro.path, 0o755) }
        #expect(FolderSafety.create(parent: ro.path, name: "new") == .failure(.parentNotWritable(ro.path)))

        #expect(FolderSafety.create(parent: "", name: "x") == .failure(.parentNotSet))
        guard case .success(let made) = FolderSafety.create(parent: parent.path, name: "reading-notes") else { Issue.record("생성 실패"); return }
        #expect(made.lastPathComponent == "reading-notes")
    }

    @Test("셸 인용")
    func quote() {
        #expect(FolderSafety.shellQuote("/a b/it's") == #"'/a b/it'\''s'"#)
        let cmd = ProjectCreationCoordinator.claudeCommand(folder: "/p/x", sessionId: "u-1", name: "x")
        #expect(cmd == "cd -- '/p/x' && claude --permission-mode plan --session-id u-1 -n 'x'")
    }

    func coordinator(_ o: FakeOrca) -> ProjectCreationCoordinator {
        var c = ProjectCreationCoordinator(orca: o, dispatcher: DispatchCoordinator(orca: o))
        c.pollInterval = 0
        c.readyTimeout = 1
        c.sleep = { _ in }
        return c
    }

    @Test("Orca 단계 실패 후 이어하기: 폴더 재사용, 터미널·전송 중복 없음 (AC-18)")
    func resume() async {
        let parent = TestDirs.fresh("cr")
        let o = FakeOrca()
        o.addRepoBehavior = { _ in throw OrcaError.timedOut(command: "repo add") }
        let c = coordinator(o)
        var cp = CreationCheckpoint(parent: parent.path, name: "reading-notes")

        let (cp1, r1) = await c.run(cp, prompt: "메타 프롬프트")
        guard case .stopped(.orca, _, true) = r1 else { Issue.record("\(r1)"); return }
        #expect(cp1.folderPath != nil)
        cp = cp1

        o.addRepoBehavior = { RepoRecord(id: "repo-new", path: $0, kind: "folder") }
        o.screenSequence["term_new1"] = [Fixture.lines("screen-shell.txt"), Fixture.lines("screen-plan-ready.txt")]
        let (cp2, r2) = await c.run(cp, prompt: "메타 프롬프트")
        guard case .completed(let project, .delivered) = r2 else { Issue.record("\(r2)"); return }
        #expect(project.canonicalPath == cp1.folderPath)
        #expect(o.createdTerminals.count == 1)
        #expect(o.createdTerminals[0].command.contains("--permission-mode plan"))
        #expect(o.sendCount == 1)

        // 완료 뒤 다시 실행해도 아무것도 다시 만들거나 보내지 않는다
        let (_, r3) = await c.run(cp2, prompt: "메타 프롬프트")
        guard case .completed = r3 else { Issue.record("\(r3)"); return }
        #expect(o.createdTerminals.count == 1)
        #expect(o.sendCount == 1)
        #expect(o.addRepoCalls == 2)
    }

    @Test("대화상자가 뜨면 멈추고 보내지 않는다, 처리 후 이어하면 같은 터미널로 1회 전송 (AC-17·18)")
    func dialogThenResume() async {
        let parent = TestDirs.fresh("dlg")
        let o = FakeOrca()
        o.setScreen("term_new1", Fixture.lines("screen-mcp-dialog.txt"))
        let c = coordinator(o)
        let (cp1, r1) = await c.run(CreationCheckpoint(parent: parent.path, name: "app-one"), prompt: "p")
        guard case .stopped(.claudeReady, _, true) = r1 else { Issue.record("\(r1)"); return }
        #expect(o.sendCount == 0)

        o.setScreen("term_new1", Fixture.lines("screen-plan-ready.txt"))
        let (_, r2) = await c.run(cp1, prompt: "p")
        guard case .completed = r2 else { Issue.record("\(r2)"); return }
        #expect(o.createdTerminals.count == 1)
        #expect(o.sendCount == 1)
    }

    @Test("플랜 모드가 확인되지 않으면 보내지 않는다 (AC-17)")
    func noPlanMode() async {
        let o = FakeOrca()
        o.setScreen("term_new1", Fixture.lines("screen-normal-ready.txt"))
        let (_, r) = await coordinator(o).run(CreationCheckpoint(parent: TestDirs.fresh("np").path, name: "app-two"), prompt: "p")
        guard case .stopped(.claudeReady, let msg, _) = r else { Issue.record("\(r)"); return }
        #expect(msg.contains("플랜 모드"))
        #expect(o.sendCount == 0)
    }

    @Test("전송 결과가 불명이면 이어하기로도 재전송하지 않는다")
    func unknownNoResend() async {
        let o = FakeOrca()
        o.setScreen("term_new1", Fixture.lines("screen-plan-ready.txt"))
        o.sendBehavior = { _ in SendReceipt(accepted: true, stages: ["input_accepted"], requestId: "r") }
        let c = coordinator(o)
        let (cp, r) = await c.run(CreationCheckpoint(parent: TestDirs.fresh("unk").path, name: "app-three"), prompt: "p")
        guard case .stopped(.prompt, _, false) = r else { Issue.record("\(r)"); return }
        _ = await c.run(cp, prompt: "p")
        #expect(o.sendCount == 1)
    }
}

@Suite("AC-19·20 스킬")
struct SkillTests {
    @Test("개인·프로젝트·레거시 각 1개를 출처와 함께 표시, 충돌은 차단 (AC-19·20)")
    func discover() throws {
        let home = TestDirs.fresh("home")
        let proj = TestDirs.fresh("proj")
        func write(_ url: URL, _ s: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try s.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(home.appendingPathComponent(".claude/skills/jl-personal/SKILL.md"), "---\nname: jl-personal\ndescription: \"개인 스킬\"\n---\n본문 지시는 실행 안 함")
        try write(proj.appendingPathComponent(".claude/skills/jl-project/SKILL.md"), "---\nname: jl-project\ndescription: 프로젝트 스킬\n---\n")
        try write(home.appendingPathComponent(".claude/commands/jl-legacy.md"), "---\ndescription: 레거시\n---\n")
        try write(proj.appendingPathComponent(".claude/commands/jl-personal.md"), "충돌용")
        try write(home.appendingPathComponent(".claude/skills/broken/SKILL.md"), "frontmatter 없음")

        let plugin = OrcaSkill(id: "1", name: "sdlc", description: "d", providers: ["claude"], sourceKind: "plugin", sourceLabel: "Claude plugin vibelabs-sdlc")
        let codexOnly = OrcaSkill(id: "2", name: "codex-thing", description: "d", providers: ["codex"], sourceKind: "home", sourceLabel: "Codex home")
        let list = SkillCatalog.discover(roots: .init(home: home), projectPath: proj.path, orcaSkills: [plugin, codexOnly])

        let byName = Dictionary(grouping: list, by: \.invocation)
        #expect(byName["/jl-project"]?.first?.source == .project)
        #expect(byName["/jl-project"]?.first?.description == "프로젝트 스킬")
        #expect(byName["/jl-legacy"]?.first?.source == .legacyCommand)
        #expect(byName["/jl-personal"]?.count == 2)
        #expect(byName["/jl-personal"]?.allSatisfy { $0.availability == .blocked } == true)
        #expect(byName["/vibelabs-sdlc:sdlc"]?.first?.availability == .inferred)
        #expect(byName["/codex-thing"] == nil)
        #expect(byName["/broken"]?.first?.description == "")
    }
}
