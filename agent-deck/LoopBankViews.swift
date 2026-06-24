import SwiftUI

struct LoopDefinitionEditorDraft: Equatable {
    var id: String?
    var filePath: String?
    var name: String
    var description: String
    var goalTemplate: String
    var structure: LoopStructureKind
    var writeTarget: LoopWriteTarget
    var maxIterations: Int
    var validationCommand: String
    var makerName: String
    var checkerName: String
    var checkerRubric: String
    var maxReviewRounds: Int
    var pipelineStageNames: [String]
    var parallelBranchesText: String
    var triageAgentName: String
    var classificationPrompt: String
    var checkpointPrompt: String
    var source: LoopDefinitionSource
    var availability: LoopDefinitionAvailability
    var projectPathsText: String
    var createdAt: Date?
    var updatedAt: Date?

    init(definition: LoopDefinition? = nil, currentProjectPath: String? = nil) {
        id = definition?.id
        filePath = definition?.filePath
        name = definition?.name ?? ""
        description = definition?.description ?? ""
        goalTemplate = definition?.goalTemplate ?? ""
        structure = definition?.structure ?? .singleAgent
        writeTarget = definition?.writeTarget ?? .artifactMarkdown
        maxIterations = definition?.maxIterations ?? LoopDraft.defaultMaxIterations
        validationCommand = definition?.validationCommand ?? ""
        let makerChecker = definition?.makerChecker ?? LoopMakerCheckerConfig()
        makerName = makerChecker.makerName
        checkerName = makerChecker.checkerName
        checkerRubric = makerChecker.checkerRubric
        maxReviewRounds = makerChecker.maxReviewRounds
        pipelineStageNames = definition?.pipeline.stageNames ?? LoopPipelineConfig().stageNames
        parallelBranchesText = (definition?.parallel.branchNames ?? LoopParallelConfig().branchNames).joined(separator: " | ")
        triageAgentName = definition?.discoveryTriage.agentName ?? LoopDiscoveryTriageConfig().agentName
        classificationPrompt = definition?.discoveryTriage.classificationPrompt ?? LoopDiscoveryTriageConfig().classificationPrompt
        checkpointPrompt = definition?.humanApproval.checkpointPrompt ?? LoopHumanApprovalConfig().checkpointPrompt
        source = definition?.source ?? .user
        availability = definition?.availability ?? .allProjects
        projectPathsText = (definition?.projectPaths ?? currentProjectPath.map { [$0] } ?? []).joined(separator: "\n")
        createdAt = definition?.createdAt
        updatedAt = definition?.updatedAt
    }

