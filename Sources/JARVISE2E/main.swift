import Foundation
import JARVISCore

/// 실제 Orca·Claude Code로 AC-07·08·10·14·17·18을 확인한다. JARVIS 화면·키 이벤트 주입은 쓰지 않는다.
/// 안전 규칙: 이 프로그램이 만든 터미널 핸들에만 전송한다. 끝나면 만든 터미널을 닫는다.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
let evidenceDir = URL(fileURLWithPath: "\(root)/qa/evidence/e2e-\(stamp)")
try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
var report: [String] = ["# 실 Orca E2E \(stamp)", ""]
func log(_ s: String) {
    let masked = s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    print(masked); report.append(masked)
}
func check(_ name: String, _ ok: Bool, _ detail: String = "") { log("- [\(ok ? "PASS" : "FAIL")] \(name)\(detail.isEmpty ? "" : " — \(detail)")") }

guard let orcaURL = OrcaCLIAdapter.locate(configured: nil) else { print("orca not found"); exit(2) }
let orca = OrcaCLIAdapter(executable: orcaURL)
let before = try await orca.listTerminals()
let preexisting = Set(before.terminals.map(\.handle))
var created: [String] = []
func ours(_ h: String) -> Bool { created.contains(h) && !preexisting.contains(h) }

let sandboxParent = PathTools.canonical("\(root)/qa/sandbox")
try FileManager.default.createDirectory(atPath: sandboxParent, withIntermediateDirectories: true)
let worktreeRoot = PathTools.canonical(root)

// ── A. 기존 프로젝트 경로: 페어링 → 재연결 → 1회 전송 ─────────────────────────
log("## A. 기존 프로젝트 전송 (AC-07·08·10·14)")
let folderA = "\(sandboxParent)/e2e-a-\(stamp)"
try FileManager.default.createDirectory(atPath: folderA, withIntermediateDirectories: true)
let sessionA = UUID().uuidString.lowercased()
let termA = try await orca.createTerminal(worktreePath: worktreeRoot, title: "jl-e2e-a",
                                          command: ProjectCreationCoordinator.claudeCommand(folder: folderA, sessionId: sessionA, name: "jl-e2e-a"))
created.append(termA.handle)
log("테스트 터미널 생성: \(termA.handle.prefix(13))…")

