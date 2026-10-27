import Foundation

public enum SkillSource: String, Codable, Sendable {
    case personal = "개인"
    case project = "프로젝트"
    case legacyCommand = "레거시 명령"
    case plugin = "플러그인"
}

public enum SkillAvailability: String, Codable, Sendable {
    /// 파일로 존재를 확인함(세션 `/skills`로 확인한 것은 아님)
    case fileVerified = "파일 확인"
    /// Orca 목록에서만 확인됨. 호출명이 추정이다.
    case inferred = "추정"
    /// 이름 충돌 등으로 호출 차단
    case blocked = "차단"
}

public struct SkillEntry: Equatable, Identifiable, Sendable {
    public var name: String
    public var invocation: String
    public var description: String
    public var source: SkillSource
    public var availability: SkillAvailability
    public var note: String
    public var location: String?

    public var id: String { "\(source.rawValue):\(invocation)" }
    public var callable: Bool { availability != .blocked }
}

/// 스킬 발견(PRD 5.8). 파일 메타데이터만 읽고 본문의 지시는 실행하지 않는다.
/// 플러그인·내장·계정 동기화 스킬은 완전히 알 수 없으므로 "전체 목록"이라고 주장하지 않는다.
public enum SkillCatalog {
    public struct Roots: Sendable {
        public var personalSkills: URL
        public var personalCommands: URL
        public init(home: URL = URL(fileURLWithPath: NSHomeDirectory())) {
            personalSkills = home.appendingPathComponent(".claude/skills")
            personalCommands = home.appendingPathComponent(".claude/commands")
        }
    }

    public static func discover(roots: Roots, projectPath: String?, orcaSkills: [OrcaSkill]) -> [SkillEntry] {
        var entries: [SkillEntry] = []
        entries += scanSkills(dir: roots.personalSkills, source: .personal)
        entries += scanCommands(dir: roots.personalCommands, source: .legacyCommand)
        if let p = projectPath {
            let base = URL(fileURLWithPath: p)
            entries += scanSkills(dir: base.appendingPathComponent(".claude/skills"), source: .project)
            entries += scanCommands(dir: base.appendingPathComponent(".claude/commands"), source: .legacyCommand)
        }
        // Orca 목록에서 Claude 플러그인 스킬만 보강(파일 스캔으로 못 찾는 것)
        for s in orcaSkills where (s.providers ?? []).contains("claude") && (s.sourceLabel ?? "").hasPrefix("Claude plugin ") {
            let plugin = String((s.sourceLabel ?? "").dropFirst("Claude plugin ".count))
            entries.append(SkillEntry(name: s.name, invocation: "/\(plugin):\(s.name)", description: s.description ?? "",
                                      source: .plugin, availability: .inferred,
                                      note: "Orca 목록 기준. 세션에서 실제 사용 가능한지는 확인되지 않음", location: nil))
        }
        return markConflicts(entries)
    }

    /// 같은 호출명이 여러 출처에 있으면 정식 호출명이 확인될 때까지 모두 차단한다.
    static func markConflicts(_ entries: [SkillEntry]) -> [SkillEntry] {
        let counts = Dictionary(grouping: entries, by: \.invocation).mapValues(\.count)
        return entries.map { e in
            var e = e
            if counts[e.invocation, default: 0] > 1 {
                e.availability = .blocked
                e.note = "같은 이름이 \(counts[e.invocation]!)곳에 있어 호출 차단"
            }
            return e
        }.sorted { ($0.name, $0.source.rawValue) < ($1.name, $1.source.rawValue) }
    }

    static func scanSkills(dir: URL, source: SkillSource) -> [SkillEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { folder in
            let file = dir.appendingPathComponent(folder).appendingPathComponent("SKILL.md")
            guard let text = readHead(file) else { return nil }
            let fm = frontmatter(text)
            var note = ""
            if let n = fm["name"], n != folder { note = "frontmatter 이름(\(n))과 폴더 이름이 다름" }
            if fm["user-invocable"] == "false" { note = "user-invocable: false — 직접 호출 불가로 표시됨" }
            return SkillEntry(name: folder, invocation: "/\(folder)", description: fm["description"] ?? "",
                              source: source, availability: fm["user-invocable"] == "false" ? .blocked : .fileVerified,
                              note: note, location: file.path)
        }
    }

    static func scanCommands(dir: URL, source: SkillSource) -> [SkillEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".md") }.sorted().compactMap { f in
            let file = dir.appendingPathComponent(f)
            guard let text = readHead(file) else { return nil }
            let name = String(f.dropLast(3))
            return SkillEntry(name: name, invocation: "/\(name)", description: frontmatter(text)["description"] ?? "",
                              source: source, availability: .fileVerified, note: "", location: file.path)
        }
    }

    /// 앞부분만 읽는다(메타데이터용). 링크·권한 오류는 건너뛴다.
    static func readHead(_ url: URL, limit: Int = 16 * 1024) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: limit) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// 단순 YAML frontmatter(한 줄 key: value)만 읽는다. 형식이 깨지면 빈 값.
    public static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var out: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, f == "\"" || f == "'", value.last == f { value = String(value.dropFirst().dropLast()) }
            if !key.isEmpty && !value.isEmpty && value != "|" && value != ">" { out[key] = value }
        }
        return out
    }
}
