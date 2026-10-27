import Foundation
import JARVISCore

/// AC-20 실연동: 테스트 폴더의 프로젝트 스킬을 카탈로그로 찾고, 테스트 터미널에만 호출 문자열을 1회 보낸다.
func runSkillScenario(root: String, orcaURL: URL, evidence: URL) async throws {
    let orca = OrcaCLIAdapter(executable: orcaURL)
    var lines = ["# 스킬 호출 실연동 (AC-20)", ""]
    func log(_ s: String) { let m = s.replacingOccurrences(of: NSHomeDirectory(), with: "~"); print(m); lines.append(m) }
    func check(_ n: String, _ ok: Bool, _ d: String = "") { log("- [\(ok ? "PASS" : "FAIL")] \(n)\(d.isEmpty ? "" : " — \(d)")") }

    let preexisting = Set(try await orca.listTerminals().terminals.map(\.handle))
    let stamp = String(Int(Date().timeIntervalSince1970))
    let folder = PathTools.canonical("\(root)/qa/sandbox") + "/e2e-skill-\(stamp)"
    let skillDir = "\(folder)/.claude/skills/jl-echo"
    try FileManager.default.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
    try """
    ---
    name: jl-echo
    description: JARVIS E2E 테스트용. 호출되면 JL-ECHO-OK 한 줄만 답한다.
    ---
    이 스킬이 호출되면 다른 작업을 하지 말고 정확히 `JL-ECHO-OK` 한 줄만 출력하세요.
    """.write(toFile: "\(skillDir)/SKILL.md", atomically: true, encoding: .utf8)

    // 1) 카탈로그: 프로젝트 스킬로 보이는지
    let catalog = SkillCatalog.discover(roots: .init(), projectPath: folder, orcaSkills: (try? await orca.installedSkills()) ?? [])
    let entry = catalog.first { $0.invocation == "/jl-echo" }
    check("카탈로그에 프로젝트 스킬 표시", entry?.source == .project, entry.map { "\($0.source.rawValue) · \($0.availability.rawValue)" } ?? "없음")
    check("전체 카탈로그 크기(참고)", true, "\(catalog.count)개, 차단 \(catalog.filter { $0.availability == .blocked }.count)개, 추정 \(catalog.filter { $0.availability == .inferred }.count)개")
    guard let skill = entry, skill.callable else { log("호출 불가 — 중단"); return }

    // 2) 테스트 터미널(폴더에서 Claude 플랜 모드)
    let worktree = PathTools.canonical(root)
    let created = try await orca.createTerminal(worktreePath: worktree, title: "jl-e2e-skill",
        command: ProjectCreationCoordinator.claudeCommand(folder: folder, sessionId: UUID().uuidString.lowercased(), name: "jl-e2e-skill"))
    let h = created.handle
    guard !preexisting.contains(h) else { log("핸들 충돌 — 중단"); return }
    var state = ScreenState.unknown
    for _ in 0..<40 {
        state = ScreenClassifier.classify((try? await orca.readScreen(handle: h)) ?? [])
        if case .dialog = state { _ = try? await orca.call(["terminal", "send", "--terminal", h, "--text", "\u{1b}"], as: Empty.self) }
        else if state.isReady { break }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    check("테스트 터미널 준비", state.isReady, "\(state)")

    // 3) 확인 → 1회 전송 (앱과 같은 DispatchCoordinator)
    let t = try await orca.showTerminal(handle: h)
    let project = ProjectRecord(alias: "skill-test", canonicalPath: worktree)
    let d = DispatchCoordinator(orca: orca)
    let out = await d.dispatch(text: skill.invocation, to: TargetSnapshot(project: project, terminal: t))
    let sent = await d.sendCount
    check("호출 문자열 1회 전송", out.label == "터미널에 전달됨" && sent == 1, "\(out.label) · \(skill.invocation)")
    var seen = false
    for _ in 0..<20 {
        let screen = (try? await orca.readScreen(handle: h)) ?? []
        if screen.contains(where: { $0.contains("JL-ECHO-OK") }) { seen = true; break }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    check("Claude가 스킬을 실행(화면에 JL-ECHO-OK)", seen, seen ? "" : "세션이 이 스킬을 인식하지 않았을 수 있음 — 화면 원문 확인 필요")
    if !seen {
        let tail = ((try? await orca.readScreen(handle: h)) ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(12)
        log("화면 끝부분:\n```\n\(tail.joined(separator: "\n"))\n```")
    }
    _ = try? await orca.call(["terminal", "close", "--terminal", h, "--tab"], as: Empty.self)
    var remaining = true
    for _ in 0..<10 where remaining {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        remaining = try await orca.listTerminals().terminals.contains { $0.handle == h }
    }
    log("테스트 터미널 정리: \(remaining ? "아직 남아 있음" : "닫힘 확인")")
    try lines.joined(separator: "\n").write(to: evidence.appendingPathComponent("skill-report.md"), atomically: true, encoding: .utf8)
}

struct Empty: Decodable {}
