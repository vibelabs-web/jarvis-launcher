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
    // 둥근 모서리는 maskImage로 자른다. 레이어 cornerRadius만 쓰면 창 뒤 흐림이 잘리지 않아
    // 네 귀퉁이에 사각형 잔상이 보였다(B23)
    blur.maskImage = roundedMask(radius: 16)
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

/// 크기가 바뀌어도 모서리만 유지되는 둥근 사각형 마스크(capInsets로 늘림)
@MainActor
func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}
