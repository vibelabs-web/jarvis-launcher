import AppKit
import SwiftUI
import Combine
import JARVISCore

/// 메뉴바 상주 앱 진입점. Dock 아이콘 없음(LSUIElement + accessory).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var panel: PanelController!
    var hotkey: GlobalHotkey!
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var bag: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = PanelController(model: model)
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onHotkeyChanged = { [weak self] h in self?.registerHotkey(h) }

        hotkey = GlobalHotkey { [weak self] in
            Diagnostics.log("hotkey.pressed visible=\(self?.panel.isVisible ?? false)")
            self?.panel.toggle()
        }
        registerHotkey(model.prefs.hotkey)
        setupStatusItem()
        model.$menuStatus.sink { [weak self] _ in self?.updateStatusIcon() }.store(in: &bag)
        Task { await model.refreshOrca() }
        Diagnostics.log("app.launched dataDir=\(model.stores.directory.path)")
        Diagnostics.log("llm.available=\(model.llmPaths != nil) useLLM=\(model.prefs.useLLM) structureDictation=\(model.prefs.structureDictation)")
        // 지난 실행에서 지우지 못한 임시 녹음 파일은 시작할 때 지운다(음성 미보관, PRD 5.3 · B18)
        let audioDir = model.stores.directory.appendingPathComponent("tmp-audio", isDirectory: true)
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil)) ?? []
        for f in leftovers where f.pathExtension == "wav" { try? FileManager.default.removeItem(at: f) }
        if !leftovers.isEmpty { Diagnostics.log("audio.cleanup removed=\(leftovers.count)") }

        // 자동 검증 훅(개발용, JARVIS_DEV_HOOKS=1일 때만): 패널 토글을 스크립트로 반복 재현(AC-01)
        if ProcessInfo.processInfo.environment["JARVIS_DEV_HOOKS"] == "1" {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("dev.vibelabs.jarvis.toggle"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                Diagnostics.log("devtoggle")
                self?.panel.toggle()
            }
        }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let m = model
        let sem = DispatchSemaphore(value: 0)
        Task.detached { await m.shutdown(); sem.signal() }
        _ = sem.wait(timeout: .now() + 2)
    }

    func registerHotkey(_ h: HotkeySetting) {
        let problem = hotkey.register(h)
        model.hotkeyProblem = problem
        Diagnostics.log("hotkey.register \(HotkeyPresets.label(h)) ok=\(problem == nil)")
        if problem != nil { updateStatusIcon() }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.addItem(withTitle: "프롬프트 열기", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Orca 연결 새로고침", action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "설정…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "JARVIS 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        updateStatusIcon()
    }

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch model.menuStatus {
        case .ready: symbol = "sparkle"
        case .attention: symbol = "exclamationmark.circle"
        case .offline: symbol = "circle.dashed"
        }
        button.image = NSImage(systemSymbolName: model.hotkeyProblem != nil ? "keyboard.badge.exclamationmark" : symbol,
                               accessibilityDescription: "JARVIS \(model.statusLabel)")
        button.toolTip = "JARVIS — \(model.statusLabel) · \(HotkeyPresets.label(model.prefs.hotkey))"
    }

    @objc func openPanel() { panel.show() }
    @objc func refresh() { Task { await model.refreshOrca() } }
    @objc func openSettingsAction() { openSettings() }

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "JARVIS 설정"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
