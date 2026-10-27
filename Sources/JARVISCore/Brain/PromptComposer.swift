import Foundation

/// 메타 프롬프트 구조(FR-07). 원문은 앱이 그대로 넣고, LLM은 나머지 칸만 채운다.
public struct MetaPrompt: Equatable, Sendable {
    public var original: String
    public var purpose: String
    public var scope: [String]
    public var doneCriteria: [String]
    public var constraints: [String]
    public var questions: [String]
    public var firstStep: String
    public var nameSuggestions: [String]
    public var source: String  // "llm" | "template"
    /// 원문의 숫자·경로·부정 표현 중 LLM이 쓴 칸에 빠진 것(사용자 검토용 경고)
    public var preservationWarnings: [String]

    public func markdown() -> String {
        func list(_ xs: [String]) -> String { xs.isEmpty ? "- 미정" : xs.map { "- \($0)" }.joined(separator: "\n") }
        return """
        ## 사용자 원문
        \(original)

        ## 목적
        \(purpose.isEmpty ? "미정" : purpose)

        ## 범위
        \(list(scope))

        ## 완료 기준(초안)
        \(list(doneCriteria))

        ## 제약/금지
        \(list(constraints))

        ## 확인할 질문
        \(list(questions))

        ## 첫 작업
        \(firstStep.isEmpty ? "바로 구현하지 말고, 위 내용을 바탕으로 구현 계획부터 작성해 주세요." : firstStep)
        """
    }
}

public enum PromptComposer {
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "purpose": ["type": "string"],
            "scope": ["type": "array", "items": ["type": "string"]],
            "done_criteria": ["type": "array", "items": ["type": "string"]],
            "constraints": ["type": "array", "items": ["type": "string"]],
            "questions": ["type": "array", "items": ["type": "string"]],
            "first_step": ["type": "string"],
            "names": ["type": "array", "items": ["type": "string"]],
        ],
        "required": ["purpose", "scope", "done_criteria", "constraints", "questions", "first_step", "names"],
    ]

    static let system = """
    너는 새 소프트웨어 프로젝트 요청을 정리하는 편집자다. 사용자 원문을 바탕으로 한국어로 정리한다.
    원문에 없는 사실은 지어내지 말고, 모르면 questions에 넣는다. 부정문·경로·숫자·고유명사·명령은 그대로 옮긴다.
    first_step은 '바로 구현하지 말고 계획부터 작성'하는 내용이어야 한다.
    names는 프로젝트 폴더 이름 후보 1~3개(영문 소문자, 숫자, 하이픈만).
    출력은 JSON 객체 하나만.
    """

    /// LLM이 없거나 실패하면 템플릿으로 정리한다. 어떤 경우든 사용자가 편집할 수 있다.
    public static func compose(original: String, llm: LocalLLM?) async -> MetaPrompt {
        if let llm,
           let raw = try? await llm.completeJSON(system: system, user: "사용자 원문:\n\"\"\"\n\(original)\n\"\"\"", schema: schema),
           let parsed = parse(raw, original: original) {
            return parsed
        }
        return template(original: original)
    }

    public static func template(original: String) -> MetaPrompt {
        MetaPrompt(original: original, purpose: "", scope: [], doneCriteria: [], constraints: [], questions: [],
                   firstStep: "", nameSuggestions: [suggestName(from: original)], source: "template", preservationWarnings: [])
    }

    public static func parse(_ raw: String, original: String) -> MetaPrompt? {
        guard let data = JSONExtract.firstObject(in: raw),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let purpose = o["purpose"] as? String else { return nil }
        func strings(_ k: String) -> [String] { ((o[k] as? [Any]) ?? []).compactMap { $0 as? String }.map { String($0.prefix(300)) } }
        var names = strings("names").map(slugify).filter(FolderSafety.isValidName)
        if names.isEmpty { names = [suggestName(from: original)] }
        var m = MetaPrompt(original: original, purpose: String(purpose.prefix(500)), scope: strings("scope"),
                           doneCriteria: strings("done_criteria"), constraints: strings("constraints"),
                           questions: strings("questions"), firstStep: String(((o["first_step"] as? String) ?? "").prefix(500)),
                           nameSuggestions: Array(names.prefix(3)), source: "llm", preservationWarnings: [])
        m.preservationWarnings = preservationWarnings(original: original, generated: m)
        return m
    }

    /// 원문의 숫자·경로·부정 표현이 LLM이 쓴 칸에서 사라졌는지 확인한다(AC-12).
    /// 원문 자체는 항상 그대로 들어가므로 정보 손실은 없고, 경고는 검토용이다.
    public static func preservationWarnings(original: String, generated m: MetaPrompt) -> [String] {
        let body = ([m.purpose, m.firstStep] + m.scope + m.doneCriteria + m.constraints + m.questions).joined(separator: "\n")
        return preservationWarnings(original: original, body: body)
    }

    public static func preservationWarnings(original: String, body: String) -> [String] {
        var tokens: [String] = []
        let patterns = [#"[~/]?[\w.-]*/[\w./-]+"#, #"\d+(\.\d+)*"#]
        for p in patterns {
            let re = try! NSRegularExpression(pattern: p)
            let ns = original as NSString
            for match in re.matches(in: original, range: NSRange(location: 0, length: ns.length)) {
                tokens.append(ns.substring(with: match.range))
            }
        }
        var warnings = Set(tokens).filter { !body.contains($0) }.sorted().map { "원문의 '\($0)'이(가) 정리본에 없습니다" }
        if hasNegation(original) && !hasNegation(body) {
            warnings.append("원문의 부정·금지 조건이 정리본에 보이지 않습니다")
        }
        return warnings
    }

    /// 한국어 부정·금지 표현. "만들지 마", "하지 말 것" 같은 '-지 마/말' 형태 포함.
    static func hasNegation(_ s: String) -> Bool {
        let words = ["금지", "않", "없이", "빼고", "제외", "말고", "생략", "미포함", "불가", "don't", "do not", "never", "without"]
        return words.contains(where: s.lowercased().contains) || s.range(of: #"지\s*(마|말)"#, options: .regularExpression) != nil
    }

    public static func slugify(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let trimmed = lowered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// 원문의 영문 단어로 이름을 만들고, 없으면 날짜 기반 이름.
    public static func suggestName(from original: String, now: Date = Date()) -> String {
        let words = original.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .filter { $0.count >= 3 }.prefix(3).map(String.init)
        let slug = slugify(words.joined(separator: "-"))
        if FolderSafety.isValidName(slug) { return slug }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return "project-\(f.string(from: now))"
    }
}
