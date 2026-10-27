import Foundation
import CoreGraphics

/// 패널 한 번의 입력 세션. 원문과 사용자 편집본을 분리해서 보관한다(PRD 4.7, AC-03).
/// 디스크에 저장하지 않는다.
public struct ComposerSession: Equatable, Sendable {
    public static let softLimit = 8_000

    /// 사용자가 입력·받아쓰기한 원문. 분류·뒤로 가기를 거쳐도 앱이 바꾸지 않는다.
    public var original: String = ""
    /// 확인 단계에서 사용자가 고친 최종 전송 문자열
    public var finalText: String?

    public init() {}

    public var canProceed: Bool { !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var isOverSoftLimit: Bool { original.count > Self.softLimit }

    /// 받아쓰기 결과를 커서 위치(UTF-16 오프셋)에 넣는다. 위치가 없으면 끝에 붙인다.
    public mutating func insertTranscript(_ text: String, atUTF16 offset: Int?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let ns = original as NSString
        let pos = min(max(offset ?? ns.length, 0), ns.length)
        let before = ns.substring(to: pos), after = ns.substring(from: pos)
        let sepL = before.isEmpty || before.hasSuffix(" ") || before.hasSuffix("\n") ? "" : " "
        let sepR = after.isEmpty || after.hasPrefix(" ") || after.hasPrefix("\n") ? "" : " "
        original = before + sepL + t + sepR + after
    }

    /// 확인 단계로 진입할 때 편집본의 시작값. 이미 고친 게 있으면 유지한다.
    public mutating func beginReview(suggested: String? = nil) -> String {
        if let f = finalText { return f }
        let start = suggested ?? original
        finalText = start
        return start
    }

    /// 뒤로 가기: 편집본은 버리고 원문만 남긴다.
    public mutating func back() { finalText = nil }
}

public enum PanelGeometry {
    /// 포인터가 있는 화면의 `visibleFrame` 안 가운데(살짝 위쪽)에 놓는다(PRD 4.1, AC-02).
    public static func frame(contentSize: CGSize, visibleFrame vf: CGRect, margin: CGFloat = 16) -> CGRect {
        let w = min(contentSize.width, vf.width - margin * 2)
        let h = min(contentSize.height, vf.height - margin * 2)
        let x = vf.minX + (vf.width - w) / 2
        // Spotlight처럼 세로 중앙보다 약간 위
        let y = vf.minY + (vf.height - h) / 2 + min((vf.height - h) / 6, 120)
        let clampedY = min(max(y, vf.minY + margin), vf.maxY - margin - h)
        return CGRect(x: x.rounded(), y: clampedY.rounded(), width: w, height: h)
    }
}
