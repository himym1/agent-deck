import AppKit
import SwiftUI

private struct DefaultModelsModelPicker: View {
    let models: [AvailableModel]
    let selectedModel: AvailableModel?
    let onSelect: (AvailableModel) -> Void

    @State private var isPresented = false
    @State private var searchText = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.caption.weight(.semibold))
                Text(selectedModel?.identifier ?? AppLocalization.string("model.title", default: "Model"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .font(.subheadline.weight(.semibold))
            .fontWidth(.expanded)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .appGlassCapsule()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.string("model.title", default: "Model"), systemImage: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)

                AppTextField(
                    text: $searchText,
                    placeholder: AppLocalization.string("model.search.placeholder", default: "Search models or providers"),
                    font: .caption
                )

                if groupedModels.isEmpty {
                    Text(AppLocalization.string("model.search.empty", default: "No matching models"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(groupedModels, id: \.provider) { group in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        ProviderLabel(provider: group.provider, logoSize: 14, spacing: 5)
                                            .font(.caption.weight(.bold))
                                            .fontWidth(.expanded)
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 2)

                                    VStack(spacing: 3) {
                                        ForEach(group.models, id: \.identifier) { model in
                                            Button {
                                                onSelect(model)
                                                isPresented = false
                                            } label: {
                                                row(
                                                    title: model.model,
                                                    subtitle: modelMetadataSubtitle(model),
                                                    isSelected: model.identifier == selectedModel?.identifier
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 340)
                }
            }
            .padding(12)
            .frame(width: 360)
        }
    }

    private var groupedModels: [(provider: String, models: [AvailableModel])] {
        Dictionary(grouping: filteredModels, by: \.provider)
            .map { provider, models in
                (provider, models.sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending })
            }
            .sorted { $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending }
    }

    private var filteredModels: [AvailableModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return models }
        return models.filter { model in
            [model.provider, model.model, model.identifier]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private func row(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AppTheme.brandAccent : AppTheme.mutedText)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isSelected ? AppTheme.selectionFill : Color.clear))
    }

    private func modelMetadataSubtitle(_ model: AvailableModel) -> String {
        var badges: [String] = []
        badges.append(model.supportsThinking ? "thinking" : "no thinking")
        if model.supportsImages { badges.append("images") }
        return badges.joined(separator: " · ")
    }
}

private struct DefaultModelsThinkingPicker: View {
    let selectedLevel: String
    let levels: [String]
    let onSelect: (String) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                Text(AppLocalization.thinkingLevel(selectedLevel))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.mutedText)
            }
            .font(.subheadline.weight(.semibold))
            .fontWidth(.expanded)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .appGlassCapsule()
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(AppLocalization.string("thinking.title", default: "Thinking"), systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)

                ForEach(levels, id: \.self) { level in
                    Button {
                        onSelect(level)
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedLevel == level ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(selectedLevel == level ? AppTheme.brandAccent : AppTheme.mutedText)
                                .frame(width: 18, height: 18)
                            Text(AppLocalization.thinkingLevel(level))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selectedLevel == level ? AppTheme.selectionFill : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(width: 220)
        }
    }
}

struct ModelsInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.string("app.models.info.title", default: "Models catalog"))
                .font(.headline)
                .fontWidth(.expanded)

            VStack(alignment: .leading, spacing: 10) {
                infoRow(
                    AppLocalization.string("app.models.info.catalog.title", default: "Catalog"),
                    AppLocalization.string("app.models.info.catalog.description", default: "Agent Deck queries Pi for available models and groups them by provider.")
                )
                infoRow(
                    AppLocalization.string("app.models.info.defaults.title", default: "Defaults"),
                    AppLocalization.string("app.models.info.defaults.description", default: "Default model and thinking apply to new Pi Agent sessions unless a session or agent overrides them.")
                )
                infoRow(
                    AppLocalization.string("app.models.info.automation.title", default: "Automation"),
                    AppLocalization.string("app.models.info.automation.description", default: "Apple Foundation Model is local and can be used for automation tasks in Settings.")
                )
                infoRow(
                    AppLocalization.string("app.models.info.availability.title", default: "Availability"),
                    AppLocalization.string("app.models.info.availability.description", default: "Disabling a model removes it from default selection, launch controls, and agent editors.")
                )
            }

            Text(AppLocalization.string("app.models.info.refresh.description", default: "Refresh reloads the catalog from Pi and updates supported thinking levels for the current selection."))
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
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

