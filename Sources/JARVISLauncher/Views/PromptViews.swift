import SwiftUI
import JARVISCore

struct PromptRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Group {
                switch model.phase {
                case .compose, .recording, .transcribing, .classifying: ComposeView(model: model)
                case .reviewExisting, .sending: ExistingReviewView(model: model)
                case .reviewNew, .creating: NewProjectView(model: model)
                case .reviewSkill: SkillPickerView(model: model)
                case .result: ResultView(model: model)
                }
            }
            if let n = model.notice {
                Label(n, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notice")
            }
        }
        .padding(20)
        .frame(width: PanelController.width, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    var header: some View {
        HStack(spacing: 8) {
            Text("JARVIS").font(.headline).tracking(1.5)
            StatusDot(status: model.menuStatus)
            Text(model.statusLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("설정").accessibilityLabel("설정")
            Button { model.escape() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("닫기 (Esc)").accessibilityLabel("닫기")
        }
    }
}

struct StatusDot: View {
    let status: AppModel.MenuStatus
    var body: some View {
        Circle()
            .fill(status == .ready ? Color.green : status == .attention ? Color.yellow : Color.gray)
            .frame(width: 8, height: 8)
            .accessibilityLabel(status == .ready ? "준비" : status == .attention ? "재확인 필요" : "연결 끊김")
    }
}

// MARK: - 입력

struct ComposeView: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var busy: Bool { model.phase == .transcribing || model.phase == .classifying }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("무엇을 도와드릴까요?").font(.title3.weight(.semibold))
            TextEditor(text: $model.session.original)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor).opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3)))
                .frame(minHeight: 90, maxHeight: 130)
                .focused($focused)
                .disabled(busy)
                .accessibilityIdentifier("promptInput")
            if model.session.isOverSoftLimit {
                Text("입력이 \(model.session.original.count)자입니다(권장 \(ComposerSession.softLimit)자). 잘라내지 않으니 필요하면 줄여 주세요.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button { model.toggleRecording() } label: {
                    Label(model.phase == .recording ? "녹음 중지" : "받아쓰기",
                          systemImage: model.phase == .recording ? "stop.circle.fill" : "mic")
                }
                .tint(model.phase == .recording ? .red : nil)
                .accessibilityLabel(model.phase == .recording ? "녹음 중지" : "받아쓰기")
                .disabled(busy)
                Button("기존 프로젝트") { routeTo(.existingProject) }.disabled(!model.session.canProceed || busy)
                Button("새 프로젝트") { routeTo(.newProject) }.disabled(!model.session.canProceed || busy)
                Button("스킬") { routeTo(.skill) }.disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if model.phase == .transcribing { Text("음성 변환 중…").font(.caption) }
                if model.phase == .classifying { Text("분류 중…").font(.caption) }
                Button("다음 단계 ⌘↵") { model.proceed() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.session.canProceed || model.phase != .compose)
            }
            if model.phase == .recording {
                Label("녹음 중 — 다시 누르면 받아 적습니다 (음성은 저장하지 않음)", systemImage: "waveform")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.phase) { _, p in if p == .compose { focused = true } }
    }

    func routeTo(_ intent: RequestIntent) {
        if intent != .skill && !model.session.canProceed { return }
        model.decision = nil
        model.switchIntent(intent)
    }
}

// MARK: - 기존 프로젝트 확인

