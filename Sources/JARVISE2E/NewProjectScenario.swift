import Foundation
import JARVISCore

/// AC-16·17·18 실연동: Git 밖 테스트 상위 폴더에서 새 프로젝트를 만든다.
/// 1차는 준비 대기를 짧게 줘서 일부러 '중단'을 만들고, 2차 '이어하기'로 완료되는지 본다.
/// 정리: 이 시나리오가 만든 터미널만 닫고, 이 시나리오가 만든 Orca 등록만 해제한다(폴더는 남긴다).
func runNewProjectScenario(parent: String, orcaURL: URL, evidence: URL) async throws {
    let orca = OrcaCLIAdapter(executable: orcaURL)
    var lines = ["# 새 프로젝트 실연동 (AC-16·17·18)", "", "- 테스트 상위 폴더: \(parent)"]
    func log(_ s: String) { let m = s.replacingOccurrences(of: NSHomeDirectory(), with: "~"); print(m); lines.append(m) }
    func check(_ n: String, _ ok: Bool, _ d: String = "") { log("- [\(ok ? "PASS" : "FAIL")] \(n)\(d.isEmpty ? "" : " — \(d)")") }

    let parentReal = PathTools.canonical(parent)
    let gitTop = Process(); gitTop.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    gitTop.arguments = ["-C", parentReal, "rev-parse", "--show-toplevel"]
    gitTop.standardOutput = FileHandle.nullDevice; gitTop.standardError = FileHandle.nullDevice
    try gitTop.run(); gitTop.waitUntilExit()
    guard gitTop.terminationStatus != 0 else { log("상위 폴더가 Git 저장소 안이다 — 중단"); return }

    let preTerminals = Set(try await orca.listTerminals().terminals.map(\.handle))
    let preRepos = try await orca.call(["repo", "list"], as: RepoList.self).repos.map(\.id)

    // AC-16 안전 검사(실제 폴더): 존재·탈출·잘못된 이름
    let name = "jl-np-\(Int(Date().timeIntervalSince1970) % 1_000_000)"
    check("AC-16 상위 탈출 이름 거부", FolderSafety.plan(parent: parentReal, name: "../escape") == .failure(.invalidName("../escape")))

    let coordinator = ProjectCreationCoordinator(orca: orca, dispatcher: DispatchCoordinator(orca: orca))
    let prompt = PromptComposer.template(original: "E2E 테스트용 새 프로젝트입니다. 아무 것도 만들지 말고 '수신'이라고만 답해 주세요.").markdown()

    // 1차: Git이 아닌 빈 폴더 → Orca 등록 단계에서 '승인 필요'로 멈춰야 한다(실제 중단)
    var (cp, r1) = await coordinator.run(CreationCheckpoint(parent: parentReal, name: name), prompt: prompt)
    log("1차 실행: \(r1)")
    let stoppedForGit: Bool = { if case .stopped(.orca, _, true) = r1 { return cp.needsGitInit == true }; return false }()
    check("1차: Git 아님 → 승인 전 정지, 터미널·전송 0회", stoppedForGit && cp.terminalHandle == nil && cp.delivery == nil, cp.lastError ?? "")
    check("AC-16 폴더가 상위 폴더 안에 생성", cp.folderPath == "\(parentReal)/\(name)", cp.folderPath ?? "-")
    check("승인 전에는 git init 하지 않음", !FileManager.default.fileExists(atPath: "\(cp.folderPath ?? "")/.git"))

    // 2차: 사용자가 'Git 초기화 후 등록'을 승인한 상황 → 이어하기
    cp.gitInitApproved = true
    var (cp2, r2) = await coordinator.run(cp, prompt: prompt)
    log("2차(승인 후 이어하기): \(r2)")
    if case .stopped(.claudeReady, _, true) = r2, let h = cp2.terminalHandle, !preTerminals.contains(h) {
        // 대화상자: 테스트 터미널에서만 Esc(사람이 Orca에서 처리한 상황을 대신함) → 한 번 더 이어하기
        // 사람 역할 대행(테스트 폴더 한정): 폴더 신뢰 → ↓ + Enter("Yes, I trust this folder"), MCP 승인 → Esc(모두 거부).
        var answered: Set<String> = []
        for _ in 0..<20 {
            let lines = (try? await orca.readScreen(handle: h)) ?? []
            let st = ScreenClassifier.classify(lines)
            if case .dialog = st {
                let body = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(10).joined(separator: "\n")
                let isTrust = body.localizedCaseInsensitiveContains("trust this folder")
                let kind = isTrust ? "trust" : "other"
                if !answered.contains(kind) {
                    log("대화상자 원문(\(kind)):\n```\n\(body)\n```")
                    log("→ 테스트 대행 응답: \(isTrust ? "↓ + Enter (Yes, I trust this folder — 테스트 폴더 한정)" : "Esc (모두 거부)")")
                    answered.insert(kind)
                }
                if isTrust {
                    _ = try? await orca.call(["terminal", "send", "--terminal", h, "--text", "\u{1b}[B"], as: Empty.self)
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    _ = try? await orca.call(["terminal", "send", "--terminal", h, "--text", "\r"], as: Empty.self)
                } else {
                    _ = try? await orca.call(["terminal", "send", "--terminal", h, "--text", "\u{1b}"], as: Empty.self)
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                continue
            }
            if st.isReady || st == .notClaude { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        (cp2, r2) = await coordinator.run(cp2, prompt: prompt)
        log("3차(대화상자 처리 후 이어하기): \(r2)")
    }
    cp = cp2
    check("Git 밖 폴더가 승인된 git init 후 자기 경로로 등록", cp.gitInitialized == true && cp.worktreeRoot == cp.folderPath && cp.insideExistingRepo == false,
          "worktreeRoot=\(cp.worktreeRoot ?? "-")")
    if case .completed(let p, let out) = r2 {
        check("AC-17 플랜 모드 확인 후 1회 전달", out.label == "터미널에 전달됨", "경로 \(p.canonicalPath)")
    } else { check("AC-17 플랜 모드 확인 후 1회 전달", false, "\(r2)") }
    let newTerms = try await orca.listTerminals().terminals.filter { !preTerminals.contains($0.handle) }
    check("AC-18 이어하기 후 새 터미널 정확히 1개(중복 없음)", newTerms.count == 1, "\(newTerms.count)개")
    try? await Task.sleep(nanoseconds: 3_000_000_000)
    let screen = (try? await orca.readScreen(handle: cp.terminalHandle ?? "")) ?? []
    check("화면에 메타 프롬프트 도착", screen.contains { $0.contains("E2E 테스트용 새 프로젝트") })
    check("화면에 플랜 모드 표시", screen.contains { $0.contains("plan mode on") })
    let (_, r3) = await coordinator.run(cp, prompt: prompt)
    check("완료 후 재실행해도 재전송 없음", { if case .completed = r3 { return true }; return false }())

    // AC-16: 같은 이름 재생성 거부
    check("AC-16 이미 있는 폴더 거부(덮어쓰지 않음)", FolderSafety.plan(parent: parentReal, name: name) == .failure(.alreadyExists("\(parentReal)/\(name)")))

    // 정리
    if let h = cp.terminalHandle, !preTerminals.contains(h) {
        _ = try? await orca.call(["terminal", "close", "--terminal", h, "--tab"], as: Empty.self)
        var gone = false
        for _ in 0..<10 where !gone { try? await Task.sleep(nanoseconds: 1_000_000_000); gone = !(try await orca.listTerminals().terminals.contains { $0.handle == h }) }
        log("테스트 터미널 정리: \(gone ? "닫힘 확인" : "아직 남아 있음")")
    }
    let setups = try await orca.call(["project", "setups"], as: SetupList.self).setups
    let mine = setups.filter { PathTools.canonical($0.path ?? "") == cp.folderPath && !preRepos.contains($0.repoId ?? "-") }
    log("해제 대상 setup: \(mine.count)개 (이 시나리오가 등록한 경로만)")
    for s in mine {
        let ok = (try? await orca.call(["project", "setup-delete", "--setup", s.id, "--force"], as: Empty.self)) != nil
        log("Orca 등록 해제(\(s.id.prefix(8))…): \(ok ? "완료" : "실패")")
    }
    if mine.isEmpty { log("Orca 등록 해제: 대상 setup을 찾지 못함(수동 확인 필요)") }
    let stillListed = try await orca.call(["repo", "list"], as: RepoList.self).repos.contains { PathTools.canonical($0.path) == cp.folderPath }
    log("해제 후 repo 목록 잔존: \(stillListed ? "있음" : "없음")")
    log("테스트 폴더는 남겨 둠: \(cp.folderPath ?? "-")")
    try lines.joined(separator: "\n").write(to: evidence.appendingPathComponent("newproject-report.md"), atomically: true, encoding: .utf8)
}

struct RepoList: Decodable { let repos: [RepoRecord] }
struct SetupList: Decodable {
    struct Setup: Decodable { let id: String; let path: String?; let repoId: String? }
    let setups: [Setup]
}
