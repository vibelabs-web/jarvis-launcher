import SwiftUI
import JARVISCore

/// 프롬프트 전체 보기 창(⌘⇧E). 패널과 같은 유리 재질. 위 머리줄(제목·보낼 곳·투명도·핀·닫기),
/// 가운데 읽기 좋은 폭의 편집기, 아래 글자 수와 보내기.
struct PromptFullView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            PromptTextView(model: model, placeholder: "보낼 프롬프트", fontSize: 16, fullView: true)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft").foregroundStyle(.secondary)
            Text("프롬프트 전체 보기").font(.headline)
            targetChip
            Spacer()
            WindowControls(opacity: model.prefs.fullViewOpacity, pinned: model.prefs.fullViewPinned,
                           setOpacity: model.setFullViewOpacity, setPinned: model.setFullViewPinned)
            Button { model.onCloseFullView?() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("닫기 (Esc)")
                .accessibilityLabel("전체 보기 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var targetChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "at").font(.caption)
            Text(target).font(.callout).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(model.selectedProject != nil || model.newProjectMode ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12)))
    }

    var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.session.original.count)자 · \(lineCount)줄")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("Esc 닫기 · ⌘E 패널 입력창 크게 · ⌘↵ 보내기").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            Button {
                model.onCloseFullView?()
                model.submit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text(model.newProjectMode ? "다음" : "보내기")
                    Text("⌘↵").font(.caption2).opacity(0.7)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var lineCount: Int {
        model.session.original.isEmpty ? 0 : model.session.original.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    var target: String {
        if model.newProjectMode { return "새 프로젝트" }
        if let p = model.selectedProject { return p.alias + (model.selectedSkill.map { " · \($0.invocation)" } ?? "") }
        return "보낼 곳 미선택 (패널에서 @)"
    }
}
