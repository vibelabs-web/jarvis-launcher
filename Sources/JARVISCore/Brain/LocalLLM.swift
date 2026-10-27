import Foundation

public enum LLMError: Error, Equatable, LocalizedError {
    case notConfigured
    case startFailed(String)
    case requestFailed(String)
    case badOutput

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "로컬 LLM이 설정되지 않았습니다"
        case .startFailed(let m): return "로컬 LLM 시작 실패: \(m)"
        case .requestFailed(let m): return "로컬 LLM 요청 실패: \(m)"
        case .badOutput: return "로컬 LLM 출력 형식 오류"
        }
    }
}

/// 로컬 판단 모델. 결과는 항상 "검토 대상 데이터"이며 지시로 취급하지 않는다(FR-07).
public protocol LocalLLM: Sendable {
    /// JSON 객체 문자열을 돌려준다. `schema`는 JSON Schema(가능한 엔진에서 출력 제약에 사용).
    func completeJSON(system: String, user: String, schema: [String: Any]) async throws -> String
}

/// llama.cpp `llama-server`를 앱이 관리하는 127.0.0.1 서브프로세스로 띄운다(ADR-2).
/// 실행마다 무작위 포트·API 키를 쓰고, 첫 요청 때 띄우고 유휴 시간이 지나면 종료한다.
public actor LlamaServerLLM: LocalLLM {
    public nonisolated let serverPath: String
    public nonisolated let modelPath: String
    public var idleTimeout: TimeInterval = 300
    private var process: Process?
    private var port: Int = 0
    private var apiKey = ""
    private var idleTask: Task<Void, Never>?

    public init(serverPath: String, modelPath: String) {
        self.serverPath = (serverPath as NSString).expandingTildeInPath
        self.modelPath = (modelPath as NSString).expandingTildeInPath
    }

    public var isRunning: Bool { process?.isRunning == true }

    public func completeJSON(system: String, user: String, schema: [String: Any]) async throws -> String {
        try await ensureStarted()
        scheduleIdleStop()
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0.2,
            "max_tokens": 900,
            "response_format": ["type": "json_object", "schema": schema],
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await Self.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError.requestFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw LLMError.badOutput }
        return content
    }

    /// loopback 전용 세션(프록시 무시).
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.connectionProxyDictionary = [:]
        return URLSession(configuration: cfg)
    }()

    public func stop() {
        idleTask?.cancel()
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    private func scheduleIdleStop() {
        idleTask?.cancel()
        let timeout = idleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled { await self?.stop() }
        }
    }

    private func ensureStarted() async throws {
        if let p = process, p.isRunning { return }
        guard FileManager.default.isExecutableFile(atPath: serverPath),
              FileManager.default.fileExists(atPath: modelPath) else { throw LLMError.notConfigured }
        port = Self.freeLoopbackPort() ?? Int.random(in: 40000...59000)
        apiKey = UUID().uuidString + UUID().uuidString
        let p = Process()
        p.executableURL = URL(fileURLWithPath: serverPath)
        p.arguments = ["-m", modelPath, "--host", "127.0.0.1", "--port", String(port), "--api-key", apiKey,
                       "-c", "4096", "-ngl", "99", "--no-webui", "--jinja"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        do { try p.run() } catch { throw LLMError.startFailed(error.localizedDescription) }
        process = p
        // /health 가 200이 될 때까지 대기(모델 로드)
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            guard p.isRunning else { throw LLMError.startFailed("프로세스가 종료됨(종료 코드 \(p.terminationStatus))") }
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
            req.timeoutInterval = 2
            if let (_, r) = try? await Self.session.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        stop()
        throw LLMError.startFailed("60초 안에 모델을 불러오지 못했습니다")
    }

    static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0
            }
        }
        return ok ? Int(UInt16(bigEndian: addr.sin_port)) : nil
    }
}
