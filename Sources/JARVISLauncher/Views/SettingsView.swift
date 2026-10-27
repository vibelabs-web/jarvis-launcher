import ServiceManagement
import SwiftUI
import JARVISCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("일반", systemImage: "gearshape") }
            ProjectSettings(model: model).tabItem { Label("프로젝트", systemImage: "folder") }
            ModelSettings(model: model).tabItem { Label("모델", systemImage: "cpu") }
            DiagnosticsSettings(model: model).tabItem { Label("진단", systemImage: "stethoscope") }
        }
        .padding(16)
        .frame(width: 760, height: 560)
    }
}

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("전역 단축키", selection: Binding(get: { model.prefs.hotkey }, set: { h in
                model.prefs.hotkey = h
                model.savePrefs()
                model.onHotkeyChanged?(h)
            })) {
                ForEach(HotkeyPresets.all, id: \.self) { Text(HotkeyPresets.label($0)).tag($0) }
            }
            if let p = model.hotkeyProblem { Text(p).foregroundStyle(.orange).font(.caption) }
            Toggle("보낸 뒤 입력 내용 지우기", isOn: Binding(get: { model.prefs.clearInputAfterSend },
                                                     set: { model.prefs.clearInputAfterSend = $0; model.savePrefs() }))
            Toggle("로그인 시 실행", isOn: Binding(get: { loginItem }, set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginItem = on
                    loginError = nil
                } catch { loginError = error.localizedDescription }
            }))
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            Text("프롬프트 원문·음성은 저장하지 않습니다. 설정과 프로젝트 연결만 저장됩니다.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

extension HotkeySetting: Hashable {
    public func hash(into h: inout Hasher) { h.combine(keyCode); h.combine(modifiers) }
}

struct ProjectSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("기본 상위 폴더").bold()
                Text(model.prefs.defaultParentFolder.isEmpty ? "설정되지 않음" : model.prefs.defaultParentFolder)
                    .lineLimit(1).truncationMode(.middle)
                Button("선택…") { choose() }
            }
            Divider()
            HStack {
                Text("연결된 프로젝트").bold()
                Spacer()
                if let d = model.lastRefresh { Text("마지막 조회 \(d.formatted(date: .omitted, time: .standard))").font(.caption) }
                Button("Orca 다시 조회") { Task { await model.refreshOrca() } }
            }
            if let p = model.orcaProblem { Text(p).foregroundStyle(.orange).font(.caption) }
            Table(model.projects) {
                TableColumn("별칭") { p in
                    TextField("별칭", text: binding(p, \.alias)).textFieldStyle(.plain)
                }.width(140)
                TableColumn("설명(추천에 사용)") { p in
                    TextField("예: 매출 대시보드", text: binding(p, \.note)).textFieldStyle(.plain)
                }
                TableColumn("경로") { p in Text(p.canonicalPath).lineLimit(1).truncationMode(.head).help(p.canonicalPath) }
                TableColumn("상태") { p in Text(model.connection[p.id]?.label ?? "미확인") }.width(90)
                TableColumn("") { p in Button("해제") { model.unpair(p.id) } }.width(44)
            }
            .frame(minHeight: 150)
            Text("Orca 터미널 (현재)").bold()
            if let list = model.lastList {
                Table(SessionRegistry.pairableCandidates(list).map(Row.init)) {
                    TableColumn("경로") { r in Text(r.t.worktreePath ?? "미확인").lineLimit(1).truncationMode(.head) }
                    TableColumn("호스트") { r in Text(r.t.executionHostId ?? "미확인") }.width(60)
                    TableColumn("종류") { r in Text(r.reason) }.width(150)
                    TableColumn("") { r in
                        Button("연결") { model.pair(r.t) }
                            .disabled(!r.pairable || model.projects.contains { $0.canonicalPath == PathTools.canonical(r.t.worktreePath ?? "") })
                    }.width(50)
                }
                .frame(minHeight: 140)
                if let omitted = list.hostScope?.omittedHostIds, !omitted.isEmpty {
                    Text("조회하지 못한 호스트 \(omitted.count)곳은 목록에 없습니다(원격 전송은 MVP 범위 밖).").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("아직 조회하지 않았습니다").foregroundStyle(.secondary)
            }
        }
        .task { await model.refreshOrca() }
    }

    struct Row: Identifiable {
        let t: TerminalCandidate; let pairable: Bool; let reason: String
        var id: String { t.handle }
        init(_ x: (terminal: TerminalCandidate, pairable: Bool, reason: String)) { t = x.terminal; pairable = x.pairable; reason = x.reason }
    }

    func binding(_ p: ProjectRecord, _ kp: WritableKeyPath<ProjectRecord, String>) -> Binding<String> {
        Binding(get: { model.projects.first { $0.id == p.id }?[keyPath: kp] ?? "" },
                set: { v in
                    if let i = model.projects.firstIndex(where: { $0.id == p.id }) {
                        model.projects[i][keyPath: kp] = v
                        model.saveProjects()
                    }
                })
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            model.prefs.defaultParentFolder = PathTools.canonical(url.path)
            model.savePrefs()
        }
    }
}

