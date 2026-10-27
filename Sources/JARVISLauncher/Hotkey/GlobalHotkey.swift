import Carbon.HIToolbox
import Foundation
import JARVISCore

/// Carbon `RegisterEventHotKey` 기반 전역 단축키. 접근성 권한이 필요 없다(PRD 5.1, AC-21).
final class GlobalHotkey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private static var instances: [UInt32: GlobalHotkey] = [:]
    private static var nextID: UInt32 = 1
    private let hotkeyID: UInt32

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        hotkeyID = Self.nextID
        Self.nextID += 1
        Self.instances[hotkeyID] = self
    }

    deinit { unregister() }

    /// 성공하면 nil, 실패하면 사용자에게 보여 줄 이유.
    func register(_ setting: HotkeySetting) -> String? {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let target = GlobalHotkey.instances[hk.id] {
                DispatchQueue.main.async { target.onPress() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        guard status == noErr else { return "단축키 처리기를 설치하지 못했습니다(\(status))" }
        let id = EventHotKeyID(signature: OSType(0x4A52_5653), id: hotkeyID)  // 'JRVS'
        let r = RegisterEventHotKey(setting.keyCode, setting.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if r != noErr {
            unregister()
            return r == OSStatus(eventHotKeyExistsErr)
                ? "\(HotkeyPresets.label(setting))은(는) 다른 앱이 이미 쓰고 있습니다. 설정에서 다른 조합을 골라 주세요"
                : "단축키 등록 실패(\(r)). 설정에서 다른 조합을 골라 주세요"
        }
        return nil
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil
        handlerRef = nil
    }
}

enum HotkeyPresets {
    static let all: [HotkeySetting] = [
        .default,                                                         // ⌃⌥Space
        HotkeySetting(keyCode: 49, modifiers: UInt32(optionKey)),         // ⌥Space
        HotkeySetting(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey)), // ⌘⇧Space
        HotkeySetting(keyCode: 38, modifiers: UInt32(controlKey | optionKey)), // ⌃⌥J
        HotkeySetting(keyCode: 46, modifiers: UInt32(controlKey | optionKey)), // ⌃⌥M
    ]

    static func label(_ s: HotkeySetting) -> String {
        var out = ""
        if s.modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if s.modifiers & UInt32(optionKey) != 0 { out += "⌥" }
        if s.modifiers & UInt32(shiftKey) != 0 { out += "⇧" }
        if s.modifiers & UInt32(cmdKey) != 0 { out += "⌘" }
        let keys: [UInt32: String] = [49: "Space", 38: "J", 46: "M"]
        return out + (keys[s.keyCode] ?? "키\(s.keyCode)")
    }
}
