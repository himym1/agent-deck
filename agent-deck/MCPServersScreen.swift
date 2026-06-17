import SwiftUI

/// Runtime → MCP. Native Model Context Protocol support: a master toggle plus the
/// configured servers (read from mcp.json), each with a connection test and
/// project assignment. Server discovery runs OFF the main thread and is cached in
/// `@State`; the SwiftUI body performs no filesystem I/O (mirrors ExtensionsScreen).
struct MCPServersScreen: View {
    var viewModel: AppViewModel

    /// All configured servers (merged across mcp.json locations), loaded off-main and
    /// cached. Never read via a body-time load.
    @State private var servers: [MCPServerEntry] = []
    @State private var isLoading = false
    @State private var statusByServer: [String: ProbeStatus] = [:]
    /// OAuth connected state per remote server (has stored tokens).
    @State private var connectedByServer: [String: Bool] = [:]
    @State private var connectingServers: Set<String> = []
    /// Bumped by the Refresh button to force a reload + reconnect.
    @State private var reloadTick = 0
    /// Presented add/edit sheet (nil = closed).
    @State private var editorModel: MCPServerEditorModel?
    /// Name pending delete confirmation.
    @State private var pendingDeleteName: String?

    /// Selected server in the master list.
    @State private var selectedServerID: MCPServerEntry.ID?

    enum ProbeStatus: Equatable {
        case probing
        case ok([MCPProbeTool])
        case failed(String)

        var tools: [MCPProbeTool] { if case let .ok(tools) = self { return tools }; return [] }
    }

    private var mcpEnabled: Bool { viewModel.appSettings.mcpEnabled }
    private var selectedServer: MCPServerEntry? {
        guard let id = selectedServerID else { return nil }
        return servers.first { $0.id == id }
    }

