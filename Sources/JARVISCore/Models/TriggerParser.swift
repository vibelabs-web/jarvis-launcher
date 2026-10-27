import Foundation

/// 입력 중 `@`(프로젝트) · `/`(스킬) 트리거를 찾는다. 위치는 NSTextView와 같은 UTF-16 오프셋이다.
public enum TriggerKind: Equatable, Sendable {
    case project  // @
    case skill    // /
}

public struct ActiveTrigger: Equatable, Sendable {
    public var kind: TriggerKind
    /// 기호 뒤에 입력한 검색어
    public var query: String
    /// 기호부터 커서까지의 범위(UTF-16)
    public var range: NSRange
}

public enum TriggerParser {
    /// 커서 바로 앞 낱말이 줄 맨 앞이나 공백 뒤에서 시작하는 `@…` 또는 `/…`이면 트리거다.
    /// `a@b.com`, `~/x/y`, `/Users/me`(슬래시가 둘 이상) 같은 경로·주소는 트리거가 아니다.
    public static func active(in text: String, caretUTF16: Int) -> ActiveTrigger? {
        let ns = text as NSString
        let caret = min(max(caretUTF16, 0), ns.length)
        var start = caret
        while start > 0 {
            let c = ns.character(at: start - 1)
            if isSpace(c) { break }
            start -= 1
        }
        guard start < caret else { return nil }
        let token = ns.substring(with: NSRange(location: start, length: caret - start))
        guard let first = token.first else { return nil }
        let rest = String(token.dropFirst())
        let kind: TriggerKind
        switch first {
        case "@":
            guard !rest.contains("@") else { return nil }
            kind = .project
        case "/":
            guard !rest.contains("/"),
                  rest.allSatisfy({ $0.isLetter || $0.isNumber || "-_:.".contains($0) }) else { return nil }
            kind = .skill
        default:
            return nil
        }
        return ActiveTrigger(kind: kind, query: rest, range: NSRange(location: start, length: caret - start))
    }

    /// 트리거 토큰을 지우고(뒤따르는 공백 하나 포함) 새 텍스트와 커서 위치를 돌려준다.
    public static func removing(_ trigger: ActiveTrigger, from text: String) -> (text: String, caretUTF16: Int) {
        let ns = text as NSString
        guard NSMaxRange(trigger.range) <= ns.length else { return (text, ns.length) }
        var r = trigger.range
        if NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) == 0x20 { r.length += 1 }
        return (ns.replacingCharacters(in: r, with: ""), r.location)
    }

    private static func isSpace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x3000
    }
}
