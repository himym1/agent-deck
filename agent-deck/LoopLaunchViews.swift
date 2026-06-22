import SwiftUI

struct LoopLaunchSheet: View {
    let session: PiAgentSessionRecord
    let activeRun: LoopRun?
    let sourceDefinition: LoopDefinition?
    let onCancel: () -> Void
    let onLaunch: (LoopLaunchRequest) -> Void

    @State private var draft: LoopDraft
    @State private var stopExistingActive = false
    @State private var saveToLoopBank = false
    @State private var saveName = ""
    @State private var saveDescription = ""
    @State private var saveForCurrentProjectOnly = false

    init(
        session: PiAgentSessionRecord,
        activeRun: LoopRun?,
        initialDraft: LoopDraft = LoopDraft(),
        sourceDefinition: LoopDefinition? = nil,
        onCancel: @escaping () -> Void,
        onLaunch: @escaping (LoopLaunchRequest) -> Void
    ) {
        self.session = session
        self.activeRun = activeRun
        self.sourceDefinition = sourceDefinition
        self.onCancel = onCancel
        self.onLaunch = onLaunch
        _draft = State(initialValue: initialDraft)
        _saveName = State(initialValue: sourceDefinition?.name ?? "")
        _saveDescription = State(initialValue: sourceDefinition?.description ?? "")
    }

    private var trimmedGoal: String {
        draft.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canLaunch: Bool {
        let saveIsValid = !saveToLoopBank || !saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !trimmedGoal.isEmpty && saveIsValid && (activeRun == nil || stopExistingActive)
    }

    private var canSaveToLoopBank: Bool {
        sourceDefinition == nil
    }

    private var title: String {
        sourceDefinition?.name ?? "Create Loop"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(sourceDefinition == nil ? "Unsaved loop · \(session.title)" : "Saved loop · \(session.title)")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            if let activeRun {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This transcript already has an active loop.", systemImage: "infinity")
                        .font(AppTheme.Font.body.weight(.semibold))
                    Text(activeRun.goal)
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                    Toggle("Stop it and start this loop", isOn: $stopExistingActive)
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Form {
                Picker("Structure", selection: $draft.structure) {
                    ForEach(LoopStructureKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Picker("Write Target", selection: $draft.writeTarget) {
                    ForEach(LoopWriteTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }

                writeTargetExplanation

                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                    TextEditor(text: $draft.goal)
                        .font(AppTheme.Font.body)
                        .frame(minHeight: 96)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                }

                Stepper(value: $draft.maxIterations, in: 1...20) {
                    Text("Max iterations: \(draft.maxIterations)")
                }

                if draft.structure == .makerChecker {
                    Section("Maker + Checker") {
                        TextField("Maker name", text: $draft.makerChecker.makerName)
                        TextField("Checker name", text: $draft.makerChecker.checkerName)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Checker rubric")
                            TextField("approve, reject once, ask human, or fail", text: $draft.makerChecker.checkerRubric, axis: .vertical)
                                .lineLimit(2...4)
                            Text("Checker is report-only. In this deterministic preview runner, the rubric controls the checker result.")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(AppTheme.mutedText)
                        }
                        Stepper(value: $draft.makerChecker.maxReviewRounds, in: 1...20) {
                            Text("Max review rounds: \(draft.makerChecker.maxReviewRounds)")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Validation command")
                    TextField("Example: swift test", text: $draft.validationCommand)
                        .textFieldStyle(.roundedBorder)
                    Text("Runs through your shell in the project directory when available. Leave empty to stop with Validation unavailable.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }

                if canSaveToLoopBank {
                    Section("Loop Bank") {
                        Toggle("Save to Loop Bank before launch", isOn: $saveToLoopBank)
                        if saveToLoopBank {
                            TextField("Name", text: $saveName)
                            TextField("Description", text: $saveDescription, axis: .vertical)
                                .lineLimit(2...4)
                            Toggle("Available only in this project", isOn: $saveForCurrentProjectOnly)
                                .disabled(session.projectPath.isEmpty)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(saveToLoopBank ? "Save & Launch" : "Launch") {
                    onLaunch(LoopLaunchRequest(
                        draft: draft,
                        stopExistingActive: stopExistingActive,
                        saveRequest: makeSaveRequest()
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canLaunch)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onChange(of: saveToLoopBank) { _, enabled in
            guard enabled, saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            saveName = defaultSaveName()
        }
    }

    @ViewBuilder
    private var writeTargetExplanation: some View {
        switch draft.writeTarget {
        case .artifactMarkdown:
            Text("Writes only to the loop artifact directory. Project files are not modified.")
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.mutedText)
        case .newWorktree:
            Text("Explicit coding target. Agent Deck creates a per-run git worktree and runs validation there; the current checkout remains untouched.")
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.mutedText)
        case .currentCheckout:
            Text("Explicit/direct coding target. The loop writes in the current checkout and runs validation in this project path: \(session.projectPath.isEmpty ? "Unavailable" : session.projectPath)")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.orange)
        }
    }

    private func makeSaveRequest() -> LoopSaveRequest? {
        guard saveToLoopBank else { return nil }
        let currentProjectPaths = (saveForCurrentProjectOnly && !session.projectPath.isEmpty) ? [session.projectPath] : []
        return LoopSaveRequest(
            name: saveName,
            description: saveDescription,
            availability: currentProjectPaths.isEmpty ? .allProjects : .projectPaths,
            projectPaths: currentProjectPaths
        )
    }

    private func defaultSaveName() -> String {
        let firstLine = trimmedGoal.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled Loop" }
        return String(trimmed.prefix(64))
    }
}
