import Foundation

/// 사용자가 페어링한 프로젝트. 런타임 핸들은 저장하더라도 임시값으로 취급한다(PRD 5.6).
public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var alias: String
    /// realpath로 정규화한 Orca worktree 루트
    public var canonicalPath: String
    public var worktreeId: String?
    public var hostId: String
    /// 사용자가 적은 설명(추천에 쓰는 최소 메타데이터)
    public var note: String
    /// JARVIS가 `--session-id`로 직접 띄운 세션이면 그 UUID. Orca가 노출하지 않으므로 표시용이다.
    public var createdClaudeSessionId: String?
    public var lastRuntimeHandle: String?
    public var lastSeenAt: Date?

    public init(id: UUID = UUID(), alias: String, canonicalPath: String, worktreeId: String? = nil,
                hostId: String = "local", note: String = "", createdClaudeSessionId: String? = nil,
                lastRuntimeHandle: String? = nil, lastSeenAt: Date? = nil) {
        self.id = id
        self.alias = alias
        self.canonicalPath = canonicalPath
        self.worktreeId = worktreeId
        self.hostId = hostId
        self.note = note
        self.createdClaudeSessionId = createdClaudeSessionId
        self.lastRuntimeHandle = lastRuntimeHandle
        self.lastSeenAt = lastSeenAt
    }

    public var folderName: String { (canonicalPath as NSString).lastPathComponent }
}

public enum ConnectionState: Equatable, Sendable {
    case connected(TerminalCandidate)
    case needsConfirmation(candidates: [TerminalCandidate], reason: String)
    case offline(reason: String)
    case unknown(reason: String)

    public var label: String {
        switch self {
        case .connected: return "연결됨"
        case .needsConfirmation: return "사용자 확인 필요"
        case .offline: return "오프라인"
        case .unknown: return "미확인"
        }
    }

    public var terminal: TerminalCandidate? {
        if case .connected(let t) = self { return t }
        return nil
    }
}

/// 확인 화면에 보여 준 시점의 대상. 전송 직전 재조회 결과와 대조한다.
public struct TargetSnapshot: Equatable, Sendable {
    public var projectID: UUID
    public var handle: String
    public var incarnationId: String?
    public var canonicalPath: String
    public var hostId: String

    public init(projectID: UUID, handle: String, incarnationId: String?, canonicalPath: String, hostId: String) {
        self.projectID = projectID
        self.handle = handle
        self.incarnationId = incarnationId
        self.canonicalPath = canonicalPath
        self.hostId = hostId
    }

    public init(project: ProjectRecord, terminal: TerminalCandidate) {
        self.init(projectID: project.id, handle: terminal.handle, incarnationId: terminal.incarnationId,
                  canonicalPath: project.canonicalPath, hostId: project.hostId)
    }
}

public enum PathTools {
    /// 심볼릭 링크를 풀고 끝의 `/`를 없앤 절대 경로. 존재하지 않으면 표준화만 한다.
    public static func canonical(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(expanded, &buf) != nil {
            return String(cString: buf)
        }
        let std = (expanded as NSString).standardizingPath
        return std.count > 1 && std.hasSuffix("/") ? String(std.dropLast()) : std
    }
}
