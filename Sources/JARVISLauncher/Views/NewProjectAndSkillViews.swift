import SwiftUI
import JARVISCore

/// 새 프로젝트 확인 카드(PRD 4.4). 같은 창 안에서 펼친다. 폴더 이름은 반드시 확인받는다.
struct NewProjectCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.composingMeta && model.meta == nil {
                HStack { ProgressView().controlSize(.small); Text("메타 프롬프트 정리 중…").font(.callout) }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        Text("상위 폴더").foregroundStyle(.secondary)
                        HStack {
                            Text(model.prefs.defaultParentFolder.isEmpty ? "설정되지 않음" : model.shortPath(model.prefs.defaultParentFolder))
                                .lineLimit(1).truncationMode(.middle)
                            Button("변경") { chooseParent() }.disabled(locked).controlSize(.small)
                        }
                    }
                    GridRow {
                        Text("폴더 이름").foregroundStyle(.secondary)
                        HStack {
                            TextField("reading-notes", text: $model.newName).frame(width: 200).disabled(locked)
                            ForEach(model.meta?.nameSuggestions ?? [], id: \.self) { n in
                                Button(n) { model.newName = n }.buttonStyle(.link).disabled(locked)
                            }
                        }
                    }
                    GridRow {
                        Text("최종 경로").foregroundStyle(.secondary)
                        pathText
                    }
                    GridRow { Text("Git 초기화").foregroundStyle(.secondary); Text(gitInitText).foregroundStyle(.secondary) }
                }
                .font(.callout)
                HStack {
                    Text("메타 프롬프트 (편집 가능)").font(.caption).foregroundStyle(.secondary)
                    if let m = model.meta { Text(m.source == "llm" ? "· 로컬 모델 정리" : "· 기본 템플릿").font(.caption).foregroundStyle(.secondary) }
                }
                TextEditor(text: $model.metaText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                    .frame(minHeight: 110, maxHeight: 150)
                    .disabled(locked)
                ForEach(model.meta?.preservationWarnings ?? [], id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.bubble").font(.caption).foregroundStyle(.orange)
                }
                if let cp = model.creation { StepsView(checkpoint: cp, running: model.phase == .creating) }
                if let msg = model.creationMessage { Label(msg, systemImage: "pause.circle.fill").font(.callout).foregroundStyle(.orange) }
                if model.creationDelivered { Label("새 터미널에 플랜 모드로 전달됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                buttons
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    @ViewBuilder var pathText: some View {
        if let folder = model.creation?.folderPath {
            Text(model.shortPath(folder)).lineLimit(1)
        } else {
            switch model.newFolderPlan {
            case .success(let url): Text(model.shortPath(url.path)).lineLimit(1).truncationMode(.middle)
            case .failure(let e): Text(e.localizedDescription).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    @ViewBuilder var buttons: some View {
        HStack {
            Button("취소") { model.meta = nil; if model.creation?.folderPath == nil { model.creation = nil } }
                .disabled(model.phase == .creating || model.creation?.folderPath != nil && !model.creationDelivered && !model.creationCanResume)
            Spacer()
            if model.creationDelivered {
                Button("완료") { model.finishNewProject() }.buttonStyle(.borderedProminent)
            } else if model.creationCanResume && model.creation?.needsGitInit == true && model.creation?.gitInitApproved != true {
                Button("Orca에서 열기") { model.openInOrca() }
                Button("Git 초기화 후 등록 (승인)") { model.approveGitInitAndResume() }
                    .help("이 폴더에서만 git init을 실행한 뒤 Orca에 등록합니다. Orca에서 폴더를 직접 열었다면 '여기서 이어하기'를 누르세요")
                Button("여기서 이어하기") { model.startCreation() }.buttonStyle(.borderedProminent)
            } else if model.creationCanResume {
                Button("Orca에서 열기") { model.openInOrca() }
                Button("여기서 이어하기") { model.startCreation() }.buttonStyle(.borderedProminent)
            } else {
                Button("폴더·터미널 만들고 전달") { model.startCreation() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart)
            }
        }
    }

    var locked: Bool { model.creation?.folderPath != nil }

    var canStart: Bool {
        guard model.phase == .compose, model.creation?.folderPath == nil else { return false }
        if case .success = model.newFolderPlan { return !model.metaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    var gitInitText: String {
        guard let cp = model.creation else { return "하지 않음 (Orca가 요구하면 따로 승인을 묻습니다)" }
        if cp.gitInitialized == true { return "승인 후 초기화함" }
        if cp.needsGitInit == true { return "필요 — Orca는 Git 저장소만 등록합니다. 아래 버튼으로 승인해야 진행" }
        return "하지 않음"
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
        HStack(spacing: 12) {
            ForEach([CreationStep.folder, .orca, .terminal, .claudeReady, .prompt], id: \.self) { step in
                let done = CreationStep.allCases.firstIndex(of: step)! < CreationStep.allCases.firstIndex(of: checkpoint.currentStep)!
                let current = step == checkpoint.currentStep
                HStack(spacing: 3) {
                    if current && running { ProgressView().controlSize(.mini) }
                    else { Image(systemName: done ? "checkmark.circle.fill" : current ? "pause.circle" : "circle").foregroundStyle(done ? .green : .secondary) }
                    Text(step.label).font(.caption)
                }
            }
        }
    }
}
