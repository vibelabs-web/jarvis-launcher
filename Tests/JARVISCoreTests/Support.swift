import Foundation
@testable import JARVISCore

enum Fixture {
    static func url(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    }
    static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }
    static func lines(_ name: String) -> [String] {
        String(decoding: data(name), as: UTF8.self).components(separatedBy: "\n")
    }
    static func terminalList() -> TerminalListResult {
        try! JSONDecoder().decode(OrcaEnvelope<TerminalListResult>.self, from: data("terminal-list.json")).result!
    }
}

/// 테스트 임시 폴더는 프로젝트 안(.local-data/test-tmp)에 만든다 — 프로젝트 밖 쓰기 금지.
enum TestDirs {
    static let root: URL = {
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return projectRoot.appendingPathComponent(".local-data/test-tmp", isDirectory: true)
    }()

    static func fresh(_ name: String) -> URL {
        let dir = root.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: PathTools.canonical(dir.path), isDirectory: true)
    }
}

/// 가짜 Orca. 호출 기록과 전송 횟수를 센다.
final class FakeOrca: OrcaAdapter, @unchecked Sendable {
    private let lock = NSLock()
    var list = TerminalListResult(terminals: [], hostScope: nil, truncated: false)
    var shows: [String: TerminalCandidate] = [:]
    var screens: [String: [String]] = [:]
    /// handle마다 화면 시퀀스(앞에서부터 하나씩 꺼냄, 마지막 것은 유지)
    var screenSequence: [String: [[String]]] = [:]
    var sendBehavior: (String) throws -> SendReceipt = { _ in SendReceipt(accepted: true, stages: ["input_accepted", "turn_started"], requestId: "req-1") }
    var addRepoBehavior: (String) throws -> RepoRecord = { RepoRecord(id: "repo-new", path: $0, kind: "folder") }
    var sendDelayNs: UInt64 = 0
    private(set) var sentTexts: [(handle: String, text: String)] = []
    private(set) var createdTerminals: [(path: String, command: String)] = []
    private(set) var addRepoCalls = 0

    var sendCount: Int { lock.withLock { sentTexts.count } }

    func status() async throws -> OrcaStatus { throw OrcaError.notInstalled }
    func listTerminals() async throws -> TerminalListResult { list }
    func showTerminal(handle: String) async throws -> TerminalCandidate {
        guard let t = lock.withLock({ shows[handle] }) else { throw OrcaError.commandFailed(command: "terminal show", message: "not found") }
        return t
    }
    func readScreen(handle: String) async throws -> [String] {
        lock.withLock {
            if var seq = screenSequence[handle], !seq.isEmpty {
                let first = seq.count > 1 ? seq.removeFirst() : seq[0]
                screenSequence[handle] = seq
                return first
            }
            return screens[handle] ?? []
        }
    }
    func send(handle: String, text: String, waitSubmitSeconds: Int, retryRequestId: String?) async throws -> SendReceipt {
        lock.withLock { sentTexts.append((handle, text)) }
        if sendDelayNs > 0 { try? await Task.sleep(nanoseconds: sendDelayNs) }
        return try sendBehavior(handle)
    }
    func createTerminal(worktreePath: String, title: String, command: String) async throws -> CreatedTerminal {
        let n = lock.withLock { () -> Int in
            createdTerminals.append((worktreePath, command))
            return createdTerminals.count
        }
        let handle = "term_new\(n)"
        lock.withLock {
            shows[handle] = TerminalCandidate(handle: handle, incarnationId: "inc-new\(n)", worktreeId: "repo-new::\(worktreePath)",
                                              worktreePath: worktreePath, agentIdentity: "claude")
        }
        return CreatedTerminal(handle: handle, incarnationId: "inc-new\(n)", worktreeId: nil, executionHostId: "local")
    }
    func waitFor(handle: String, condition: String, timeoutMs: Int) async throws -> WaitResult {
        WaitResult(satisfied: true, status: "running", exitCode: nil)
    }
    func addRepo(path: String) async throws -> RepoRecord {
        lock.withLock { addRepoCalls += 1 }
        return try addRepoBehavior(path)
    }
    func installedSkills() async throws -> [OrcaSkill] { [] }

    func setScreen(_ handle: String, _ lines: [String]) { lock.withLock { screens[handle] = lines } }
    func setShow(_ t: TerminalCandidate) { lock.withLock { shows[t.handle] = t } }
}

struct FakeLLM: LocalLLM {
    var output: String
    var fail = false
    func completeJSON(system: String, user: String, schema: [String: Any]) async throws -> String {
        if fail { throw LLMError.requestFailed("fake") }
        return output
    }
}
