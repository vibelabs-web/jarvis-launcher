import Foundation

/// 받아쓴 말을 업무 지시 형태(목표 · 할 일 · 조건 · 확인할 점)로 정리한 결과.
/// 정리본은 입력창에 넣어 작가님이 고친 뒤 보낸다. 자동으로 보내지 않는다.
public struct StructuredTask: Equatable, Sendable {
    /// 받아쓴 원문. 작은 모델은 조건을 빠뜨리거나 뒤집을 수 있어 정리본 끝에 항상 함께 보낸다.
    public var transcript: String = ""
    public var goal: String
    public var actions: [String]
    public var constraints: [String]
    public var questions: [String]
    /// 원문의 숫자·경로·부정 표현 중 정리본에 빠진 것(검토용 경고)
    public var warnings: [String]

    public func text() -> String {
        var parts = ["목표: \(goal)"]
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
            "actions": ["type": "array", "items": ["type": "string"]],
            "constraints": ["type": "array", "items": ["type": "string"]],
            "questions": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["goal", "actions", "constraints", "questions"],
    ]

    static let system = """
    너는 사용자가 말로 한 작업 지시를 코딩 에이전트에게 보낼 업무 지시로 정리하는 편집자다. 한국어로 쓴다.
    goal: 이루려는 것 한 문장(명사형으로 끝낸다).
    actions: 해야 할 작업만 순서대로. 각 항목은 "~하기"로 끝나는 짧은 문장. 하지 말라는 것은 actions에 넣지 않는다.
    constraints: 금지·조건·범위. 무엇을 하지 말라는지 대상을 반드시 포함한 완전한 문장으로 쓴다. 없으면 빈 배열.
    questions: 모호해서 확인이 필요한 것. 없으면 빈 배열.
    원문에 없는 작업은 지어내지 않는다. 경로·파일명·숫자·고유명사는 그대로 옮긴다. "음", "어", "그" 같은 군말은 버린다.
    예시)
    받아쓴 말: 어 결제 페이지 로딩이 느린데 api/payment 쪽 원인 찾아서 고쳐 주고 근데 결제 모듈 버전은 올리지 마
    출력: {"goal":"결제 페이지 로딩 속도 개선","actions":["api/payment 쪽에서 로딩이 느린 원인 찾기","원인 고치기"],"constraints":["결제 모듈 버전은 올리지 않기"],"questions":[]}
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
        for a in strings("actions") { (PromptComposer.hasNegation(a) ? { constraints.append(a) } : { actions.append(a) })() }
        // "하지 마"처럼 대상이 없는 조건은 버린다(무엇을 하지 말라는지 잃은 것)
        constraints = (constraints + strings("constraints")).filter { hasSubject($0) }
        // 원문에 부정 표현이 없는데 생긴 금지 조건은 모델이 지어낸 것이다(실측: "커버리지를 올리지 않기")
        if !PromptComposer.hasNegation(original) { constraints.removeAll(where: PromptComposer.hasNegation) }
        guard !actions.isEmpty else { return nil }
        var t = StructuredTask(goal: String(goal.prefix(300)), actions: Array(actions.prefix(12)),
                               constraints: Array(constraints.prefix(12)),
                               questions: Array(strings("questions").prefix(6)), warnings: [])
        // 부정 조건은 '조건' 칸에 대상과 함께 있어야 한다. 할 일·목표에만 있으면 놓친 것으로 본다.
        // (원문을 붙이기 전의 정리본으로 검사한다)
        t.warnings = PromptComposer.preservationWarnings(original: original, body: t.text())
        t.transcript = original
        if PromptComposer.hasNegation(original) && !t.constraints.contains(where: PromptComposer.hasNegation),
           !t.warnings.contains(where: { $0.contains("부정") }) {
            t.warnings.append("원문의 부정·금지 조건이 정리본에 보이지 않습니다")
        }
        return t
    }

    /// 부정 표현을 빼고도 내용이 남아 있는가("하지 마", "말 것" 같은 빈 조건 거르기)
    static func hasSubject(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: #"(하지|말|마|않|기|것|도|는|은|아직|절대|\s|[.,!·-])"#, with: "", options: .regularExpression)
        return stripped.count >= 2
    }
}
