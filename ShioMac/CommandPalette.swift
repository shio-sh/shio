import SwiftUI
import SwiftData

/// One actionable entry in the command palette.
struct ShioCommand: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var shortcut: String? = nil
    let run: () -> Void
}

/// Superhuman/Raycast-style command console (⌘K): fuzzy-filter every Shio
/// action and run it from the keyboard. Type to filter, ↑/↓ to move, ⏎ to run,
/// esc to dismiss. Dynamic entries (open a project, connect a machine) come
/// from SwiftData so the palette is a single home for everything.
struct CommandPalette: View {
    @Bindable var model: MacTerminalModel
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Host.name) private var machines: [Host]

    @State private var query = ""
    @State private var selection = 0
    @State private var fileSearcher = FileSpotlightSearcher()
    @FocusState private var fieldFocused: Bool

    /// A selectable row in the palette: a Shio command, or a Spotlight file hit.
    private enum Item: Identifiable {
        case command(ShioCommand)
        case file(FileHit)
        var id: UUID {
            switch self {
            case .command(let c): return c.id
            case .file(let f): return f.id
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search machines, projects, files — or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { runSelected(); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
            }
            .padding(14)
            Divider()
            results
        }
        .frame(width: 580)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        .onAppear { fieldFocused = true; selection = 0 }
        .onChange(of: query) { _, q in selection = 0; fileSearcher.search(q) }
        .onChange(of: fileSearcher.results.count) { _, _ in
            if selection >= items.count { selection = max(0, items.count - 1) }
        }
        .onDisappear { fileSearcher.stop() }
    }

    @ViewBuilder
    private var results: some View {
        let rows = items
        if rows.isEmpty {
            Text("No results").foregroundStyle(.secondary).padding(.vertical, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                            row(item, selected: idx == selection)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = idx; runSelected() }
                                .onHover { if $0 { selection = idx } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 380)
                .onChange(of: selection) { _, s in withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(s, anchor: .center) } }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: Item, selected: Bool) -> some View {
        switch item {
        case .command(let c): CommandRow(cmd: c, selected: selected)
        case .file(let f):
            CommandRow(cmd: ShioCommand(title: f.name,
                                        subtitle: f.path,
                                        symbol: f.isDirectory ? "folder" : "doc",
                                        run: {}),
                       selected: selected)
        }
    }

    // MARK: Items + execution

    /// Commands (filtered) followed by Spotlight file hits (when querying).
    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let commands = q.isEmpty
            ? allCommands()
            : allCommands().filter {
                $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false)
            }
        return commands.map(Item.command) + fileSearcher.results.map(Item.file)
    }

    private func move(_ delta: Int) {
        let n = items.count
        guard n > 0 else { return }
        selection = max(0, min(n - 1, selection + delta))
    }

    private func runSelected() {
        let rows = items
        guard rows.indices.contains(selection) else { return }
        let item = rows[selection]
        close()
        switch item {
        case .command(let c): c.run()
        case .file(let f): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)])
        }
    }

    private func close() {
        fileSearcher.stop()
        model.showingCommandPalette = false
        query = ""
    }

    // MARK: Command registry

    private func allCommands() -> [ShioCommand] {
        var c: [ShioCommand] = []

        // Terminal
        c.append(.init(title: "New Shell", symbol: "plus.square", shortcut: "⌘T") { model.newLocalTab() })
        c.append(.init(title: "Split Right", symbol: "rectangle.split.2x1", shortcut: "⌘D") { model.splitFocused(.horizontal) })
        c.append(.init(title: "Split Down", symbol: "rectangle.split.1x2", shortcut: "⇧⌘D") { model.splitFocused(.vertical) })
        c.append(.init(title: "Close Pane or Conversation", symbol: "xmark.square", shortcut: "⌘W") { model.closeSelectedTab() })
        c.append(.init(title: "Clear Terminal", symbol: "clear", shortcut: "⌃L") {
            NSApp.sendAction(#selector(GhosttyMacSurface.terminalClearScreen(_:)), to: nil, from: nil)
        })
        c.append(.init(title: "Open Terminal on This Mac", symbol: "laptopcomputer") { model.newLocalTab() })

        // Navigate
        c.append(.init(title: "Go to Dashboard", symbol: "square.grid.2x2", shortcut: "⇧⌘P") { model.canvas = .dashboard })
        c.append(.init(title: "Go to Terminal", symbol: "terminal", shortcut: "⇧⌘T") { model.showTerminal() })
        c.append(.init(title: "Go to Machines", symbol: "desktopcomputer", shortcut: "⇧⌘M") { model.canvas = .machines })
        c.append(.init(title: "Go to Files", symbol: "tray.full.fill", shortcut: "⇧⌘F") { model.canvas = .files })

        // Create
        c.append(.init(title: "Add Machine…", symbol: "desktopcomputer", shortcut: "⇧⌘K") {
            model.showingAddHost = true
        })
        c.append(.init(title: "Add Project…", symbol: "folder.badge.plus") {
            model.showingAddProject = true
        })
        c.append(.init(title: "Pair iPhone…", symbol: "qrcode") {
            model.canvas = .machines; model.showingPairing = true
        })

        // Open a project
        for project in projects {
            c.append(.init(title: "Open Project: \(project.name)",
                           subtitle: project.activeCheckout?.host?.name ?? project.host?.name ?? "This Mac",
                           symbol: "folder.fill") {
                project.lastOpenedAt = .now
                try? context.save()
                model.open(project: project)
            })
        }

        // Connect a machine. This Mac is excluded — "connecting" to it would
        // SSH into ourselves; the local shell has its own entry points.
        for machine in machines where !MacSelfHost.isThisMac(machine) {
            c.append(.init(title: "Connect: \(machine.name)",
                           subtitle: "\(machine.username)@\(machine.hostname)",
                           symbol: "desktopcomputer") {
                machine.lastConnectedAt = .now
                try? context.save()
                model.connect(to: machine)
            })
        }

        return c
    }
}

private struct CommandRow: View {
    let cmd: ShioCommand
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? ShioTheme.background : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.title)
                    .foregroundStyle(selected ? ShioTheme.background : .primary)
                if let subtitle = cmd.subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(selected ? ShioTheme.background.opacity(0.8) : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = cmd.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(selected ? ShioTheme.background.opacity(0.9) : Color.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? ShioTheme.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 6)
    }
}

/// Dimmed backdrop + top-anchored palette. Click-outside or esc dismisses.
struct CommandPaletteContainer: View {
    @Bindable var model: MacTerminalModel
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { model.showingCommandPalette = false }
            CommandPalette(model: model)
                .padding(.top, 90)
        }
    }
}
