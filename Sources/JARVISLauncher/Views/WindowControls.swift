import SwiftUI
import JARVISCore

/// 창 머리줄 오른쪽의 투명도 메뉴와 탑모스트(항상 위) 핀. 패널과 전체 보기 창이 같이 쓴다.
struct WindowControls: View {
    let opacity: Double
    let pinned: Bool
    let setOpacity: (Double) -> Void
    let setPinned: (Bool) -> Void

    static let steps: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6]

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(Self.steps, id: \.self) { v in
                    Button { setOpacity(v) } label: {
                        if abs(v - opacity) < 0.01 { Label("\(Int(v * 100))%", systemImage: "checkmark") } else { Text("\(Int(v * 100))%") }
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("창 투명도 (지금 \(Int(opacity * 100))%)")
            .accessibilityLabel("창 투명도 \(Int(opacity * 100))퍼센트")
            Button { setPinned(!pinned) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .rotationEffect(.degrees(pinned ? 0 : 45))
                    .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(pinned ? "항상 위에 표시 켜짐 — 누르면 끔" : "항상 위에 표시 꺼짐 — 누르면 켬")
            .accessibilityLabel(pinned ? "항상 위에 표시 켜짐" : "항상 위에 표시 꺼짐")
        }
    }
}

/// 둥근 반투명 유리 배경(NSVisualEffectView) 위에 SwiftUI를 올린 내용 뷰. 크기를 재려면 `hostOut`으로 호스팅 뷰를 받는다.
@MainActor
func glassContent<V: View>(_ root: V, material: NSVisualEffectView.Material = .hudWindow, hostOut: ((NSView) -> Void)? = nil) -> NSView {
    let blur = NSVisualEffectView()
    blur.material = material
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 16
    blur.layer?.masksToBounds = true
    let host = NSHostingView(rootView: root)
    host.translatesAutoresizingMaskIntoConstraints = false
    blur.addSubview(host)
    hostOut?(host)
    NSLayoutConstraint.activate([
        host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
        host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
        host.topAnchor.constraint(equalTo: blur.topAnchor),
        host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
    ])
    return blur
}
