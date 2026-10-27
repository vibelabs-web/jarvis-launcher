import AppKit
import SwiftUI
import JARVISCore

/// 프롬프트 입력창. 커서 위치를 모델에 알리고, 칩 위 목록이 열려 있으면 ↑↓·Enter·Esc를 목록 조작으로 쓴다.
/// ⌘↵ = 전송. 한글 조합 중(markedText)에는 키를 가로채지 않는다.
final class ComposerTextView: NSTextView {
    weak var model: AppModel?

    override func keyDown(with event: NSEvent) {
        guard let model, !hasMarkedText() else { super.keyDown(with: event); return }
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
        tv.model = model
        if tv.string != model.session.original && !tv.hasMarkedText() {
            tv.string = model.session.original
        }
        if let caret = model.pendingCaret {
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(caret, len), length: 0))
            DispatchQueue.main.async { model.pendingCaret = nil }
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

        init(model: AppModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            placeholderView?.isHidden = !tv.string.isEmpty
            // 한글 조합 중에는 확정 후에 반영한다(트리거 오인식 방지)
            guard !tv.hasMarkedText() else { return }
            MainActor.assumeIsolated {
                model.textChanged(tv.string, caret: tv.selectedRange().location)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, !tv.hasMarkedText() else { return }
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
