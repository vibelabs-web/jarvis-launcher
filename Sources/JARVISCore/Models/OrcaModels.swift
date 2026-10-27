import Foundation

/// `orca … --json` 공통 응답 봉투. 계약: docs/orca-cli-contract.md §1
public struct OrcaEnvelope<T: Decodable>: Decodable {
    public let ok: Bool
    public let result: T?
    public let error: OrcaErrorBody?
}

public struct OrcaErrorBody: Decodable, Equatable {
    public let code: String?
    public let message: String?
}

/// `terminal list/show`의 한 행. 모르는 필드는 nil로 둔다(PRD FR-04).
public struct TerminalCandidate: Codable, Equatable, Identifiable, Sendable {
    public var handle: String
    public var incarnationId: String?
    public var orphaned: Bool?
    public var worktreeId: String?
    public var worktreePath: String?
    public var title: String?
    public var connected: Bool?
    public var writable: Bool?
    public var executionHostId: String?
    public var agentIdentity: String?
    public var lastOutputAt: Double?

    public var id: String { handle }

    public init(handle: String, incarnationId: String? = nil, orphaned: Bool? = false,
                worktreeId: String? = nil, worktreePath: String? = nil, title: String? = nil,
                connected: Bool? = true, writable: Bool? = true, executionHostId: String? = "local",
                agentIdentity: String? = nil, lastOutputAt: Double? = nil) {
        self.handle = handle
        self.incarnationId = incarnationId
        self.orphaned = orphaned
        self.worktreeId = worktreeId
        self.worktreePath = worktreePath
        self.title = title
        self.connected = connected
        self.writable = writable
        self.executionHostId = executionHostId
        self.agentIdentity = agentIdentity
        self.lastOutputAt = lastOutputAt
    }

    public var isClaude: Bool { agentIdentity == "claude" }
    public var isLocal: Bool { executionHostId == "local" }
}

public struct TerminalListResult: Decodable, Sendable {
    public struct HostScope: Decodable, Sendable {
        public let hostIds: [String]?
        public let omittedHostIds: [String]?
        public init(hostIds: [String]?, omittedHostIds: [String]?) {
            self.hostIds = hostIds
            self.omittedHostIds = omittedHostIds
        }
    }
    public var terminals: [TerminalCandidate]
    public var hostScope: HostScope?
    public var truncated: Bool?

    public init(terminals: [TerminalCandidate], hostScope: HostScope? = nil, truncated: Bool? = false) {
        self.terminals = terminals
        self.hostScope = hostScope
        self.truncated = truncated
    }
}

public struct TerminalShowResult: Decodable { public let terminal: TerminalCandidate }

public struct ScreenReadResult: Decodable {
    public struct Body: Decodable {
        public let source: String?
        public let tail: [String]?
    }
    public let terminal: Body
}

public struct SendResult: Decodable {
    public struct Send: Decodable {
        public struct Prompt: Decodable {
            public let requestId: String?
            public let stages: [String]?
            public let processIncarnation: String?
        }
        public let accepted: Bool?
        public let prompt: Prompt?
    }
    public let send: Send
}

/// 전송 결과. CLI 수락과 Claude의 턴 시작을 구분한다(FR-08).
public struct SendReceipt: Equatable, Sendable {
    public var accepted: Bool
    public var stages: [String]
    public var requestId: String?
    public var processIncarnation: String?

    public init(accepted: Bool, stages: [String], requestId: String? = nil, processIncarnation: String? = nil) {
        self.accepted = accepted
        self.stages = stages
        self.requestId = requestId
        self.processIncarnation = processIncarnation
    }
}

public struct CreatedTerminal: Decodable, Equatable, Sendable {
    public let handle: String
    public let incarnationId: String?
    public let worktreeId: String?
    public let executionHostId: String?
}

public struct TerminalCreateResult: Decodable { public let terminal: CreatedTerminal }

public struct WaitResult: Decodable, Equatable, Sendable {
    public let satisfied: Bool?
    public let status: String?
    public let exitCode: Int?
}

public struct TerminalWaitResult: Decodable { public let wait: WaitResult }

public struct RepoRecord: Decodable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let kind: String?
}

public struct RepoAddResult: Decodable { public let repo: RepoRecord }
public struct RepoListResult: Decodable { public let repos: [RepoRecord] }

public struct OrcaStatus: Decodable, Sendable {
    public struct App: Decodable, Sendable { public let running: Bool? }
    public struct Runtime: Decodable, Sendable {
        public let state: String?
        public let reachable: Bool?
        public let appVersion: String?
    }
    public let app: App?
    public let runtime: Runtime?

    public var isReady: Bool { runtime?.state == "ready" && runtime?.reachable != false }
}

public struct OrcaSkill: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let providers: [String]?
    public let sourceKind: String?
    public let sourceLabel: String?
}

public struct SkillsInstalledResult: Decodable { public let skills: [OrcaSkill] }