struct ModelSettings: View {
    @ObservedObject var model: AppModel
    @State private var sttCheck: String?
    @State private var llmCheck: String?

    var body: some View {
        Form {
            Section("받아쓰기 (whisper.cpp, 로컬)") {
                TextField("whisper-cli 경로", text: pref(\.whisperCLIPath))
                TextField("모델 파일(.bin)", text: pref(\.whisperModelPath))
                HStack {
                    Button("확인") { sttCheck = model.recognizer.check()?.localizedDescription ?? "사용 가능" }
                    if let sttCheck { Text(sttCheck).font(.caption) }
                }
            }
            Section("판단 엔진 (llama.cpp, 로컬 127.0.0.1)") {
                Toggle("로컬 LLM 사용 (끄면 규칙·템플릿만)", isOn: Binding(get: { model.prefs.useLLM }, set: { model.prefs.useLLM = $0; model.savePrefs() }))
                TextField("llama-server 경로", text: pref(\.llamaServerPath))
                TextField("GGUF 모델 경로", text: pref(\.llmModelPath))
                HStack {
                    Button("로컬 테스트") { testLLM() }
                    if let llmCheck { Text(llmCheck).font(.caption).lineLimit(2) }
                }
                Text("모델은 자동으로 내려받지 않습니다. 내려받기는 scripts/fetch-models.sh(승인 후 실행)를 쓰세요.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func pref(_ kp: WritableKeyPath<Preferences, String>) -> Binding<String> {
        Binding(get: { model.prefs[keyPath: kp] }, set: { model.prefs[keyPath: kp] = $0; model.savePrefs() })
    }

    func testLLM() {
        guard let llm = model.llm else { llmCheck = "설정되지 않음(경로 확인)"; return }
        llmCheck = "실행 중…"
        let started = Date()
        Task {
            do {
                let out = try await llm.completeJSON(system: "JSON 객체 하나만 출력", user: "{\"ok\": true} 를 그대로 출력", schema: ["type": "object"])
                llmCheck = String(format: "응답 %.1f초: %@", Date().timeIntervalSince(started), String(out.prefix(60)))
            } catch { llmCheck = error.localizedDescription }
        }
    }
}

struct DiagnosticsSettings: View {
    @ObservedObject var model: AppModel
    @State private var orcaStatus = "확인 전"
    @State private var claudePath = "확인 전"

    var body: some View {
        Form {
            LabeledContent("Orca CLI", value: OrcaCLIAdapter.locate(configured: model.prefs.orcaPath)?.path ?? "찾지 못함")
            LabeledContent("Orca 상태", value: orcaStatus)
            LabeledContent("Claude Code", value: claudePath)
            LabeledContent("마이크 권한", value: MicRecorder.permissionLabel)
            LabeledContent("접근성 권한", value: "요청하지 않음 (필요 없음)")
            LabeledContent("데이터 폴더", value: model.stores.directory.path)
            LabeledContent("진단 로그", value: Diagnostics.url.path)
            Button("다시 확인") { check() }
            Text("진단 로그에는 프롬프트 원문을 남기지 않지만, 경로 등 민감할 수 있는 정보가 있을 수 있으니 공유 전에 확인하세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task { check() }
    }

    func check() {
        let candidates = ["\(NSHomeDirectory())/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        claudePath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "찾지 못함 (Orca 터미널의 PATH에서 실행됨)"
        Task {
            guard let o = model.orca else { orcaStatus = "CLI 없음"; return }
            do {
                let s = try await o.status()
                orcaStatus = "\(s.runtime?.state ?? "?") · v\(s.runtime?.appVersion ?? "?")"
            } catch { orcaStatus = error.localizedDescription }
        }
    }
}