struct ModelsScreen: View {
    var viewModel: AppViewModel

    @State private var loginService = PiProviderLoginService()

    var body: some View {
        AppPage(AppLocalization.string("app.models.catalog.title", default: "Models")) {
            if displayModels.isEmpty {
                AppCard(title: AppLocalization.string("app.models.info.catalog.title", default: "Catalog")) {
                    Text(AppLocalization.string("app.models.catalog.empty", default: "No models loaded yet. Use the toolbar Refresh action to query Pi."))
                        .foregroundStyle(AppTheme.mutedText)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.availableModels.isEmpty {
                        defaultSelectionSection
                    }
                    ForEach(groupedModels, id: \.provider) { group in
                        providerSection(group)
                    }
                }
            }
        }
        .onAppear {
            viewModel.ensureAvailableModelsLoaded()
            viewModel.refreshProviderAuthState()
            viewModel.ensureConnectableProvidersLoaded()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.isAddProviderPresented },
            set: { viewModel.isAddProviderPresented = $0 }
        )) {
            AddProviderFlowSheet(viewModel: viewModel, loginService: loginService)
        }
    }

    private func providerSection(_ group: (provider: String, models: [AvailableModel])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ProviderLabel(provider: group.provider, logoSize: 22, spacing: 8)
                    .font(.title3.weight(.bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.primary)
                Spacer()
                if group.provider != FoundationModelAutomationService.provider {
                    if viewModel.signedInProviders.contains(group.provider) {
                        signOutButton(for: group.provider)
                    }
                    providerToggle(for: group)
                }
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                    modelRow(model)
                    if index < group.models.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(AppTheme.contentFill)
                    .stroke(AppTheme.contentStroke, lineWidth: 1)
            )
        }
    }

    private var defaultSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image("pi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                Text(AppLocalization.string("Agent Defaults", default: "Agent Defaults"))
                    .font(.title3.weight(.bold))
                    .fontWidth(.expanded)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 2)

            HStack(alignment: .top, spacing: 16) {
                defaultModelCard
                defaultThinkingCard
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var defaultModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundStyle(AppTheme.brandAccent)
                    .font(.title3.weight(.semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Default Model", default: "Default Model"))
                        .font(.headline)
                        .fontWidth(.expanded)
                    Text(AppLocalization.string("Used for new Pi Agent sessions unless a session or agent overrides it.", default: "Used for new Pi Agent sessions unless a session or agent overrides it."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DefaultModelsModelPicker(
                models: viewModel.enabledAvailableModels,
                selectedModel: selectedDefaultModel,
                onSelect: { model in
                    defaultModelBinding.wrappedValue = model.identifier
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let model = selectedDefaultModel {
                    AppLabelTag(text: model.supportsImages ? "Images" : "Text Only", color: model.supportsImages ? .purple : .secondary)
                    AppLabelTag(text: model.supportsThinking ? "Thinking" : "No Thinking", color: model.supportsThinking ? .green : .secondary)
                } else {
                    Text(AppLocalization.string("No enabled models available", default: "No enabled models available"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.contentStroke, lineWidth: 1)
        )
    }

    private var defaultThinkingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(AppTheme.brandAccent)
                    .font(.title3.weight(.semibold))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Default Thinking", default: "Default Thinking"))
                        .font(.headline)
                        .fontWidth(.expanded)
                    Text(AppLocalization.string("Thinking level used for new Pi Agent sessions.", default: "Thinking level used for new Pi Agent sessions."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DefaultModelsThinkingPicker(
                selectedLevel: defaultThinkingBinding.wrappedValue,
                levels: defaultThinkingLevels,
                onSelect: { level in
                    defaultThinkingBinding.wrappedValue = level
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                AppLabelTag(
                    text: AppLocalization.format("Selected: %@", default: "Selected: %@", currentDefaultThinkingLabel),
                    color: AppTheme.brandAccent
                )
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.contentStroke, lineWidth: 1)
        )
    }

    private var defaultModelBinding: Binding<String> {
        Binding(
            get: {
                viewModel.defaultPiAgentModel()?.identifier ?? viewModel.enabledAvailableModels.first?.identifier ?? ""
            },
            set: { identifier in
                let model = viewModel.enabledAvailableModels.first { $0.identifier == identifier }
                viewModel.setDefaultPiAgentModel(model)
                guard let model else { return }
                let normalizedThinking = viewModel.defaultPiAgentThinkingLevel(for: model.supportedThinkingLevels)
                if viewModel.piRuntimeDefaultThinkingLevel() != normalizedThinking {
                    viewModel.setDefaultPiAgentThinkingLevel(normalizedThinking)
                }
            }
        )
    }

    private var defaultThinkingBinding: Binding<String> {
        Binding(
            get: {
                viewModel.defaultPiAgentThinkingLevel(for: defaultThinkingLevels)
            },
            set: { viewModel.setDefaultPiAgentThinkingLevel($0) }
        )
    }

    private var defaultThinkingLevels: [String] {
        selectedDefaultModel?.supportedThinkingLevels ?? []
    }

    private var selectedDefaultModel: AvailableModel? {
        let identifier = defaultModelBinding.wrappedValue
        return viewModel.enabledAvailableModels.first { $0.identifier == identifier }
    }

    private var currentDefaultThinkingLabel: String {
        let current = defaultThinkingBinding.wrappedValue
        return AppLocalization.thinkingLevel(current)
    }

    private func modelRow(_ model: AvailableModel) -> some View {
        let isProviderEnabled = viewModel.isProviderEnabled(model.provider)
        let isEnabled = viewModel.isModelEnabled(model)
        return HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { viewModel.isModelEnabled(model) },
                set: { viewModel.setModelEnabled(model, isEnabled: $0) }
            ))
            .appSwitch()
            .labelsHidden()
            .disabled(!isProviderEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(model.modelDisplayName)
                        .font(.headline)
                        .fontWidth(.expanded)
                        .foregroundStyle(isEnabled ? .primary : AppTheme.mutedText)
                }
                Text(model.identifier)
                    .font(.footnote.monospaced())
                    .foregroundStyle(AppTheme.mutedText)
                    .textSelection(.enabled)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if FoundationModelAutomationService.isFoundationModel(model) {
                        AppLabelTag(text: "Local", color: .green)
                        AppLabelTag(text: "Automation Only", color: AppTheme.brandAccent)
                    }
                    AppLabelTag(text: model.supportsThinking ? "Thinking" : "No Thinking", color: model.supportsThinking ? .green : .secondary)
                    AppLabelTag(text: model.supportsImages ? "Images" : "Text Only", color: model.supportsImages ? .purple : .secondary)
                    if PiNativeSubagentBridgeExtensions.isOpenAIFastEligibleModel(provider: model.provider, modelID: model.model) {
                        fastModeTagButton(for: model, isModelEnabled: isEnabled)
                    }
                }
                Text("ctx \(model.contextWindow) · out \(model.maxOutput)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .opacity(isProviderEnabled ? (isEnabled ? 1 : 0.55) : 0.4)
        .allowsHitTesting(isProviderEnabled)
        .padding(.vertical, 10)
    }

    private func signOutButton(for provider: String) -> some View {
        Button {
            Task { try? viewModel.signOutProvider(provider) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.caption.weight(.semibold))
                Text(AppLocalization.string("Sign out", default: "Sign out"))
                    .font(.caption.weight(.semibold))
                    .fontWidth(.expanded)
            }
            .foregroundStyle(AppTheme.brandAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.brandAccent.opacity(0.12), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(AppLocalization.format("Sign out of %@ (removes its credentials from auth.json).", default: "Sign out of %@ (removes its credentials from auth.json).", provider))
    }

    private func providerToggle(for group: (provider: String, models: [AvailableModel])) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.isProviderEnabled(group.provider) },
                set: { viewModel.setProviderEnabled(group.provider, isEnabled: $0) }
            )
        ) {
            EmptyView()
        }
        .appSwitch()
        .labelsHidden()
        .help(providerToggleHelp(for: group.provider, isEnabled: viewModel.isProviderEnabled(group.provider)))
    }

    private func providerToggleHelp(for provider: String, isEnabled: Bool) -> String {
        isEnabled
            ? AppLocalization.format("models.provider.disable.help", default: "Disable all %@ models without changing per-model preferences.", provider)
            : AppLocalization.format("models.provider.enable.help", default: "Enable all %@ models and restore prior per-model preferences.", provider)
    }

    private func fastModeTagButton(for model: AvailableModel, isModelEnabled: Bool) -> some View {
        let isFastEnabled = viewModel.isOpenAIFastModeEnabled(model)
        return Button {
            viewModel.setOpenAIFastMode(model, isEnabled: !isFastEnabled)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isFastEnabled ? "checkmark.square.fill" : "square")
                    .font(.caption.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(AppLocalization.string("Fast", default: "Fast"))
                    .font(.caption.weight(.semibold))
                    .fontWidth(.expanded)
            }
            .foregroundStyle(isFastEnabled ? AppTheme.brandAccent : AppTheme.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isFastEnabled ? AppTheme.brandAccent : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isModelEnabled)
        .help(AppLocalization.string("Use OpenAI priority service tier for this ChatGPT-auth Codex model in parent sessions and Deck agents.", default: "Use OpenAI priority service tier for this ChatGPT-auth Codex model in parent sessions and Deck agents."))
        .animation(.snappy(duration: 0.18), value: isFastEnabled)
    }

    private var displayModels: [AvailableModel] {
        var models = viewModel.availableModels
        if let foundationModel = viewModel.foundationAutomationModel,
           !models.contains(where: { $0.identifier == foundationModel.identifier }) {
            models.insert(foundationModel, at: 0)
        }
        return models
    }

    private var groupedModels: [(provider: String, models: [AvailableModel])] {
        Dictionary(grouping: displayModels, by: \.provider)
            .map { provider, models in
                (provider, models.sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending })
            }
            .sorted { lhs, rhs in
                if lhs.provider == FoundationModelAutomationService.provider { return true }
                if rhs.provider == FoundationModelAutomationService.provider { return false }
                return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
            }
    }
}

struct SubagentsScreen: View {
    var viewModel: AppViewModel
    var onReturnToAgent: () -> Void = {}

    var body: some View {
        AppPage(AppLocalization.string("sidebar.item.subagents", default: "Deck agents"), subtitle: AppLocalization.string("App-managed delegation and supervision", default: "App-managed delegation and supervision")) {
            headerCard
            nativeRuntimeCard
            sessionDefaultsCard
            availableAgentsCard
            safetyCard
        }
    }

    private var headerCard: some View {
        AppCard(title: AppLocalization.string("sidebar.item.subagents", default: "Deck agents")) {
            HStack(alignment: .center, spacing: AppTheme.contentSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("App-managed delegation and supervision", default: "App-managed delegation and supervision"))
                        .font(.callout.weight(.semibold))
                    Text(AppLocalization.string("Use the Pi Agent page to start or continue sessions; this page explains the Deck agent runtime and defaults.", default: "Use the Pi Agent page to start or continue sessions; this page explains the Deck agent runtime and defaults."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button {
                    onReturnToAgent()
                } label: {
                    Label(AppLocalization.string("navigation.backToPiAgent", default: "Back to Pi Agent"), systemImage: "chevron.left")
                }
                .appSecondaryButton()
            }
        }
    }

    private var nativeRuntimeCard: some View {
        AppCard(title: "Deck Agent Runtime") {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.format("subagents.runtime.launches", default: "• %@ launches child Pi sessions itself and keeps parent, child, transcript, artifact, and supervisor state in the app.", AppBrand.displayName))
                Text(AppLocalization.string("• Parent sessions receive app-provided managed tools for single and parallel delegation.", default: "• Parent sessions receive app-provided managed tools for single and parallel delegation."))
                Text(AppLocalization.format("subagents.runtime.supervisor", default: "• Child sessions can contact the supervisor through %@'s supervisor request cards.", AppBrand.displayName))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sessionDefaultsCard: some View {
        AppCard(title: "Session Defaults") {
            AppKeyValueList(rows: [
                (
                    "New Sessions",
                    viewModel.areSubagentsEnabledForNewSessions
                        ? AppLocalization.string("Deck agents enabled", default: "Deck agents enabled")
                        : AppLocalization.string("Deck agents disabled", default: "Deck agents disabled")
                ),
                ("Selected Session", selectedSessionStatus),
                ("Available Agents", "\(viewModel.snapshot.effectiveAgents.count(where: { $0.resolved.disabled != true }))")
            ])
        }
    }

    private var availableAgentsCard: some View {
        AppCard(title: "Available Deck Agents") {
            VStack(alignment: .leading, spacing: 10) {
                let agents = viewModel.snapshot.effectiveAgents
                    .filter { $0.resolved.disabled != true }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if agents.isEmpty {
                    Text(AppLocalization.string("No enabled agents are available in the current scope.", default: "No enabled agents are available in the current scope."))
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    ForEach(agents.prefix(12)) { agent in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "paperplane")
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(width: 18)
                            Text(agent.name)
                                .font(.body.weight(.semibold))
                            Text(AppLocalization.agentDescription(name: agent.name, default: agent.resolved.description))
                                .foregroundStyle(AppTheme.mutedText)
                                .lineLimit(1)
                        }
                    }

                    if agents.count > 12 {
                        Text(AppLocalization.format("subagents.moreAgents", default: "%lld more agents are available from the run picker.", agents.count - 12))
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var safetyCard: some View {
        AppCard(title: "Safety") {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.string("• Writer-like Deck agent runs use isolated worktrees unless direct project writes are explicitly allowed.", default: "• Writer-like Deck agent runs use isolated worktrees unless direct project writes are explicitly allowed."))
                Text(AppLocalization.format("subagents.safety.persisted", default: "• Parent and child transcript state is persisted by %@.", AppBrand.displayName))
                Text(AppLocalization.string("• Supervisor questions stay scoped to the owning parent session and window.", default: "• Supervisor questions stay scoped to the owning parent session and window."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedSessionStatus: String {
        guard let session = viewModel.piAgentSessionStore.selectedSession else { return AppLocalization.string("No session selected", default: "No session selected") }
        guard session.subagentsEnabled else { return AppLocalization.string("Deck agents disabled", default: "Deck agents disabled") }
        return viewModel.catalogAgents(for: session).isEmpty
            ? AppLocalization.string("Deck agents disabled (no agents selected)", default: "Deck agents disabled (no agents selected)")
            : AppLocalization.string("Deck agents enabled", default: "Deck agents enabled")
    }
}

struct AgentModelQuickEditorContext: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let sections: [AgentModelQuickEditorSection]
    let preferredOverrideScope: AgentEditingTarget.OverrideScope
}

struct AgentModelQuickEditorSection: Identifiable {
    let title: String
    let agents: [EffectiveAgentRecord]
    var isDimmed = false

    var id: String { title }
}

struct AgentModelQuickEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: AgentModelQuickEditorContext
    let availableModels: [AvailableModel]
    let modelsLastUpdatedAt: Date?
    let makeDraft: (EffectiveAgentRecord) -> AgentEditorDraft?
    let onSaveAll: ([(AgentEditorDraft, EffectiveAgentRecord)]) throws -> Void

    @State private var drafts: [EffectiveAgentRecord.ID: AgentEditorDraft]
    @State private var baselines: [EffectiveAgentRecord.ID: AgentEditorDraft]
    @State private var saveMessage: String?

    init(
        context: AgentModelQuickEditorContext,
        availableModels: [AvailableModel],
        modelsLastUpdatedAt: Date?,
        makeDraft: @escaping (EffectiveAgentRecord) -> AgentEditorDraft?,
        onSaveAll: @escaping ([(AgentEditorDraft, EffectiveAgentRecord)]) throws -> Void
    ) {
        self.context = context
        self.availableModels = availableModels
        self.modelsLastUpdatedAt = modelsLastUpdatedAt
        self.makeDraft = makeDraft
        self.onSaveAll = onSaveAll

        var seeded: [EffectiveAgentRecord.ID: AgentEditorDraft] = [:]
        for agent in context.sections.flatMap(\.agents) where seeded[agent.id] == nil {
            seeded[agent.id] = makeDraft(agent)
        }
        _drafts = State(initialValue: seeded)
        _baselines = State(initialValue: seeded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.title)
                        .font(.title2.bold())
                        .fontWidth(.expanded)
                    Text(context.subtitle)
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    ForEach(context.sections) { section in
                        if !section.agents.isEmpty {
                            AgentModelQuickEditSectionView(
                                section: section,
                                availableModels: availableModels,
                                binding: binding(for:),
                                isDirty: isDirty
                            )
                        }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Default model and thinking can be changed in Sidebar > Models.", default: "Default model and thinking can be changed in Sidebar > Models."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                Button(AppLocalization.string("Cancel", default: "Cancel")) {
                    dismiss()
                }
                .appSecondaryButton()
                Button(AppLocalization.string("Save All", default: "Save All")) {
                    saveAll()
                }
                .appPrimaryButton()
                .disabled(dirtyAgentIDs.isEmpty)
            }
        }
        .padding(AppTheme.pagePadding)
        .frame(minWidth: 900, minHeight: 560)
    }

    private var dirtyAgentIDs: [EffectiveAgentRecord.ID] {
        drafts.keys.filter(isDirty)
    }

    private func isDirty(_ id: EffectiveAgentRecord.ID) -> Bool {
        drafts[id] != baselines[id]
    }

    private func binding(for id: EffectiveAgentRecord.ID) -> Binding<AgentEditorDraft>? {
        guard let initial = drafts[id] else { return nil }
        return Binding(
            get: { drafts[id] ?? initial },
            set: { drafts[id] = $0 }
        )
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func saveAll() {
        var pairs: [(AgentEditorDraft, EffectiveAgentRecord)] = []
        for section in context.sections {
            for agent in section.agents where isDirty(agent.id) {
                guard let draft = drafts[agent.id] else { continue }
                pairs.append((draft, agent))
            }
        }
        guard !pairs.isEmpty else { return }

        do {
            try onSaveAll(pairs)
            for (draft, agent) in pairs {
                baselines[agent.id] = draft
            }
            dismiss()
        } catch {
            NSSound.beep()
            saveMessage = nil
        }
    }
}

struct AgentModelQuickEditSectionView: View {
    let section: AgentModelQuickEditorSection
    let availableModels: [AvailableModel]
    let binding: (EffectiveAgentRecord.ID) -> Binding<AgentEditorDraft>?
    let isDirty: (EffectiveAgentRecord.ID) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppLocalization.string(section.title, default: section.title))
                    .font(.headline)
                    .fontWidth(.expanded)
                Spacer()
            }
            .padding(.horizontal, sectionContentInset)
            .padding(.top, sectionContentInset)
            .padding(.bottom, AppTheme.contentSpacing)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AppTheme.contentSpacing) {
                    AgentModelColumnHeader("Agent")
                        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    AgentModelColumnHeader("Model")
                        .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                    AgentModelColumnHeader("Thinking")
                        .frame(width: 130, alignment: .leading)
                    AgentModelColumnHeader("")
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.bottom, AppTheme.contentSpacing / 2)

                Divider()

                ForEach(editableAgents) { agent in
                    if let draftBinding = binding(agent.id) {
                        AgentModelQuickEditRow(
                            agent: agent,
                            draft: draftBinding,
                            availableModels: availableModels,
                            isDirty: isDirty(agent.id)
                        )
                    }
                }
            }
            .padding(.horizontal, sectionContentInset)

            Spacer(minLength: sectionContentInset)
        }
        .opacity(section.isDimmed ? 0.58 : 1)
        .background(AppTheme.contentSubtleFill.opacity(section.isDimmed ? 0.10 : 0.18), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.contentStroke, lineWidth: 1)
        )
    }

    private var sectionContentInset: CGFloat { AppTheme.pagePadding }

    private var editableAgents: [EffectiveAgentRecord] {
        section.agents.filter { binding($0.id) != nil }
    }
}

