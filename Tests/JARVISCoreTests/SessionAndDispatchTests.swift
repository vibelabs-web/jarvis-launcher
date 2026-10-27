import Foundation
import Testing
@testable import JARVISCore

private func project(_ path: String, alias: String = "p", worktreeId: String? = nil) -> ProjectRecord {
    ProjectRecord(alias: alias, canonicalPath: PathTools.canonical(path), worktreeId: worktreeId)
}

@Suite("AC-07~10 세션 탐색·재연결")
struct SessionRegistryTests {
    @Test("실측 형태 JSON을 해석하고 원격 호스트 누락을 읽는다 (AC-07)")
    func decodeRealShape() {
        let list = Fixture.terminalList()
        #expect(list.terminals.count == 3)
        #expect(list.hostScope?.omittedHostIds == ["runtime:remote-1"])
        let rows = SessionRegistry.pairableCandidates(list)
        #expect(rows.filter(\.pairable).map(\.terminal.handle) == ["term_a1", "term_b1"])
        #expect(rows.first { $0.terminal.handle == "term_s1" }?.pairable == false)
    }

    @Test("저장한 프로젝트가 앱 재시작 후 같은 터미널에 다시 짝지어진다 (AC-08)")
    func reconnects() {
        let list = Fixture.terminalList()
        let a = project("/tmp/jl/alpha-app", worktreeId: "repoA::/tmp/jl/alpha-app")
        let b = project("/tmp/jl/sales-dashboard")
        #expect(SessionRegistry.resolve(project: a, list: list).terminal?.handle == "term_a1")
        // B 경로의 분리된(orphaned) 셸은 후보에서 빠진다
        #expect(SessionRegistry.resolve(project: b, list: list).terminal?.handle == "term_b1")
    }

    @Test("핸들이 바뀌면 새 핸들로 매칭하고, 구 핸들 기준 확인 화면은 전송이 막힌다 (AC-09)")
    func handleChanged() async {
        var list = Fixture.terminalList()
        list.terminals[0].handle = "term_a2"
        list.terminals[0].incarnationId = "inc-a2"
        var a = project("/tmp/jl/alpha-app")
        a.lastRuntimeHandle = "term_a1"
        let state = SessionRegistry.resolve(project: a, list: list)
        #expect(state.terminal?.handle == "term_a2")

        // 확인 화면은 term_a1/inc-a1 기준이었는데 그 사이 Orca가 재시작된 경우
        let orca = FakeOrca()
        orca.setShow(TerminalCandidate(handle: "term_a1", incarnationId: "inc-a9", worktreePath: "/tmp/jl/alpha-app", agentIdentity: "claude"))
        orca.setScreen("term_a1", Fixture.lines("screen-normal-ready.txt"))
        let d = DispatchCoordinator(orca: orca)
        let out = await d.dispatch(text: "hi", to: TargetSnapshot(projectID: a.id, handle: "term_a1", incarnationId: "inc-a1",
                                                                 canonicalPath: a.canonicalPath, hostId: "local"))
        #expect(out == .blocked(.incarnationChanged))
        #expect(orca.sendCount == 0)
    }

    @Test("터미널이 사라지면 오프라인, 원격 호스트 누락이면 미확인")
    func offlineAndUnknown() {
        let list = Fixture.terminalList()
        #expect(SessionRegistry.resolve(project: project("/tmp/jl/gone"), list: list) == .offline(reason: "이 프로젝트의 Orca 터미널이 없습니다"))
        var remote = project("/tmp/jl/alpha-app")
        remote.hostId = "runtime:remote-1"
        if case .unknown = SessionRegistry.resolve(project: remote, list: list) {} else { Issue.record("원격은 미확인이어야 함") }
    }

    @Test("같은 폴더에 Claude 2개면 자동 확정하지 않는다 (AC-10)")
    func duplicateClaude() {
        var list = Fixture.terminalList()
        var dup = list.terminals[0]
        dup.handle = "term_a_dup"
        list.terminals.append(dup)
        let state = SessionRegistry.resolve(project: project("/tmp/jl/alpha-app"), list: list)
        guard case .needsConfirmation(let c, _) = state else { Issue.record("확인 필요여야 함: \(state)"); return }
        #expect(c.count == 2)
        #expect(state.terminal == nil)
    }

    @Test("경로·호스트가 빠진 응답이 섞이면 자동 확정하지 않는다 (AC-10)")
    func missingIdentity() {
        var list = Fixture.terminalList()
        list.terminals.append(TerminalCandidate(handle: "term_x", worktreePath: nil, executionHostId: nil, agentIdentity: "claude"))
        let state = SessionRegistry.resolve(project: project("/tmp/jl/alpha-app"), list: list)
        #expect(state.terminal == nil)
    }
}

@Suite("AC-13~15 전송 안전")
struct DispatchTests {
    let target = TargetSnapshot(projectID: UUID(), handle: "term_a1", incarnationId: "inc-a1",
                                canonicalPath: PathTools.canonical("/tmp/jl/alpha-app"), hostId: "local")

