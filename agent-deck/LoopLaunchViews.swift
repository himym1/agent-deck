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
    @State private var isInfoPresented = false

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

    private var pipelineStagesBinding: Binding<String> {
        Binding(
            get: { draft.pipeline.stageNames.joined(separator: " | ") },
            set: { draft.pipeline = LoopPipelineConfig(stageNames: splitList($0)) }
        )
    }

    private var parallelBranchesBinding: Binding<String> {
        Binding(
            get: { draft.parallel.branchNames.joined(separator: " | ") },
            set: { draft.parallel = LoopParallelConfig(branchNames: splitList($0)) }
        )
    }

    private var title: String {
        sourceDefinition?.name ?? "Create Loop"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if let activeRun {
                        activeLoopWarning(activeRun)
                    }

                    AppCard(title: "Loop") {
                        VStack(alignment: .leading, spacing: 14) {
                            pickerRow("Structure") {
                                HStack(spacing: 8) {
                                    Picker("Structure", selection: $draft.structure) {
                                        ForEach(LoopStructureKind.allCases) { kind in
                                            Text(kind.displayName).tag(kind)
                                        }
                                    }
                                    .labelsHidden()
                                    .appMenuPicker()

                                    LoopInlineInfoButton(
                                        title: "Structure",
                                        rows: [
                                            .init("Single Agent", "Repeats one agent against the goal."),
                                            .init("Maker/Checker", "Maker produces work, checker reviews it, and retries can happen."),
                                            .init("Agent Pipeline", "Runs named stages in order, like Explorer → Implementer → Verifier."),
                                            .init("Parallel Agents", "Tracks independent branches or hypotheses in the same run."),
                                            .init("Discovery Triage", "Collects findings and classifies them by severity / next action."),
                                            .init("Human Approval", "Pauses at a checkpoint for explicit approval before continuing.")
                                        ]
                                    )
                                }
                            }

                            pickerRow("Write Target") {
                                HStack(spacing: 8) {
                                    Picker("Write Target", selection: $draft.writeTarget) {
                                        ForEach(LoopWriteTarget.allCases) { target in
                                            Text(target.displayName).tag(target)
                                        }
                                    }
                                    .labelsHidden()
                                    .appMenuPicker()

                                    LoopInlineInfoButton(
                                        title: "Write Target",
                                        rows: [
                                            .init("Artifact / Markdown output", "Safest mode; writes only loop artifacts and never modifies project files."),
                                            .init("New worktree", "Creates an isolated git worktree for code changes and validation, leaving the current checkout untouched."),
                                            .init("Current checkout", "Writes directly into this project checkout; use only when you want the loop to edit files in place.")
                                        ]
                                    )
                                }
                            }

                            writeTargetExplanation

                            fieldGroup("Goal") {
                                TextEditor(text: $draft.goal)
                                    .font(AppTheme.Font.body)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 104)
                                    .background(AppTheme.textContentFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppTheme.contentStroke, lineWidth: 1)
                                    }
                            }

                            HStack(spacing: 8) {
                                Text("Max iterations")
                                    .font(AppTheme.Font.body)
                                LoopNumericStepper(value: $draft.maxIterations, range: 1...20)

                                LoopInlineInfoButton(
                                    title: "Max iterations",
                                    message: "A hard safety limit for repeated work. The loop stops once it reaches this count even if the goal still needs follow-up."
                                )
                            }
                        }
                    }

                    structureFields

                    AppCard(title: "Validation") {
                        fieldGroup {
                            HStack(spacing: 6) {
                                Text("Validation command")
                                    .font(AppTheme.Font.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.mutedText)
                                LoopInlineInfoButton(
                                    title: "Validation command",
                                    message: "Optional shell command for checking the result. It runs from the project directory when available and its output is attached to the loop result."
                                )
                            }
                        } content: {
                            AppTextField(text: $draft.validationCommand, placeholder: "Example: swift test")
                                .frame(maxWidth: .infinity)
                            Text("Runs through your shell in the project directory when available. Leave empty to stop with Validation unavailable.")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(AppTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if canSaveToLoopBank {
                        loopBankSection
                    }
                }
                .padding(24)
            }

            Divider()

            sheetFooter
        }
        .frame(width: 560, height: 640)
        .onChange(of: saveToLoopBank) { _, enabled in
            guard enabled, saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            saveName = defaultSaveName()
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "infinity")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.brandAccent)
                .frame(width: 34, height: 34)
                .background(AppTheme.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .fontWidth(.expanded)
                Text(sourceDefinition == nil ? "Unsaved loop · \(session.title)" : "Saved loop · \(session.title)")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                isInfoPresented.toggle()
            } label: {
                Label("Info", systemImage: "info.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.mutedText)
            .help("Explain loops")
            .popover(isPresented: $isInfoPresented, arrowEdge: .bottom) {
                LoopLaunchInfoPopover()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var sheetFooter: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .appSecondaryButton()
                .keyboardShortcut(.cancelAction)
            Button(saveToLoopBank ? "Save & Launch" : "Launch") {
                onLaunch(LoopLaunchRequest(
                    draft: draft,
                    stopExistingActive: stopExistingActive,
                    saveRequest: makeSaveRequest()
                ))
            }
            .appPrimaryButton()
            .keyboardShortcut(.defaultAction)
            .disabled(!canLaunch)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func activeLoopWarning(_ activeRun: LoopRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This transcript already has an active loop.", systemImage: "exclamationmark.triangle.fill")
                .font(AppTheme.Font.body.weight(.semibold))
                .foregroundStyle(.orange)
            Text(activeRun.goal)
                .font(AppTheme.Font.caption)
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(2)
            Toggle("Stop it and start this loop", isOn: $stopExistingActive)
                .appSwitch()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.20), lineWidth: 1)
        }
    }

    private var structureFields: some View {
        AppCard(title: draft.structure.displayName) {
            VStack(alignment: .leading, spacing: 14) {
                switch draft.structure {
                case .makerChecker:
                    fieldGroup("Maker name") {
                        AppTextField(text: $draft.makerChecker.makerName, placeholder: "Maker name")
                    }
                    fieldGroup("Checker name") {
                        AppTextField(text: $draft.makerChecker.checkerName, placeholder: "Checker name")
                    }
                    fieldGroup {
                        HStack(spacing: 6) {
                            Text("Checker rubric")
                                .font(AppTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            LoopInlineInfoButton(
                                title: "Checker rubric",
                                message: "Tells the checker how to decide whether the maker's result is acceptable, should be retried, needs a human, or should fail the loop."
                            )
                        }
                    } content: {
                        AppTextField(
                            text: $draft.makerChecker.checkerRubric,
                            placeholder: "approve, reject once, ask human, or fail",
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        Text("Checker is report-only. In this deterministic preview runner, the rubric controls the checker result.")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Text("Max review rounds")
                            .font(AppTheme.Font.body)
                        LoopNumericStepper(value: $draft.makerChecker.maxReviewRounds, range: 1...20)
                        LoopInlineInfoButton(
                            title: "Max review rounds",
                            message: "Caps maker/checker retry cycles so a rejected result cannot loop indefinitely."
                        )
                    }
                case .agentPipeline:
                    fieldGroup {
                        HStack(spacing: 6) {
                            Text("Stages")
                                .font(AppTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            LoopInlineInfoButton(
                                title: "Pipeline stages",
                                message: "Stage names are split with | and run in order. Use this when work should progress through named phases such as Explorer | Implementer | Verifier."
                            )
                        }
                    } content: {
                        AppTextField(text: pipelineStagesBinding, placeholder: "Stages, separated by |")
                        Text("Runs stages in this fixed order and records the timeline.")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                case .parallelAgents:
                    fieldGroup {
                        HStack(spacing: 6) {
                            Text("Branches")
                                .font(AppTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            LoopInlineInfoButton(
                                title: "Parallel branches",
                                message: "Branch names are split with | and represent independent attempts or hypotheses tracked in one loop run."
                            )
                        }
                    } content: {
                        AppTextField(text: parallelBranchesBinding, placeholder: "Branches, separated by |")
                        Text("Records branch timeline. Choose New worktree for isolated coding-preview writes.")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                case .discoveryTriage:
                    fieldGroup {
                        HStack(spacing: 6) {
                            Text("Classification prompt")
                                .font(AppTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            LoopInlineInfoButton(
                                title: "Classification prompt",
                                message: "Instruction used by discovery triage to sort findings by severity and recommend the next action."
                            )
                        }
                    } content: {
                        AppTextField(text: $draft.discoveryTriage.classificationPrompt, placeholder: "Classification prompt", axis: .vertical)
                            .lineLimit(2...4)
                    }
                case .humanApproval:
                    fieldGroup {
                        HStack(spacing: 6) {
                            Text("Checkpoint prompt")
                                .font(AppTheme.Font.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.mutedText)
                            LoopInlineInfoButton(
                                title: "Checkpoint prompt",
                                message: "The message shown when the loop pauses for human approval before continuing."
                            )
                        }
                    } content: {
                        AppTextField(text: $draft.humanApproval.checkpointPrompt, placeholder: "Checkpoint prompt", axis: .vertical)
                            .lineLimit(2...4)
                        Text("The deterministic preview runner stops with Human input required at this checkpoint.")
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                case .singleAgent:
                    Text("Runs one agent loop against the selected write target.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
        }
    }

    private var loopBankSection: some View {
        AppCard(title: "Loop Bank") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Save to Loop Bank before launch", isOn: $saveToLoopBank)
                    .appSwitch()
                if saveToLoopBank {
                    fieldGroup("Name") {
                        AppTextField(text: $saveName, placeholder: "Name")
                    }
                    fieldGroup("Description") {
                        AppTextField(text: $saveDescription, placeholder: "Description", axis: .vertical)
                            .lineLimit(2...4)
                    }
                    Toggle("Available only in this project", isOn: $saveForCurrentProjectOnly)
                        .appSwitch()
                        .disabled(session.projectPath.isEmpty)
                }
            }
        }
    }

    private func pickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 96, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        fieldGroup {
            Text(label)
                .font(AppTheme.Font.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
        } content: {
            content()
        }
    }

    private func fieldGroup<Label: View, Content: View>(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func splitList(_ value: String) -> [String] {
        value.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct LoopInlineInfoButton: View {
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let description: String

        init(_ title: String, _ description: String) {
            self.title = title
            self.description = description
        }
    }

    let title: String
    let message: String?
    let rows: [Row]
    @State private var isPresented = false

    init(title: String, message: String) {
        self.title = title
        self.message = message
        self.rows = []
    }

    init(title: String, rows: [Row]) {
        self.title = title
        self.message = nil
        self.rows = rows
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppTheme.brandAccent)
                    Text(title)
                        .font(.headline)
                        .fontWidth(.expanded)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { row in
                            infoRow(row.title, row.description)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: rows.isEmpty ? 320 : 430, alignment: .leading)
        }
    }

    private func infoRow(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fontWidth(.expanded)
            Text(description)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LoopLaunchInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "infinity")
                    .foregroundStyle(AppTheme.brandAccent)
                Text("Loops")
                    .font(.headline)
                    .fontWidth(.expanded)
            }

            VStack(alignment: .leading, spacing: 10) {
                infoRow("What runs", "A loop repeatedly asks Pi to work toward the goal, records each iteration, and stops when it reaches the max iterations or needs attention.")
                infoRow("Structure", "Choose a single agent, maker/checker review, a pipeline, parallel branches, discovery triage, or a human approval checkpoint.")
                infoRow("Write target", "Artifact writes keep project files untouched. Worktree writes isolate code changes. Current checkout writes directly to this project.")
                infoRow("Validation", "An optional command runs from the project directory when available and is included in the loop result.")
            }
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
    }

    private func infoRow(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fontWidth(.expanded)
            Text(description)
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
