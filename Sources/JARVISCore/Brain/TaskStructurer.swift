import Foundation

/// 받아쓴 말을 업무 지시 형태(목표 · 할 일 · 조건 · 확인할 점)로 정리한 결과.
/// 정리본은 입력창에 넣어 작가님이 고친 뒤 보낸다. 자동으로 보내지 않는다.
public struct StructuredTask: Equatable, Sendable {
    /// 받아쓴 원문. 작은 모델은 조건을 빠뜨리거나 뒤집을 수 있어 정리본 끝에 항상 함께 보낸다.
    public var transcript: String = ""
    public var goal: String
    public var background: String = ""
    public var actions: [String]
    public var constraints: [String]
    public var questions: [String]
    /// 원문의 숫자·경로·부정 표현 중 정리본에 빠진 것(검토용 경고)
    public var warnings: [String]

    public func text() -> String {
        var parts = ["목표: \(goal)"]
        if !background.isEmpty { parts.append("배경: \(background)") }
        parts.append("할 일\n" + actions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        if !constraints.isEmpty { parts.append("조건·하지 말 것\n" + constraints.map { "- \($0)" }.joined(separator: "\n")) }
        if !questions.isEmpty { parts.append("확인할 점\n" + questions.map { "- \($0)" }.joined(separator: "\n")) }
        if !transcript.isEmpty { parts.append("받아쓴 원문(위 정리와 다르면 원문을 따를 것)\n\(transcript)") }
        return parts.joined(separator: "\n\n")
    }
}

public enum TaskStructurer {
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "goal": ["type": "string"],
            "background": ["type": "string"],
            "actions": ["type": "array", "items": ["type": "string"]],
            "constraints": ["type": "array", "items": ["type": "string"]],
            "questions": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["goal", "background", "actions", "constraints", "questions"],
    ]

    static let system = """
    너는 사용자가 말로 한 작업 지시를 코딩 에이전트(Claude Code)에게 보낼 업무 지시로 정리하는 편집자다. 한국어로 쓴다.
    입력은 음성 받아쓰기라서 군말·반복·인식 오류가 섞여 있다.
    goal: 이루려는 것 한 문장.
    background: 사용자가 이 일을 원하는 이유·상황을 말했다면 1~2문장으로 요약. 없으면 빈 문자열.
    actions: 사용자가 말한 작업을 실행 순서대로 나눈 목록. 각 항목은 "~하기"로 끝나는 한 문장. 하지 말라는 것은 넣지 않는다.
    constraints: 사용자가 말한 금지·조건·범위. 무엇을 하지 말라는지 대상을 포함한 완전한 문장. 말하지 않았으면 빈 배열.
    questions: 말이 모호하거나 받아쓰기가 이상해 뜻을 확정할 수 없는 부분. 원래 구절을 따옴표로 인용해 묻는다. 없으면 빈 배열.
    규칙:
    - 사용자가 말하지 않은 작업 단계·세부 기술·조건을 지어내지 않는다. 생각을 길게 풀어 말했으면 그 안의 요구를 빠짐없이 actions로 옮긴다.
    - 받아쓰기 오류는 문맥상 확실할 때만 고친다(예: 프럼프트→프롬프트, 막다운→마크다운, Claude Code 맥락의 후기 이벤트→훅 이벤트). 확실하지 않으면 고치지 말고 questions에 넣는다.
    - 경로·파일명·숫자·명령·고유명사는 그대로 옮긴다.
    - 실행 환경·작업 폴더·저장소 상태에 대해 언급하지 않는다. 입력 문장만 보고 정리한다.
    예시)
    받아쓴 말: 어 결제 페이지 로딩이 느린데 api/payment 쪽 원인 찾아서 고쳐 주고 근데 결제 모듈 버전은 올리지 마
    출력: {"goal":"결제 페이지 로딩 속도 개선","background":"","actions":["api/payment 쪽에서 로딩이 느린 원인 찾기","원인 고치기"],"constraints":["결제 모듈 버전은 올리지 않기"],"questions":[]}
    출력은 JSON 객체 하나만.
    """