    var body: some View {
        Group {
            // With no servers there's nothing to put in two panes — collapse the
            // split into one centered empty state (matching the app's other
            // "nothing here" screens) instead of two half-empty messages.
            if servers.isEmpty {
                emptyState
            } else {
                SplitView {
                    listPane
                } detail: {
                    detailPane
                }
            }
        }
        // Reload on project switch, enable toggle, and manual Refresh. Off-main.
        .task(id: "\(viewModel.projectRootURL?.path ?? "")#\(mcpEnabled)#\(reloadTick)") {
            await loadServers()
        }
        // Window-toolbar actions (the toolbar lives in ContentView).
        .onChange(of: viewModel.mcpAddRequestToken) { _, _ in editorModel = .add }
        .onChange(of: viewModel.mcpRefreshRequestToken) { _, _ in reloadTick += 1 }
        .sheet(item: $editorModel) { model in
            MCPServerEditorSheet(model: model, existingNames: Set(servers.map(\.name))) { name, config in
                do {
                    try viewModel.upsertMCPServer(name: name, config: config)
                    reloadTick += 1
                } catch { NSSound.beep() }
            }
        }
        .alert("Remove MCP server?", isPresented: Binding(get: { pendingDeleteName != nil }, set: { if !$0 { pendingDeleteName = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeleteName = nil }
            Button("Remove", role: .destructive) {
                if let name = pendingDeleteName {
                    if selectedServerID == name { selectedServerID = nil }
                    do { try viewModel.removeMCPServer(named: name); reloadTick += 1 }
                    catch { NSSound.beep() }
                }
                pendingDeleteName = nil
            }
        } message: {
            Text("This removes “\(pendingDeleteName ?? "")” from ~/.pi/agent/mcp.json and clears it from any project and agent assignments.")
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        // Enable/disable lives in the window toolbar (mirrors Memory); the title
        // shows "MCP: On/Off". The empty case is handled before the split, so the
        // list always has servers here.
        AppList(
            sections: [AppListSection(id: "servers", title: "Servers", items: servers)],
            selection: .single($selectedServerID)
        ) { entry in
            listRow(entry)
        }
    }

    /// Single centered empty state shown in place of the split view when no servers
    /// are configured. Uses `ContentUnavailableView` for consistent system fonts and
    /// centering, matching the app's other empty screens.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(isLoading ? "Loading MCP servers…" : "No MCP servers", systemImage: SidebarItem.mcp.systemImage)
        } description: {
            Text("Add a server from the toolbar — paste a config or fill the form. Servers are read from mcp.json in ~/.config/mcp, ~/.pi/agent, and the project's .mcp.json / .pi/mcp.json.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func listRow(_ entry: MCPServerEntry) -> some View {
        let isSelected = selectedServerID == entry.id
        return HStack(spacing: 10) {
            Image(systemName: entry.config.resolvedTransport == .stdio ? "terminal" : "globe")
                .font(.callout)
                .foregroundStyle(isSelected ? AppTheme.brandAccent : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                Text(transportLabel(entry))
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            rowStatus(entry)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rowStatus(_ entry: MCPServerEntry) -> some View {
        switch statusByServer[entry.name] {
        case .probing: AppSpinner().controlSize(.small)
        case let .ok(tools): Text("\(tools.count)").font(.caption.weight(.semibold)).foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let entry = selectedServer {
            AppPage(entry.name, subtitle: transportLabel(entry)) {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard(entry)
                    toolsCard(entry)
                    projectAssignmentCard(entry)
                }
            }
        } else {
            AppPage("MCP", subtitle: "Connect Model Context Protocol servers and assign them to projects and agents") {
                detailPlaceholder
            }
        }
    }

    private var detailPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a server")
                .font(.title3.weight(.semibold))
            Text("Pick a server on the left to see its tools, test the connection, and assign it to projects.")
                .font(.callout).foregroundStyle(AppTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionCard(_ entry: MCPServerEntry) -> some View {
        AppCard(title: "Connection") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    detailStatusTag(entry)
                    Spacer(minLength: 8)
                    if entry.config.resolvedTransport != .stdio {
                        if connectingServers.contains(entry.name) {
                            AppSpinner().controlSize(.small)
                        } else if connectedByServer[entry.name] ?? false {
                            Button("Sign out") { Task { await signOut(entry) } }.controlSize(.small)
                        } else {
                            Button("Connect") { Task { await connect(entry) } }.controlSize(.small)
                        }
                    }
                    Button("Test") { Task { await probe(entry) } }
                        .controlSize(.small)
                        .disabled(statusByServer[entry.name] == .probing)
                    if viewModel.mcpServerIsEditable(entry) {
                        Button("Edit") { editorModel = .edit(entry) }.controlSize(.small)
                        Button(role: .destructive) { pendingDeleteName = entry.name } label: {
                            Image(systemName: "trash")
                        }.controlSize(.small)
                    }
                }
                detailRow(icon: entry.config.resolvedTransport == .stdio ? "terminal" : "globe", text: transportLabel(entry))
                detailRow(icon: "doc", text: sourceLabel(entry))
                if case let .failed(message) = statusByServer[entry.name] {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(text)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func detailStatusTag(_ entry: MCPServerEntry) -> some View {
        switch statusByServer[entry.name] {
        case .probing:
            HStack(spacing: 6) { AppSpinner().controlSize(.small); Text("Testing…").font(.caption).foregroundStyle(.secondary) }
        case let .ok(tools):
            AppLabelTag(text: "Connected · \(tools.count) tool\(tools.count == 1 ? "" : "s")", color: .green)
        case .failed:
            AppLabelTag(text: "Not reachable", color: .orange)
        case nil:
            AppLabelTag(text: "Untested", color: .secondary)
        }
    }

    private func toolsCard(_ entry: MCPServerEntry) -> some View {
        let tools = statusByServer[entry.name]?.tools ?? []
        return AppCard(title: tools.isEmpty ? "Tools" : "Tools (\(tools.count))") {
            if tools.isEmpty {
                Text(statusByServer[entry.name] == .probing
                     ? "Loading tools…"
                     : "Run Test (or Connect for OAuth servers) to load this server's tools.")
                    .font(.caption).foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name).font(.callout.monospaced().weight(.medium))
                            if let description = tool.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(AppTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        if index < tools.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
        }
    }

    private func projectAssignmentCard(_ entry: MCPServerEntry) -> some View {
        let name = entry.name
        let isGlobal = viewModel.isMcpServerEnabledForAllProjects(name)
        return AppCard(title: "Project assignment") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Enable this server for every project, or pick specific ones. A session only gets a server assigned to its project (or to a Deck agent's `mcpServers`).")
                    .font(.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
                LazyVStack(alignment: .leading, spacing: 0) {
                    AllProjectsAssignmentRow(
                        isOn: Binding(
                            get: { isGlobal },
                            set: { viewModel.setMcpServerEnabledForAllProjects(name, enabled: $0) }
                        ),
                        subtitle: "Enable this server for every project"
                    )
                    Divider()
                    ForEach(viewModel.enabledProjects) { project in
                        ProjectAssignmentToggleRow(
                            project: project,
                            isOn: Binding(
                                get: { isGlobal ? true : viewModel.mcpServer(name, isEnabledFor: project) },
                                set: { viewModel.setMcpServer(name, enabled: $0, for: project) }
                            )
                        )
                        .opacity(isGlobal ? 0.4 : 1)
                        .allowsHitTesting(!isGlobal)
                        if project.id != viewModel.enabledProjects.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func transportLabel(_ entry: MCPServerEntry) -> String {
        switch entry.config.resolvedTransport {
        case .stdio: return entry.config.command ?? "stdio"
        case .http, .sse: return entry.config.url ?? entry.config.resolvedTransport.rawValue
        }
    }

    private func sourceLabel(_ entry: MCPServerEntry) -> String {
        viewModel.mcpServerIsEditable(entry) ? "~/.pi/agent/mcp.json" : URL(fileURLWithPath: entry.sourcePath).lastPathComponent + " (read-only)"
    }

    // MARK: - Off-main loading

    private func loadServers() async {
        let root = viewModel.projectRootURL
        isLoading = true
        let loaded = await Task.detached(priority: .utility) {
            MCPConfigLoader().load(projectRoot: root).servers
        }.value
        servers = loaded
        statusByServer = statusByServer.filter { key, _ in loaded.contains { $0.name == key } }
        isLoading = false

        // Refresh OAuth connected-state for remote servers, then auto-probe each so the
        // health pill shows without a manual Test.
        for entry in loaded where entry.config.resolvedTransport != .stdio {
            connectedByServer[entry.name] = await viewModel.mcpServerIsConnected(entry.name)
        }
        for entry in loaded {
            Task { await probe(entry) }
        }
    }

    private func probe(_ entry: MCPServerEntry) async {
        statusByServer[entry.name] = .probing
        switch await viewModel.probeMCPServer(entry) {
        case let .ok(tools): statusByServer[entry.name] = .ok(tools)
        case let .failure(message): statusByServer[entry.name] = .failed(message)
        }
    }

    private func connect(_ entry: MCPServerEntry) async {
        connectingServers.insert(entry.name)
        defer { connectingServers.remove(entry.name) }
        if let error = await viewModel.connectMCPServer(entry) {
            statusByServer[entry.name] = .failed(error)
        } else {
            connectedByServer[entry.name] = true
            await probe(entry)
        }
    }

    private func signOut(_ entry: MCPServerEntry) async {
        await viewModel.disconnectMCPServer(entry.name)
        connectedByServer[entry.name] = false
        statusByServer[entry.name] = nil
    }
}

// MARK: - Editor

enum MCPServerEditorModel: Identifiable {
    case add
    case edit(MCPServerEntry)

    var id: String {
        switch self {
        case .add: return "__add__"
        case let .edit(entry): return "edit:\(entry.name)"
        }
    }

    var existingEntry: MCPServerEntry? {
        if case let .edit(entry) = self { return entry }
        return nil
    }
}

/// Add/edit form for an MCP server, writing to ~/.pi/agent/mcp.json on Save. Supports a
/// smart paste box (mcp.json / `claude mcp add` / `codex mcp add`) plus a Local/Remote
/// transport picker. Follows the app's modal sheet chrome.
private struct MCPServerEditorSheet: View {
    let model: MCPServerEditorModel
    let existingNames: Set<String>
    let onSave: (String, MCPServerConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isRemote: Bool
    @State private var command: String
    @State private var argsText: String
    @State private var envText: String
    @State private var url: String
    @State private var headersText: String
    @State private var pasteText: String = ""
    @State private var inputMode: InputMode = .manual
    @FocusState private var focusedField: Field?

    private enum Field { case name, command, args, env, url, headers, paste }
    private enum InputMode: Hashable { case manual, paste }

    /// True when the paste tab is the active input (add only).
    private var isPasting: Bool { !isEditing && inputMode == .paste }

    init(model: MCPServerEditorModel, existingNames: Set<String>, onSave: @escaping (String, MCPServerConfig) -> Void) {
        self.model = model
        self.existingNames = existingNames
        self.onSave = onSave
        let entry = model.existingEntry
        let config = entry?.config ?? MCPServerConfig()
        _name = State(initialValue: entry?.name ?? "")
        _isRemote = State(initialValue: config.resolvedTransport != .stdio && config.url != nil)
        _command = State(initialValue: config.command ?? "")
        _argsText = State(initialValue: (config.args ?? []).joined(separator: "\n"))
        _envText = State(initialValue: (config.env ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"))
        _url = State(initialValue: config.url ?? "")
        _headersText = State(initialValue: (config.headers ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
    }

    private var isEditing: Bool { model.existingEntry != nil }

    private var canSave: Bool {
        if isPasting { return !MCPConfigParser.parse(pasteText).isEmpty }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        if isRemote {
            guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        } else {
            guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        if !isEditing && existingNames.contains(trimmedName) { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? "Edit MCP server" : "Add MCP server")
                        .font(.headline)
                        .fontWidth(.expanded)
                    Text("Written to ~/.pi/agent/mcp.json")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.mutedText)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isEditing {
                        Picker("Input", selection: $inputMode) {
                            Text("Manual").tag(InputMode.manual)
                            Text("Paste").tag(InputMode.paste)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    if isPasting {
                        pasteSection
                    } else {
                        manualSection
                    }

                    Text("Assign this server to your projects or agents after saving.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .appSecondaryButton()
                Button(isEditing ? "Save" : "Add") { save() }
                    .appPrimaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.mutedText)
            content()
        }
    }

    private func editorBox(_ text: Binding<String>, field: Field, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.callout.monospaced())
            .scrollContentBackground(.hidden)
            .focused($focusedField, equals: field)
            .frame(height: 72)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(AppTheme.contentSubtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty && focusedField != field {
                    Text(placeholder)
                        .font(.callout.monospaced())
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var pasteSection: some View {
        field("Paste a server's config, or a `claude mcp add` / `codex mcp add` command") {
            editorBox($pasteText, field: .paste, placeholder: "{ \"mcpServers\": { \"Amplitude\": { \"url\": \"https://mcp.amplitude.com/mcp\" } } }")
        }
        Text("We parse the config and add the server(s). Switch to Manual to fill the fields yourself.")
            .font(.caption)
            .foregroundStyle(AppTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var manualSection: some View {
        field("Name") {
            AppTextField(text: $name, placeholder: "amplitude")
                .focused($focusedField, equals: .name)
                .disabled(isEditing)
        }
        field("Type") {
            Picker("Type", selection: $isRemote) {
                Text("Local (stdio)").tag(false)
                Text("Remote (HTTP)").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if isRemote {
            field("URL") {
                AppTextField(text: $url, placeholder: "https://mcp.amplitude.com/mcp")
                    .focused($focusedField, equals: .url)
            }
            field("Headers (KEY: VALUE per line, optional)") {
                editorBox($headersText, field: .headers, placeholder: "Authorization: Bearer …")
            }
            Text("After saving, use Connect on the server to authorize with OAuth. For token servers, add an Authorization header instead.")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            field("Command") {
                AppTextField(text: $command, placeholder: "npx")
                    .focused($focusedField, equals: .command)
            }
            field("Arguments (one per line)") {
                editorBox($argsText, field: .args, placeholder: "-y\n@modelcontextprotocol/server-everything")
            }
            field("Environment (KEY=VALUE per line)") {
                editorBox($envText, field: .env, placeholder: "GITHUB_TOKEN=…")
            }
        }
    }

    /// A name for a pasted server when the source didn't carry one.
    private func derivedName(_ parsed: MCPParsedServer) -> String {
        if let parsedName = parsed.name?.trimmingCharacters(in: .whitespacesAndNewlines), !parsedName.isEmpty {
            return parsedName
        }
        if let urlString = parsed.config.url, let host = URL(string: urlString)?.host {
            let labels = host.split(separator: ".").map(String.init)
            return labels.first { !["api", "www", "mcp", "app"].contains($0) } ?? host
        }
        if let command = parsed.config.command { return (command as NSString).lastPathComponent }
        return "mcp-server"
    }

    private func save() {
        if isPasting {
            for parsed in MCPConfigParser.parse(pasteText) {
                onSave(derivedName(parsed), parsed.config)
            }
            dismiss()
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var config = MCPServerConfig()
        if isRemote {
            config.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
            config.transport = .http
            config.headers = parsePairs(headersText, separator: ":")
        } else {
            config.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let args = argsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            config.args = args.isEmpty ? nil : args
            config.env = parsePairs(envText, separator: "=")
            config.transport = .stdio
        }
        onSave(trimmedName, config)
        dismiss()
    }

    private func parsePairs(_ text: String, separator: Character) -> [String: String]? {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: separator, maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        return result.isEmpty ? nil : result
    }
}