struct ExistingReviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReviewHeader(model: model, title: "보낼 대상 확인")
            TargetPicker(model: model)
            Text("전달할 내용 (편집 가능)").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.reviewText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.55)))
                .frame(minHeight: 120)
                .accessibilityIdentifier("reviewText")
            OutcomeLine(outcome: model.outcome)
            HStack {
                Button("뒤로") { model.backToCompose() }
                Spacer()
                if model.phase == .sending { ProgressView().controlSize(.small); Text("재확인 후 전송 중…").font(.caption) }
                Button("전송") { model.sendExisting() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.currentTarget == nil || model.phase == .sending
                              || model.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct ReviewHeader: View {
    @ObservedObject var model: AppModel
    let title: String
    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Picker("작업 종류", selection: Binding(get: { currentIntent }, set: { model.switchIntent($0) })) {
                Text("기존 프로젝트").tag(RequestIntent.existingProject)
                Text("새 프로젝트").tag(RequestIntent.newProject)
                Text("스킬").tag(RequestIntent.skill)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .disabled(model.phase == .sending || model.phase == .creating)
        }
        if let d = model.decision {
            Text("추천: \(d.reason)\(d.source == "llm" ? " · 로컬 모델" : d.source == "rule" ? " · 규칙" : "")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    var currentIntent: RequestIntent {
        switch model.phase {
        case .reviewNew, .creating: return .newProject
        case .reviewSkill: return .skill
        default: return .existingProject
        }
    }
}

/// 프로젝트·경로·호스트·터미널을 함께 보여 준다(PRD 4.3).
struct TargetPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.projects.isEmpty {
                Text("페어링된 프로젝트가 없습니다. 설정 > 프로젝트에서 Orca 터미널을 연결해 주세요.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("프로젝트", selection: $model.selectedProjectID) {
                Text("대상을 고르세요").tag(UUID?.none)
                ForEach(orderedProjects) { p in
                    Text("\(p.alias) — \(model.connection[p.id]?.label ?? "미확인")").tag(UUID?.some(p.id))
                }
            }
            .onChange(of: model.selectedProjectID) { _, _ in model.selectedHandle = nil }
            if let p = model.selectedProject {
                let state = model.connection[p.id] ?? .unknown(reason: "아직 조회하지 않음")
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow { Text("경로").foregroundStyle(.secondary); Text(p.canonicalPath).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                    GridRow { Text("호스트").foregroundStyle(.secondary); Text(p.hostId == "local" ? "이 Mac (local)" : p.hostId) }
                    GridRow { Text("상태").foregroundStyle(.secondary); Text(stateText(state)) }
                    if let (_, t) = model.currentTarget {
                        GridRow { Text("터미널").foregroundStyle(.secondary); Text("Claude Code · \(t.title ?? String(t.handle.prefix(13)) + "…")\(t.orphaned == true ? " · Orca 탭과 분리됨" : "")") }
                    }
                }
                .font(.callout)
                if case .needsConfirmation(let cands, _) = state {
                    Picker("터미널 직접 선택", selection: $model.selectedHandle) {
                        Text("고르세요").tag(String?.none)
                        ForEach(cands) { t in
                            Text("\(t.title ?? String(t.handle.prefix(13)) + "…") · 마지막 출력 \(relative(t.lastOutputAt))").tag(String?.some(t.handle))
                        }
                    }
                }
            }
        }
    }

    var orderedProjects: [ProjectRecord] {
        let ranked = model.decision?.ranked ?? []
        return model.projects.sorted { a, b in
            (ranked.firstIndex(of: a.id) ?? .max, a.alias) < (ranked.firstIndex(of: b.id) ?? .max, b.alias)
        }
    }

    func stateText(_ s: ConnectionState) -> String {
        switch s {
        case .connected: return "연결 확인됨"
        case .needsConfirmation(_, let r): return "확인 필요 — \(r)"
        case .offline(let r): return "오프라인 — \(r)"
        case .unknown(let r): return "미확인 — \(r)"
        }
    }

    func relative(_ ms: Double?) -> String {
        guard let ms else { return "알 수 없음" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        return f.localizedString(for: Date(timeIntervalSince1970: ms / 1000), relativeTo: Date())
    }
}

struct OutcomeLine: View {
    let outcome: DeliveryOutcome?
    var body: some View {
        if let o = outcome {
            switch o {
            case .blocked(let g): Label("전송하지 않았습니다: \(g.localizedDescription)", systemImage: "hand.raised.fill").foregroundStyle(.orange).font(.callout)
            case .failed(let m): Label("실패: \(m)", systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout)
            case .rejectedDuplicate: Label("이미 전송 중입니다", systemImage: "clock").font(.callout)
            case .delivered: Label("터미널에 전달됨", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            case .unknown(_, let r): Label("전송 여부 불명: \(r)", systemImage: "questionmark.circle.fill").foregroundStyle(.orange).font(.callout)
            }
        }
    }
}

// MARK: - 결과

struct ResultView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OutcomeLine(outcome: model.outcome).font(.title3)
            if case .delivered = model.outcome {
                Text("Claude Code가 입력을 받아 처리를 시작했습니다. 작업 완료 여부는 Orca에서 확인해 주세요.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if case .unknown = model.outcome {
                Text("자동으로 다시 보내지 않습니다. Orca 화면을 확인한 뒤, 정말 도착하지 않았을 때만 같은 요청으로 재시도하세요.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Orca에서 열기") { model.openInOrca() }
                if case .unknown(let rid, _) = model.outcome, rid != nil {
                    Button("같은 요청으로 재시도") { model.manualRetry() }
                }
                Spacer()
                Button("새 요청") { model.reset(clear: model.prefs.clearInputAfterSend) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