    var isNew: Bool { id == nil }
    var isBuiltin: Bool { source == .builtin }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var projectPaths: [String] {
        var seen = Set<String>()
        return projectPathsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    func makeDefinition() -> LoopDefinition {
        LoopDefinition(
            id: id ?? UUID().uuidString,
            name: name,
            description: description,
            goalTemplate: goalTemplate,
            structure: structure,
            writeTarget: writeTarget,
            maxIterations: maxIterations,
            validationCommand: validationCommand,
            makerChecker: LoopMakerCheckerConfig(
                makerName: makerName,
                checkerName: checkerName,
                checkerRubric: checkerRubric,
                maxReviewRounds: maxReviewRounds
            ),
            pipeline: LoopPipelineConfig(stageNames: pipelineStageNames),
            parallel: LoopParallelConfig(branchNames: splitList(parallelBranchesText)),
            discoveryTriage: LoopDiscoveryTriageConfig(agentName: triageAgentName, classificationPrompt: classificationPrompt),
            humanApproval: LoopHumanApprovalConfig(checkpointPrompt: checkpointPrompt),
            source: .user,
            availability: availability,
            projectPaths: availability == .projectPaths ? projectPaths : [],
            filePath: filePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func splitList(_ value: String) -> [String] {
        value.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct LoopBankScreen: View {
    var viewModel: AppViewModel
    @Binding var searchText: String
    @State private var editorDraft = LoopDefinitionEditorDraft()
    @State private var errorMessage: String?
    @State private var pendingDelete: LoopDefinition?
    @State private var launchDefinition: LoopDefinition?
    @State private var isLaunchSheetPresented = false
    @State private var isCreatingNewLoop = false
    @State private var isDiscardNewLoopDraftAlertPresented = false

    private var availableLoopAgents: [EffectiveAgentRecord] {
        viewModel.allDisplayAgents
            .filter { $0.resolved.disabled != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SplitView {
            loopListPane
        } detail: {
            loopDetailPane
        }
        .onAppear {
            viewModel.reloadLoopDefinitions()
            if let pendingDraft = viewModel.pendingNewLoopEditorDraft {
                isCreatingNewLoop = true
                viewModel.selectedLoopDefinitionID = nil
                editorDraft = pendingDraft
            } else {
                if viewModel.selectedLoopDefinitionID == nil, let first = viewModel.loopDefinitions.first {
                    viewModel.selectedLoopDefinitionID = first.id
                }
                if viewModel.selectedLoopDefinition != nil {
                    resetEditor(to: viewModel.selectedLoopDefinition)
                }
            }
        }
        .onChange(of: viewModel.selectedLoopDefinitionID) { _, newID in
            if newID != nil {
                isCreatingNewLoop = false
                resetEditor(to: viewModel.selectedLoopDefinition)
            } else if isCreatingNewLoop {
                resetEditor(to: nil)
            }
        }
        .onChange(of: viewModel.loopDefinitions) { _, definitions in
            if viewModel.selectedLoopDefinitionID == nil, let first = definitions.first, !isCreatingNewLoop, viewModel.pendingNewLoopEditorDraft == nil {
                viewModel.selectedLoopDefinitionID = first.id
            }
            if viewModel.selectedLoopDefinition != nil || isCreatingNewLoop {
                resetEditor(to: viewModel.selectedLoopDefinition)
            }
        }
        .onChange(of: viewModel.newLoopRequestID) { _, _ in
            createNewLoop()
        }
        .onChange(of: editorDraft) { _, draft in
            if isCreatingNewLoop {
                viewModel.pendingNewLoopEditorDraft = draft
            }
        }
        .alert("Loop Bank", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Discard new loop draft?", isPresented: $isDiscardNewLoopDraftAlertPresented) {
            Button("Discard and Create New", role: .destructive) {
                startNewLoop(discardPendingDraft: true)
            }
            Button("Keep Editing", role: .cancel) { }
        } message: {
            Text("You already have an unsaved new loop draft. Discard it and start over?")
        }
        .alert("Delete Loop?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { definition in
            Button("Delete", role: .destructive) {
                delete(definition)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { definition in
            Text("Delete \"\(definition.name)\" from the user Loop Bank? Built-in loop resources are never edited.")
        }
        .sheet(isPresented: $isLaunchSheetPresented) {
            if let session = viewModel.piAgentSessionStore.selectedSession,
               let definition = launchDefinition {
                LoopLaunchSheet(
                    session: session,
                    activeRun: viewModel.piAgentSessionStore.activeLoopRun(for: session.id),
                    initialDraft: definition.makeDraft(),
                    sourceDefinition: definition,
                    availableAgents: viewModel.allDisplayAgents,
                    projectAgents: viewModel.startupSnapshot(forProjectPath: session.projectPath).effectiveAgents,
                    onCancel: {
                        isLaunchSheetPresented = false
                        launchDefinition = nil
                    },
                    onAssignMissingAgents: { names in
                        viewModel.assignAgentNames(names, toProjectPath: session.projectPath)
                    },
                    onEnableDeckAgents: {
                        viewModel.setSubagentsEnabled(true, forSessionID: session.id)
                    },
                    onLaunch: { request in
                        launch(definition, in: session, request: request)
                    }
                )
            }
        }
    }

    private var loopListPane: some View {
        AppList(
            sections: listSections,
            selection: .single(Binding(
                get: { viewModel.selectedLoopDefinitionID },
                set: {
                    isCreatingNewLoop = false
                    viewModel.selectedLoopDefinitionID = $0
                }
            )),
            isDisabled: { _ in false },
            keyboardNavigation: true
        ) { definition in
            loopRow(definition)
        }
    }

    @ViewBuilder
    private var loopDetailPane: some View {
        if viewModel.selectedLoopDefinition == nil && !isCreatingNewLoop {
            emptyLoopDetailPane
        } else {
            loopEditorPane
        }
    }

    private var emptyLoopDetailPane: some View {
        AppPage("Loops", subtitle: "No loop selected", constrainsContentToViewport: true) {
            AppCard(title: "Loop Bank") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No saved loops yet.")
                        .font(.headline.weight(.semibold))
                        .fontWidth(.expanded)
                    Text("Use the + button in the toolbar to create a new saved loop.")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var loopEditorPane: some View {
        AppPage(editorDraft.isNew ? "New Loop" : editorDraft.name.nonEmpty ?? "Loop", subtitle: detailSubtitle, constrainsContentToViewport: true) {
            AppCard(title: "Definition", trailing: {
                AppLabelTag(text: availabilityLabel(for: editorDraft), color: availabilityColor(for: editorDraft))
            }) {
                VStack(alignment: .leading, spacing: 0) {
                        if editorDraft.isBuiltin {
                            Text("Built-in templates are read-only. Duplicate to create an editable user copy.")
                                .font(AppTheme.Font.caption)
                                .foregroundStyle(AppTheme.mutedText)
                                .padding(.bottom, 12)
                            Divider()
                        }

                        definitionFields
                }
                .disabled(editorDraft.isBuiltin)
            }

            loopStructureSection
                .disabled(editorDraft.isBuiltin)

            availabilitySection
                .disabled(editorDraft.isBuiltin)

            lastRunSection

            loopActionsCard
        }
    }

    private var savedEditorDraft: LoopDefinitionEditorDraft {
        LoopDefinitionEditorDraft(definition: viewModel.selectedLoopDefinition, currentProjectPath: viewModel.selectedProjectPath)
    }

    private var hasUnsavedEditorChanges: Bool {
        if editorDraft.isNew {
            return editorDraft != LoopDefinitionEditorDraft(currentProjectPath: viewModel.selectedProjectPath)
        }
        return editorDraft != savedEditorDraft
    }

    private var canSaveEditorDraft: Bool {
        hasUnsavedEditorChanges && !editorDraft.trimmedName.isEmpty && !editorDraft.isBuiltin && requiredAgentsAreSelected
    }

    private var definitionFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("Name", info: "Use a short action-oriented name. This is what appears in the Loop Bank and launch menus.") {
                TextField("", text: $editorDraft.name)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
            }
            detailEditor("Description", text: $editorDraft.description, minHeight: 64, info: "Optional summary for the Loop Bank list. Use it to explain when someone should choose this loop.")
            detailRow("Structure", infoRows: loopStructureInfoRows) {
                Picker("Structure", selection: $editorDraft.structure) {
                    ForEach(LoopStructureKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
            }
            detailRow("Write target", infoRows: loopWriteTargetInfoRows) {
                Picker("Write target", selection: $editorDraft.writeTarget) {
                    ForEach(LoopWriteTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .labelsHidden()
            }
            detailRow("Max iterations", info: "A hard safety limit. The loop stops after this many passes even if the goal still needs follow-up.") {
                LoopNumericStepper(value: $editorDraft.maxIterations, range: 1...20)
            }
            detailEditor("Goal template", text: $editorDraft.goalTemplate, minHeight: 120, info: "The reusable instruction the loop runs against. Be explicit about the desired outcome, constraints, and what counts as done.")
            detailRow("Validation command", info: "Optional shell command for checking the result. It runs from the project directory when available and is attached to the loop result.") {
                AppTextField(text: $editorDraft.validationCommand, placeholder: "Optional shell command")
                    .frame(maxWidth: 360)
            }
        }
    }

    private var availabilitySection: some View {
        AppCard(title: "Availability") {
            VStack(alignment: .leading, spacing: 0) {
                detailRow("All Projects/default", info: "When enabled, this loop is available in every project.") {
                    Toggle("All Projects/default", isOn: Binding(
                        get: { editorDraft.availability == .allProjects },
                        set: { enabled in
                            if enabled { setAllProjectsAvailability() }
                            else { setUnassignedAvailability() }
                        }
                    ))
                    .labelsHidden()
                    .appSwitch()
                }
                detailRow("Current setting") {
                    Text(availabilityLabel(for: editorDraft))
                }
                if !availableProjectsForLoopAssignment.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        detailLabel("Project assignments", info: "Assign this loop to one or more specific projects. Turning off All Projects/default uses these project assignments; no selected projects means Unassigned/catalog.")
                        VStack(spacing: 0) {
                            ForEach(availableProjectsForLoopAssignment, id: \.path) { project in
                                loopProjectAssignmentRow(project)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.contentStroke, lineWidth: 1)
                        }
                    }
                    .padding(.vertical, 11)
                    Divider()
                }
                detailEditor("Advanced project paths", text: Binding(
                    get: { editorDraft.projectPathsText },
                    set: { value in
                        editorDraft.projectPathsText = value
                        editorDraft.availability = .projectPaths
                    }
                ), minHeight: 72, monospaced: true, info: "Optional: add absolute project paths that are not currently listed above. One path per line.")
                    .disabled(editorDraft.availability == .allProjects)
                Text("All Projects/default overrides per-project assignment. With All Projects off, an empty project list keeps the loop unassigned in the catalog.")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.top, 8)
            }
        }
    }

    private var currentProjectPath: String? {
        let trimmed = viewModel.selectedProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func setAllProjectsAvailability() {
        editorDraft.availability = .allProjects
        editorDraft.projectPathsText = ""
    }

    private func setCurrentProjectAvailability() {
        guard let currentProjectPath else { return }
        setLoopAssigned(true, toProjectPath: currentProjectPath)
    }

    private var availableProjectsForLoopAssignment: [DiscoveredProject] {
        viewModel.enabledProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loopProjectAssignmentRow(_ project: DiscoveredProject) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(AppTheme.Font.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(project.path)
                    .font(AppTheme.Font.caption2.monospaced())
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Toggle("Assigned", isOn: Binding(
                get: { editorDraft.availability == .projectPaths && editorDraft.projectPaths.contains(project.path) },
                set: { setLoopAssigned($0, toProjectPath: project.path) }
            ))
            .labelsHidden()
            .appSwitch()
            .disabled(editorDraft.availability == .allProjects)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.textContentFill.opacity(editorDraft.availability == .allProjects ? 0.35 : 1))
        .contextMenu {
            if editorDraft.availability == .allProjects {
                Button("Use Project Assignments") { setUnassignedAvailability() }
            }
            Button(editorDraft.projectPaths.contains(project.path) ? "Remove from Project" : "Assign to Project") {
                setLoopAssigned(!editorDraft.projectPaths.contains(project.path), toProjectPath: project.path)
            }
            Button("Make All Projects/default") { setAllProjectsAvailability() }
            Button("Make Unassigned/catalog") { setUnassignedAvailability() }
        }
    }

    private func setLoopAssigned(_ assigned: Bool, toProjectPath projectPath: String) {
        var paths = editorDraft.projectPaths
        if assigned {
            if !paths.contains(projectPath) { paths.append(projectPath) }
        } else {
            paths.removeAll { $0 == projectPath }
        }
        editorDraft.availability = .projectPaths
        editorDraft.projectPathsText = paths.joined(separator: "\n")
    }

    private func setUnassignedAvailability() {
        editorDraft.availability = .projectPaths
        editorDraft.projectPathsText = ""
    }

    private var lastRunSection: some View {
        AppCard(title: "Last Run") {
            if let definition = viewModel.selectedLoopDefinition, let run = lastRun(for: definition) {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Status") { Text(run.status.displayName) }
                    if let stopReason = run.stopReason {
                        detailRow("Stop reason") { Text(stopReason.displayName) }
                    }
                    detailRow("Iterations") { Text("\(run.currentIteration)/\(run.maxIterations)") }
                    if let latest = run.iterations.last {
                        detailRow("Latest summary") { Text(latest.summary.nonEmpty ?? "Iteration \(latest.index)") }
                        if let checkerResult = latest.checkerResult {
                            detailRow("Checker result") { Text(checkerResult.displayName) }
                        }
                        if let validation = latest.validationResult {
                            detailRow("Validation") { Text(validation.didPass ? "Passed" : "Failed") }
                        }
                        if !latest.artifacts.isEmpty {
                            detailRow("Artifacts") { Text("\(latest.artifacts.count)") }
                        }
                        if !latest.changedFiles.isEmpty {
                            detailRow("Changed files") { Text("\(latest.changedFiles.count)") }
                        }
                    }
                    detailRow("Write target") { Text(run.writeTarget.displayName) }
                    if let projectPath = run.projectPath, !projectPath.isEmpty {
                        detailRow("Project") { Text(URL(fileURLWithPath: projectPath).lastPathComponent.nonEmpty ?? projectPath) }
                    }
                    detailRow("Ended") { Text((run.endedAt ?? run.startedAt).formatted(date: .abbreviated, time: .shortened)) }
                    if let session = session(for: run) {
                        detailRow("Transcript") {
                            Button(session.displayTitle) { viewModel.selectPiAgentSession(session.id) }
                                .buttonStyle(.link)
                                .help("Open the transcript that owns this loop run")
                        }
                    }
                }
            } else {
                Text("No exact matching loop runs yet.")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    private func session(for run: LoopRun) -> PiAgentSessionRecord? {
        viewModel.piAgentSessionStore.sessions.first { $0.id == run.sessionID }
    }

    private func lastRun(for definition: LoopDefinition) -> LoopRun? {
        let goal = definition.goalTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty else { return nil }
        let runs = viewModel.piAgentSessionStore.sessions
            .flatMap { viewModel.piAgentSessionStore.loopRuns(for: $0.id) }
            .filter { run in
                run.goal == goal &&
                run.structure == definition.structure &&
                run.writeTarget == definition.writeTarget &&
                run.maxIterations == definition.maxIterations &&
                run.validationCommand == definition.validationCommand.trimmingCharacters(in: .whitespacesAndNewlines) &&
                run.makerChecker == definition.makerChecker &&
                run.pipeline == definition.pipeline &&
                run.parallel == definition.parallel &&
                run.discoveryTriage == definition.discoveryTriage &&
                run.humanApproval == definition.humanApproval
            }
        if let selectedProjectPath = viewModel.selectedProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines), !selectedProjectPath.isEmpty,
           let projectRun = runs.filter({ $0.projectPath == selectedProjectPath }).max(by: { $0.startedAt < $1.startedAt }) {
            return projectRun
        }
        return runs.max { $0.startedAt < $1.startedAt }
    }

    private var loopActionsCard: some View {
        AppCard {
            HStack {
                if let selected = viewModel.selectedLoopDefinition, !editorDraft.isNew {
                    Button("Launch") { presentLaunch(selected) }
                        .disabled(viewModel.piAgentSessionStore.selectedSession == nil || !selected.isAvailable(in: viewModel.piAgentSessionStore.selectedSession?.projectPath))
                        .help(launchHelp(for: selected))
                    Button("Duplicate") { duplicate(selected) }
                    if selected.source == .user {
                        Button("Delete", role: .destructive) { pendingDelete = selected }
                    }
                } else if editorDraft.isNew {
                    Button("Discard", role: .destructive) { discardNewLoopDraft() }
                        .disabled(!hasUnsavedEditorChanges)
                }
                Spacer()
                Button(editorDraft.isNew ? "Reset" : "Revert") { resetEditor(to: viewModel.selectedLoopDefinition) }
                    .disabled(!hasUnsavedEditorChanges)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSaveEditorDraft)
            }
        }
    }

    @ViewBuilder
    private var loopStructureSection: some View {
        switch editorDraft.structure {
        case .makerChecker:
            AppCard(title: "Maker + Checker") {
                VStack(alignment: .leading, spacing: 0) {
                    detailRow("Maker agent", info: "The agent that produces the work for each review round.") {
                        LoopAgentNameMenu(selection: $editorDraft.makerName, availableAgents: availableLoopAgents, fallbackLabel: "Maker")
                    }
                    detailRow("Checker agent", info: "The agent that reviews the maker output and decides whether another round is needed.") {
                        LoopAgentNameMenu(selection: $editorDraft.checkerName, availableAgents: availableLoopAgents, fallbackLabel: "Checker")
                    }
                    detailEditor("Checker rubric", text: $editorDraft.checkerRubric, minHeight: 84, info: "Instructions for the checker. Keep the approval criteria concrete so the loop knows when to stop retrying.")
                    detailRow("Max review rounds", info: "Limits maker/checker retries inside an iteration before the loop stops asking for another review pass.") {
                        LoopNumericStepper(value: $editorDraft.maxReviewRounds, range: 1...20)
                    }
                }
            }
        case .agentPipeline:
            AppCard(title: "Agent Pipeline") {
                VStack(alignment: .leading, spacing: 10) {
                    LoopPipelineStagePicker(stages: $editorDraft.pipelineStageNames, availableAgents: availableLoopAgents)
                    Text("Stages are saved as an ordered agent list. The current runner records this order; child agent execution is the next runner slice.")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
        case .parallelAgents:
            AppCard(title: "Parallel Agents") {
                detailRow("Branches", info: "Named parallel tracks, separated by vertical bars. Use them for independent hypotheses, approaches, or workstreams.") {
                    TextField("Branches, separated by |", text: $editorDraft.parallelBranchesText)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        case .discoveryTriage:
            AppCard(title: "Discovery / Triage") {
                detailRow("Triage agent", info: "The agent that gathers findings and applies the classification prompt.") {
                    LoopAgentNameMenu(selection: $editorDraft.triageAgentName, availableAgents: availableLoopAgents, fallbackLabel: "Explorer")
                }
                detailEditor("Classification prompt", text: $editorDraft.classificationPrompt, minHeight: 84, info: "Tell the triage agent how to sort findings, for example by severity, confidence, owner, or next action.")
            }
        case .humanApproval:
            AppCard(title: "Human Approval") {
                detailEditor("Checkpoint prompt", text: $editorDraft.checkpointPrompt, minHeight: 84, info: "The question or review instruction shown before the loop continues. Use this for risky or preference-dependent steps.")
            }
        case .singleAgent:
            AppCard(title: "Single Agent") {
                detailRow("Agent", info: "The agent that will run each iteration. Choose the role best matched to the goal, such as explorer, coder, or reviewer.") {
                    LoopAgentNameMenu(selection: $editorDraft.makerName, availableAgents: availableLoopAgents, fallbackLabel: "Agent")
                }
            }
        }
    }

    private var requiredAgentsAreSelected: Bool {
        switch editorDraft.structure {
        case .singleAgent:
            return !editorDraft.makerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .makerChecker:
            return !editorDraft.makerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !editorDraft.checkerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .discoveryTriage:
            return !editorDraft.triageAgentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .agentPipeline:
            return !editorDraft.pipelineStageNames.isEmpty
                && editorDraft.pipelineStageNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .parallelAgents, .humanApproval:
            return true
        }
    }

    private var loopStructureInfoRows: [LoopInlineInfoButton.Row] {
        [
            .init("Single Agent", "Repeats one selected agent against the goal."),
            .init("Maker + Checker", "A maker produces work, a checker reviews it, and review rounds can retry."),
            .init("Agent Pipeline", "Records ordered stages such as Explorer → Implementer → Verifier."),
            .init("Parallel Agents", "Names independent branches or hypotheses in the same loop run."),
            .init("Discovery / Triage", "Collects findings and classifies them by severity or next action."),
            .init("Human Approval", "Pauses at a checkpoint for explicit approval before continuing.")
        ]
    }

    private var loopWriteTargetInfoRows: [LoopInlineInfoButton.Row] {
        [
            .init("Artifact / Markdown output", "Safest mode. The loop writes artifacts and does not modify project files."),
            .init("New worktree", "Creates an isolated git worktree for code changes and validation."),
            .init("Current checkout", "Writes directly into the current project checkout. Use only when in-place edits are intended.")
        ]
    }

    private var loopAvailabilityInfoRows: [LoopInlineInfoButton.Row] {
        [
            .init("All Projects/default", "Available as a default saved loop everywhere."),
            .init("Current Project only", "Assigns the loop to the selected project path."),
            .init("Unassigned/catalog", "Keeps the loop saved but out of project launch menus until assigned.")
        ]
    }

    private func detailRow<Content: View>(
        _ title: String,
        info: String? = nil,
        infoRows: [LoopInlineInfoButton.Row] = [],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.contentSpacing) {
                detailLabel(title, info: info, infoRows: infoRows)
                Spacer(minLength: AppTheme.contentSpacing)
                content()
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 11)
            Divider()
        }
    }

    private func detailEditor(_ title: String, text: Binding<String>, minHeight: CGFloat, monospaced: Bool = false, info: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            detailLabel(title, info: info)
            TextEditor(text: text)
                .font(monospaced ? .body.monospaced() : AppTheme.Font.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(AppTheme.textContentFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.contentStroke, lineWidth: 1)
                }
        }
        .padding(.vertical, 11)
    }

    private func detailLabel(_ title: String, info: String? = nil, infoRows: [LoopInlineInfoButton.Row] = []) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fontWidth(.expanded)
                .foregroundStyle(AppTheme.mutedText)
            if let info {
                LoopInlineInfoButton(title: title, message: info)
            } else if !infoRows.isEmpty {
                LoopInlineInfoButton(title: title, rows: infoRows)
            }
        }
    }

    private var detailSubtitle: String {
        if editorDraft.isNew { return "Create a saved user loop without editing bundled resources" }
        if editorDraft.isBuiltin { return "Built-in template · duplicate to customize" }
        return "Edit explicit fields and save changes to the user Loop Bank"
    }

    private var listSections: [AppListSection<LoopDefinition>] {
        let selectedProjectPath = viewModel.selectedProjectPath
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let definitions = viewModel.loopDefinitions
            .filter { definition in
                guard !query.isEmpty else { return true }
                return [
                    definition.name,
                    definition.description,
                    definition.goalTemplate,
                    definition.structure.displayName,
                    definition.writeTarget.displayName,
                    availabilityLabel(for: definition),
                    definition.filePath ?? ""
                ].contains { $0.lowercased().contains(query) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let current = definitions.filter { definition in
            guard let selectedProjectPath else { return false }
            return definition.source == .user && definition.availability == .projectPaths && definition.projectPaths.contains(selectedProjectPath)
        }
        let defaults = definitions.filter { $0.source == .user && $0.availability == .allProjects }
        let catalog = definitions.filter { definition in
            definition.source == .user
                && definition.availability == .projectPaths
                && (definition.projectPaths.isEmpty || !current.contains(definition))
        }
        let builtins = definitions.filter { $0.source == .builtin }

        return [
            AppListSection(
                id: "default",
                title: "Default Loops",
                info: "User loops available to every project. Assign one to specific projects from its detail card.",
                items: defaults,
                emptyMessage: "No default loops."
            ),
            AppListSection(
                id: "project",
                title: "Project Loops",
                items: current,
                emptyMessage: "No loops assigned to the selected project."
            ),
            AppListSection(
                id: "catalog",
                title: "Catalog Loops",
                items: catalog,
                emptyMessage: "No catalog loops."
            ),
            AppListSection(
                id: "builtin",
                title: "Builtin Loops",
                info: "Builtins are bundled with \(AppBrand.displayName) and customized by duplicating them into the user Loop Bank.",
                items: builtins,
                emptyMessage: "No builtin loops discovered."
            )
        ]
    }

    private func loopRow(_ definition: LoopDefinition) -> some View {
        LoopListRow(
            definition: definition,
            tint: availabilityColor(for: definition),
            isMuted: loopIsInactive(definition)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if definition.source == .user {
                Button("Make All Projects/default") {
                    updateLoopAvailability(definition, availability: .allProjects, projectPaths: [])
                }
                if let currentProjectPath {
                    Button(definition.projectPaths.contains(currentProjectPath) ? "Remove Current Project" : "Assign to Current Project") {
                        var paths = definition.projectPaths
                        if paths.contains(currentProjectPath) { paths.removeAll { $0 == currentProjectPath } }
                        else { paths.append(currentProjectPath) }
                        updateLoopAvailability(definition, availability: .projectPaths, projectPaths: paths)
                    }
                }
                Button("Disable / Move to Catalog") {
                    updateLoopAvailability(definition, availability: .projectPaths, projectPaths: [])
                }
                Divider()
                Button("Duplicate") { duplicate(definition) }
                Button("Delete", role: .destructive) { pendingDelete = definition }
            } else {
                Button("Duplicate") { duplicate(definition) }
            }
        }
    }

    private func loopIsInactive(_ definition: LoopDefinition) -> Bool {
        definition.source == .user && definition.availability == .projectPaths && definition.projectPaths.isEmpty
    }

    private func updateLoopAvailability(_ definition: LoopDefinition, availability: LoopDefinitionAvailability, projectPaths: [String]) {
        var draft = LoopDefinitionEditorDraft(definition: definition, currentProjectPath: viewModel.selectedProjectPath)
        draft.availability = availability
        draft.projectPathsText = availability == .projectPaths ? projectPaths.joined(separator: "\n") : ""
        do {
            let saved = try viewModel.saveLoopDefinition(draft.makeDefinition())
            if editorDraft.id == saved.id { resetEditor(to: saved) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createNewLoop() {
        if isCreatingNewLoop || viewModel.pendingNewLoopEditorDraft != nil {
            isDiscardNewLoopDraftAlertPresented = true
        } else {
            startNewLoop(discardPendingDraft: false)
        }
    }

    private func startNewLoop(discardPendingDraft: Bool) {
        isCreatingNewLoop = true
        viewModel.selectedLoopDefinitionID = nil
        if discardPendingDraft {
            viewModel.pendingNewLoopEditorDraft = nil
        }
        editorDraft = viewModel.pendingNewLoopEditorDraft ?? LoopDefinitionEditorDraft(currentProjectPath: viewModel.selectedProjectPath)
    }

    private func resetEditor(to definition: LoopDefinition?) {
        editorDraft = LoopDefinitionEditorDraft(definition: definition, currentProjectPath: viewModel.selectedProjectPath)
    }

    private func discardNewLoopDraft() {
        guard editorDraft.isNew else { return }
        viewModel.pendingNewLoopEditorDraft = nil
        isCreatingNewLoop = false
        if let first = viewModel.loopDefinitions.first {
            viewModel.selectedLoopDefinitionID = first.id
            resetEditor(to: first)
        } else {
            resetEditor(to: nil)
        }
    }

    private func save() {
        guard !editorDraft.isBuiltin else { return }
        do {
            let saved = try viewModel.saveLoopDefinition(editorDraft.makeDefinition())
            isCreatingNewLoop = false
            viewModel.pendingNewLoopEditorDraft = nil
            resetEditor(to: saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicate(_ definition: LoopDefinition) {
        do {
            let saved = try viewModel.duplicateLoopDefinition(definition)
            resetEditor(to: saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ definition: LoopDefinition) {
        do {
            try viewModel.deleteLoopDefinition(definition)
            pendingDelete = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func presentLaunch(_ definition: LoopDefinition) {
        guard let session = viewModel.piAgentSessionStore.selectedSession else {
            errorMessage = "Select a Pi session before launching a saved loop."
            return
        }
        guard definition.isAvailable(in: session.projectPath) else {
            errorMessage = "This loop is not available for the selected session project. Assign it to the project or duplicate it before launching."
            return
        }
        launchDefinition = definition
        isLaunchSheetPresented = true
    }

    private func launchHelp(for definition: LoopDefinition) -> String {
        guard let session = viewModel.piAgentSessionStore.selectedSession else {
            return "Select a Pi session before launching a saved loop."
        }
        guard definition.isAvailable(in: session.projectPath) else {
            return "This loop is not available for the selected session project."
        }
        return "Launch this saved loop in the selected Pi session."
    }

    private func launch(_ definition: LoopDefinition, in session: PiAgentSessionRecord, request: LoopLaunchRequest) {
        let store = viewModel.piAgentSessionStore
        if store.activeLoopRun(for: session.id) != nil && !request.stopExistingActive {
            store.append(.init(sessionID: session.id, role: .error, title: "Loop Launch Failed", text: "This transcript already has an active loop."))
            return
        }
        if let saveRequest = request.saveRequest {
            do {
                try viewModel.saveLoopDefinitionFromDraft(request.draft, request: saveRequest)
            } catch {
                store.append(.init(sessionID: session.id, role: .error, title: "Loop Save Failed", text: error.localizedDescription))
                return
            }
        }
        Task { @MainActor in
            isLaunchSheetPresented = false
            launchDefinition = nil
            let launched = await viewModel.launchLoop(
                session: session,
                draft: request.draft,
                stopExistingActive: request.stopExistingActive
            )
            guard launched != nil else {
                store.append(.init(sessionID: session.id, role: .error, title: "Loop Launch Failed", text: "\"\(definition.name)\" could not be started."))
                return
            }
        }
    }

    private func availabilityLabel(for definition: LoopDefinition) -> String {
        if definition.source == .builtin { return "Built-in" }
        switch definition.availability {
        case .allProjects:
            return "All Projects/default"
        case .projectPaths:
            if definition.projectPaths.isEmpty { return "Unassigned" }
            if let selectedProjectPath = viewModel.selectedProjectPath,
               definition.projectPaths.contains(selectedProjectPath) {
                return "Current Project"
            }
            return definition.projectPaths.count == 1 ? "1 Project" : "\(definition.projectPaths.count) Projects"
        }
    }

    private func availabilityLabel(for draft: LoopDefinitionEditorDraft) -> String {
        switch draft.availability {
        case .allProjects:
            return "All Projects/default"
        case .projectPaths:
            if draft.projectPaths.isEmpty { return "Unassigned/catalog" }
            if let currentProjectPath, draft.projectPaths == [currentProjectPath] { return "Current Project only" }
            return draft.projectPaths.count == 1 ? "1 Project" : "\(draft.projectPaths.count) Projects"
        }
    }

    private func availabilityColor(for definition: LoopDefinition) -> Color {
        if definition.source == .builtin { return AppTheme.sourceBuiltin }
        switch definition.availability {
        case .allProjects: return AppTheme.brandAccent
        case .projectPaths: return definition.projectPaths.isEmpty ? AppTheme.sourceLibrary : AppTheme.sourceProject
        }
    }

    private func availabilityColor(for draft: LoopDefinitionEditorDraft) -> Color {
        switch draft.availability {
        case .allProjects: return AppTheme.brandAccent
        case .projectPaths: return draft.projectPaths.isEmpty ? AppTheme.sourceLibrary : AppTheme.sourceProject
        }
    }
}

private struct LoopListRow: View {
    let definition: LoopDefinition
    let tint: Color
    let isMuted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
                Image(systemName: "infinity")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(definition.name)
                    .font(.headline)
                    .fontWidth(.expanded)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(definition.description.isEmpty ? definition.goalTemplate : definition.description)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .opacity(isMuted ? 0.62 : 1)
        .saturation(isMuted ? 0.25 : 1)
    }
}