    /// LLM이 없거나 출력이 쓸 수 없으면 nil(받아쓴 원문을 그대로 둔다).
    public static func structure(transcript: String, llm: LocalLLM?) async -> StructuredTask? {
        guard let llm, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let raw = try? await llm.completeJSON(system: system, user: "받아쓴 말:\n\"\"\"\n\(transcript)\n\"\"\"", schema: schema)
        else { return nil }
        return parse(raw, original: transcript)
    }

    public static func parse(_ raw: String, original: String) -> StructuredTask? {
        guard let data = JSONExtract.firstObject(in: raw),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let goal = (o["goal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !goal.isEmpty else { return nil }
        func strings(_ k: String) -> [String] {
            ((o[k] as? [Any]) ?? []).compactMap { $0 as? String }
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }
                .filter { !$0.isEmpty }
        }
        // 하지 말라는 내용이 할 일에 섞이면 조건으로 옮긴다
        var actions: [String] = [], constraints: [String] = []
        // "깨지지 않게 확인하기"처럼 부정어가 섞인 할 일은 그대로 두고, 문장 끝이 금지형일 때만 옮긴다
        for a in strings("actions") { (isProhibition(a) ? { constraints.append(a) } : { actions.append(a) })() }
        // "하지 마"처럼 대상이 없는 조건은 버린다(무엇을 하지 말라는지 잃은 것)
        constraints = (constraints + strings("constraints")).filter { hasSubject($0) }
        // 원문에 부정 표현이 없는데 생긴 금지 조건은 모델이 지어낸 것이다(실측: "커버리지를 올리지 않기")
        if !PromptComposer.hasNegation(original) { constraints.removeAll(where: PromptComposer.hasNegation) }
        guard !actions.isEmpty else { return nil }
        var t = StructuredTask(goal: String(goal.prefix(300)), actions: Array(actions.prefix(12)),
                               constraints: Array(constraints.prefix(12)),
                               questions: Array(strings("questions").prefix(6)), warnings: [])
        t.background = String(((o["background"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        // 부정 조건은 '조건' 칸에 대상과 함께 있어야 한다. 할 일·목표에만 있으면 놓친 것으로 본다.
        // (원문을 붙이기 전의 정리본으로 검사한다)
        // 부정 경고는 '하지 마'·'말고' 같은 실제 금지 지시가 있을 때만 낸다
        // ("저장해 놓지 않는 이상", "없더라고" 같은 서술은 금지 지시가 아니다 — 실측 오탐)
        t.warnings = PromptComposer.preservationWarnings(original: original, body: t.text()).filter { !$0.contains("부정") }
        t.transcript = original
        if requestsProhibition(original) && !t.constraints.contains(where: PromptComposer.hasNegation) {
            t.warnings.append("원문의 부정·금지 조건이 정리본에 보이지 않습니다")
        }
        return t
    }

    /// 원문에 금지 지시가 있는가("건드리지 마", "고치지는 말고", "로그인은 빼고", "외부 API 금지")
    static func requestsProhibition(_ s: String) -> Bool {
        s.range(of: #"(지(는|도)?\s*(마|말)|하지\s*않(게|도록)\s*해|금지|빼고|제외하고|없이\s*해|don't|do not|never)"#,
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isProhibition(_ s: String) -> Bool {
        s.range(of: #"(않기|않는다|않을 것|말 것|말기|지\s*마(세요|라)?|금지)[.!]?\s*$"#, options: .regularExpression) != nil
    }

    /// 부정 표현을 빼고도 내용이 남아 있는가("하지 마", "말 것" 같은 빈 조건 거르기)
    static func hasSubject(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: #"(하지|말|마|않|기|것|도|는|은|아직|절대|\s|[.,!·-])"#, with: "", options: .regularExpression)
        return stripped.count >= 2
    }
}
