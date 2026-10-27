import Foundation

/// 받아쓰기 정리를 Claude Code CLI(`claude -p`, Haiku 5.5)로 한다(작가님 결정 2026-10-28, ADR-7).
/// 받아쓴 말이 Anthropic 서버로 전송된다. 도구는 모두 끄고, 세션을 저장하지 않으며,
/// 설정·MCP·훅을 읽지 않고, 빈 전용 폴더에서 실행해 작업 환경 정보가 섞이지 않게 한다.
public struct ClaudeCLILLM: LocalLLM {
    public let cliPath: String
    public let model: String
    public let workDir: URL
    public let timeout: TimeInterval
    let runner: CommandRunning

    public init(cliPath: String, model: String = "claude-haiku-5-5", workDir: URL, timeout: TimeInterval = 45,
                runner: CommandRunning? = nil) {
        self.cliPath = cliPath
        self.model = model
        self.workDir = workDir
        self.timeout = timeout
        self.runner = runner ?? CLIProcessRunner(workingDirectory: workDir)
    }

    /// 실행 인자. 셸을 거치지 않고 배열로 넘긴다(받아쓴 말은 마지막 인자 하나).
    public func arguments(system: String, user: String, schema: [String: Any]) -> [String] {
        let schemaJSON = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return ["-p", "--model", model, "--output-format", "json", "--json-schema", schemaJSON,
                "--system-prompt", system, "--tools", "", "--no-session-persistence",
                "--setting-sources", "", "--strict-mcp-config", user]
    }

    public func completeJSON(system: String, user: String, schema: [String: Any]) async throws -> String {
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let r = try await runner.run(executable: URL(fileURLWithPath: cliPath),
                                     arguments: arguments(system: system, user: user, schema: schema), timeout: timeout)
        return try Self.extract(r)
    }

    /// `--output-format json` 결과에서 구조화 출력(없으면 result 문자열)을 꺼낸다.
    static func extract(_ r: CLIResult) throws -> String {
        guard let o = try? JSONSerialization.jsonObject(with: r.stdout) as? [String: Any] else {
            throw StructurerError.failed("claude 출력이 JSON이 아님(종료 코드 \(r.exitCode)): \(r.stderr.suffix(200))")
        }
        if (o["is_error"] as? Bool) == true || r.exitCode != 0 {
            let msg = (o["result"] as? String) ?? (o["api_error_status"].map { "\($0)" } ?? "")
            throw StructurerError.failed("claude 오류(종료 코드 \(r.exitCode)): \(msg.prefix(200))")
        }
        if let so = o["structured_output"], JSONSerialization.isValidJSONObject(so),
           let d = try? JSONSerialization.data(withJSONObject: so) {
            return String(decoding: d, as: UTF8.self)
        }
        if let s = o["result"] as? String { return s }
        throw StructurerError.failed("claude 출력에 결과가 없음")
    }

    /// PATH가 짧은 앱 환경에서도 찾도록 흔한 설치 위치를 본다.
    public static func locate(home: String = NSHomeDirectory()) -> String? {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public enum StructurerError: Error, Equatable, LocalizedError {
    case failed(String)
    public var errorDescription: String? {
        switch self { case .failed(let m): return "업무 정리 실패: \(m)" }
    }
}
