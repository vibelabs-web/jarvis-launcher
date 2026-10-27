import SwiftUI
import JARVISCore

// MARK: - 새 프로젝트 (PRD 4.4)

struct NewProjectView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewHeader(model: model, title: "새 프로젝트 시작")
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("기본 상위 경로").foregroundStyle(.secondary)
                    HStack {
                        Text(model.prefs.defaultParentFolder.isEmpty ? "설정되지 않음" : model.prefs.defaultParentFolder)
                            .lineLimit(1).truncationMode(.middle)
                        Button("변경") { chooseParent() }.disabled(locked)
                    }
                }
                GridRow {
                    Text("새 폴더 이름").foregroundStyle(.secondary)
                    HStack {
                        TextField("reading-notes", text: $model.newName).frame(width: 220).disabled(locked)
                        ForEach(model.meta?.nameSuggestions ?? [], id: \.self) { n in
                            Button(n) { model.newName = n }.buttonStyle(.link).disabled(locked)
                        }
                    }
                }
                GridRow {
                    Text("최종 경로").foregroundStyle(.secondary)
                    switch model.newFolderPlan {
                    case .success(let url): Text(url.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    case .failure(let e):
                        if case .alreadyExists = e, model.creationCanResume { Text(model.creation?.folderPath ?? "").lineLimit(1) }
                        else { Text(e.localizedDescription).foregroundStyle(.orange) }
                    }
                }
                GridRow { Text("Claude 모드").foregroundStyle(.secondary); Text("Plan (고정) · 새 Orca 터미널") }
                GridRow { Text("Git 초기화").foregroundStyle(.secondary); Text("하지 않음 (필요하면 Claude 세션에서 직접)") }
            }
            .font(.callout)
            HStack {
                Text("메타 프롬프트 (편집 가능)").font(.caption).foregroundStyle(.secondary)
                if let m = model.meta { Text(m.source == "llm" ? "· 로컬 모델 정리" : "· 기본 템플릿").font(.caption).foregroundStyle(.secondary) }
            }
            TextEditor(text: $model.metaText)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.55)))
                .frame(minHeight: 150)
                .disabled(locked)
            ForEach(model.meta?.preservationWarnings ?? [], id: \.self) { w in
                Label(w, systemImage: "exclamationmark.bubble").font(.caption).foregroundStyle(.orange)
            }
            if let cp = model.creation { StepsView(checkpoint: cp, running: model.phase == .creating && model.creationMessage == nil && model.outcome == nil) }
            if let msg = model.creationMessage { Label(msg, systemImage: "pause.circle.fill").font(.callout).foregroundStyle(.orange) }
            OutcomeLine(outcome: model.outcome)
            HStack {
                Button("뒤로") { model.backToCompose() }.disabled(model.phase == .creating && model.creationMessage == nil && model.outcome == nil)
                Spacer()
                if case .delivered = model.outcome {
                    Button("완료") { model.reset(clear: model.prefs.clearInputAfterSend) }.buttonStyle(.borderedProminent)
                } else if model.creationCanResume {
                    Button("Orca에서 열기") { model.openInOrca() }
                    Button("여기서 이어하기") { model.startCreation() }.buttonStyle(.borderedProminent)
                } else {
                    Button("폴더/터미널 생성 후 전달") { model.startCreation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStart)
                }
            }
        }
    }

    var locked: Bool { model.creation?.folderPath != nil }

    var canStart: Bool {
        guard model.phase == .reviewNew, model.creation == nil else { return false }
        if case .success = model.newFolderPlan { return !model.metaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "기본 상위 폴더로 선택"
        if panel.runModal() == .OK, let url = panel.url {
            model.prefs.defaultParentFolder = PathTools.canonical(url.path)
            model.savePrefs()
        }
    }
}

struct StepsView: View {
    let checkpoint: CreationCheckpoint
    let running: Bool
    var body: some View {
        HStack(spacing: 14) {
            ForEach([CreationStep.folder, .orca, .terminal, .claudeReady, .prompt], id: \.self) { step in
                let done = CreationStep.allCases.firstIndex(of: step)! < CreationStep.allCases.firstIndex(of: checkpoint.currentStep)!
                let current = step == checkpoint.currentStep
                HStack(spacing: 4) {
                    if current && running { ProgressView().controlSize(.mini) }
                    else { Image(systemName: done ? "checkmark.circle.fill" : current ? "pause.circle" : "circle").foregroundStyle(done ? .green : .secondary) }
                    Text(step.label).font(.caption)
                }
            }
        }
    }
}

// MARK: - 스킬 (PRD 2.4)

struct SkillPickerView: View {
    @ObservedObject var model: AppModel
    @State private var confirmedInferred = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewHeader(model: model, title: "스킬 호출")
            TargetPicker(model: model)
                .onChange(of: model.selectedProjectID) { _, _ in model.refreshSkillsForProject() }
            HStack {
                TextField("스킬 검색", text: $model.skillFilter).textFieldStyle(.roundedBorder)
                Text("\(model.filteredSkills.count)개 · 파일·Orca 목록 기준(전체 목록 아님)").font(.caption).foregroundStyle(.secondary)
            }
            List(model.filteredSkills, selection: $model.selectedSkillID) { s in
                HStack(alignment: .firstTextBaseline) {
                    Text(s.invocation).font(.system(.body, design: .monospaced))
                    Text(s.source.rawValue).font(.caption2).padding(.horizontal, 5).background(Capsule().fill(.quaternary))
                    Text(s.availability.rawValue).font(.caption2)
                        .foregroundStyle(s.availability == .blocked ? .red : s.availability == .inferred ? .orange : .green)
                    Text(s.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(s.id)
            }
            .frame(minHeight: 150)
            .onChange(of: model.selectedSkillID) { _, _ in confirmedInferred = false }
            if let s = model.selectedSkill {
                if !s.note.isEmpty { Text(s.note).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Text("인자").foregroundStyle(.secondary)
                    TextField("선택", text: $model.skillArgs).textFieldStyle(.roundedBorder)
                }
                Text("보낼 문자열: \(model.skillInvocation)").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                if s.availability == .inferred {
                    Toggle("이 세션에서 이 스킬을 쓸 수 있음을 직접 확인했습니다(/skills)", isOn: $confirmedInferred).font(.caption)
                }
            }
            OutcomeLine(outcome: model.outcome)
            HStack {
                Button("뒤로") { model.backToCompose() }
                Spacer()
                Button("스킬 호출 전송") { model.sendSkill() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }
        }
    }

    var canSend: Bool {
        guard let s = model.selectedSkill, s.callable, model.currentTarget != nil, model.phase == .reviewSkill else { return false }
        return s.availability != .inferred || confirmedInferred
    }
}
