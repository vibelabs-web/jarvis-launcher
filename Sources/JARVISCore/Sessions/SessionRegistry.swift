import Foundation

/// 저장된 프로젝트를 현재 Orca 터미널 목록에 다시 짝짓는다(PRD 5.6 재연결 알고리즘).
/// 재연결은 전송을 일으키지 않는다.
public enum SessionRegistry {
    public static func resolve(project: ProjectRecord, list: TerminalListResult,
                               canonicalize: (String) -> String = PathTools.canonical) -> ConnectionState {
        if let omitted = list.hostScope?.omittedHostIds, omitted.contains(project.hostId) {
            return .unknown(reason: "호스트 \(project.hostId)를 이번 조회에서 확인하지 못했습니다")
        }
        if project.hostId != "local" {
            return .unknown(reason: "원격 호스트 전송은 MVP 범위 밖입니다")
        }
        let samePath = list.terminals.filter { t in
            guard let p = t.worktreePath, t.executionHostId != nil else { return false }
            return t.executionHostId == project.hostId && canonicalize(p) == project.canonicalPath
        }
        let missingIdentity = list.terminals.filter { $0.worktreePath == nil || $0.executionHostId == nil }

        let claude = samePath.filter { $0.isClaude && $0.orphaned != true }
        let usable = claude.filter { $0.connected != false && $0.writable != false }

        if let wid = project.worktreeId, usable.contains(where: { $0.worktreeId != nil && $0.worktreeId != wid }) {
            return .needsConfirmation(candidates: usable, reason: "worktree 식별자가 저장값과 다릅니다")
        }
        switch usable.count {
        case 1 where missingIdentity.isEmpty:
            return .connected(usable[0])
        case 1:
            return .needsConfirmation(candidates: usable,
                                      reason: "경로·호스트를 알 수 없는 터미널이 \(missingIdentity.count)개 있어 자동 확정하지 않습니다")
        case 0:
            if !missingIdentity.isEmpty {
                return .unknown(reason: "경로·호스트를 알 수 없는 터미널이 있습니다")
            }
            if samePath.isEmpty { return .offline(reason: "이 프로젝트의 Orca 터미널이 없습니다") }
            return .offline(reason: "터미널은 있지만 Claude Code가 실행 중이 아닙니다")
        default:
            return .needsConfirmation(candidates: usable,
                                      reason: "같은 폴더에 Claude 세션이 \(usable.count)개 있습니다. Orca가 세션 ID를 제공하지 않아 직접 골라야 합니다")
        }
    }

    /// 설정 > 프로젝트 화면에 보여 줄 후보 목록. 페어링 가능 여부를 함께 표시한다.
    public static func pairableCandidates(_ list: TerminalListResult) -> [(terminal: TerminalCandidate, pairable: Bool, reason: String)] {
        list.terminals.map { t in
            if t.worktreePath == nil || t.executionHostId == nil { return (t, false, "미확인: 경로·호스트 정보 없음") }
            if !t.isLocal { return (t, false, "원격 호스트") }
            if t.orphaned == true { return (t, false, "분리된 터미널") }
            if !t.isClaude { return (t, false, "Claude Code 아님/미확인") }
            return (t, true, "Claude Code")
        }
    }
}
