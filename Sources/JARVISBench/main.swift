import Foundation
import JARVISCore

/// AC-05 예비 측정: macOS TTS(ko_KR) 음성 → 앱과 같은 WhisperCLIRecognizer로 전사 → CER·RTF.
/// 작가님 실제 음성 40문장 측정을 대신하지 않는다(결과는 '예비'로 표시).
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
if CommandLine.arguments.dropFirst().first == "structure-stdin" {
    // 한 문장만 정리해 화면에 출력한다(파일로 남기지 않음 — 작가님 실제 발화 확인용)
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    let llm = ClaudeCLILLM(cliPath: ClaudeCLILLM.locate()!, workDir: URL(fileURLWithPath: "\(root)/.local-data/claude-structurer"))
    let t0 = Date()
    let t = await TaskStructurer.structure(transcript: text.trimmingCharacters(in: .whitespacesAndNewlines), llm: llm)
    print(String(format: "(%.2f초)", Date().timeIntervalSince(t0)))
    print(t?.text() ?? "정리 실패")
    print("경고: " + (t?.warnings.joined(separator: " · ") ?? "-"))
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "structure" {
    try await runStructureBench(root: root, engine: CommandLine.arguments.dropFirst(2).first ?? "local")
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "llm" {
    try await runLLMBench(root: root)
    exit(0)
}
let work = URL(fileURLWithPath: "\(root)/.local-data/bench-audio", isDirectory: true)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let sentences: [(group: String, text: String)] = [
    ("일반", "지난번에 만들던 대시보드 다시 열어 줘"),
    ("일반", "오늘 회의 내용을 정리해서 요약해 줘"),
    ("일반", "새로운 독서 메모 앱을 만들어 보자"),
    ("일반", "로그인 기능은 아직 만들지 마"),
    ("개발용어", "매출 그래프의 날짜 필터 버그 고쳐 줘"),
    ("개발용어", "리액트 컴포넌트를 타입스크립트로 바꿔 줘"),
    ("개발용어", "API 응답이 느리면 캐시를 추가해 줘"),
    ("개발용어", "깃허브 풀 리퀘스트 리뷰 코멘트 반영해 줘"),
    ("경로·명령", "src 폴더의 main 파일을 열어 줘"),
    ("경로·명령", "npm test 를 실행하고 결과 알려 줘"),
    ("경로·명령", "포트 3000 번 서버를 재시작해 줘"),
    ("경로·명령", "버전 2.1 로 올리고 체인지로그 써 줘"),
]

func run(_ exe: String, _ args: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: exe, code: Int(p.terminationStatus)) }
}

/// 공백·문장부호를 뺀 글자 단위 편집 거리 / 정답 길이
func cer(_ ref: String, _ hyp: String) -> Double {
    func norm(_ s: String) -> [Character] { Array(s.lowercased().filter { $0.isLetter || $0.isNumber }) }
    let a = norm(ref), b = norm(hyp)
    guard !a.isEmpty else { return b.isEmpty ? 0 : 1 }
    var prev = Array(0...b.count)
    for i in 1...a.count {
        var cur = [i] + Array(repeating: 0, count: b.count)
        for j in stride(from: 1, through: b.count, by: 1) {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return Double(prev[b.count]) / Double(a.count)
}

func duration(_ url: URL) -> Double {
    guard let h = try? FileHandle(forReadingFrom: url), let d = try? h.readToEnd() else { return 0 }
    return Double(max(d.count - 44, 0)) / (16_000 * 2)  // 16kHz mono 16-bit WAV
}

// 1) 음성 생성(16kHz mono WAV, 앱 MicRecorder와 같은 형식)
var wavs: [URL] = []
for (i, s) in sentences.enumerated() {
    let aiff = work.appendingPathComponent("s\(i).aiff"), wav = work.appendingPathComponent("s\(i).wav")
    if !FileManager.default.fileExists(atPath: wav.path) {
        try run("/usr/bin/say", ["-v", "Yuna", "-o", aiff.path, s.text])
        try run("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        try? FileManager.default.removeItem(at: aiff)
    }
    wavs.append(wav)
}

let models = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst())
    : ["~/.cache/whisper-cpp/ggml-small.bin", "~/whisper-models/ggml-large-v3-turbo.bin"]
var md = ["# 받아쓰기 예비 벤치마크 (\(ISO8601DateFormatter().string(from: Date())))", "",
          "- **예비 측정**: 음성은 macOS TTS(Yuna, ko_KR)로 만든 12문장. 작가님 실제 음성 40문장 측정(AC-05)을 대신하지 않는다.",
          "- 경로: 앱과 같은 `WhisperCLIRecognizer`(`whisper-cli -l ko -nt -np`). 1회 호출마다 모델을 새로 읽으므로 지연에 모델 로드가 포함된다.",
          "- CER: 공백·문장부호를 뺀 글자 편집 거리 ÷ 정답 글자 수. RTF = 전사 시간 ÷ 음성 길이.", ""]
for model in models {
    let rec = WhisperCLIRecognizer(cliPath: "/opt/homebrew/bin/whisper-cli", modelPath: model)
    if let e = rec.check() { md.append("## \(model)\n\n사용 불가: \(e.localizedDescription)\n"); continue }
    md += ["## \((model as NSString).lastPathComponent)", "", "| # | 분류 | 정답 | 전사 | CER | 지연(초) | RTF |", "|---|---|---|---|---|---|---|"]
    var cers: [Double] = [], lat: [Double] = [], rtfs: [Double] = []
    for (i, s) in sentences.enumerated() {
        let t0 = Date()
        let hyp = (try? await rec.transcribe(wav: wavs[i])) ?? "(실패)"
        let dt = Date().timeIntervalSince(t0), dur = duration(wavs[i])
        let c = cer(s.text, hyp)
        cers.append(c); lat.append(dt); rtfs.append(dur > 0 ? dt / dur : 0)
        md.append(String(format: "| %d | %@ | %@ | %@ | %.2f | %.2f | %.2f |", i + 1, s.group, s.text, hyp, c, dt, dur > 0 ? dt / dur : 0))
        print(String(format: "%@ #%d CER %.2f %.2fs  %@", (model as NSString).lastPathComponent, i + 1, c, dt, hyp))
    }
    let sorted = lat.sorted()
    func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)] }
    md += ["", String(format: "**평균 CER %.3f · 지연 P50 %.2fs / P95 %.2fs · 평균 RTF %.2f** (n=%d)", cers.reduce(0, +) / Double(cers.count),
                      pct(0.5), pct(0.95), rtfs.reduce(0, +) / Double(rtfs.count), cers.count)]
    for g in ["일반", "개발용어", "경로·명령"] {
        let idx = sentences.indices.filter { sentences[$0].group == g }
        md.append(String(format: "- %@ 평균 CER %.3f", g, idx.map { cers[$0] }.reduce(0, +) / Double(idx.count)))
    }
    md.append("")
}
let out = URL(fileURLWithPath: "\(root)/docs/model-benchmarks.md")
try md.joined(separator: "\n").replacingOccurrences(of: NSHomeDirectory(), with: "~").write(to: out, atomically: true, encoding: .utf8)
// 생성한 음성 파일은 지운다
try? FileManager.default.removeItem(at: work)
print("saved: docs/model-benchmarks.md")
