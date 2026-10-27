import Foundation
import JARVISCore

/// 최소 진단 로그. 프롬프트 원문·화면 내용은 기록하지 않는다(PRD 5.9, 6.5).
enum Diagnostics {
    private static let queue = DispatchQueue(label: "jarvis.diagnostics")
    static var url: URL { DataLocation.directory().appendingPathComponent("diagnostics.log") }

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(SecretMasker.mask(message))\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 1MB 넘으면 새로 시작
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
