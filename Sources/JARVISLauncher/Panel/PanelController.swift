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

/// 제목 표시줄 없는(borderless) 창도 키 입력을 받게 한다(전체 보기 창)
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PanelController {
    private let panel: PromptPanel
    private let model: AppModel
    private var bag: Set<AnyCancellable> = []
    /// 프롬프트 전체 보기 창(⌘⇧E)
    private var fullWindow: NSWindow?
    static let width: CGFloat = 680

    init(model: AppModel) {
        self.model = model
        panel = PromptPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                            // 제목 표시줄을 두지 않는다: 숨긴 제목 표시줄 높이만큼 위쪽이 비던 문제(캡션바 빈 공간)
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
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
        panel.contentView = glassContent(PromptRootView(model: model))
        model.onRequestHide = { [weak self] in self?.hide() }
        model.onOpenFullView = { [weak self] in self?.openFullView() }
        model.onCloseFullView = { [weak self] in self?.closeFullView() }
        // 목록·결과 줄·새 프로젝트 카드가 열리고 닫힐 때 높이를 맞춘다(위쪽 모서리 고정)
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyWindowPrefs()
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
        applyWindowPrefs()
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

    /// 투명도·항상 위 설정을 두 창에 반영한다
    func applyWindowPrefs() {
        let p = model.prefs
        let pa = CGFloat(min(max(p.panelOpacity, 0.4), 1))
        if abs(panel.alphaValue - pa) > 0.001 { panel.alphaValue = pa }
        let pl: NSWindow.Level = p.panelPinned ? .floating : .normal
        if panel.level != pl { panel.level = pl }
        guard let w = fullWindow else { return }
        let fa = CGFloat(min(max(p.fullViewOpacity, 0.4), 1))
        if abs(w.alphaValue - fa) > 0.001 { w.alphaValue = fa }
        // 켜져 있으면 패널보다 한 단계 위
        let fl: NSWindow.Level = p.fullViewPinned ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .normal
        if w.level != fl { w.level = fl }
    }

    func openFullView() {
        if let w = fullWindow { w.makeKeyAndOrderFront(nil); return }
        // 패널과 같은 유리 재질의 둥근 창. 제목 표시줄 대신 SwiftUI 머리줄을 쓴다
        let w = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        w.title = "프롬프트 전체 보기"
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = true
        w.minSize = NSSize(width: 520, height: 360)
        w.contentView = glassContent(PromptFullView(model: model), material: .underWindowBackground)
        if let vf = (panel.screen ?? NSScreen.main)?.visibleFrame {
            let size = CGSize(width: min(900, vf.width - 40), height: min(700, vf.height - 40))
            w.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height), display: false)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fullWindowDidClose() }
        }
        fullWindow = w
        applyWindowPrefs()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        model.focusTick += 1
        Diagnostics.log("fullview.open chars=\(model.session.original.count)")
    }

    func closeFullView() {
        fullWindow?.close()  // willClose 알림에서 정리한다
    }

    private func fullWindowDidClose() {
        fullWindow = nil
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); model.focusTick += 1 }
    }

    func hide() {
        closeFullView()
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
