import AppKit
import Combine
import SwiftUI
import JARVISCore

/// 입력 포커스를 받을 수 있는 비활성(nonactivating) 패널.
final class PromptPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Esc: 기록은 남기고 패널만 닫는다(FR-01)
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class PanelController {
    private let panel: PromptPanel
    private let model: AppModel
    private var bag: Set<AnyCancellable> = []
    static let width: CGFloat = 680

    init(model: AppModel) {
        self.model = model
        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.onCancel = { [weak model] in model?.escape() }

        // 반투명 배경. "투명도 줄이기" 설정이면 macOS가 자동으로 불투명하게 그린다(PRD 4.1).
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        let host = NSHostingView(rootView: PromptRootView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur
        model.onRequestHide = { [weak self] in self?.hide() }
        // 목록·결과 줄·새 프로젝트 카드가 열리고 닫힐 때 높이를 맞춘다(위쪽 모서리 고정)
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if abs(self.panel.frame.height - self.model.panelHeight) > 1 { self.resize(height: self.model.panelHeight) }
            }
            .store(in: &bag)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let frame = PanelGeometry.frame(contentSize: CGSize(width: Self.width, height: model.panelHeight), visibleFrame: vf)
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.panelDidShow()
        let screenIndex = NSScreen.screens.firstIndex { $0 == screen } ?? -1
        let inside = vf.contains(frame)
        Diagnostics.log("panel.show screen=\(screenIndex) frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width))x\(Int(frame.height)) insideVisibleFrame=\(inside)")
        // 포커스는 표시 직후가 아니라 한 박자 뒤에 확정되므로 0.4초 뒤에 기록한다(AC-01 증거용)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.panel.isVisible else { return }
            let textFocused = self.panel.firstResponder is NSTextView
            Diagnostics.log("panel.focus key=\(self.panel.isKeyWindow) textInputFocused=\(textFocused)")
        }
    }

    func hide() {
        panel.orderOut(nil)
        model.panelDidHide()
        Diagnostics.log("panel.hide")
    }

    private func resize(height: CGFloat) {
        guard panel.isVisible, let screen = panel.screen else { return }
        var f = panel.frame
        let target = PanelGeometry.frame(contentSize: CGSize(width: Self.width, height: height), visibleFrame: screen.visibleFrame)
        // 위쪽 모서리를 고정한 채 높이만 바꾼다
        let top = f.maxY
        f.size.height = target.height
        f.origin.y = max(screen.visibleFrame.minY + 16, top - target.height)
        panel.setFrame(f, display: true, animate: false)
    }
}
