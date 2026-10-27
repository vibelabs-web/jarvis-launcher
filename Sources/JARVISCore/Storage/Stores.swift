import Foundation

/// 앱 데이터 폴더. 개발·테스트 중에는 `JARVIS_DATA_DIR`로 프로젝트 안을 가리킨다(ADR-5).
public enum DataLocation {
    public static let bundleID = "dev.vibelabs.jarvis-launcher"

    public static func directory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let dir = environment["JARVIS_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }
}

/// 원자적으로 쓰는 단순 JSON 파일 저장소.
public struct JSONStore<Value: Codable> {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

public struct HotkeySetting: Codable, Equatable, Sendable {
    /// Carbon 가상 키코드. 기본 Space(49)
    public var keyCode: UInt32
    /// Carbon 수정키 마스크(cmdKey=256, shiftKey=512, optionKey=2048, controlKey=4096)
    public var modifiers: UInt32
    public static let `default` = HotkeySetting(keyCode: 49, modifiers: 4096 | 2048)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// 설정. 프롬프트 원문은 저장하지 않는다(PRD 5.9).
public struct Preferences: Codable, Equatable, Sendable {
    public var hotkey: HotkeySetting = .default
    public var defaultParentFolder: String = ""
    public var orcaPath: String = ""
    public var whisperCLIPath: String = "/opt/homebrew/bin/whisper-cli"
    public var whisperModelPath: String = "~/.cache/whisper-cpp/ggml-small.bin"
    public var llamaServerPath: String = ""
    public var llmModelPath: String = ""
    public var useLLM: Bool = true
    public var clearInputAfterSend: Bool = true
    /// 다음 호출 때 프로젝트 칩에 미리 채울 마지막 대상
    public var lastProjectID: UUID?

    public init() {}

    public init(from decoder: Decoder) throws {
        // 필드가 추가돼도 기존 설정 파일을 읽을 수 있게 하나씩 기본값으로 채운다.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var p = Preferences()
        p.hotkey = (try? c.decode(HotkeySetting.self, forKey: .hotkey)) ?? p.hotkey
        p.defaultParentFolder = (try? c.decode(String.self, forKey: .defaultParentFolder)) ?? p.defaultParentFolder
        p.orcaPath = (try? c.decode(String.self, forKey: .orcaPath)) ?? p.orcaPath
        p.whisperCLIPath = (try? c.decode(String.self, forKey: .whisperCLIPath)) ?? p.whisperCLIPath
        p.whisperModelPath = (try? c.decode(String.self, forKey: .whisperModelPath)) ?? p.whisperModelPath
        p.llamaServerPath = (try? c.decode(String.self, forKey: .llamaServerPath)) ?? p.llamaServerPath
        p.llmModelPath = (try? c.decode(String.self, forKey: .llmModelPath)) ?? p.llmModelPath
        p.useLLM = (try? c.decode(Bool.self, forKey: .useLLM)) ?? p.useLLM
        p.clearInputAfterSend = (try? c.decode(Bool.self, forKey: .clearInputAfterSend)) ?? p.clearInputAfterSend
        p.lastProjectID = try? c.decode(UUID.self, forKey: .lastProjectID)
        self = p
    }
}

public struct AppStores {
    public let directory: URL
    public let preferences: JSONStore<Preferences>
    public let projects: JSONStore<[ProjectRecord]>
    public let creations: JSONStore<[CreationCheckpoint]>

    public init(directory: URL = DataLocation.directory()) {
        self.directory = directory
        preferences = JSONStore(url: directory.appendingPathComponent("preferences.json"))
        projects = JSONStore(url: directory.appendingPathComponent("projects.json"))
        creations = JSONStore(url: directory.appendingPathComponent("creations.json"))
    }
}
