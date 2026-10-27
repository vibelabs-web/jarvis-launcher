import SwiftUI
import JARVISCore

/// 한 화면 컴포저: 입력창 · 대상 요약 · (칩 위 목록) · 칩 줄 · 결과 한 줄 · (새 프로젝트 카드)
struct PromptRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            PromptTextView(model: model)
                .frame(height: model.inputExpanded ? AppModel.expandedInputHeight : AppModel.inputHeight)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25)))
                .overlay(alignment: .topTrailing) { viewButtons }
            if let summary = model.targetSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("보낼 대상: \(summary)")
            }
            if model.listKind != nil { ChipListView(model: model) }
            ChipBar(model: model)
            if let s = model.status { StatusLineView(model: model, line: s) }
            if model.showNewProjectCard { NewProjectCard(model: model) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: PanelController.width, alignment: .topLeading)
        // 높이는 내용이 정한다. 패널은 이 크기를 재서 맞춘다(B21: 고정 높이 안에서 내용이 늘면 머리줄이 눌렸다)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 입력창 오른쪽 위: 크게 보기(⌘E) · 전체 보기(⌘⇧E)
    var viewButtons: some View {
        HStack(spacing: 2) {
            Button { model.toggleExpanded() } label: {
                Image(systemName: model.inputExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .help(model.inputExpanded ? "원래 크기로 (⌘E)" : "입력창 크게 보기 (⌘E)")
            .accessibilityLabel(model.inputExpanded ? "입력창 원래 크기" : "입력창 크게 보기")
            Button { model.onOpenFullView?() } label: { Image(systemName: "macwindow") }
                .help("전체 보기 창 (⌘⇧E)")
                .accessibilityLabel("프롬프트 전체 보기")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(6)
    }

    var header: some View {
        HStack(spacing: 8) {
            Text("JARVIS").font(.subheadline.weight(.semibold)).tracking(1.5)
            StatusDot(status: model.menuStatus)
            Text(model.statusLabel).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { model.toggleHistory() } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(model.historyOpen ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help(model.historyOpen ? "프롬프트 기록 닫기 (⌘Y)" : "프롬프트 기록 (⌘Y)")
            .accessibilityLabel(model.historyOpen ? "프롬프트 기록 닫기" : "프롬프트 기록 열기")
            WindowControls(opacity: model.prefs.panelOpacity, pinned: model.prefs.panelPinned,
                           setOpacity: model.setPanelOpacity, setPinned: model.setPanelPinned)
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
            .frame(width: 7, height: 7)
            .accessibilityLabel(status == .ready ? "준비" : status == .attention ? "재확인 필요" : "연결 끊김")
    }
}

// MARK: - 칩 줄

struct ChipBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            projectChip
            Button { model.toggleRecording() } label: {
                Image(systemName: model.phase == .recording ? "stop.circle.fill" : "mic")
                    .foregroundStyle(model.phase == .recording ? Color.red : Color.primary)
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(model.phase != .compose && model.phase != .recording)
            .help(model.phase == .recording ? "녹음 중지 — 받아 적기" : "받아쓰기(음성은 저장하지 않음)")
            .accessibilityLabel(model.phase == .recording ? "녹음 중지" : "받아쓰기")
            if model.phase == .recording { WaveformView(meter: model.meter) }
            if model.phase == .transcribing { ProgressView().controlSize(.small); Text(model.statusLabel).font(.caption).lineLimit(1).fixedSize() }
            Spacer(minLength: 8)
            skillChip
            sendButton
        }
    }

    var projectChip: some View {
        Chip(icon: "at", label: projectLabel, badge: projectBadge, badgeColor: projectBadgeColor,
             active: model.selectedProjectID != nil || model.newProjectMode,
             onTap: { model.openList(.project) },
             onClear: (model.selectedProjectID != nil || model.newProjectMode) ? { model.clearProject() } : nil)
            .help("보낼 프로젝트 고르기 (입력 중 @)")
            .accessibilityLabel("프로젝트: \(projectLabel) \(projectBadge ?? "")")
    }

    var projectLabel: String {
        if model.newProjectMode { return "새 프로젝트" }
        return model.selectedProject?.alias ?? "프로젝트"
    }

    var projectBadge: String? {
        // 녹음 중에는 파형 자리를 위해 '추천'·'지난 대상' 배지를 잠시 숨긴다(B22)
        if model.phase == .recording, model.softSelection != nil { return nil }
        if let soft = model.softSelection, model.selectedProjectID != nil || model.newProjectMode { return soft }
        guard let p = model.selectedProject else { return nil }
        if model.currentTarget != nil { return "연결됨" }
        return model.connection[p.id]?.label ?? "미확인"
    }

    var projectBadgeColor: Color {
        if model.softSelection != nil { return .blue }
        if model.newProjectMode || model.currentTarget != nil { return .green }
        return .orange
    }

    var skillChip: some View {
        Chip(icon: "slash.circle", label: model.selectedSkill?.invocation ?? "스킬",
             badge: model.selectedSkill?.availability == .inferred ? "추정" : nil, badgeColor: .orange,
             active: model.selectedSkill != nil,
             onTap: { model.openList(.skill) },
             onClear: model.selectedSkill != nil ? { model.clearSkill() } : nil)
            .help("스킬 고르기 (입력 중 /)")
            .accessibilityLabel("스킬: \(model.selectedSkill?.invocation ?? "없음")")
    }

    var sendButton: some View {
        Button { model.submit() } label: {
            HStack(spacing: 4) {
                if model.phase == .sending { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.up") }
                Text(model.newProjectMode ? "다음" : "보내기")
                Text("⌘↵").font(.caption2).opacity(0.7)
            }
        }
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(!model.canSubmit)
        .accessibilityLabel(model.newProjectMode ? "새 프로젝트 다음 단계" : "보내기")
    }
}

/// ChatGPT 입력창 아래 옵션 같은 둥근 칩
struct Chip: View {
    let icon: String
    let label: String
    let badge: String?
    let badgeColor: Color
    let active: Bool
    let onTap: () -> Void
    let onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.caption)
                    Text(label).font(.callout).lineLimit(1).truncationMode(.middle).frame(maxWidth: 170, alignment: .leading)
                    if let b = badge {
                        Text(b).font(.caption2.weight(.medium)).foregroundStyle(badgeColor)
                            .lineLimit(1).fixedSize()  // B22: 폭이 줄면 '지난 대상'이 두 줄로 접혀 칩 밖으로 넘쳤다
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(badgeColor.opacity(0.15)))
                    }
                    Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                }
            }
            .buttonStyle(.plain)
            if let onClear {
                Button(action: onClear) { Image(systemName: "xmark.circle.fill").font(.caption).opacity(0.5) }
                    .buttonStyle(.plain).accessibilityLabel("\(label) 해제")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(active ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12)))
        .overlay(Capsule().stroke(active ? Color.accentColor.opacity(0.4) : Color.clear))
    }
}

