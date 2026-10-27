import Foundation

/// `terminal read --screen`의 화면 줄로 Claude Code TUI 상태를 판정한다.
/// 패턴은 Claude Code 2.1.311 기준 휴리스틱이다(docs/orca-cli-contract.md §4).
/// 애매하면 전송을 막는 쪽으로 판정한다.
public enum ScreenState: Equatable, Sendable {
    case ready(planMode: Bool, busy: Bool)
    case dialog(String)
    case notClaude
    case unknown

    public var isReady: Bool { if case .ready = self { return true } else { return false } }
}

public enum ScreenClassifier {
    static let dialogPatterns = [
        "Enable selected", "Esc to reject", "Do you trust", "trust the files",
        "Yes, proceed", "Do you want to", "Would you like to proceed", "❯ 1.", "Esc to cancel",
        "Press Enter to continue", "Select any you wish",
    ]
    /// zsh/bash 기본 프롬프트(`user@host 폴더 %`). Claude 상태줄의 '1.07$' 같은 끝 문자를 오인하지 않도록 엄격하게 본다.
    static let shellPromptPattern = #"^\S+@\S+ .*[%$#]\s*$"#

    /// 대화상자는 화면 하단에 그려지므로 마지막 20줄만 본다(대화 본문의 문장을 오인하지 않도록).
    public static func classify(_ allLines: [String]) -> ScreenState {
        let lines = Array(allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(20))
        // Claude가 끝나 셸로 돌아오면 위쪽에 대화상자 문구가 남아 있어도 셸 프롬프트가 우선이다(B11).
        if let last = lines.last, last.range(of: shellPromptPattern, options: .regularExpression) != nil {
            return .notClaude
        }
        let text = lines.joined(separator: "\n")
        if let hit = dialogPatterns.first(where: { text.contains($0) }) {
            let context = lines.first(where: { $0.contains(hit) })?.trimmingCharacters(in: .whitespaces) ?? hit
            return .dialog(context)
        }
        let planMode = lines.contains { $0.contains("plan mode on") }
        let promptLine = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("❯") }
        let busy = lines.contains { $0.contains("esc to interrupt") }
        if promptLine { return .ready(planMode: planMode, busy: busy) }
        return .unknown
    }

    /// Claude Code TUI 표지: 하단 상태줄 문구. Orca의 agentIdentity가 비었을 때 쓴다(Claude Code 2.1.311 기준).
    static let claudeFooterMarkers = ["shift+tab", "plan mode on", "bypass permissions", "accept edits",
                                      "? for shortcuts", "esc to interrupt", "auto-accept"]

    public static func looksLikeClaude(_ allLines: [String]) -> Bool {
        let lines = Array(allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(20))
        if let last = lines.last, last.range(of: shellPromptPattern, options: .regularExpression) != nil { return false }
        let text = lines.joined(separator: "\n")
        let hasPrompt = lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("❯") }
        return hasPrompt && claudeFooterMarkers.contains { text.contains($0) }
    }
}
