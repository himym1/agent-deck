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
        .onReceive(NotificationCenter.default.publisher(for: .agentDeckNewLoopRequested)) { _ in
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
            AppCard(title: "Definition") {
                VStack(alignment: .leading, spacing: AppTheme.contentSpacing) {
                    HStack(alignment: .top) {
                        Label(editorDraft.isNew ? "User loop draft" : "User loop", systemImage: "infinity")
                            .font(.headline)
                        Spacer()
                        AppLabelTag(text: availabilityLabel(for: editorDraft), color: availabilityColor(for: editorDraft))
                    }

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
            detailRow("Description") {
                TextField("Description", text: $editorDraft.description, axis: .vertical)
                    .lineLimit(2...4)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
            }
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
                detailRow("Available in") {
                    Picker("Available in", selection: $editorDraft.availability) {
                        Text("All Projects/default").tag(LoopDefinitionAvailability.allProjects)
                        Text("Project path list").tag(LoopDefinitionAvailability.projectPaths)
                    }
                    .labelsHidden()
                }
                detailEditor("Project paths", text: $editorDraft.projectPathsText, minHeight: 72, monospaced: true)
                    .disabled(editorDraft.availability == .allProjects)
                Text("One absolute path per line. Leave the list empty with Project path list selected to keep the loop unassigned.")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .padding(.top, 8)
            }
        }
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
                    detailRow("Write target") { Text(run.writeTarget.displayName) }
                    if let projectPath = run.projectPath, !projectPath.isEmpty {
                        detailRow("Project") { Text(URL(fileURLWithPath: projectPath).lastPathComponent.nonEmpty ?? projectPath) }
                    }
                    detailRow("Ended") { Text((run.endedAt ?? run.startedAt).formatted(date: .abbreviated, time: .shortened)) }
                }
            } else {
                Text("No exact matching loop runs yet.")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
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
                    .disabled(editorDraft.trimmedName.isEmpty || editorDraft.isBuiltin)
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
                    detailRow("Checker rubric") {
                        TextField("Checker rubric", text: $editorDraft.checkerRubric, axis: .vertical)
                            .lineLimit(2...4)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                    }
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
                detailRow("Classification prompt") {
                    TextField("Classification prompt", text: $editorDraft.classificationPrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        case .humanApproval:
            AppCard(title: "Human Approval") {
                detailRow("Checkpoint prompt") {
                    TextField("Checkpoint prompt", text: $editorDraft.checkpointPrompt, axis: .vertical)
                        .lineLimit(2...4)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                }
            }
        case .singleAgent:
            AppCard(title: "Single Agent") {
                detailRow("Agent") {
                    LoopAgentNameMenu(selection: $editorDraft.makerName, availableAgents: availableLoopAgents, fallbackLabel: "Agent")
                }
            }
        }
    }

    private func detailRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.contentSpacing) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
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
                .font(.headline)
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
        case .allProjects: return "All Projects/default"
        case .projectPaths: return draft.projectPaths.isEmpty ? "Unassigned" : "\(draft.projectPaths.count) Project(s)"
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
