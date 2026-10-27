import Foundation
import JARVISCore

// Claude Code UserPromptSubmit 훅: 프롬프트를 JARVIS 프롬프트 기록(SQLite)에 남긴다(ADR-8).
// 절대 규칙 — 프롬프트를 막거나 바꾸지 않는다:
//   표준 출력에는 아무것도 쓰지 않는다(이 훅의 표준 출력은 Claude 문맥에 붙는다). 항상 exit 0. 1초 안에 못 쓰면 포기.
// 사용: jarvis-prompt-hook --db <경로/prompts.sqlite>

let args = CommandLine.arguments
guard let i = args.firstIndex(of: "--db"), i + 1 < args.count else { exit(0) }
let dbURL = URL(fileURLWithPath: args[i + 1])

func logError(_ message: String) {
    // 프롬프트 내용은 남기지 않는다
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    let url = dbURL.deletingLastPathComponent().appendingPathComponent("prompt-hook-errors.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

// 1초 감시: 넘기면 기록을 포기하고 그대로 끝낸다
DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
    logError("timeout")
    exit(0)
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let o = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let prompt = o["prompt"] as? String else {
    logError("bad-input bytes=\(input.count)")
    exit(0)
}
do {
    let log = try PromptLog(url: dbURL)
    try log.record(prompt: prompt, sessionId: (o["session_id"] as? String) ?? "?", cwd: (o["cwd"] as? String) ?? "")
} catch {
    logError("record-failed \(error.localizedDescription)")
}
exit(0)
