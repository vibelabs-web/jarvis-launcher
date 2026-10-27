import AppKit
import SwiftUI
import JARVISCore

/// 프롬프트 입력창. 커서 위치를 모델에 알리고, 칩 위 목록이 열려 있으면 ↑↓·Enter·Esc를 목록 조작으로 쓴다.
/// ⌘↵ = 전송. 한글 조합 중(markedText)에는 목록이 닫혀 있으면 키를 가로채지 않는다.
/// 목록이 열려 있으면 ↵·Tab·↑↓ 전에 조합 중인 글자를 먼저 확정한다(한글 자판으로 `/검색어`를 친 경우).
final class ComposerTextView: NSTextView {
    weak var model: AppModel?
    var onCommitMarked: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        guard let model else { super.keyDown(with: event); return }
        let listKeys: Set<UInt16> = [36, 76, 48, 125, 126]
        if hasMarkedText() {
            guard model.listKind != nil, listKeys.contains(event.keyCode) else { super.keyDown(with: event); return }
            unmarkText()
            onCommitMarked?()
        }
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 36, 76:  // Return, keypad Enter
            if cmd { model.submit(); return }
            if model.listKind != nil { model.chooseHighlighted(); return }
        case 125 where model.listKind != nil: model.moveHighlight(1); return   // ↓
        case 126 where model.listKind != nil: model.moveHighlight(-1); return  // ↑
        case 48 where model.listKind != nil: model.chooseHighlighted(); return  // Tab
        case 53: model.escape(); return  // Esc
        default: break
        }
        super.keyDown(with: event)
    }
}

struct PromptTextView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var placeholder = "무엇을 도와드릴까요?  @ 프로젝트 · / 스킬 · ⌘↵ 보내기"

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = ComposerTextView()
        tv.model = model
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .labelColor
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = model.session.original
        tv.setAccessibilityLabel("프롬프트 입력")
        tv.setAccessibilityIdentifier("promptInput")
        scroll.documentView = tv
        context.coordinator.textView = tv
        tv.onCommitMarked = { [weak coordinator = context.coordinator] in coordinator?.push() }
        context.coordinator.placeholderView = makePlaceholder(in: tv)
        return scroll
    }

    private func makePlaceholder(in tv: NSTextView) -> NSTextField {
        let label = NSTextField(labelWithString: placeholder)
        label.textColor = .placeholderTextColor
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 9),
            label.topAnchor.constraint(equalTo: tv.topAnchor, constant: 6),
        ])
        label.isHidden = !tv.string.isEmpty
        return label
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        // 여기서 바꾸는 글자·커서는 모델에서 온 것이다. 델리게이트가 이를 다시 모델로 보내면
        // 화면 갱신 중에 상태가 바뀌어 갱신이 끝없이 반복될 수 있으므로 그동안은 무시한다.
        context.coordinator.applyingModel = true
        defer { context.coordinator.applyingModel = false }
        tv.model = model
        if tv.string != model.session.original && !tv.hasMarkedText() {
            tv.string = model.session.original
        }
        if let caret = model.pendingCaret {
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(caret, len), length: 0))
            model.caretUTF16 = min(caret, len)
            DispatchQueue.main.async { if model.pendingCaret != nil { model.pendingCaret = nil } }
        }
        context.coordinator.placeholderView?.isHidden = !tv.string.isEmpty
        tv.isEditable = model.phase == .compose || model.phase == .recording
        if context.coordinator.lastFocusTick != model.focusTick {
            context.coordinator.lastFocusTick = model.focusTick
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        weak var textView: ComposerTextView?
        weak var placeholderView: NSTextField?
        var lastFocusTick = -1
        var applyingModel = false

        init(model: AppModel) { self.model = model }

        func push() {
            guard let tv = textView else { return }
            MainActor.assumeIsolated {
                model.textChanged(tv.string, caret: tv.selectedRange().location)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, !applyingModel else { return }
            placeholderView?.isHidden = !tv.string.isEmpty
            // 한글 조합 중에는 확정 후에 반영한다(트리거 오인식 방지).
            // 단 목록이 열려 있으면 조합 중인 검색어도 바로 반영한다.
            let listOpen = MainActor.assumeIsolated { model.listKind != nil }
            guard !tv.hasMarkedText() || listOpen else { return }
            push()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, !applyingModel, !tv.hasMarkedText() else { return }
            MainActor.assumeIsolated {
                if model.session.original != tv.string {
                    model.textChanged(tv.string, caret: tv.selectedRange().location)
                } else {
                    model.caretMoved(tv.selectedRange().location)
                }
            }
        }
    }
}
