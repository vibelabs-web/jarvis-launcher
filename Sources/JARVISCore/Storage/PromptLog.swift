import CryptoKit
import Foundation
import SQLite3

/// 기록된 프롬프트 한 건(내보내기·목록용)
public struct PromptEntry: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var time: Date
    public var sessionId: String
    public var cwd: String
    public var project: String
    public var text: String
    /// 세션의 첫 프롬프트
    public var isFirst: Bool
    /// JARVIS 런처로 보낸 것(전송 기록과 짝지어짐)
    public var viaLauncher: Bool
    /// 받아쓰기였다면 받아쓴 원문
    public var transcript: String?
}

public enum PromptLogError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let m) = self { return "프롬프트 기록 DB 오류: \(m)" }; return nil }
}

/// 프롬프트 기록(작가님 결정 2026-10-28, ADR-8). Claude Code 훅이 `prompts`에, JARVIS 전송이 `launcher_sends`에 쓴다.
/// 비밀키처럼 보이는 문자열은 저장 전에 가린다. 음성은 저장하지 않는다.
public final class PromptLog {
    public let url: URL
    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    /// 런처 전송과 훅 기록을 같은 프롬프트로 보는 시간 범위
    static let pairWindow: TimeInterval = 300

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw PromptLogError.sqlite("열기 실패")
        }
        sqlite3_busy_timeout(db, 2000)
        try exec("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS prompts(id INTEGER PRIMARY KEY, ts REAL NOT NULL, session_id TEXT NOT NULL, cwd TEXT NOT NULL,
          project TEXT NOT NULL, text TEXT NOT NULL, text_sha TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS prompts_ts ON prompts(ts);
        CREATE INDEX IF NOT EXISTS prompts_sha ON prompts(text_sha);
        CREATE TABLE IF NOT EXISTS launcher_sends(id INTEGER PRIMARY KEY, ts REAL NOT NULL, text_sha TEXT NOT NULL,
          transcript TEXT, project TEXT NOT NULL, skill TEXT, outcome TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS sends_sha ON launcher_sends(text_sha);
        """)
    }

    deinit { sqlite3_close_v2(db) }

    /// 일시 중지 표시 파일(앱 스위치가 만들고 지운다. 훅은 이 파일이 있으면 기록하지 않는다)
    public var pauseMarker: URL { URL(fileURLWithPath: url.path + ".paused") }
    public var isPaused: Bool { FileManager.default.fileExists(atPath: pauseMarker.path) }
    public func setPaused(_ paused: Bool) {
        if paused { FileManager.default.createFile(atPath: pauseMarker.path, contents: Data()) }
        else { try? FileManager.default.removeItem(at: pauseMarker) }
    }

    // MARK: 쓰기

    /// 훅에서 부른다. 일시 중지 상태거나 빈 글이면 아무것도 하지 않고 false.
    @discardableResult
    public func record(prompt: String, sessionId: String, cwd: String, at time: Date = Date()) throws -> Bool {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPaused, !text.isEmpty else { return false }
        let masked = SecretMasker.mask(text)
        try run("INSERT INTO prompts(ts, session_id, cwd, project, text, text_sha) VALUES(?,?,?,?,?,?)",
                [.real(time.timeIntervalSince1970), .text(sessionId), .text(cwd),
                 .text(Self.projectName(cwd: cwd)), .text(masked), .text(Self.sha(text))])
        return true
    }

    /// JARVIS가 보낼 때 부른다. 훅 기록과 같은 글(sha)로 짝지어 받아쓴 원문·프로젝트를 붙인다.
    public func recordLauncherSend(text: String, transcript: String?, project: String, skill: String?, outcome: String,
                                   at time: Date = Date()) throws {
        guard !isPaused else { return }
        try run("INSERT INTO launcher_sends(ts, text_sha, transcript, project, skill, outcome) VALUES(?,?,?,?,?,?)",
                [.real(time.timeIntervalSince1970), .text(Self.sha(text.trimmingCharacters(in: .whitespacesAndNewlines))),
                 transcript.map { .text(SecretMasker.mask($0)) } ?? .null, .text(project), skill.map { .text($0) } ?? .null,
                 .text(outcome)])
    }

    public func delete(ids: [Int64]) throws {
        for id in ids { try run("DELETE FROM prompts WHERE id = ?", [.int(id)]) }
    }

    // MARK: 읽기

    public func projects() throws -> [String] {
        try query("SELECT DISTINCT project FROM prompts ORDER BY project", []) { s in Self.column(s, 0) }
    }

    /// 최신순. 검색은 본문·받아쓴 원문에서 대소문자 무시.
    public func entries(project: String? = nil, search: String? = nil, firstOnly: Bool = false, limit: Int = 1000) throws -> [PromptEntry] {
        let sql = """
        SELECT p.id, p.ts, p.session_id, p.cwd, p.project, p.text,
          p.ts = (SELECT MIN(q.ts) FROM prompts q WHERE q.session_id = p.session_id) AS first,
          (SELECT l.transcript FROM launcher_sends l WHERE l.text_sha = p.text_sha AND ABS(l.ts - p.ts) <= ?
             ORDER BY l.ts DESC LIMIT 1) AS transcript,
          EXISTS(SELECT 1 FROM launcher_sends l WHERE l.text_sha = p.text_sha AND ABS(l.ts - p.ts) <= ?) AS via
        FROM prompts p
        WHERE (? IS NULL OR p.project = ?)
        ORDER BY p.ts DESC
        """
        let rows = try query(sql, [.real(Self.pairWindow), .real(Self.pairWindow),
                                   project.map { .text($0) } ?? .null, project.map { .text($0) } ?? .null]) { s in
            PromptEntry(id: sqlite3_column_int64(s, 0), time: Date(timeIntervalSince1970: sqlite3_column_double(s, 1)),
                        sessionId: Self.column(s, 2), cwd: Self.column(s, 3), project: Self.column(s, 4), text: Self.column(s, 5),
                        isFirst: sqlite3_column_int(s, 6) != 0,
                        viaLauncher: sqlite3_column_int(s, 8) != 0,
                        transcript: sqlite3_column_type(s, 7) == SQLITE_NULL ? nil : Self.column(s, 7))
        }
        let q = (search ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return Array(rows.filter { e in
            (!firstOnly || e.isFirst) &&
            (q.isEmpty || e.text.lowercased().contains(q) || (e.transcript?.lowercased().contains(q) ?? false))
        }.prefix(limit))
    }

    // MARK: 내보내기

    /// 고른 프롬프트를 마크다운 하나로. 프로젝트별, 시간순. 최초 프롬프트는 ★.
    public static func markdown(_ entries: [PromptEntry], title: String = "프롬프트 기록", now: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var out = ["# \(title)", "", "내보낸 시각: \(df.string(from: now)) · \(entries.count)건", ""]
        let byProject = Dictionary(grouping: entries, by: \.project)
        for project in byProject.keys.sorted() {
            out.append("## \(project)")
            out.append("")
            for e in byProject[project]!.sorted(by: { $0.time < $1.time }) {
                var head = "### \(df.string(from: e.time))"
                if e.isFirst { head += " ★ 최초 프롬프트" }
                if e.viaLauncher { head += " · JARVIS" }
                out.append(head)
                out.append("")
                // 프롬프트 안의 ``` 와 겹치지 않도록 더 긴 울타리를 쓴다
                let fence = String(repeating: "`", count: max(3, longestBacktickRun(e.text) + 1))
                out.append(fence)
                out.append(e.text)
                out.append(fence)
                if let t = e.transcript, !t.isEmpty, !e.text.contains(t) {
                    out.append("")
                    out.append("<details><summary>받아쓴 원문</summary>")
                    out.append("")
                    out.append(t)
                    out.append("")
                    out.append("</details>")
                }
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }

    static func longestBacktickRun(_ s: String) -> Int {
        var best = 0, cur = 0
        for c in s { if c == "`" { cur += 1; best = max(best, cur) } else { cur = 0 } }
        return best
    }

    public static func projectName(cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "(알 수 없음)" : name
    }

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: SQLite

    enum Value { case int(Int64), real(Double), text(String), null }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            let m = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw PromptLogError.sqlite(m)
        }
    }

    private func prepare(_ sql: String, _ args: [Value]) throws -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else {
            throw PromptLogError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .int(let v): sqlite3_bind_int64(s, idx, v)
            case .real(let v): sqlite3_bind_double(s, idx, v)
            case .text(let v): sqlite3_bind_text(s, idx, v, -1, Self.transient)
            case .null: sqlite3_bind_null(s, idx)
            }
        }
        return s
    }

    private func run(_ sql: String, _ args: [Value]) throws {
        let s = try prepare(sql, args)
        defer { sqlite3_finalize(s) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw PromptLogError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    private func query<T>(_ sql: String, _ args: [Value], _ map: (OpaquePointer?) -> T) throws -> [T] {
        let s = try prepare(sql, args)
        defer { sqlite3_finalize(s) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(s)
            if rc == SQLITE_ROW { out.append(map(s)); continue }
            if rc == SQLITE_DONE { break }
            throw PromptLogError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return out
    }

    private static func column(_ s: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(s, i).map { String(cString: $0) } ?? ""
    }
}
