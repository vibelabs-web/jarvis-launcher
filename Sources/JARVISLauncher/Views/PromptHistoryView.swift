import AppKit
import SwiftUI
import JARVISCore

/// 런처 바로 아래에 붙는 프롬프트 기록 창(⌘Y). 훅이 저장한 프롬프트를 보고, 골라서 입력창에 넣거나 복사한다.
struct PromptHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var entries: [PromptEntry] = []
    @State private var search = ""
    @State private var thisProjectOnly = true
    @State private var selectedID: Int64?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("기록 검색", text: $search).textFieldStyle(.plain)
                if let name = projectFolder {
                    Toggle("\(name)만", isOn: $thisProjectOnly).toggleStyle(.checkbox).font(.caption)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            if entries.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    list
                    detail
                }
            }
        }
        .padding(12)
        .frame(width: PanelController.width, height: PanelController.historyHeight, alignment: .topLeading)
        .onAppear(perform: reload)
        .onChange(of: search) { _, _ in reload() }
        .onChange(of: thisProjectOnly) { _, _ in reload() }
        .onChange(of: model.historyOpen) { _, open in if open { reload() } }
    }

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
            Text("프롬프트 기록").font(.subheadline.weight(.semibold))
            Text("\(entries.count)건").font(.caption).foregroundStyle(.secondary)
            if let m = message { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("새로 고침").accessibilityLabel("기록 새로 고침")
            Button { model.onOpenSettings?() } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(.borderless).help("내보내기는 설정 > 프롬프트 기록에서").accessibilityLabel("내보내기 설정 열기")
            Button { model.toggleHistory() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("닫기 (⌘Y)").accessibilityLabel("프롬프트 기록 닫기")
        }
    }

    var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { e in
                    HistoryRow(entry: e, selected: e.id == selectedID)
                        .onTapGesture(count: 2) { model.insertFromHistory(e.text) }  // 두 번 클릭을 먼저 둬야 한 번 클릭과 구분된다
                        .onTapGesture { selectedID = e.id }
                }
            }
        }
        .frame(width: 270)
    }

    @ViewBuilder var detail: some View {
        if let e = entries.first(where: { $0.id == selectedID }) ?? entries.first {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(e.project).font(.caption.weight(.semibold))
                    if e.isFirst { Text("★ 최초").font(.caption2).foregroundStyle(.orange) }
                    if e.viaLauncher { Text("JARVIS").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    Text(e.time.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(e.text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(e.text, forType: .string)
                        message = "복사했습니다"
                    }
                    Button("입력창에 넣기") { model.insertFromHistory(e.text) }.buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
    }

    var projectFolder: String? { model.selectedProject?.folderName }

    var emptyText: String {
        if !PromptLogView.hookInstalled() { return "훅이 설치되지 않아 기록이 없습니다 (설정 > 프롬프트 기록)" }
        return search.isEmpty ? "아직 기록된 프롬프트가 없습니다" : "맞는 기록이 없습니다"
    }

    func reload() {
        guard let log = model.promptLog else { message = "기록 DB를 열지 못했습니다"; return }
        let project = thisProjectOnly ? projectFolder : nil
        entries = (try? log.entries(project: project, search: search, limit: 200)) ?? []
        if let id = selectedID, !entries.contains(where: { $0.id == id }) { selectedID = nil }
        message = nil
    }
}

struct HistoryRow: View {
    let entry: PromptEntry
    let selected: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.text.replacingOccurrences(of: "\n", with: " ")).font(.callout).lineLimit(1)
            HStack(spacing: 4) {
                if entry.isFirst { Text("★").foregroundStyle(.orange) }
                Text(entry.project)
                Text("·")
                Text(entry.time.formatted(date: .numeric, time: .shortened))
            }
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(
            selected ? Color.accentColor.opacity(0.2) : hovered ? Color.secondary.opacity(0.1) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help("클릭: 내용 보기 · 두 번 클릭: 입력창에 넣기")
    }
}
