import Foundation

public enum OrcaError: Error, Equatable, LocalizedError {
    case notInstalled
    case commandFailed(command: String, message: String)
    case badResponse(command: String)
    case timedOut(command: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "Orca CLI를 찾을 수 없습니다"
        case .commandFailed(let c, let m): return "orca \(c) 실패: \(m)"
        case .badResponse(let c): return "orca \(c) 응답을 해석할 수 없습니다"
        case .timedOut(let c): return "orca \(c) 응답 시간 초과"
        }
    }
}

/// Orca 연동 추상화. 명령·필드 근거: docs/orca-cli-contract.md
public protocol OrcaAdapter: Sendable {
    func status() async throws -> OrcaStatus
    func listTerminals() async throws -> TerminalListResult
    func showTerminal(handle: String) async throws -> TerminalCandidate
    func readScreen(handle: String) async throws -> [String]
    /// 1회 전송. 재시도는 `retryRequestId`가 있을 때만(사용자 수동 재시도).
    func send(handle: String, text: String, waitSubmitSeconds: Int, retryRequestId: String?) async throws -> SendReceipt
    func createTerminal(worktreePath: String, title: String, command: String) async throws -> CreatedTerminal
    func waitFor(handle: String, condition: String, timeoutMs: Int) async throws -> WaitResult
    func addRepo(path: String) async throws -> RepoRecord
    func installedSkills() async throws -> [OrcaSkill]
}

public struct OrcaCLIAdapter: OrcaAdapter {
    public let executable: URL
    public let runner: CommandRunning
    public var defaultTimeout: TimeInterval = 15

    public init(executable: URL, runner: CommandRunning = CLIProcessRunner()) {
        self.executable = executable
        self.runner = runner
    }

    /// 설정값 → Orca.app 번들 → PATH 순서로 찾는다.
    public static func locate(configured: String?) -> URL? {
        var candidates: [String] = []
        if let c = configured, !c.isEmpty { candidates.append(c) }
        candidates.append("/Applications/Orca.app/Contents/Resources/bin/orca")
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates += path.split(separator: ":").map { "\($0)/orca" }
        candidates += ["/opt/homebrew/bin/orca", "/usr/local/bin/orca"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    public func call<T: Decodable>(_ args: [String], as: T.Type, timeout: TimeInterval? = nil) async throws -> T {
        let label = args.prefix(2).joined(separator: " ")
        let result: CLIResult
        do {
            result = try await runner.run(executable: executable, arguments: args + ["--json"], timeout: timeout ?? defaultTimeout)
        } catch CLIError.executableNotFound {
            throw OrcaError.notInstalled
        } catch CLIError.timedOut {
            throw OrcaError.timedOut(command: label)
        }
        let envelope = try? JSONDecoder().decode(OrcaEnvelope<T>.self, from: result.stdout)
        guard result.exitCode == 0, let envelope, envelope.ok, let value = envelope.result else {
            let msg = envelope?.error?.message ?? (result.stderr.isEmpty ? "종료 코드 \(result.exitCode)" : result.stderr)
            if envelope == nil && result.exitCode == 0 { throw OrcaError.badResponse(command: label) }
            throw OrcaError.commandFailed(command: label, message: SecretMasker.mask(String(msg.prefix(400))))
        }
        return value
    }

    public func status() async throws -> OrcaStatus {
        try await call(["status"], as: OrcaStatus.self, timeout: 5)
    }

    public func listTerminals() async throws -> TerminalListResult {
        try await call(["terminal", "list"], as: TerminalListResult.self)
    }

    public func showTerminal(handle: String) async throws -> TerminalCandidate {
        try await call(["terminal", "show", "--terminal", handle], as: TerminalShowResult.self, timeout: 5).terminal
    }

    public func readScreen(handle: String) async throws -> [String] {
        let r = try await call(["terminal", "read", "--terminal", handle, "--screen"], as: ScreenReadResult.self, timeout: 5)
        return r.terminal.tail ?? []
    }

    public func send(handle: String, text: String, waitSubmitSeconds: Int, retryRequestId: String?) async throws -> SendReceipt {
        var args = ["terminal", "send", "--terminal", handle, "--text", text, "--enter",
                    "--wait-submit", String(waitSubmitSeconds)]
        if let retryRequestId { args += ["--retry-request", retryRequestId] }
        let r = try await call(args, as: SendResult.self, timeout: TimeInterval(waitSubmitSeconds) + 10)
        return SendReceipt(accepted: r.send.accepted ?? false,
                           stages: r.send.prompt?.stages ?? [],
                           requestId: r.send.prompt?.requestId,
                           processIncarnation: r.send.prompt?.processIncarnation)
    }

    public func createTerminal(worktreePath: String, title: String, command: String) async throws -> CreatedTerminal {
        try await call(["terminal", "create", "--worktree", "path:\(worktreePath)", "--title", title, "--command", command],
                       as: TerminalCreateResult.self, timeout: 20).terminal
    }

    public func waitFor(handle: String, condition: String, timeoutMs: Int) async throws -> WaitResult {
        try await call(["terminal", "wait", "--terminal", handle, "--for", condition, "--timeout-ms", String(timeoutMs)],
                       as: TerminalWaitResult.self, timeout: TimeInterval(timeoutMs) / 1000 + 10).wait
    }

    public func addRepo(path: String) async throws -> RepoRecord {
        try await call(["repo", "add", "--path", path], as: RepoAddResult.self, timeout: 20).repo
    }

    public func installedSkills() async throws -> [OrcaSkill] {
        try await call(["skills", "installed"], as: SkillsInstalledResult.self, timeout: 20).skills
    }
}
