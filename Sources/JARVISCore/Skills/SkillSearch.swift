import Foundation

/// `/검색어`로 스킬을 찾는다. 이름 앞부분이 맞는 것 → 이름에 포함 → 설명에 포함 순서.
/// 한글 자판 상태로 친 검색어(`/ㅐㄱㅊㅁ`)는 두벌식 키 위치로 바꿔(`orca`) 함께 찾는다.
public enum SkillSearch {
    public static func rank(_ skills: [SkillEntry], query: String) -> [SkillEntry] {
        let q = query.lowercased()
        guard !q.isEmpty else { return skills }
        let queries = [q, HangulKeys.toQwerty(q)].compactMap { $0 }
        func score(_ s: SkillEntry) -> Int? {
            let name = s.name.lowercased()
            // 플러그인 스킬은 "/plugin:name" — 콜론 뒤 이름도 앞부분 일치로 본다
            let inv = String(s.invocation.lowercased().drop { $0 == "/" })
            let tail = inv.split(separator: ":").last.map(String.init) ?? inv
            var best: Int?
            for q in queries {
                let v: Int?
                if name == q || tail == q { v = 0 }
                else if name.hasPrefix(q) || tail.hasPrefix(q) || inv.hasPrefix(q) { v = 1 }
                else if name.contains(q) || inv.contains(q) { v = 2 }
                else if s.description.lowercased().contains(q) { v = 3 }
                else { v = nil }
                if let v { best = min(best ?? v, v) }
            }
            return best
        }
        return skills.enumerated()
            .compactMap { i, s in score(s).map { (s, $0, i) } }
            .sorted { ($0.1, $0.2) < ($1.1, $1.2) }
            .map(\.0)
    }
}

/// 한글 두벌식 자판으로 친 글자를 같은 키의 영문 소문자로 바꾼다. 한글이 없으면 nil.
public enum HangulKeys {
    private static let jamo: [Character: String] = [
        "ㅂ": "q", "ㅈ": "w", "ㄷ": "e", "ㄱ": "r", "ㅅ": "t", "ㅛ": "y", "ㅕ": "u", "ㅑ": "i", "ㅐ": "o", "ㅔ": "p",
        "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f", "ㅎ": "g", "ㅗ": "h", "ㅓ": "j", "ㅏ": "k", "ㅣ": "l",
        "ㅋ": "z", "ㅌ": "x", "ㅊ": "c", "ㅍ": "v", "ㅠ": "b", "ㅜ": "n", "ㅡ": "m",
        "ㅃ": "q", "ㅉ": "w", "ㄸ": "e", "ㄲ": "r", "ㅆ": "t", "ㅒ": "o", "ㅖ": "p",
        "ㅘ": "hk", "ㅙ": "ho", "ㅚ": "hl", "ㅝ": "nj", "ㅞ": "np", "ㅟ": "nl", "ㅢ": "ml",
        "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg", "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq", "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv", "ㅀ": "fg", "ㅄ": "qt",
    ]
    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { Optional($0) }

    public static func toQwerty(_ text: String) -> String? {
        var out = ""
        var sawHangul = false
        for ch in text {
            if let k = jamo[ch] { out += k; sawHangul = true; continue }
            if let v = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, (0xAC00...0xD7A3).contains(v) {
                let idx = Int(v - 0xAC00)
                let parts: [Character?] = [initials[idx / (21 * 28)], medials[(idx % (21 * 28)) / 28], finals[idx % 28]]
                for case let p? in parts { out += jamo[p] ?? "" }
                sawHangul = true
                continue
            }
            out.append(ch)
        }
        return sawHangul ? out.lowercased() : nil
    }
}

extension SkillSearch {
    /// 목록은 그대로 두고 입력한 철자에 가장 잘 맞는 줄의 위치를 돌려준다(타이핑으로 찾아가기). 없으면 nil.
    public static func bestIndex(in skills: [SkillEntry], query: String) -> Int? {
        guard !query.isEmpty, let best = rank(skills, query: query).first else { return nil }
        return skills.firstIndex { $0.id == best.id }
    }

    /// 목록 표시 순서: 호출 이름 알파벳순
    public static func displayOrder(_ skills: [SkillEntry]) -> [SkillEntry] {
        skills.sorted { $0.invocation.lowercased() < $1.invocation.lowercased() }
    }
}
