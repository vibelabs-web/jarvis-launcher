import Foundation

public struct CLIResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String
}

public enum CLIError: Error, Equatable, LocalizedError {
    case executableNotFound(String)
    case timedOut(seconds: Double)
    case outputTooLarge(limit: Int)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let p): return "실행 파일을 찾을 수 없습니다: \(p)"
        case .timedOut(let s): return "명령이 \(Int(s))초 안에 끝나지 않았습니다"
        case .outputTooLarge(let l): return "출력이 너무 큽니다(\(l) 바이트 초과)"
        case .launchFailed(let m): return "실행 실패: \(m)"
        }
    }
}

/// 외부 명령 실행 추상화. 테스트에서는 fake를 주입한다.
public protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CLIResult
}

/// 실행 파일 URL과 인자 배열만 받는다. 셸 문자열 보간은 하지 않는다(PRD 5.5).
public struct CLIProcessRunner: CommandRunning {
    public var maxOutputBytes: Int

    public init(maxOutputBytes: Int = 8 * 1024 * 1024) {
        self.maxOutputBytes = maxOutputBytes
    }

    public func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CLIResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CLIError.executableNotFound(executable.path)
        }
        let limit = maxOutputBytes
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let state = RunState()
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if !chunk.isEmpty { state.appendOut(chunk) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if !chunk.isEmpty { state.appendErr(chunk) }
            }
            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                state.appendOut(outPipe.fileHandleForReading.readDataToEndOfFile())
                state.appendErr(errPipe.fileHandleForReading.readDataToEndOfFile())
                guard state.finish() else { return }
                if state.outCount > limit {
                    continuation.resume(throwing: CLIError.outputTooLarge(limit: limit))
                    return
                }
                continuation.resume(returning: CLIResult(
                    exitCode: p.terminationStatus,
                    stdout: state.out,
                    stderr: SecretMasker.mask(String(decoding: state.err, as: UTF8.self))
                ))
            }
            do {
                try process.run()
            } catch {
                if state.finish() { continuation.resume(throwing: CLIError.launchFailed(error.localizedDescription)) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning, state.finish() else { return }
                process.terminate()
                continuation.resume(throwing: CLIError.timedOut(seconds: timeout))
            }
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private(set) var out = Data()
    private(set) var err = Data()
    var outCount: Int { lock.withLock { out.count } }

    func appendOut(_ d: Data) { lock.withLock { out.append(d) } }
    func appendErr(_ d: Data) { lock.withLock { if err.count < 64 * 1024 { err.append(d) } } }
    /// 처음 호출한 쪽만 true. continuation 이중 resume 방지.
    func finish() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

/// stderr·진단에 섞일 수 있는 비밀값과 홈 경로를 가린다.
public enum SecretMasker {
    public static func mask(_ s: String) -> String {
        var r = s
        let patterns: [(String, String)] = [
            (#"(?i)(api[_-]?key|token|secret|password|authorization)(["'\s:=]+)[^\s"']+"#, "$1$2<masked>"),
            (#"orca://pair\?[^\s"']+"#, "orca://pair?<masked>"),
            (#"sk-[A-Za-z0-9_\-]{10,}"#, "sk-<masked>"),
        ]
        for (p, template) in patterns {
            r = r.replacingOccurrences(of: p, with: template, options: .regularExpression)
        }
        r = r.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return r
    }
}