// MARK: - 칩 위로 펼치는 목록 (@ / 공용)

struct ChipListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let items = model.listItems
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.listKind == .project ? "보낼 프로젝트" : "스킬 (파일·Orca 목록 기준, 전체 목록 아님)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if !model.listQuery.isEmpty { Text("“\(model.listQuery)”").font(.caption).foregroundStyle(.secondary) }
                if model.listNoMatch {
                    Text("맞는 스킬 없음").font(.caption2).foregroundStyle(.orange)
                } else {
                    Text(model.listKind == .skill && !items.isEmpty ? "\(model.highlight + 1)/\(items.count)" : "\(items.count)개")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                Spacer()
                Text("↑↓ 이동 · ↵ 선택 · esc 닫기").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            if items.isEmpty {
                Text(model.listKind == .project ? "맞는 프로젝트가 없습니다. 설정 > 프로젝트에서 Orca를 다시 조회해 보세요" : "맞는 스킬이 없습니다")
                    .font(.callout).foregroundStyle(.secondary).padding(10)
            }
            // 마우스를 올려도 키보드 강조(model.highlight)는 바꾸지 않는다.
            // 바꾸면 강조 → 스크롤 → 마우스 아래 행이 바뀜 → 강조 …가 끝없이 반복되어 앱이 멈췄다(B16).
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            ListRow(item: item, highlighted: i == model.highlight, monospaced: model.listKind == .skill)
                                .id(i)
                                .onTapGesture { model.choose(item) }
                        }
                    }
                    .padding(.horizontal, 4).padding(.bottom, 4)
                }
                .frame(height: min(CGFloat(items.count), 6) * 40)
                // 철자를 칠 때마다 맞는 줄로 강조가 옮겨 가고, 그 줄이 목록 가운데 보이도록 스크롤한다
                .onChange(of: model.highlight) { _, h in proxy.scrollTo(h, anchor: .center) }
                .onChange(of: model.listQuery) { _, _ in proxy.scrollTo(model.highlight, anchor: .center) }
                .onAppear { proxy.scrollTo(model.highlight, anchor: .center) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor).opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

}

/// 목록 한 줄. 마우스를 올렸을 때의 표시는 이 줄 안에서만 처리한다.
struct ListRow: View {
    let item: AppModel.ListItem
    let highlighted: Bool
    let monospaced: Bool
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(monospaced ? .system(.callout, design: .monospaced) : .callout.weight(.medium)).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !item.badge.isEmpty {
                Text(item.badge).font(.caption2).foregroundStyle(item.enabled ? Color.secondary : Color.red)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 7).fill(
            highlighted ? Color.accentColor.opacity(0.2) : hovered ? Color.secondary.opacity(0.1) : Color.clear))
        .opacity(item.enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - 결과 한 줄

struct StatusLineView: View {
    @ObservedObject var model: AppModel
    let line: AppModel.StatusLine

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(line.text).font(.callout).foregroundStyle(line.kind == .ok ? Color.primary : color)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if line.confirmInferredSkill { Button("확인했음, 보내기") { model.confirmInferredAndSend() } }
            if line.canOpenOrca { Button("Orca에서 열기") { model.openInOrca() } }
            if line.canRetry { Button("같은 요청으로 재시도") { model.manualRetry() } }
            if line.canRevertDictation { Button("원문으로 되돌리기") { model.revertDictation() } }
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
    }

    var icon: String {
        switch line.kind {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch line.kind {
        case .ok: return .green
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}


// MARK: - 녹음 중 파형

/// 마이크 소리 크기를 실시간 막대로 보여 준다. 소리가 2초 넘게 안 들어오면 알린다.
struct WaveformView: View {
    @ObservedObject var meter: MicMeter

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(meter.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color.red.opacity(0.75))
                        .frame(width: 2, height: max(2, CGFloat(level) * 20))
                }
            }
            .frame(height: 24)
            .animation(.linear(duration: 0.08), value: meter.levels)
            if let start = meter.startedAt {
                TimelineView(.periodic(from: start, by: 1)) { ctx in
                    let s = Int(ctx.date.timeIntervalSince(start))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.caption.monospacedDigit()).foregroundStyle(.red).fixedSize()
                }
            }
            if meter.silent {
                Image(systemName: "speaker.slash").font(.caption).foregroundStyle(.orange).help("소리가 들리지 않습니다")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.silent ? "녹음 중, 소리가 들리지 않음" : "녹음 중")
    }
}
