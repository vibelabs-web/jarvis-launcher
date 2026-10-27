import Foundation
import JARVISCore

/// 받아쓰기 → 업무 지시 정리를 실모델로 확인한다. 예시 발화는 받아쓰기처럼 군말·띄어쓰기 오류를 섞어 만든 가상 문장이다.
func runStructureBench(root: String) async throws {
    let llm = LlamaServerLLM(serverPath: "\(root)/.local-models/llama-b11606/llama-b11606/llama-server",
                             modelPath: "\(root)/.local-models/Qwen3-1.7B-Q4_K_M.gguf")
    let samples = [
        "음 그 매출 대시보드에서 날짜 필터가 이상한데 src/sales 쪽 보고 고쳐 주고 테스트도 돌려 줘 근데 DB 스키마는 건드리지 마",
        "로그인 화면 디자인 좀 바꿔 줘 버튼을 파란색으로 하고 비밀번호 찾기 링크 추가하고 어 그리고 모바일에서도 깨지지 않게 확인해 줘",
        "README 업데이트 해 줘 설치 방법이랑 실행 방법 정리하고 스크린샷은 아직 넣지 마",
        "어제 만든 API에서 500 에러가 나는데 원인 찾아서 알려만 줘 고치지는 말고",
        "테스트 커버리지 80퍼센트 넘게 올려 줘 우선 utils 폴더부터",
    ]
    var md = ["# 받아쓰기 → 업무 지시 정리 (실모델 Qwen3-1.7B Q4_K_M, \(ISO8601DateFormatter().string(from: Date())))", ""]
    for (i, s) in samples.enumerated() {
        let t0 = Date()
        let t = await TaskStructurer.structure(transcript: s, llm: llm)
        let secs = Date().timeIntervalSince(t0)
        md.append("## \(i + 1). (\(String(format: "%.2f", secs))초)")
        md.append("받아쓴 말: \(s)\n")
        if let t {
            md.append("```\n\(t.text())\n```")
            md.append(t.warnings.isEmpty ? "경고: 없음" : "경고: " + t.warnings.joined(separator: " · "))
        } else {
            md.append("정리 실패 → 원문 그대로 둠")
        }
        md.append("")
    }
    await llm.stop()
    let text = md.joined(separator: "\n")
    print(text)
    let dir = URL(fileURLWithPath: "\(root)/qa/evidence/dictation-structure", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try text.write(to: dir.appendingPathComponent("real-model-run.md"), atomically: true, encoding: .utf8)
}
