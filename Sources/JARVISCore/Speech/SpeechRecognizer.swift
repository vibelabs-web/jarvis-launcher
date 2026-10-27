import Foundation

public enum SpeechError: Error, Equatable, LocalizedError {
    case notConfigured(String)
    case failed(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let m): return "받아쓰기 설정 문제: \(m)"
        case .failed(let m): return "받아쓰기 실패: \(m)"
        case .empty: return "인식된 말이 없습니다"
        }
    }
}

public protocol SpeechRecognizer: Sendable {
    func transcribe(wav: URL) async throws -> String
}

/// 설치된 whisper.cpp `whisper-cli`를 재사용한다(ADR-1).
public struct WhisperCLIRecognizer: SpeechRecognizer {
    public let cliPath: String
    public let modelPath: String
    public var language = "ko"
    public var runner: CommandRunning = CLIProcessRunner()
    public var timeout: TimeInterval = 120

    public init(cliPath: String, modelPath: String) {
        self.cliPath = (cliPath as NSString).expandingTildeInPath
        self.modelPath = (modelPath as NSString).expandingTildeInPath
    }

    public func check() -> SpeechError? {
        if !FileManager.default.isExecutableFile(atPath: cliPath) { return .notConfigured("whisper-cli 없음: \(cliPath)") }
        if !FileManager.default.fileExists(atPath: modelPath) { return .notConfigured("모델 파일 없음: \(modelPath)") }
        return nil
    }

    public func transcribe(wav: URL) async throws -> String {
        if let e = check() { throw e }
        // 옵션 근거: qa/evidence/spike0/07-whisper-cli-help.txt
        let args = ["-m", modelPath, "-l", language, "-f", wav.path, "-nt", "-np"]
        let r = try await runner.run(executable: URL(fileURLWithPath: cliPath), arguments: args, timeout: timeout)
        guard r.exitCode == 0 else { throw SpeechError.failed("종료 코드 \(r.exitCode): \(r.stderr.suffix(300))") }
        let text = Self.clean(String(decoding: r.stdout, as: UTF8.self))
        if text.isEmpty { throw SpeechError.empty }
        return text
    }

    /// 빈 줄·whisper가 무음에 내는 표식([BLANK_AUDIO] 등)을 정리한다.
    public static func clean(_ raw: String) -> String {
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"\[[A-Z_ ]+\]|\([^)]*음악[^)]*\)"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
