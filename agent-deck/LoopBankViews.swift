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
        availability = definition?.availability ?? .allProjects
        projectPathsText = (definition?.projectPaths ?? currentProjectPath.map { [$0] } ?? []).joined(separator: "\n")
        createdAt = definition?.createdAt
        updatedAt = definition?.updatedAt
    }

    var isNew: Bool { filePath == nil }

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
            source: .user,
            availability: availability,
            projectPaths: availability == .projectPaths ? projectPaths : [],
            filePath: filePath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct LoopBankScreen: View {
    var viewModel: AppViewModel
    @State private var editorDraft = LoopDefinitionEditorDraft()
    @State private var errorMessage: String?
    @State private var pendingDelete: LoopDefinition?

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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loop Bank")
                        .font(.headline)
                    Text("Saved user loops")
                        .font(AppTheme.Font.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
                Button {
                    createNewLoop()
                } label: {
                    Label("New Loop", systemImage: "plus")
                }
                .help("Create a user loop")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
    }

    private var loopDetailPane: some View {
        AppPage(editorDraft.isNew ? "New Loop" : editorDraft.name.nonEmpty ?? "Loop", subtitle: detailSubtitle, constrainsContentToViewport: true) {
            AppCard(title: "Definition") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Label(editorDraft.isNew ? "User loop draft" : "User loop", systemImage: "infinity")
                            .font(.headline)
                        Spacer()
                        AppLabelTag(text: availabilityLabel(for: editorDraft), color: availabilityColor(for: editorDraft))
                    }

                    Form {
                        TextField("Name", text: $editorDraft.name)
                        TextField("Description", text: $editorDraft.description, axis: .vertical)
                            .lineLimit(2...4)

                        Picker("Structure", selection: $editorDraft.structure) {
                            ForEach(LoopStructureKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }

                        Picker("Write target", selection: $editorDraft.writeTarget) {
                            ForEach(LoopWriteTarget.allCases) { target in
                                Text(target.displayName).tag(target)
                            }
                        }

                        Stepper(value: $editorDraft.maxIterations, in: 1...20) {
                            Text("Max iterations: \(editorDraft.maxIterations)")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Goal template")
                            TextEditor(text: $editorDraft.goalTemplate)
                                .font(AppTheme.Font.body)
                                .frame(minHeight: 120)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.25))
                                }
                        }

                        TextField("Validation command", text: $editorDraft.validationCommand)
                            .textFieldStyle(.roundedBorder)

                        if editorDraft.structure == .makerChecker {
                            Section("Maker + Checker") {
                                TextField("Maker name", text: $editorDraft.makerName)
                                TextField("Checker name", text: $editorDraft.checkerName)
                                TextField("Checker rubric", text: $editorDraft.checkerRubric, axis: .vertical)
                                    .lineLimit(2...4)
                                Stepper(value: $editorDraft.maxReviewRounds, in: 1...20) {
                                    Text("Max review rounds: \(editorDraft.maxReviewRounds)")
                                }
                            }
                        }

                        Section("Availability") {
                            Picker("Available in", selection: $editorDraft.availability) {
                                Text("All Projects/default").tag(LoopDefinitionAvailability.allProjects)
                                Text("Project path list").tag(LoopDefinitionAvailability.projectPaths)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Project paths")
                                TextEditor(text: $editorDraft.projectPathsText)
                                    .font(.body.monospaced())
                                    .frame(minHeight: 72)
                                    .disabled(editorDraft.availability == .allProjects)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.25))
                                    }
                                Text("One absolute path per line. Leave the list empty with Project path list selected to keep the loop unassigned.")
                                    .font(AppTheme.Font.caption)
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                        }
                    }
                    .formStyle(.grouped)

                    HStack {
                        if let selected = viewModel.selectedLoopDefinition, !editorDraft.isNew {
                            Button("Duplicate") { duplicate(selected) }
                            Button("Delete", role: .destructive) { pendingDelete = selected }
                        }
                        Spacer()
                        Button("Revert") { resetEditor(to: viewModel.selectedLoopDefinition) }
                            .disabled(editorDraft.isNew && editorDraft.trimmedName.isEmpty && editorDraft.goalTemplate.isEmpty)
                        Button("Save") { save() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(editorDraft.trimmedName.isEmpty)
                    }
                }
            }
        }
    }

    private var detailSubtitle: String {
        if editorDraft.isNew { return "Create a saved user loop without editing bundled resources" }
        return "Edit explicit fields and save changes to the user Loop Bank"
    }

    private var listSections: [AppListSection<LoopDefinition>] {
        let selectedProjectPath = viewModel.selectedProjectPath
        let definitions = viewModel.loopDefinitions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let current = definitions.filter { definition in
            guard let selectedProjectPath else { return false }
            return definition.source == .user && definition.availability == .projectPaths && definition.projectPaths.contains(selectedProjectPath)
        }
        let all = definitions.filter { $0.source == .user && $0.availability == .allProjects }
        let unassigned = definitions.filter { $0.source == .user && $0.availability == .projectPaths && $0.projectPaths.isEmpty }
        let otherProjects = definitions.filter { definition in
            definition.source == .user
                && definition.availability == .projectPaths
                && !definition.projectPaths.isEmpty
                && !current.contains(definition)
        }
        let builtins = definitions.filter { $0.source == .builtin }

        return [
            AppListSection(id: "current", title: "Current Project", items: current, emptyMessage: "No loops assigned to the selected project"),
            AppListSection(id: "all", title: "All Projects/default", items: all, emptyMessage: "No default loops"),
            AppListSection(id: "unassigned", title: "Unassigned", items: unassigned, emptyMessage: "No unassigned loops"),
            AppListSection(id: "other", title: "Other Projects", items: otherProjects, emptyMessage: "No other project loops"),
            AppListSection(id: "builtin", title: "Built-in", items: builtins, emptyMessage: "No built-in loops discovered")
        ]
    }

    private func loopRow(_ definition: LoopDefinition) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "infinity")
                .foregroundStyle(availabilityColor(for: definition))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(definition.name)
                    .font(.headline)
                    .fontWidth(.expanded)
                    .lineLimit(1)
                Text(definition.description.isEmpty ? definition.goalTemplate : definition.description)
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    AppLabelTag(text: definition.structure.displayName, color: .secondary)
                    AppLabelTag(text: definition.writeTarget.displayName, color: .secondary)
                    AppLabelTag(text: availabilityLabel(for: definition), color: availabilityColor(for: definition))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func createNewLoop() {
        viewModel.selectedLoopDefinitionID = nil
        editorDraft = LoopDefinitionEditorDraft(currentProjectPath: viewModel.selectedProjectPath)
    }

    private func resetEditor(to definition: LoopDefinition?) {
        editorDraft = LoopDefinitionEditorDraft(definition: definition, currentProjectPath: viewModel.selectedProjectPath)
    }

    private func save() {
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
        if definition.source == .builtin { return .gray }
        switch definition.availability {
        case .allProjects: return .blue
        case .projectPaths: return definition.projectPaths.isEmpty ? .orange : .cyan
        }
    }

    private func availabilityColor(for draft: LoopDefinitionEditorDraft) -> Color {
        switch draft.availability {
        case .allProjects: return .blue
        case .projectPaths: return draft.projectPaths.isEmpty ? .orange : .cyan
        }
    }
}
