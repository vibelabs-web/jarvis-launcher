import Foundation
import JARVISCore

/// AC-11 추천 40건 + AC-12 실모델 메타 프롬프트 + AC-06 오프라인(외부 네트워크 차단 상태에서 실행).
/// 프로젝트 목록은 가상 후보다(실제 세션에 보내지 않음).
func runLLMBench(root: String) async throws {
    var md = ["# 로컬 LLM 벤치마크 (\(ISO8601DateFormatter().string(from: Date())))", ""]
    func log(_ s: String) { print(s); md.append(s) }

    // 0) 외부 네트워크가 실제로 막혀 있는지 확인(AC-06 전제)
    var external = "열림"
    do {
        var r = URLRequest(url: URL(string: "https://huggingface.co")!); r.timeoutInterval = 5
        _ = try await URLSession(configuration: .ephemeral).data(for: r)
    } catch { external = "차단됨(\((error as NSError).code))" }
    log("- 외부 네트워크(https://huggingface.co): **\(external)**")

    let server = "\(root)/.local-models/llama-b11606/llama-b11606/llama-server"
    let model = "\(root)/.local-models/Qwen3-1.7B-Q4_K_M.gguf"
    let llm = LlamaServerLLM(serverPath: server, modelPath: model)

    let p: [(alias: String, folder: String, note: String)] = [
        ("sales-dashboard", "sales-dashboard", "매출 대시보드. 매출 그래프, 날짜 필터, 지역별 집계"),
        ("고객관리", "crm-app", "고객 관리 앱. 고객 검색, 상담 기록"),
        ("독서메모", "reading-notes", "독서 메모 앱. 태그 검색, 책 목록"),
        ("유튜브업로드", "youtube-upload", "유튜브 영상 업로드 자동화, 썸네일, 자막"),
        ("관측대시보드", "obs-dashboard", "서버 로그·지표 관측 대시보드, 알림"),
        ("블로그", "blog-site", "개인 블로그 사이트, 글 목록, 댓글"),
    ]
    let cands = p.map { RouteCandidate(id: UUID(), alias: $0.alias, folderName: $0.folder, note: $0.note) }
    func id(_ i: Int) -> UUID { cands[i].id }

    // 명백 20건(기대 대상) / 모호 20건(자동 추천하면 안 됨)
    let clear: [(String, Int)] = [
        ("sales-dashboard에서 날짜 필터 버그 고쳐줘", 0), ("매출 그래프 지역별 집계가 틀려, 확인해줘", 0),
        ("매출 대시보드 첫 화면 로딩이 느려", 0), ("고객관리 앱에 상담 기록 내보내기 추가해줘", 1),
        ("crm-app 고객 검색이 안 돼", 1), ("고객 상담 기록 화면에 날짜 정렬 넣어줘", 1),
        ("독서메모에 태그 검색 기능 개선해줘", 2), ("reading-notes 책 목록 정렬 바꿔줘", 2),
        ("책 목록에 표지 이미지 보여줘", 2), ("유튜브 업로드 자동화에서 썸네일 생성 고쳐줘", 3),
        ("youtube-upload 자막 업로드가 실패해", 3), ("영상 업로드할 때 자막 언어를 한국어로 기본 설정해줘", 3),
        ("관측대시보드 알림이 너무 많이 와", 4), ("obs-dashboard 서버 지표 차트에 CPU 추가해줘", 4),
        ("서버 로그 검색 화면 만들어줘", 4), ("블로그 댓글 기능 스팸 막아줘", 5),
        ("blog-site 글 목록 페이지네이션 넣어줘", 5), ("개인 블로그 글 목록 디자인 바꿔줘", 5),
        ("고객관리 고객 검색 결과에 전화번호도 보여줘", 1), ("sales-dashboard 지역별 집계 표를 엑셀로 내보내줘", 0),
    ]
    let ambiguous = [
        "지난번 그거 고쳐줘", "대시보드 차트 좀 고쳐줘", "검색이 안 돼", "그 앱 로그인 붙여줘", "어제 하던 거 이어서 해줘",
        "목록 정렬 바꿔줘", "버그 있던 거 확인해줘", "테스트 돌려줘", "화면이 깨져 보여", "속도 좀 빠르게 해줘",
        "날짜 필터 고쳐줘", "알림 설정 바꿔줘", "디자인 다듬어줘", "배포 준비해줘", "에러 로그 확인해줘",
        "README 정리해줘", "업로드가 실패해", "목록에 이미지 넣어줘", "차트 추가해줘", "코드 리뷰 반영해줘",
    ]

    log(""); log("## AC-11 추천 (후보 6개, 규칙 → LLM, 후보 밖 ID·형식 오류는 폐기)")
    log(""); log("| 종류 | 요청 | 기대 | 추천 | 수동 선택 요구 | 출처 | 판정 | 지연(초) |"); log("|---|---|---|---|---|---|---|---|")
    var clearOK = 0, ambSafe = 0, lat: [Double] = []
    for (text, exp) in clear {
        let t0 = Date(); let d = await IntentRouter.route(text: text, candidates: cands, llm: llm); let dt = Date().timeIntervalSince(t0); lat.append(dt)
        let got = d.suggested.flatMap { s in cands.firstIndex { $0.id == s } }
        let ok = got == exp
        if ok { clearOK += 1 }
        log(String(format: "| 명백 | %@ | %@ | %@ | %@ | %@ | %@ | %.2f |", text, cands[exp].alias, got.map { cands[$0].alias } ?? "-",
                   d.needsUserSelection ? "예" : "아니오", d.source, ok ? "정답" : (got == nil ? "수동(안전)" : "오답"), dt))
    }
    for text in ambiguous {
        let t0 = Date(); let d = await IntentRouter.route(text: text, candidates: cands, llm: llm); let dt = Date().timeIntervalSince(t0); lat.append(dt)
        let got = d.suggested.flatMap { s in cands.firstIndex { $0.id == s } }
        let safe = got == nil || d.needsUserSelection
        if safe { ambSafe += 1 }
        log(String(format: "| 모호 | %@ | (수동) | %@ | %@ | %@ | %@ | %.2f |", text, got.map { cands[$0].alias } ?? "-",
                   d.needsUserSelection ? "예" : "아니오", d.source, safe ? "안전" : "자동확정(위험)", dt))
    }
    let s = lat.sorted()
    log(""); log(String(format: "**명백 정답 %d/20 · 모호 안전 %d/20 · 지연 P50 %.2fs / P95 %.2fs** (첫 요청은 모델 로드 포함)",
                        clearOK, ambSafe, s[s.count / 2], s[Int(Double(s.count) * 0.95) - 1]))
    log("- 어떤 경우든 앱은 추천만으로 보내지 않는다. 모호 요청에서 '자동확정'이 나와도 확인 화면에서 사용자가 대상을 확인해야 전송된다.")

    log(""); log("## AC-12 실모델 메타 프롬프트")
    for original in ["새로운 독서 메모 앱을 만들어보자. 노션처럼 태그 검색이 필요하고 ~/notes/books 폴더를 읽어. 로그인은 만들지 마.",
                     "매출 리포트 자동화 도구. 매주 월요일 9시에 CSV 3개를 합쳐서 PDF로. 외부 API는 쓰지 말 것."] {
        let t0 = Date(); let m = await PromptComposer.compose(original: original, llm: llm); let dt = Date().timeIntervalSince(t0)
        log(""); log(String(format: "### 원문: %@ (%.1f초, 출처 %@)", original, dt, m.source))
        log("- 원문 그대로 포함: \(m.markdown().contains(original) ? "예" : "아니오")")
        log("- 이름 제안: \(m.nameSuggestions.joined(separator: ", "))")
        log("- 보존 경고: \(m.preservationWarnings.isEmpty ? "없음" : m.preservationWarnings.joined(separator: " / "))")
        log("```markdown\n\(m.markdown())\n```")
    }

    // AC-06: 같은 차단 상태에서 받아쓰기 1회
    log(""); log("## AC-06 받아쓰기(외부 네트워크 차단 상태)")
    let work = URL(fileURLWithPath: "\(root)/.local-data/offline-audio", isDirectory: true)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    let aiff = work.appendingPathComponent("o.aiff"), wav = work.appendingPathComponent("o.wav")
    for (exe, args) in [("/usr/bin/say", ["-v", "Yuna", "-o", aiff.path, "오프라인에서도 받아쓰기가 됩니다"]),
                        ("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])] {
        let pr = Process(); pr.executableURL = URL(fileURLWithPath: exe); pr.arguments = args; try pr.run(); pr.waitUntilExit()
    }
    let stt = try? await WhisperCLIRecognizer(cliPath: "/opt/homebrew/bin/whisper-cli", modelPath: "~/.cache/whisper-cpp/ggml-small.bin").transcribe(wav: wav)
    log("- 결과: \(stt ?? "(실패)")")
    try? FileManager.default.removeItem(at: work)

    await llm.stop()
    let out = URL(fileURLWithPath: "\(root)/qa/evidence/AC-11/llm-bench-\(Int(Date().timeIntervalSince1970)).md")
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try md.joined(separator: "\n").replacingOccurrences(of: NSHomeDirectory(), with: "~").write(to: out, atomically: true, encoding: .utf8)
    print("saved: \(out.path)")
}