private struct AgentModelColumnHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(AppLocalization.string(title, default: title))
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.mutedText)
    }
}

struct AgentModelQuickEditRow: View {
    let agent: EffectiveAgentRecord
    @Binding var draft: AgentEditorDraft
    let availableModels: [AvailableModel]
    let isDirty: Bool

    var body: some View {
        HStack(spacing: AppTheme.contentSpacing) {
            HStack(spacing: 8) {
                Text(agent.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if isDirty {
                    AppLabelTag(text: "Unsaved", color: .orange)
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Picker(AppLocalization.string("Model", default: "Model"), selection: modelSelectionBinding) {
                Text(AppLocalization.string("Default", default: "Default")).tag("")
                ForEach(availableModels, id: \.identifier) { model in
                    Text(model.identifier).tag(model.identifier)
                }
            }
            .labelsHidden()
            .appMenuPicker()
            .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
            .help(selectedModelMetadataSummary ?? AppLocalization.string("Use the default model from Sidebar > Models", default: "Use the default model from Sidebar > Models"))

            Picker(AppLocalization.string("Thinking", default: "Thinking"), selection: thinkingSelectionBinding) {
                if usesDefaultModel {
                    Text(AppLocalization.string("Default", default: "Default")).tag(defaultThinkingSelection)
                } else {
                    ForEach(availableThinkingLevels, id: \.self) { level in
                        Text(AppLocalization.thinkingLevel(level)).tag(level)
                    }
                }
            }
            .labelsHidden()
            .appMenuPicker()
            .frame(width: 130, alignment: .leading)
            .disabled(usesDefaultModel || availableThinkingLevels.isEmpty)
            .help(usesDefaultModel ? "Select a specific model to override thinking for this agent" : "Override thinking for the selected model")

            Text(selectedModelMetadataSummary ?? "Default")
                .font(.caption.monospaced())
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)
                .frame(width: 120, alignment: .trailing)
        }
        .frame(minHeight: rowHeight)
        .background(rowHighlight)
    }

    private var rowHeight: CGFloat { 42 }

    @ViewBuilder
    private var rowHighlight: some View {
        if isDirty {
            Color.orange.opacity(0.08)
        } else {
            Color.clear
        }
    }

    private var usesDefaultModel: Bool {
        draft.config.model == nil
    }

    private var selectedModel: AvailableModel? {
        guard let identifier = draft.config.model else { return nil }
        return availableModels.first { $0.identifier == identifier }
    }

    private var selectedModelMetadataSummary: String? {
        guard let model = selectedModel else { return nil }
        return "context: \(model.contextWindow)"
    }

    private var defaultThinkingSelection: String { "__default__" }

    private var availableThinkingLevels: [String] {
        selectedModel?.supportedThinkingLevels ?? []
    }

    private var modelSelectionBinding: Binding<String> {
        Binding(
            get: { draft.config.model ?? "" },
            set: { newValue in
                draft.config.model = newValue.isEmpty ? nil : newValue
                clampThinkingSelection()
            }
        )
    }

    private var thinkingSelectionBinding: Binding<String> {
        Binding(
            get: {
                guard !usesDefaultModel else { return defaultThinkingSelection }
                let current = draft.config.thinking ?? "off"
                return availableThinkingLevels.contains(current) ? current : (availableThinkingLevels.first ?? "off")
            },
            set: { newValue in
                guard newValue != defaultThinkingSelection else { return }
                draft.config.thinking = newValue == "off" ? nil : newValue
            }
        )
    }

    private func clampThinkingSelection() {
        let current = draft.config.thinking ?? "off"
        guard !availableThinkingLevels.contains(current) else { return }
        let fallback = availableThinkingLevels.first ?? "off"
        draft.config.thinking = fallback == "off" ? nil : fallback
    }
}
