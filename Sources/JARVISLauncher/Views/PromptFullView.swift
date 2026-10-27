import SwiftUI
import JARVISCore

/// 프롬프트 전체 보기 창(⌘⇧E). 패널 입력창과 같은 글을 큰 글씨로 보고 고친다.
struct PromptFullView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PromptTextView(model: model, placeholder: "보낼 프롬프트", fontSize: 16, fullView: true)
                .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack(spacing: 10) {
                Text(target).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(model.session.original.count)자 · \(lineCount)줄").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("닫기") { model.onCloseFullView?() }.keyboardShortcut(.cancelAction)
                Button {
                    model.onCloseFullView?()
                    model.submit()
                } label: { Text(model.newProjectMode ? "다음 ⌘↵" : "보내기 ⌘↵") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    var lineCount: Int { model.session.original.isEmpty ? 0 : model.session.original.split(separator: "\n", omittingEmptySubsequences: false).count }

    var target: String {
        if model.newProjectMode { return "보낼 곳: 새 프로젝트" }
        if let p = model.selectedProject { return "보낼 곳: \(p.alias)" + (model.selectedSkill.map { " · \($0.invocation)" } ?? "") }
        return "보낼 곳: 아직 고르지 않음 (패널에서 @로 고르기)"
    }
}
