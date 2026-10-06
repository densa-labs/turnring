#if os(macOS)
import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when a setting the running agent must react to changes (HTTP endpoint, hooks).
    static let turnringSettingsChanged = Notification.Name("turnringSettingsChanged")
}

/// Bridges Prefs into SwiftUI. Each property writes straight through to UserDefaults.
final class SettingsModel: ObservableObject {
    @Published var playSound = Prefs.playSound { didSet { Prefs.playSound = playSound } }
    @Published var doneSound = Prefs.doneSound { didSet { Prefs.doneSound = doneSound } }
    @Published var waitingSound = Prefs.waitingSound { didSet { Prefs.waitingSound = waitingSound } }
    @Published var launchAtLogin = LoginItem.isEnabled { didSet { if launchAtLogin != LoginItem.isEnabled { LoginItem.isEnabled = launchAtLogin } } }
    @Published var quietWhenActive = Prefs.quietWhenActive { didSet { Prefs.quietWhenActive = quietWhenActive } }
    @Published var focusTab = Prefs.focusTab { didSet { Prefs.focusTab = focusTab } }
    @Published var checkForUpdates = Prefs.checkForUpdates { didSet { Prefs.checkForUpdates = checkForUpdates } }

    @Published var ntfyEnabled = Prefs.ntfyEnabled { didSet { Prefs.ntfyEnabled = ntfyEnabled } }
    @Published var ntfyServer = Prefs.ntfyServer { didSet { Prefs.ntfyServer = ntfyServer } }
    @Published var ntfyTopics = Prefs.ntfyTopics { didSet { Prefs.ntfyTopics = ntfyTopics } }
    @Published var ntfyUrgentWaiting = Prefs.ntfyUrgentWaiting { didSet { Prefs.ntfyUrgentWaiting = ntfyUrgentWaiting } }
    @Published var ntfyClickRepo = Prefs.ntfyClickRepo { didSet { Prefs.ntfyClickRepo = ntfyClickRepo } }
    @Published var ntfyAttachReply = Prefs.ntfyAttachReply { didSet { Prefs.ntfyAttachReply = ntfyAttachReply } }

    @Published var rules = Prefs.rules { didSet { Prefs.rules = rules } }

    @Published var httpEnabled = Prefs.httpEnabled { didSet { Prefs.httpEnabled = httpEnabled; changed() } }
    @Published var httpPort = Prefs.httpPort { didSet { Prefs.httpPort = httpPort; changed() } }

    @Published var newTopic = ""
    @Published var hookStatus: [Hooks.Agent: Hooks.Status] = [:]
    @Published var hookError: String?
    let hooks = Hooks()

    init() { refreshHooks() }

    func refreshHooks() {
        hookStatus = Dictionary(uniqueKeysWithValues: Hooks.Agent.allCases.map { ($0, hooks.status($0)) })
    }

    func setHooks(_ agent: Hooks.Agent, on: Bool) {
        do {
            if on {
                try hooks.install(agent)
                Prefs.hooksOptOut.remove(agent.rawValue)
            } else {
                try hooks.remove(agent)
                Prefs.hooksOptOut.insert(agent.rawValue)
            }
            hookError = nil
        } catch {
            hookError = "\(error)"
        }
        refreshHooks()
    }

    private func changed() { NotificationCenter.default.post(name: .turnringSettingsChanged, object: nil) }
}

/// One pane of the Preferences window. Each is a toolbar tab, like a native settings window.
enum PreferencesPane: String, CaseIterable {
    case general = "General", agents = "Agents", phone = "Phone", rules = "Rules", advanced = "Advanced"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .phone: "iphone"
        case .rules: "line.3.horizontal.decrease.circle"
        case .advanced: "network"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: 330
        case .agents: 340
        case .phone: 430
        case .rules: 360
        case .advanced: 240
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let pane: PreferencesPane

    var body: some View {
        Group {
            switch pane {
            case .general: general
            case .agents: agents
            case .phone: phone
            case .rules: rules
            case .advanced: advanced
            }
        }
        .frame(width: 560, height: pane.height)
    }

