import AppKit
import SwiftUI
import JARVISCore

/// 설정 > 프롬프트 기록(ADR-8). Claude Code 훅이 남긴 프롬프트를 골라 마크다운 하나로 내보낸다.
struct PromptLogView: View {
    @ObservedObject var model: AppModel
    @State private var entries: [PromptEntry] = []
    @State private var projects: [String] = []
    @State private var project = ""
    @State private var search = ""
    @State private var firstOnly = false
    @State private var selection = Set<Int64>()
    @State private var paused = false
    @State private var hookInstalled = false
    @State private var message: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hookStatus
            HStack {
                Picker("프로젝트", selection: $project) {
                    Text("전체").tag("")
                    ForEach(projects, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 220)
                TextField("검색 (본문·받아쓴 원문)", text: $search).textFieldStyle(.roundedBorder)
                Toggle("★ 최초 프롬프트만", isOn: $firstOnly)
            }
            Table(entries, selection: $selection) {
                TableColumn("시각") { e in Text(e.time.formatted(date: .numeric, time: .shortened)).monospacedDigit() }.width(130)
                TableColumn("프로젝트") { e in Text(e.project).lineLimit(1) }.width(120)
                TableColumn("") { e in Text(e.isFirst ? "★" : "").help(e.isFirst ? "세션의 최초 프롬프트" : "") }.width(18)
                TableColumn("내용") { e in Text(e.text.replacingOccurrences(of: "\n", with: " ")).lineLimit(1) }
                TableColumn("경유") { e in Text(e.viaLauncher ? "JARVIS" : "").foregroundStyle(.secondary) }.width(56)
            }
            .frame(minHeight: 200)
            detail
            HStack {
                Text("\(entries.count)건 · 선택 \(selection.count)건").font(.caption).foregroundStyle(.secondary)
                if let m = message { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button("선택 삭제…") { confirmDelete = true }.disabled(selection.isEmpty)
                Button("보이는 항목 모두 내보내기…") { export(entries) }.disabled(entries.isEmpty)
                Button("선택 항목 마크다운으로 내보내기…") { export(entries.filter { selection.contains($0.id) }) }
                    .buttonStyle(.borderedProminent).disabled(selection.isEmpty)
            }
        }
        .padding()
        .onAppear(perform: reload)
        .onChange(of: project) { _, _ in reload() }
        .onChange(of: search) { _, _ in reload() }
        .onChange(of: firstOnly) { _, _ in reload() }
        .confirmationDialog("선택한 \(selection.count)건을 기록에서 지울까요? 되돌릴 수 없습니다.", isPresented: $confirmDelete) {
            Button("지우기", role: .destructive) { deleteSelected() }
        }
    }

    var hookStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: hookInstalled ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(hookInstalled ? .green : .orange)
            Text(hookInstalled ? "Claude Code 훅 설치됨 — Claude Code에 입력하는 프롬프트가 기록됩니다"
                               : "훅이 설치되지 않았습니다. 터미널에서 scripts/install-prompt-hook.sh 로 미리 보고 --apply 로 설치하세요")
                .font(.callout)
            Spacer()
            Toggle("기록 일시 중지", isOn: Binding(get: { paused }, set: { paused = $0; model.promptLog?.setPaused($0) }))
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }.help("새로 고침").accessibilityLabel("새로 고침")
        }
    }

    @ViewBuilder var detail: some View {
        if selection.count == 1, let e = entries.first(where: { selection.contains($0.id) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    if let t = e.transcript {
                        Divider()
                        Text("받아쓴 원문").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(t).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(height: 150)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }

    func reload() {
        guard let log = model.promptLog else { message = "기록 DB를 열지 못했습니다"; return }
        paused = log.isPaused
        hookInstalled = Self.hookInstalled()
        do {
            projects = try log.projects()
            entries = try log.entries(project: project.isEmpty ? nil : project, search: search, firstOnly: firstOnly)
            selection = selection.filter { id in entries.contains { $0.id == id } }
        } catch {
            message = error.localizedDescription
        }
    }

    func export(_ chosen: [PromptEntry]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "prompts-\(project.isEmpty ? "all" : project)-\(stamp).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let title = project.isEmpty ? "프롬프트 기록" : "프롬프트 기록 — \(project)"
        do {
            try PromptLog.markdown(chosen, title: title).write(to: url, atomically: true, encoding: .utf8)
            message = "\(chosen.count)건을 내보냈습니다: \(url.lastPathComponent)"
            Diagnostics.log("promptlog.export count=\(chosen.count)")
        } catch {
            message = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    func deleteSelected() {
        do { try model.promptLog?.delete(ids: Array(selection)); selection = []; reload() }
        catch { message = error.localizedDescription }
    }

    /// ~/.claude/settings.json 에 이 훅 항목이 있는지 읽기만 한다(쓰지 않음)
    static func hookInstalled() -> Bool {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return false }
        return s.contains("jarvis-prompt-hook")
    }
}
