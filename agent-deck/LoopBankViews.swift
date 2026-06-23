import SwiftUI

private struct LoopDefinitionEditorDraft: Equatable {
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

    private var availableLoopAgents: [EffectiveAgentRecord] {
        viewModel.snapshot.effectiveAgents
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
            if viewModel.selectedLoopDefinitionID == nil {
                viewModel.selectedLoopDefinitionID = viewModel.loopDefinitions.first?.id
            }
            resetEditor(to: viewModel.selectedLoopDefinition)
        }
        .onChange(of: viewModel.selectedLoopDefinitionID) { _, _ in
            resetEditor(to: viewModel.selectedLoopDefinition)
        }
        .onChange(of: viewModel.loopDefinitions) { _, definitions in
            if viewModel.selectedLoopDefinitionID == nil {
                viewModel.selectedLoopDefinitionID = definitions.first?.id
            }
            resetEditor(to: viewModel.selectedLoopDefinition)
        }
        .onChange(of: viewModel.newLoopRequestID) { _, _ in
            createNewLoop()
        }
        .alert("Loop Bank", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
                    availableAgents: viewModel.startupSnapshot(forProjectPath: session.projectPath).effectiveAgents,
                    onCancel: {
                        isLaunchSheetPresented = false
                        launchDefinition = nil
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
                set: { viewModel.selectedLoopDefinitionID = $0 }
            )),
            isDisabled: { _ in false },
            keyboardNavigation: true
        ) { definition in
            loopRow(definition)
        }
    }

    private var loopDetailPane: some View {
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

    private var definitionFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailRow("Name") {
                TextField("Name", text: $editorDraft.name)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
            detailEditor("Description", text: $editorDraft.description, minHeight: 64)
            detailRow("Structure") {
                Picker("Structure", selection: $editorDraft.structure) {
                    ForEach(LoopStructureKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
            }
            detailRow("Write target") {
                Picker("Write target", selection: $editorDraft.writeTarget) {
                    ForEach(LoopWriteTarget.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .labelsHidden()
            }
            detailRow("Max iterations") {
                LoopNumericStepper(value: $editorDraft.maxIterations, range: 1...20)
            }
            detailEditor("Goal template", text: $editorDraft.goalTemplate, minHeight: 120)
            detailRow("Validation command") {
                TextField("Validation command", text: $editorDraft.validationCommand)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
        }
    }

    private var availabilitySection: some View {
        AppCard(title: "Availability") {
            VStack(alignment: .leading, spacing: 0) {
                detailRow("Assignment") {
                    HStack(spacing: 8) {
                        Button("All Projects/default") { setAllProjectsAvailability() }
                            .buttonStyle(.bordered)
                        if currentProjectPath != nil {
                            Button("Current Project only") { setCurrentProjectAvailability() }
                                .buttonStyle(.bordered)
                        }
                        Button("Unassigned/catalog") { setUnassignedAvailability() }
                            .buttonStyle(.bordered)
                    }
                }
                detailRow("Current setting") {
                    Text(availabilityLabel(for: editorDraft))
                }
                detailEditor("Advanced project paths", text: $editorDraft.projectPathsText, minHeight: 72, monospaced: true)
                    .disabled(editorDraft.availability == .allProjects)
                Text("One absolute path per line. Editing the list uses project-specific assignment; an empty list keeps the loop unassigned in the catalog.")
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
        editorDraft.availability = .projectPaths
        editorDraft.projectPathsText = currentProjectPath
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
                }
                Spacer()
                Button("Revert") { resetEditor(to: viewModel.selectedLoopDefinition) }
                    .disabled(editorDraft.isNew && editorDraft.trimmedName.isEmpty && editorDraft.goalTemplate.isEmpty)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(editorDraft.trimmedName.isEmpty || editorDraft.isBuiltin || !requiredAgentsAreSelected)
            }
        }
    }

    @ViewBuilder
    private var loopStructureSection: some View {
        switch editorDraft.structure {
        case .makerChecker:
            AppCard(title: "Maker + Checker") {
                VStack(alignment: .leading, spacing: 0) {
                    detailRow("Maker agent") {
                        LoopAgentNameMenu(selection: $editorDraft.makerName, availableAgents: availableLoopAgents, fallbackLabel: "Maker")
                    }
                    detailRow("Checker agent") {
                        LoopAgentNameMenu(selection: $editorDraft.checkerName, availableAgents: availableLoopAgents, fallbackLabel: "Checker")
                    }
                    detailEditor("Checker rubric", text: $editorDraft.checkerRubric, minHeight: 84)
                    detailRow("Max review rounds") {
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
                detailRow("Branches") {
                    TextField("Branches, separated by |", text: $editorDraft.parallelBranchesText)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        case .discoveryTriage:
            AppCard(title: "Discovery / Triage") {
                detailRow("Triage agent") {
                    LoopAgentNameMenu(selection: $editorDraft.triageAgentName, availableAgents: availableLoopAgents, fallbackLabel: "Explorer")
                }
                detailEditor("Classification prompt", text: $editorDraft.classificationPrompt, minHeight: 84)
            }
        case .humanApproval:
            AppCard(title: "Human Approval") {
                detailEditor("Checkpoint prompt", text: $editorDraft.checkpointPrompt, minHeight: 84)
            }
        case .singleAgent:
            AppCard(title: "Single Agent") {
                detailRow("Agent") {
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
        case .agentPipeline, .parallelAgents, .humanApproval:
            return true
        }
    }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.contentSpacing) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fontWidth(.expanded)
                    .foregroundStyle(AppTheme.mutedText)
                Spacer(minLength: AppTheme.contentSpacing)
                content()
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 11)
            Divider()
        }
    }

    private func detailEditor(_ title: String, text: Binding<String>, minHeight: CGFloat, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fontWidth(.expanded)
                .foregroundStyle(AppTheme.mutedText)
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
            availabilityText: availabilityLabel(for: definition),
            isMuted: loopIsInactive(definition)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func loopIsInactive(_ definition: LoopDefinition) -> Bool {
        guard definition.source == .user, definition.availability == .projectPaths else { return false }
        guard let selectedProjectPath = viewModel.selectedProjectPath else { return definition.projectPaths.isEmpty }
        return !definition.projectPaths.contains(selectedProjectPath)
    }

    private func createNewLoop() {
        viewModel.selectedLoopDefinitionID = nil
        editorDraft = LoopDefinitionEditorDraft(currentProjectPath: viewModel.selectedProjectPath)
    }

    private func resetEditor(to definition: LoopDefinition?) {
        editorDraft = LoopDefinitionEditorDraft(definition: definition, currentProjectPath: viewModel.selectedProjectPath)
    }

    private func save() {
        guard !editorDraft.isBuiltin else { return }
        do {
            let saved = try viewModel.saveLoopDefinition(editorDraft.makeDefinition())
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
    let availabilityText: String
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

                HStack(spacing: 6) {
                    AppLabelTag(text: definition.structure.displayName, color: .secondary)
                    AppLabelTag(text: definition.writeTarget.displayName, color: .secondary)
                    AppLabelTag(text: availabilityText, color: tint)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .opacity(isMuted ? 0.62 : 1)
        .saturation(isMuted ? 0.25 : 1)
    }
}