    private var general: some View {
        Form {
            Toggle("Play sound", isOn: $model.playSound)
            soundPicker("Sound when done", selection: $model.doneSound)
            soundPicker("Sound when waiting", selection: $model.waitingSound)
            Toggle("Launch at login", isOn: $model.launchAtLogin)
                .disabled(LoginItem.managedByBrew)
                .help(LoginItem.managedByBrew ? "Managed by Homebrew. Run `brew services stop turnring` to turn it off." : "")
            Toggle("Stay quiet while I'm looking at the agent", isOn: $model.quietWhenActive)
                .help("Skips the banner and phone push when the agent's app (and, for Terminal and iTerm2, its tab) is in front.")
            Toggle("Bring back the exact Terminal or iTerm2 tab", isOn: $model.focusTab)
                .help("macOS asks once for permission to control Terminal or iTerm2.")
            Toggle("Check for updates daily", isOn: $model.checkForUpdates)
        }
        .formStyle(.grouped)
    }

    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                ForEach(Sounds.available, id: \.self) { Text($0).tag($0) }
            }
            Button("Play") { Sounds.preview(selection.wrappedValue) }
                .accessibilityLabel("Play \(title.lowercased())")
        }
        .disabled(!model.playSound)
    }

    private var agents: some View {
        Form {
            Section {
                ForEach(Hooks.Agent.allCases, id: \.self) { agent in
                    let status = model.hookStatus[agent] ?? .notInstalled
                    Toggle(isOn: Binding(get: { status == .on || status == .untrusted },
                                         set: { model.setHooks(agent, on: $0) })) {
                        VStack(alignment: .leading) {
                            Text(agent.name)
                            Text(caption(status)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(status == .notInstalled)
                }
            } footer: {
                Text("Turnring adds its hooks to agents it finds, including ones you install later. Turning one off here keeps it off.")
            }
            if let error = model.hookError { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshHooks() }
    }

    private func caption(_ status: Hooks.Status) -> String {
        switch status {
        case .notInstalled: "Not installed"
        case .off: "Off"
        case .on: "On"
        case .untrusted: "Waiting for you to trust the hook in Codex. Start Codex and choose Trust."
        }
    }

    private var phone: some View {
        Form {
            Section {
                if model.ntfyTopics.isEmpty {
                    HStack {
                        Text("Get banners on your phone through the free ntfy app.")
                        Spacer()
                        Button("Set Up with ntfy") {
                            let topic = Ntfy.enable()
                            model.ntfyTopics = Prefs.ntfyTopics
                            model.ntfyEnabled = true
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(topic, forType: .string)
                        }
                        .help("Creates a private topic and copies it. In the ntfy app, tap + and paste it.")
                    }
                } else {
                    Toggle("Send to my phone with ntfy", isOn: $model.ntfyEnabled)
                }
                TextField("Server", text: $model.ntfyServer)
            }
            Section("Topics") {
                ForEach(model.ntfyTopics, id: \.self) { topic in
                    HStack {
                        Text(topic).textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(topic, forType: .string)
                        }
                        Button(role: .destructive) { model.ntfyTopics.removeAll { $0 == topic } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel("Remove \(topic)")
                    }
                }
                HStack {
                    TextField("Add a topic", text: $model.newTopic)
                    Button("Random") { model.newTopic = Ntfy.randomTopic() }
                    Button("Add") {
                        let topic = model.newTopic.trimmingCharacters(in: .whitespaces)
                        if !topic.isEmpty, !model.ntfyTopics.contains(topic) { model.ntfyTopics.append(topic) }
                        model.newTopic = ""
                    }
                }
            }
            Section {
                Toggle("Send \"Waiting\" at high priority", isOn: $model.ntfyUrgentWaiting)
                Toggle("Tapping a push opens the project's repository", isOn: $model.ntfyClickRepo)
                Toggle("Attach long replies as a text file", isOn: $model.ntfyAttachReply)
                Link("Get the ntfy app", destination: URL(string: "https://ntfy.sh/#subscribe-phone")!)
            }
        }
        .formStyle(.grouped)
    }

    private var rules: some View {
        VStack(alignment: .leading) {
            Text("The first rule that matches decides where a message goes. Messages that match no rule go everywhere.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach($model.rules) { $rule in
                    HStack {
                        Picker("Agent", selection: $rule.agent) {
                            Text("Any agent").tag(String?.none)
                            ForEach(Hooks.Agent.allCases, id: \.self) { Text($0.name).tag(Optional($0.rawValue)) }
                        }
                        .labelsHidden()
                        TextField("Project contains", text: $rule.project)
                        Picker("Event", selection: $rule.event) {
                            Text("Done or waiting").tag(String?.none)
                            Text("Done").tag(Optional("done"))
                            Text("Waiting").tag(Optional("waiting"))
                        }
                        .labelsHidden()
                        Picker("Route", selection: $rule.route) {
                            ForEach(Rule.Route.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        Button(role: .destructive) { model.rules.removeAll { $0.id == rule.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete rule")
                    }
                }
            }
            Button("Add Rule") { model.rules.append(Rule()) }
        }
        .padding()
    }

    private var advanced: some View {
        Form {
            Section {
                Toggle("Local HTTP endpoint", isOn: $model.httpEnabled)
                TextField("Port", value: $model.httpPort, format: .number.grouping(.never))
            } footer: {
                Text("Listens on 127.0.0.1 only. For tools that can't run a command.")
            }
            if model.httpEnabled {
                Section("Example") {
                    Text("curl -X POST http://127.0.0.1:\(String(model.httpPort))/notify -H 'Authorization: Bearer \(Prefs.httpToken)' -d '{\"title\":\"Build done\"}'")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Search text for the History window. (No @State: it's a macro the Command Line Tools can't expand.)
final class HistoryModel: ObservableObject {
    let history: History
    @Published var query = ""
    @Published var tick = 0
    init(history: History) { self.history = history }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    private var history: History { model.history }

    var body: some View {
        let results = { _ = model.tick; return history.search(model.query) }()
        VStack(spacing: 0) {
            TextField("Search titles, replies and folders", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(Array(results.enumerated()), id: \.offset) { _, entry in
                Button {
                    Focus.bringBack(app: entry.msg.app, cwd: entry.msg.cwd, tty: entry.msg.tty)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.msg.fullTitle).bold()
                            Spacer()
                            Text(entry.date, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                        if !entry.msg.message.isEmpty {
                            Text(entry.msg.message).lineLimit(2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bring back \(entry.msg.project ?? "this agent")")
                .contextMenu {
                    Button("Copy Reply") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.msg.fullText, forType: .string)
                    }
                }
            }
            .overlay { if results.isEmpty { Text(model.query.isEmpty ? "Nothing yet" : "No matches").foregroundStyle(.secondary) } }
            HStack {
                Text("\(results.count) of \(history.entries.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear History") { history.clear(); model.tick += 1 }
            }
            .padding(8)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

/// The Preferences window: toolbar tabs across the top, one pane each, resizing to fit.
final class PreferencesController: NSTabViewController {
    private let model = SettingsModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        for pane in PreferencesPane.allCases {
            let host = NSHostingController(rootView: SettingsView(model: model, pane: pane))
            host.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: host)
            item.label = pane.rawValue
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.rawValue)
            item.identifier = pane.rawValue
            addTabViewItem(item)
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        view.window?.title = item?.label ?? "Turnring Preferences"
        if item?.identifier as? String == PreferencesPane.agents.rawValue { model.refreshHooks() }
    }

    func select(_ pane: PreferencesPane) {
        if let index = PreferencesPane.allCases.firstIndex(of: pane) { selectedTabViewItemIndex = index }
    }
}

/// Opens a SwiftUI view in a regular window and brings Turnring forward for it.
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]
    private var preferences: PreferencesController?

    func showPreferences(_ pane: PreferencesPane = .general) {
        if preferences == nil {
            let controller = PreferencesController()
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            preferences = controller
        }
        preferences!.select(pane)
        preferences!.view.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func show<V: View>(_ id: String, title: String, view: @autoclosure () -> V) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view()))
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
