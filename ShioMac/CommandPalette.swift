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
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Run a command…", text: $query)
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
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
        .onAppear { fieldFocused = true; selection = 0 }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    @ViewBuilder
    private var results: some View {
        let items = filtered
        if items.isEmpty {
            Text("No commands").foregroundStyle(.secondary).padding(.vertical, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, cmd in
                            CommandRow(cmd: cmd, selected: idx == selection)
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = idx; runSelected() }
                                .onHover { if $0 { selection = idx } }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
                .onChange(of: selection) { _, s in withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(s, anchor: .center) } }
            }
        }
    }

    // MARK: Filtering + execution

    private var filtered: [ShioCommand] {
        let all = allCommands()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false)
        }
    }

    private func move(_ delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selection = max(0, min(n - 1, selection + delta))
    }

    private func runSelected() {
        let items = filtered
        guard items.indices.contains(selection) else { return }
        let cmd = items[selection]
        close()
        cmd.run()
    }

    private func close() {
        model.showingCommandPalette = false
        query = ""
    }

    // MARK: Command registry

    private func allCommands() -> [ShioCommand] {
        var c: [ShioCommand] = []

        // Terminal
        c.append(.init(title: "New Tab", symbol: "plus.square", shortcut: "⌘T") { model.newLocalTab() })
        c.append(.init(title: "Split Right", symbol: "rectangle.split.2x1", shortcut: "⌘D") { model.splitFocused(.horizontal) })
        c.append(.init(title: "Split Down", symbol: "rectangle.split.1x2", shortcut: "⇧⌘D") { model.splitFocused(.vertical) })
        c.append(.init(title: "Close Pane or Tab", symbol: "xmark.square", shortcut: "⌘W") { model.closeSelectedTab() })
        c.append(.init(title: "Clear Terminal", symbol: "clear", shortcut: "⌃L") {
            NSApp.sendAction(#selector(GhosttyMacSurface.terminalClearScreen(_:)), to: nil, from: nil)
        })
        c.append(.init(title: "Open Terminal on This Mac", symbol: "laptopcomputer") { model.newLocalTab() })

        // Navigate
        for section in MacSection.allCases {
            c.append(.init(title: "Go to \(section.rawValue)", symbol: section.icon) { model.section = section })
        }

        // Create
        c.append(.init(title: "Add Machine…", symbol: "desktopcomputer", shortcut: "⇧⌘K") {
            model.section = .hosts; model.showingAddHost = true
        })
        c.append(.init(title: "Add Project…", symbol: "folder.badge.plus") {
            model.section = .projects; model.showingAddProject = true
        })

        // Open a project
        for project in projects {
            c.append(.init(title: "Open Project: \(project.name)",
                           subtitle: project.host?.name ?? "This Mac",
                           symbol: "folder.fill") {
                project.lastOpenedAt = .now
                try? context.save()
                model.open(project: project)
            })
        }

        // Connect a machine
        for machine in machines {
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
                .foregroundStyle(selected ? Color.white : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.title)
                    .foregroundStyle(selected ? Color.white : .primary)
                if let subtitle = cmd.subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = cmd.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor : Color.clear)
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
