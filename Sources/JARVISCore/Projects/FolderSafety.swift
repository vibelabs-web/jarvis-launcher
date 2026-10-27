import Foundation

public enum FolderError: Error, Equatable, LocalizedError {
    case parentNotSet
    case parentMissing(String)
    case parentNotWritable(String)
    case invalidName(String)
    case escapesParent
    case alreadyExists(String)
    case createFailed(String)

    public var errorDescription: String? {
        switch self {
        case .parentNotSet: return "설정에서 기본 상위 폴더를 먼저 지정해 주세요"
        case .parentMissing(let p): return "상위 폴더가 없습니다: \(p)"
        case .parentNotWritable(let p): return "상위 폴더에 쓸 권한이 없습니다: \(p)"
        case .invalidName(let n): return "폴더 이름으로 쓸 수 없습니다: \(n) (영문 소문자·숫자·-·_만, 64자 이하)"
        case .escapesParent: return "상위 폴더 밖을 가리키는 경로는 만들 수 없습니다"
        case .alreadyExists(let p): return "이미 같은 이름이 있습니다(덮어쓰지 않음): \(p)"
        case .createFailed(let m): return "폴더 생성 실패: \(m)"
        }
    }
}

/// 새 프로젝트 폴더 안전 검사(PRD FR-09, AC-16). 기존 파일은 절대 덮어쓰지 않는다.
public enum FolderSafety {
    static let namePattern = #"^[a-z0-9][a-z0-9_-]{0,63}$"#

    public static func isValidName(_ name: String) -> Bool {
        name.range(of: namePattern, options: .regularExpression) != nil
    }

    /// 만들 경로를 계산하고 검사한다. 파일 시스템은 바꾸지 않는다.
    public static func plan(parent: String, name: String) -> Result<URL, FolderError> {
        guard !parent.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(.parentNotSet) }
        guard isValidName(name) else { return .failure(.invalidName(name)) }
        let fm = FileManager.default
        let parentReal = PathTools.canonical(parent)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: parentReal, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.parentMissing(parentReal))
        }
        guard access(parentReal, W_OK) == 0 else { return .failure(.parentNotWritable(parentReal)) }
        let target = URL(fileURLWithPath: parentReal, isDirectory: true).appendingPathComponent(name, isDirectory: true)
        guard PathTools.canonical(target.deletingLastPathComponent().path) == parentReal else { return .failure(.escapesParent) }
        // lstat: 깨진 심볼릭 링크까지 "존재"로 본다.
        var st = stat()
        if lstat(target.path, &st) == 0 { return .failure(.alreadyExists(target.path)) }
        return .success(target)
    }

    /// 단일 mkdir(중간 폴더 생성 없음). 경합으로 이미 생겼다면 실패한다.
    public static func create(parent: String, name: String) -> Result<URL, FolderError> {
        switch plan(parent: parent, name: name) {
        case .failure(let e): return .failure(e)
        case .success(let url):
            if mkdir(url.path, 0o755) != 0 {
                if errno == EEXIST { return .failure(.alreadyExists(url.path)) }
                return .failure(.createFailed(String(cString: strerror(errno))))
            }
            return .success(url)
        }
    }

    /// 셸에 입력되는 `--command`용 작은따옴표 이스케이프.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