    func readyOrca() -> FakeOrca {
        let o = FakeOrca()
        o.setShow(Fixture.terminalList().terminals[0])
        o.setScreen("term_a1", Fixture.lines("screen-normal-ready.txt"))
        return o
    }

    @Test("확인 뒤 대상 폴더가 바뀌면 전송 0회 (AC-13)")
    func pathChanged() async {
        let o = readyOrca()
        var moved = Fixture.terminalList().terminals[0]
        moved.worktreePath = "/tmp/jl/other"
        o.setShow(moved)
        let out = await DispatchCoordinator(orca: o).dispatch(text: "작업해줘", to: target)
        guard case .blocked(.pathChanged) = out else { Issue.record("\(out)"); return }
        #expect(o.sendCount == 0)
    }

    @Test("확인 뒤 호스트가 바뀌면 전송 0회 (AC-13)")
    func hostChanged() async {
        let o = readyOrca()
        var moved = Fixture.terminalList().terminals[0]
        moved.executionHostId = "ssh:abc"
        o.setShow(moved)
        let out = await DispatchCoordinator(orca: o).dispatch(text: "작업해줘", to: target)
        guard case .blocked(.hostChanged) = out else { Issue.record("\(out)"); return }
        #expect(o.sendCount == 0)
    }

    @Test("대화상자가 떠 있으면 전송 0회")
    func dialogBlocks() async {
        let o = readyOrca()
        o.setScreen("term_a1", Fixture.lines("screen-mcp-dialog.txt"))
        let out = await DispatchCoordinator(orca: o).dispatch(text: "작업해줘", to: target)
        guard case .blocked(.screen) = out else { Issue.record("\(out)"); return }
        #expect(o.sendCount == 0)
    }

    @Test("정상이면 정확히 1회 전송하고 '터미널에 전달됨' (AC-14)")
    func deliversOnce() async {
        let o = readyOrca()
        let out = await DispatchCoordinator(orca: o).dispatch(text: "날짜 필터 고쳐줘", to: target)
        #expect(out == .delivered(requestId: "req-1"))
        #expect(out.label == "터미널에 전달됨")
        #expect(o.sendCount == 1)
        #expect(o.sentTexts.first?.text == "날짜 필터 고쳐줘")
    }

    @Test("중복 클릭은 1회만 처리 (AC-14)")
    func duplicateClick() async {
        let o = readyOrca()
        o.sendDelayNs = 200_000_000
        let d = DispatchCoordinator(orca: o)
        async let first = d.dispatch(text: "한 번만", to: target)
        try? await Task.sleep(nanoseconds: 50_000_000)
        async let second = d.dispatch(text: "한 번만", to: target)
        let (r1, r2) = await (first, second)
        #expect([r1, r2].contains(.rejectedDuplicate))
        #expect(o.sendCount == 1)
    }

    @Test("send 응답 시간 초과는 '상태 불명'이고 재전송하지 않는다 (AC-15)")
    func timeoutUnknown() async {
        let o = readyOrca()
        o.sendBehavior = { _ in throw OrcaError.timedOut(command: "terminal send") }
        let out = await DispatchCoordinator(orca: o).dispatch(text: "작업", to: target)
        guard case .unknown = out else { Issue.record("\(out)"); return }
        #expect(out.label == "전송 여부 불명")
        #expect(o.sendCount == 1)
    }

    @Test("입력 수락만 관찰되면 '상태 불명'")
    func acceptedOnly() {
        #expect(DeliveryOutcome.from(receipt: SendReceipt(accepted: true, stages: ["input_accepted"])).label == "전송 여부 불명")
        #expect(DeliveryOutcome.from(receipt: SendReceipt(accepted: false, stages: [])).label == "실패")
    }

    @Test("실측 receipt JSON을 해석한다")
    func decodeReceipt() throws {
        let env = try JSONDecoder().decode(OrcaEnvelope<SendResult>.self, from: Fixture.data("send-receipt-delivered.json"))
        #expect(env.result?.send.prompt?.stages == ["input_accepted", "turn_started"])
    }
}

@Suite("화면 판정")
struct ScreenClassifierTests {
    @Test func planReady() { #expect(ScreenClassifier.classify(Fixture.lines("screen-plan-ready.txt")) == .ready(planMode: true, busy: false)) }
    @Test func normalReady() { #expect(ScreenClassifier.classify(Fixture.lines("screen-normal-ready.txt")) == .ready(planMode: false, busy: false)) }
    @Test func mcpDialog() {
        guard case .dialog = ScreenClassifier.classify(Fixture.lines("screen-mcp-dialog.txt")) else { Issue.record("dialog여야 함"); return }
    }
    @Test func shell() { #expect(ScreenClassifier.classify(Fixture.lines("screen-shell.txt")) == .notClaude) }
    @Test func empty() { #expect(ScreenClassifier.classify([]) == .unknown) }
}