// Claude 준비 대기. 기동 시 MCP 대화상자가 뜨면 테스트 터미널에서만 Esc(모두 거부)로 닫는다(앱은 자동 응답하지 않음).
func waitReady(_ h: String, dismissDialog: Bool) async -> ScreenState {
    var state = ScreenState.unknown
    for _ in 0..<40 {
        state = ScreenClassifier.classify((try? await orca.readScreen(handle: h)) ?? [])
        if case .dialog = state, dismissDialog, ours(h) {
            _ = try? await OrcaCLIAdapter(executable: orcaURL).call(["terminal", "send", "--terminal", h, "--text", "\u{1b}"], as: SendRawResult.self)
        } else if state.isReady { return state }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    return state
}
let readyA = await waitReady(termA.handle, dismissDialog: true)
check("테스트 터미널 Claude 준비", readyA.isReady, "\(readyA)")

let list = try await orca.listTerminals()
let rows = SessionRegistry.pairableCandidates(list)
check("AC-07 목록에 경로·호스트·종류 표시", !rows.isEmpty, "터미널 \(rows.count)개, 페어링 가능 \(rows.filter(\.pairable).count)개, 미확인/제외 \(rows.filter { !$0.pairable }.count)개")
let project = ProjectRecord(alias: "jarvis-launcher", canonicalPath: worktreeRoot, worktreeId: termA.worktreeId)
let stateA = SessionRegistry.resolve(project: project, list: list)
// 이 worktree에는 작업 중인 이 세션의 Claude도 있으므로 2개 이상 → 자동 확정 금지가 정답
if case .needsConfirmation(let c, let reason) = stateA {
    check("AC-10 같은 폴더 Claude 다중 → 자동 확정 안 함(실제 Orca)", true, "후보 \(c.count)개: \(reason)")
} else { check("AC-10 같은 폴더 Claude 다중 → 자동 확정 안 함(실제 Orca)", false, "\(stateA)") }

// 앱 재시작 상황: 저장 파일을 다시 읽어 재조회(핸들 대신 경로·호스트로)
let store = JSONStore<[ProjectRecord]>(url: evidenceDir.appendingPathComponent("projects.json"))
try store.save([project])
let reloaded = store.load()!.first!
let stateReload = SessionRegistry.resolve(project: reloaded, list: try await orca.listTerminals())
check("AC-08 저장·재로드 후 동일 판정(핸들 재조회)", stateReload.label == stateA.label, stateReload.label)

// 사용자가 테스트 터미널을 직접 고른 상황 → 1회 전송
guard case .needsConfirmation(let candsA, _) = stateA, let tA = candsA.first(where: { $0.handle == termA.handle }), ours(tA.handle) else {
    log("테스트 터미널을 후보에서 찾지 못해 전송 생략"); exit(1)
}
let dispatcher = DispatchCoordinator(orca: orca)
let target = TargetSnapshot(project: project, terminal: tA)
async let o1 = dispatcher.dispatch(text: "JARVIS E2E 테스트입니다. 아무 작업도 하지 말고 '수신' 이라고만 답해 주세요.", to: target)
try? await Task.sleep(nanoseconds: 100_000_000)
async let o2 = dispatcher.dispatch(text: "중복 클릭", to: target)
let (r1, r2) = await (o1, o2)
check("AC-14 1회 전송 → 터미널에 전달됨", r1.label == "터미널에 전달됨", r1.label)
check("AC-14 중복 클릭은 처리 안 함", r2 == .rejectedDuplicate, r2.label)
let sentAfterA = await dispatcher.sendCount
check("AC-14 실제 send 호출 수", sentAfterA == 1, "\(sentAfterA)회")
try? await Task.sleep(nanoseconds: 6_000_000_000)
let screenAfter = (try? await orca.readScreen(handle: termA.handle)) ?? []
check("AC-14 화면에 프롬프트 도착", screenAfter.contains { $0.contains("JARVIS E2E 테스트") }, "")
check("중복 문구는 도착하지 않음", !screenAfter.contains { $0.contains("중복 클릭") }, "")

// AC-13 실제 환경: 확인 화면의 incarnation과 다르면 전송 0회
var stale = target; stale.incarnationId = "stale-incarnation"
let r3 = await dispatcher.dispatch(text: "보내지면 안 됨", to: stale)
let sentAfterStale = await dispatcher.sendCount
check("AC-13 확인 후 프로세스 변경 → 전송 0회", r3 == .blocked(.incarnationChanged) && sentAfterStale == 1, r3.label)

// ── B. 새 프로젝트: 폴더 → Orca → 터미널 → 플랜 모드 → 1회 전송 (+이어하기) ──
log(""); log("## B. 새 프로젝트 (AC-16·17·18)")
var coordinator = ProjectCreationCoordinator(orca: orca, dispatcher: DispatchCoordinator(orca: orca))
coordinator.readyTimeout = 45
let cp0 = CreationCheckpoint(parent: sandboxParent, name: "e2e-b-\(stamp.replacingOccurrences(of: "-", with: ""))")
let meta = PromptComposer.template(original: "E2E 테스트용 새 프로젝트. 아무 것도 만들지 말고 계획 대신 '수신'이라고만 답해 주세요.").markdown()
var (cp, result) = await coordinator.run(cp0, prompt: meta)
if let h = cp.terminalHandle { created.append(h) }
log("1차 실행: \(result)")
if case .stopped(.claudeReady, let msg, true) = result {
    check("AC-17 대화상자/미확인 상태에서 전송하지 않고 단계 표시", true, msg)
    if let h = cp.terminalHandle, ours(h) {
        _ = await waitReady(h, dismissDialog: true)   // 테스트에서만: Orca에서 사람이 처리한 상황을 대신함
    }
    (cp, result) = await coordinator.run(cp, prompt: meta)
    log("이어하기: \(result)")
}
if case .completed(let p, let out) = result {
    check("AC-17 플랜 모드 확인 후 1회 전달", out.label == "터미널에 전달됨", "경로 \(p.canonicalPath)")
    check("AC-18 이어하기에서 터미널 중복 생성 없음", Set(created).count == created.count, "만든 터미널 \(created.count)개")
    let (_, again) = await coordinator.run(cp, prompt: meta)
    check("완료 후 재실행해도 재전송 없음", { if case .completed = again { return true }; return false }())
} else {
    check("AC-17 플랜 모드 확인 후 1회 전달", false, "\(result)")
}
check("새 폴더가 기본 상위 폴더 안에 생성", cp.folderPath?.hasPrefix(sandboxParent + "/") == true, cp.folderPath ?? "-")
log("참고: 샌드박스가 Git 저장소 안이라 repo add는 상위 저장소로 해석됨(insideExistingRepo=\(cp.insideExistingRepo ?? false)). Git 밖 폴더 등록은 미검증.")

// ── 정리: 만든 터미널만 닫는다 ─────────────────────────────────────────────
log(""); log("## 정리")
for h in Set(created) where ours(h) {
    _ = try? await OrcaCLIAdapter(executable: orcaURL).call(["terminal", "close", "--terminal", h, "--tab"], as: SendRawResult.self)
    let w = try? await orca.waitFor(handle: h, condition: "exit", timeoutMs: 10_000)
    log("닫기 \(h.prefix(13))… → \(w?.status ?? "확인 불가")")
}
try report.joined(separator: "\n").write(to: evidenceDir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
print("saved: \(evidenceDir.path)")

/// 결과 본문이 필요 없는 명령용
struct SendRawResult: Decodable {}
