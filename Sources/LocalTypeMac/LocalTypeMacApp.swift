import LocalTypeCore
import SwiftUI

@main
struct LocalTypeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        WindowGroup("QuietType") {
            TesterView(model: model)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit QuietType") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class DictationOverlayController {
    private var panel: NSPanel?

    func show(state: OverlayState, level: Double = 0) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: DictationOverlayView(state: state, level: level))
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide(after delay: TimeInterval = 0) {
        guard let panel else {
            return
        }

        if delay <= 0 {
            panel.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak panel] in
                panel?.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.minY + 110
        )
        panel.setFrameOrigin(origin)
    }
}

struct OverlayState {
    var title: String
    var subtitle: String
    var icon: String
    var tint: Color

    static let listening = OverlayState(
        title: "Listening",
        subtitle: "Speak freely",
        icon: "mic.fill",
        tint: .primary
    )

    static let processing = OverlayState(
        title: "Processing",
        subtitle: "Transcribing locally",
        icon: "waveform",
        tint: .secondary
    )

    static let inserted = OverlayState(
        title: "Inserted",
        subtitle: "Nothing left your Mac",
        icon: "checkmark.circle.fill",
        tint: .primary
    )
}

private struct DictationOverlayView: View {
    var state: OverlayState
    var level: Double

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 46, height: 46)
                Image(systemName: state.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(state.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: level)
                    .progressViewStyle(.linear)
                    .frame(width: 170)
                    .opacity(state.title == OverlayState.listening.title ? 1 : 0.25)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}

struct TesterView: View {
    @ObservedObject var model: MenuBarModel
    @State private var selectedSection: QuietTypeSection = .home
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1220, minHeight: 780)
        .animation(.easeInOut(duration: 0.22), value: selectedSection)
        .onAppear {
            model.startAppServices()
        }
        .onReceive(permissionTimer) { _ in
            Task {
                await model.refreshPermissions()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "moonphase.waxing.crescent")
                    .font(.title2)
                Text("QuietType")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }
            .padding(.top, 26)

            VStack(spacing: 8) {
                ForEach(QuietTypeSection.primary) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        SidebarItem(icon: section.icon, title: section.title, selected: selectedSection == section)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Label("Local only", systemImage: "lock.fill")
                    .font(.callout.weight(.semibold))
                Text("Audio, text, vocabulary, and corrections stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                selectedSection = .settings
            } label: {
                SidebarItem(icon: QuietTypeSection.settings.icon, title: QuietTypeSection.settings.title, selected: selectedSection == .settings)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
        .frame(width: 238)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            switch selectedSection {
            case .home:
                homePage
            case .history:
                historyPage
            case .dictionary:
                dictionaryPage
            case .settings:
                settingsPage
            }
        }
        .id(selectedSection)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var homePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                metricsGrid
                HStack(alignment: .top, spacing: 22) {
                    dictationPanel
                        .frame(minWidth: 390, maxWidth: 480)
                    securityPanel
                }
                outputPanel
                if !model.permissionsReady {
                    permissionsPanel
                }
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
    }

    private var historyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "History",
                    subtitle: "Recent local dictations and insertion results."
                )

                historySummary
                EmptyStatePanel(
                    icon: "clock.arrow.circlepath",
                    title: "No saved dictations yet",
                    subtitle: "QuietType will show recent local sessions here once history review is enabled."
                )
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
    }

    private var dictionaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Dictionary",
                    subtitle: "Private vocabulary and SAGE memories used by QuietType."
                )

                sageMemoryPanel

                VStack(alignment: .leading, spacing: 12) {
                    Text("Local vocabulary")
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        DictionaryTerm(term: "SAGE", detail: "Memory system")
                        DictionaryTerm(term: "CometBFT", detail: "Consensus")
                        DictionaryTerm(term: "Ollama", detail: "Local models")
                        DictionaryTerm(term: "Ed25519", detail: "Crypto")
                        DictionaryTerm(term: "WhisperKit", detail: "Apple Silicon ASR")
                        DictionaryTerm(term: "QuietType", detail: "App name")
                    }
                }
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            Task {
                if model.sageMemories.isEmpty {
                    await model.refreshSageMemories()
                }
            }
        }
    }

    private var sageMemoryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SAGE memory")
                        .font(.title3.weight(.semibold))
                    Text(model.sageAgentID.isEmpty ? model.sageAgentStatus : "\(model.sageAgentStatus) · \(model.sageAgentID.prefix(12))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isQueryingSage {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    Task {
                        await model.refreshSageMemories()
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Search SAGE memories", text: $model.sageQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task {
                            await model.searchSageMemories()
                        }
                    }
                Button("Search") {
                    Task {
                        await model.searchSageMemories()
                    }
                }
                .disabled(model.isQueryingSage)
            }

            if model.sageMemories.isEmpty {
                EmptyStatePanel(
                    icon: "brain.head.profile",
                    title: model.sageDetected ? "No QuietType memories yet" : "SAGE is not connected",
                    subtitle: model.sageDetected ? "Approved vocabulary, corrections, and style memories will appear here under quiettype-agent." : "QuietType will keep using its local dictionary until SAGE is available."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(model.sageMemories) { memory in
                        SageMemoryRow(memory: memory)
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Settings",
                    subtitle: "Transcription quality, privacy memory, and local diagnostics."
                )
                settingsPanel
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var historySummary: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            MetricTile(icon: "text.bubble", value: model.output.isEmpty ? "0" : "1", label: "Sessions today")
            MetricTile(icon: "timer", value: model.lastLatencyMS.map { "\($0) ms" } ?? "Warm", label: "Last insert")
            MetricTile(icon: "network.slash", value: "0", label: "Cloud calls")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speak freely. Transcribe locally.")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("Nothing leaves your Mac.")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Text(model.hotKeyLabel)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    Text("start / stop")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                StatusPill(icon: model.speechEngineReady ? "waveform" : "waveform.slash", text: model.speechEngineStatus, tint: .secondary)
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            MetricTile(icon: "person.text.rectangle", value: model.sageDetected ? "12%" : "Local", label: "Personalization")
            MetricTile(icon: "timer", value: model.recordingDuration > 0 ? String(format: "%.1fs", model.recordingDuration) : "Ready", label: "Current dictation")
            MetricTile(icon: "bolt.fill", value: model.lastLatencyMS.map { "\($0) ms" } ?? "Warm", label: "Release latency")
            MetricTile(icon: "lock.shield", value: "0", label: "Network calls")
        }
    }

    private var privacyStrip: some View {
        HStack(spacing: 10) {
            StatusPill(icon: "lock.fill", text: "Offline", tint: .secondary)
            StatusPill(icon: "desktopcomputer", text: "On-device", tint: .secondary)
            StatusPill(icon: model.speechEngineReady ? "waveform" : "waveform.slash", text: model.speechEngineStatus, tint: .secondary)
            Spacer()
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection(title: "Transcription") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Writing style", selection: $model.selectedProfile) {
                        ForEach(MenuBarModel.ProfileChoice.allCases) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Insert into active app", isOn: Binding(
                        get: { !model.previewOnly },
                        set: { model.previewOnly = !$0 }
                    ))
                    .toggleStyle(.checkbox)

                    HStack {
                        Text("Shortcut")
                        Spacer()
                        Text(model.hotKeyLabel)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            settingsSection(title: "Privacy memory") {
                HStack {
                    Label(model.sageStatus, systemImage: model.sageDetected ? "brain.head.profile" : "internaldrive")
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Refresh") {
                        Task {
                            await model.registerSageAgentIfAvailable()
                        }
                    }
                }
                if !model.sageAgentID.isEmpty {
                    Text("quiettype-agent identity is preserved in Keychain and mirrored locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            permissionsPanel
            startupPanel
            advancedPanel
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var startupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Startup")
                    .font(.headline)
                Spacer()
                if model.isBooting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(model.startupSummary, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(model.startupSteps) { step in
                    StartupStepRow(step: step)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Setup")
                    .font(.headline)
                Spacer()
                if model.permissionsReady {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                PermissionRow(
                    title: "Microphone",
                    state: model.microphonePermission,
                    actionTitle: model.microphonePermission == .notDetermined ? "Allow" : "Open settings"
                ) {
                    Task {
                        await model.requestMicrophone()
                    }
                }

                PermissionRow(
                    title: "Accessibility",
                    state: model.accessibilityPermission,
                    actionTitle: "Allow"
                ) {
                    model.requestAccessibility()
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var dictationPanel: some View {
        VStack(spacing: 18) {
            Button {
                Task {
                    await model.toggleDictation()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(model.isRecording ? Color.black : Color(nsColor: .windowBackgroundColor))
                        .frame(width: 156, height: 156)
                    Circle()
                        .stroke(model.isRecording ? Color.red.opacity(0.34) : Color.black.opacity(0.10), lineWidth: 13)
                        .frame(width: 190, height: 190)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(model.isRecording ? .white : .secondary)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning && !model.isRecording)
            .help(model.isRecording ? "Stop and insert" : "Start dictation")

            Text(model.primaryPrompt)
                .font(.system(size: 25, weight: .semibold, design: .rounded))

            ProgressView(value: model.inputLevel)
                .progressViewStyle(.linear)
                .tint(.secondary)
                .frame(width: 285)
                .opacity(model.isRecording ? 1 : 0.35)

            Text(model.helperText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Local activity")
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusPill(icon: "lock.fill", text: "Private", tint: .secondary)
            }

            VStack(spacing: 10) {
                ActivityRow(icon: "brain.head.profile", title: "SAGE memory", value: model.sageDetected ? "Detected" : "Local store")
                ActivityRow(icon: "waveform", title: "Secure transcription", value: model.nativeSpeechServerReady ? "Warm" : model.speechEngineStatus)
                ActivityRow(icon: "square.stack.3d.up", title: "Audio chunks", value: "\(model.partialChunkCount)")
                ActivityRow(icon: "cpu", title: "Apple Silicon path", value: model.nativeSpeechServerReady ? "Active" : "Warming")
                ActivityRow(icon: "network.slash", title: "Cloud processing", value: "None")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Polished text")
                    .font(.title3.weight(.semibold))
                Spacer()
                if model.didInsert {
                    Label("Inserted", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if !model.output.isEmpty {
                    Label("Ready", systemImage: "doc.text")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(model.output.isEmpty ? "Your polished text will appear here." : model.output)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Button {
                    model.copyOutput()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(model.output.isEmpty)

                Spacer()
                statusLine
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusLine: some View {
        HStack {
            if let latency = model.lastLatencyMS {
                Text("\(latency) ms")
            }
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
            }
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var advancedPanel: some View {
        DisclosureGroup("Advanced testing") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Editor", selection: $model.editorMode) {
                    ForEach(MenuBarModel.EditorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.editorMode == .ollama {
                    TextField("Ollama model", text: $model.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prototype speech text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Speech text", text: $model.transcript, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(4...7)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Teach spelling")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("When I say...", text: $model.teachRaw)
                            .textFieldStyle(.roundedBorder)
                        TextField("write...", text: $model.teachCorrected)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            Task {
                                await model.saveCorrection()
                            }
                        }
                        .disabled(!model.canSaveCorrection)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private enum QuietTypeSection: String, CaseIterable, Identifiable {
    case home
    case history
    case dictionary
    case settings

    var id: String { rawValue }

    static let primary: [QuietTypeSection] = [.home, .history, .dictionary]

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "book.closed"
        case .settings: "gearshape"
        }
    }
}

private struct SidebarItem: View {
    var icon: String
    var title: String
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 17, weight: selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .foregroundStyle(selected ? .primary : .secondary)
        .background(selected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptyStatePanel: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DictionaryTerm: View {
    var term: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(term)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SageMemoryRow: View {
    var memory: SageMemoryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(memory.type.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(memory.domain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let confidence = memory.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(memory.content.isEmpty ? "Memory content unavailable." : memory.content)
                .font(.callout)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(memory.id.prefix(12))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricTile: View {
    var icon: String
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(20)
        .frame(minHeight: 140, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ActivityRow: View {
    var icon: String
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct PermissionRow: View {
    var title: String
    var state: PermissionState
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.primary)
            Spacer()
            if state != .granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var icon: String {
        state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle"
    }

    private var tint: Color { .secondary }
}

private struct StartupStepRow: View {
    var step: StartupStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.callout.weight(.semibold))
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var icon: String {
        switch step.state {
        case .pending: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch step.state {
        case .pending: .secondary
        case .running: .secondary
        case .ready: .primary
        case .warning: .secondary
        case .failed: .red
        }
    }
}

struct StartupStep: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var state: StartupStepState

    static let defaults = [
        StartupStep(id: "sage", title: "SAGE memory", detail: "Checking governed local memory.", state: .pending),
        StartupStep(id: "permissions", title: "macOS permissions", detail: "Checking microphone and Accessibility.", state: .pending),
        StartupStep(id: "nativeSpeech", title: "Secure transcription engine", detail: "Waiting to start the Apple Silicon engine.", state: .pending),
        StartupStep(id: "fallbackSpeech", title: "Local fallback", detail: "Checking local whisper.cpp fallback.", state: .pending)
    ]
}

enum StartupStepState: Equatable {
    case pending
    case running
    case ready
    case warning
    case failed
}

private struct StatusPill: View {
    var icon: String
    var text: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var transcript = "the sage benchmark needs to rerun the comet b f t latency numbers"
    @Published var output = ""
    @Published var sageStatus = "SAGE unchecked"
    @Published var sageDetected = false
    @Published var sageAgentID = ""
    @Published var sageAgentStatus = "Not registered"
    @Published var sageMemories: [SageMemoryRecord] = []
    @Published var sageQuery = ""
    @Published var isQueryingSage = false
    @Published var speechEngineStatus = "Checking speech"
    @Published var speechEngineReady = false
    @Published var nativeSpeechServerReady = false
    @Published var fallbackSpeechReady = false
    @Published var startupSteps = StartupStep.defaults
    @Published var isBooting = false
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var recordingDuration = 0.0
    @Published var inputLevel = 0.0
    @Published var capturedFrameCount = 0
    @Published var lastRecordingURL: URL?
    @Published var partialChunkCount = 0
    @Published var lastLatencyMS: Int?
    @Published var lastError: String?
    @Published var previewOnly = false
    @Published var didInsert = false
    @Published var selectedProfile = ProfileChoice.messaging
    @Published var editorMode = EditorMode.ruleBased
    @Published var ollamaModel = "qwen3:4b"
    @Published var teachRaw = "all llama"
    @Published var teachCorrected = "Ollama"
    @Published var statusMessage = ""
    @Published var hotKeyLabel = "⌃⇧D"
    @Published var microphonePermission: PermissionState = .unknown
    @Published var accessibilityPermission: PermissionState = .unknown

    private let permissionService = MacOSPermissionService()
    private let memoryStore = SQLiteMemoryStore()
    private var sageDirectClient: SageDirectClient?
    private var whisperKitSupervisor: WhisperKitServerSupervisor?
    private var didStartAppServices = false
    private var nativeSpeechStartupTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var captureService: AVAudioCaptureService?
    private var recordingStartedAt: Date?
    private var recordedSamples: [Float] = []
    private var recordingSampleRate = 16_000
    private var chunker = StreamingWavChunker()
    private let chunkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("quiettype-stream")
    private var streamingTranscriptionSession: StreamingAudioTranscriptionSession?
    private var hotKeyController: CarbonHotKeyController?
    private var lastHotKeyToggleAt: Date?
    private let overlayController = DictationOverlayController()

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.shutdownAppServices()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    var statusIcon: String {
        isRunning ? "waveform" : "mic"
    }

    var primaryPrompt: String {
        if !permissionsReady {
            return "Click the mic to finish setup"
        }
        if isRecording {
            return "Listening... \(String(format: "%.1f", recordingDuration))s"
        }
        return "Press \(hotKeyLabel) or click the mic"
    }

    var primaryButtonTitle: String {
        if isRecording {
            return "Stop"
        }
        if microphonePermission != .granted {
            return "Allow Microphone"
        }
        if accessibilityPermission != .granted {
            return "Allow Accessibility"
        }
        return "Click Mic"
    }

    var helperText: String {
        if !permissionsReady {
            return "QuietType will ask macOS for the permissions it needs."
        }
        if isRecording {
            return "Speak naturally, then press \(hotKeyLabel) or click the mic again to insert."
        }
        if nativeSpeechServerReady {
            return "Ready for private Apple Silicon dictation. Text inserts automatically."
        }
        if fallbackSpeechReady {
            return "Native speech is warming. Local fallback is available."
        }
        return "Secure transcription is starting in the background."
    }

    var startupSummary: String {
        if nativeSpeechServerReady {
            return "Native speech ready"
        }
        if fallbackSpeechReady {
            return "Fallback ready"
        }
        return "Startup running"
    }

    var permissionsReady: Bool {
        microphonePermission == .granted && accessibilityPermission == .granted
    }

    var canSaveCorrection: Bool {
        !teachRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshSageStatus() {
        let installation = SageDetector().detect()
        sageDetected = installation.isInstalled
        sageStatus = installation.isInstalled ? "SAGE detected · registration pending" : "Local memory"
        updateStartupStep(
            id: "sage",
            detail: installation.isInstalled ? "SAGE app detected. SDK registration is pending." : "SAGE not found. Using encrypted local memory.",
            state: installation.isInstalled ? .ready : .warning
        )
    }

    func refreshSpeechEngineStatus() {
        fallbackSpeechReady = LocalASRDiscovery().commandBackend() != nil

        if nativeSpeechServerReady {
            speechEngineReady = true
            speechEngineStatus = "Native speech ready"
        } else if fallbackSpeechReady {
            speechEngineReady = true
            speechEngineStatus = "Fallback speech"
        } else if WhisperKitServerBundleLocator.bundledExecutable() != nil {
            speechEngineReady = false
            speechEngineStatus = "Native speech starting"
        } else {
            speechEngineReady = false
            speechEngineStatus = "Speech setup"
        }

        updateStartupStep(
            id: "fallbackSpeech",
            detail: fallbackSpeechReady ? "whisper.cpp fallback is installed for local transcription." : "No whisper.cpp fallback found.",
            state: fallbackSpeechReady ? .ready : .warning
        )
    }

    func refreshPermissions(promptForAccessibility: Bool = false) async {
        let snapshot = await permissionService.snapshot(promptForAccessibility: promptForAccessibility)
        microphonePermission = snapshot.microphone
        accessibilityPermission = snapshot.accessibility
        updatePermissionsStartupStep()
    }

    func requestMicrophone() async {
        microphonePermission = await permissionService.requestMicrophone()
        await refreshPermissions(promptForAccessibility: false)
    }

    func requestAccessibility() {
        accessibilityPermission = permissionService.requestAccessibility()
        Task {
            await refreshPermissions(promptForAccessibility: true)
        }
    }

    func startAppServices() {
        guard !didStartAppServices else {
            return
        }
        didStartAppServices = true
        isBooting = true

        Task {
            refreshSageStatus()
            await registerSageAgentIfAvailable()
            await refreshPermissions(promptForAccessibility: false)
            refreshSpeechEngineStatus()
            registerGlobalHotKey()
            startNativeSpeechWarmup()
        }
    }

    func shutdownAppServices() {
        hotKeyController?.unregister()
        hotKeyController = nil
        overlayController.hide()
        nativeSpeechStartupTask?.cancel()
        nativeSpeechStartupTask = nil
        whisperKitSupervisor?.stop()
        whisperKitSupervisor = nil
        nativeSpeechServerReady = false
    }

    private func registerGlobalHotKey() {
        guard hotKeyController == nil else {
            return
        }

        let preferred = CarbonHotKeyController(descriptor: .controlShiftD) { [weak self] phase in
            guard phase == .pressed else {
                return
            }
            Task { @MainActor [weak self] in
                await self?.toggleFromHotKey()
            }
        }

        do {
            try preferred.register()
            hotKeyController = preferred
            hotKeyLabel = "⌃⇧D"
            statusMessage = "Shortcut ready"
        } catch {
            lastError = "Could not register shortcut: \(error)"
        }
    }

    private func toggleFromHotKey() async {
        if let lastHotKeyToggleAt, Date().timeIntervalSince(lastHotKeyToggleAt) < 0.45 {
            return
        }
        lastHotKeyToggleAt = Date()
        await toggleDictation()
    }

    func registerSageAgentIfAvailable() async {
        let installation = SageDetector().detect()
        guard installation.isInstalled else {
            sageAgentStatus = "Local store"
            return
        }

        do {
            let identity = try SageSigningIdentity.loadOrCreate()
            let client = try SageDirectClient(endpoint: installation.localEndpoint, identity: identity)
            sageDirectClient = client
            sageAgentID = identity.agentID

            let registration = try await client.registerQuietTypeAgent()
            sageAgentStatus = registration.status == "already_registered" ? "Registered" : "Registered"
            sageStatus = "SAGE connected · quiettype-agent"
            updateStartupStep(
                id: "sage",
                detail: "quiettype-agent registered with local SAGE.",
                state: .ready
            )
            await refreshSageMemories()
        } catch {
            sageAgentStatus = "Registration needed"
            sageStatus = "SAGE detected · registration failed"
            updateStartupStep(
                id: "sage",
                detail: "SAGE detected, but agent registration failed: \(error.localizedDescription)",
                state: .warning
            )
        }
    }

    func refreshSageMemories() async {
        guard let sageDirectClient else {
            return
        }
        isQueryingSage = true
        defer {
            isQueryingSage = false
        }

        do {
            sageMemories = try await sageDirectClient.listMemories(limit: 12)
        } catch {
            lastError = "SAGE memory list failed: \(error.localizedDescription)"
        }
    }

    func searchSageMemories() async {
        guard let sageDirectClient else {
            await registerSageAgentIfAvailable()
            return
        }

        let query = sageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            await refreshSageMemories()
            return
        }

        isQueryingSage = true
        defer {
            isQueryingSage = false
        }

        do {
            sageMemories = try await sageDirectClient.searchMemories(query: query, limit: 12)
        } catch {
            lastError = "SAGE search failed: \(error.localizedDescription)"
        }
    }

    private func startNativeSpeechWarmup() {
        guard nativeSpeechStartupTask == nil else {
            return
        }

        nativeSpeechStartupTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.warmNativeSpeechServerOnLaunch()
        }
    }

    private func warmNativeSpeechServerOnLaunch() async {
        guard let executableURL = WhisperKitServerBundleLocator.bundledExecutable(),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            nativeSpeechServerReady = false
            updateStartupStep(
                id: "nativeSpeech",
                detail: "Native engine is not bundled in this build.",
                state: .warning
            )
            refreshSpeechEngineStatus()
            isBooting = false
            return
        }

        if whisperKitSupervisor == nil {
            whisperKitSupervisor = WhisperKitServerSupervisor(executableURL: executableURL)
        }

        updateStartupStep(
            id: "nativeSpeech",
            detail: "Warming the Apple Silicon speech engine in the background.",
            state: .running
        )
        speechEngineStatus = fallbackSpeechReady ? "Fallback ready, native warming" : "Native speech starting"

        do {
            if await whisperKitSupervisor?.isServerHealthy() == true {
                nativeSpeechServerReady = true
                isBooting = false
                updateStartupStep(
                    id: "nativeSpeech",
                    detail: "Apple Silicon transcription server is already warm.",
                    state: .ready
                )
                statusMessage = "Native speech ready"
                refreshSpeechEngineStatus()
                return
            }

            try whisperKitSupervisor?.startWarming()
            isBooting = false

            let startedAt = Date()
            while !Task.isCancelled {
                if await whisperKitSupervisor?.isServerHealthy() == true {
                    nativeSpeechServerReady = true
                    updateStartupStep(
                        id: "nativeSpeech",
                        detail: "Apple Silicon transcription server is warm.",
                        state: .ready
                    )
                    statusMessage = "Native speech ready"
                    refreshSpeechEngineStatus()
                    return
                }

                if whisperKitSupervisor?.isProcessRunning != true {
                    throw WhisperKitServerSupervisorError.startupTimedOut("Native speech process exited during warmup.")
                }

                let elapsed = Int(Date().timeIntervalSince(startedAt))
                let detail = fallbackSpeechReady
                    ? "Native engine is warming in the background. Bundled local fallback is ready."
                    : "Native engine is warming in the background. First launch can take a few minutes."
                updateStartupStep(
                    id: "nativeSpeech",
                    detail: elapsed > 0 ? "\(detail) \(elapsed)s elapsed." : detail,
                    state: .running
                )
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            nativeSpeechServerReady = false
            let detail = String(describing: error)
            updateStartupStep(
                id: "nativeSpeech",
                detail: fallbackSpeechReady ? "Native engine is not ready yet. QuietType will use the local fallback." : detail,
                state: fallbackSpeechReady ? .warning : .failed
            )
            if !fallbackSpeechReady {
                lastError = detail
            }
        }

        refreshSpeechEngineStatus()
        isBooting = false
    }

    func apply(_ sample: Sample) {
        transcript = sample.transcript
        selectedProfile = sample.profile
        output = ""
        lastLatencyMS = nil
        lastError = nil
        didInsert = false
        statusMessage = ""
    }

    private func updateStartupStep(id: String, detail: String, state: StartupStepState) {
        guard let index = startupSteps.firstIndex(where: { $0.id == id }) else {
            return
        }
        startupSteps[index].detail = detail
        startupSteps[index].state = state
    }

    private func updatePermissionsStartupStep() {
        let microphoneReady = microphonePermission == .granted
        let accessibilityReady = accessibilityPermission == .granted
        let detail: String
        let state: StartupStepState

        switch (microphoneReady, accessibilityReady) {
        case (true, true):
            detail = "Microphone and Accessibility are granted."
            state = .ready
        case (false, true):
            detail = "Microphone permission is needed for dictation."
            state = microphonePermission == .denied ? .failed : .warning
        case (true, false):
            detail = "Accessibility is needed to insert text into other apps."
            state = accessibilityPermission == .denied ? .warning : .pending
        case (false, false):
            detail = "Microphone and Accessibility permissions are needed."
            state = .warning
        }

        updateStartupStep(id: "permissions", detail: detail, state: state)
    }

    func runLocalSession() async {
        await refreshPermissions(promptForAccessibility: false)
        guard permissionsReady else {
            lastError = "Microphone and Accessibility are required."
            statusMessage = "Setup incomplete"
            return
        }

        isRunning = true
        lastError = nil
        didInsert = false
        statusMessage = ""
        defer { isRunning = false }

        await processTranscript(transcript)
        statusMessage = editorMode == .ollama ? "Ollama mode, loopback only" : "Rule editor"
    }

    func toggleDictation() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard await prepareForDictation() else {
            return
        }
        refreshSpeechEngineStatus()

        await refreshPermissions(promptForAccessibility: false)
        guard permissionsReady else {
            lastError = "Microphone and Accessibility are required."
            statusMessage = "Setup incomplete"
            return
        }

        output = ""
        lastError = nil
        statusMessage = ""
        capturedFrameCount = 0
        partialChunkCount = 0
        inputLevel = 0
        recordingDuration = 0
        recordedSamples = []
        recordingSampleRate = 16_000
        chunker = StreamingWavChunker(sampleRate: recordingSampleRate, chunkDurationSeconds: 1.0, maxDurationSeconds: 60.0)
        streamingTranscriptionSession = nativeSpeechServerReady
            ? StreamingAudioTranscriptionSession(transcriber: WhisperKitServerTranscriber(timeoutSeconds: 10.0))
            : nil
        try? FileManager.default.removeItem(at: chunkDirectory)
        lastRecordingURL = nil
        recordingStartedAt = Date()

        let service = AVAudioCaptureService { [weak self] frame in
            await self?.record(frame)
        }

        do {
            try service.start()
            captureService = service
            isRecording = true
            statusMessage = "Listening locally"
            overlayController.show(state: .listening, level: inputLevel)
        } catch {
            captureService = nil
            recordingStartedAt = nil
            isRecording = false
            lastError = "Could not start microphone: \(error)"
        }
    }

    private func prepareForDictation() async -> Bool {
        lastError = nil
        statusMessage = "Checking setup"

        if microphonePermission != .granted {
            microphonePermission = await permissionService.requestMicrophone()
        }

        if accessibilityPermission != .granted {
            accessibilityPermission = permissionService.requestAccessibility()
        }

        await refreshPermissions(promptForAccessibility: true)

        guard permissionsReady else {
            statusMessage = "Waiting for macOS permissions"
            lastError = "Allow Microphone and Accessibility, then QuietType will continue automatically."
            return false
        }

        return true
    }

    func stopRecording() async {
        captureService?.stop()
        captureService = nil
        isRecording = false
        overlayController.show(state: .processing)

        let durationText = String(format: "%.1f", recordingDuration)
        if capturedFrameCount == 0 {
            output = "I could not detect microphone audio. Check your input device and microphone permission."
            statusMessage = "No audio captured"
            overlayController.hide()
            return
        }

        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiettype-last.wav")
            try WavFileWriter.writeMonoPCM16(samples: recordedSamples, sampleRate: recordingSampleRate, to: url)
            lastRecordingURL = url
            output = "Captured \(durationText)s of local audio. Looking for the local speech engine..."
            if let finalChunk = try chunker.flush(outputDirectory: chunkDirectory) {
                partialChunkCount += 1
                statusMessage = "Saved \(partialChunkCount) chunks"
                lastRecordingURL = finalChunk.url
                await streamingTranscriptionSession?.enqueue(finalChunk)
            } else {
                statusMessage = "Saved \(url.lastPathComponent)"
            }
            lastError = nil
            await transcribeAndProcess(url, streamingSession: streamingTranscriptionSession)
            streamingTranscriptionSession = nil
        } catch {
            output = "Captured \(durationText)s of local audio, but could not save the WAV file."
            lastError = String(describing: error)
            overlayController.hide(after: 1.1)
        }
    }

    private func record(_ frame: AudioFrame) async {
        capturedFrameCount += 1
        recordingSampleRate = frame.sampleRate
        recordedSamples.append(contentsOf: frame.samples)
        do {
            let chunks = try chunker.append(frame, outputDirectory: chunkDirectory)
            partialChunkCount += chunks.count
            if let last = chunks.last {
                lastRecordingURL = last.url
                statusMessage = "Streaming chunk \(last.sequence + 1)"
            }
            for chunk in chunks {
                await streamingTranscriptionSession?.enqueue(chunk)
            }
        } catch {
            lastError = "Could not write audio chunk: \(error)"
        }

        if let recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }

        if chunker.reachedMaxDuration && isRecording {
            statusMessage = "60 second limit reached"
            await stopRecording()
            return
        }

        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        inputLevel = min(1.0, rms * 24)
        if isRecording {
            overlayController.show(state: .listening, level: inputLevel)
        }
    }

    private func transcribeAndProcess(_ audioURL: URL, streamingSession: StreamingAudioTranscriptionSession? = nil) async {
        do {
            isRunning = true
            await prepareNativeSpeechServerIfAvailable()
            statusMessage = "Transcribing locally"
            overlayController.show(state: .processing)
            output = """
            Transcribing local audio...

            QuietType captured \(String(format: "%.1f", recordingDuration))s of audio and is running \(speechEngineStatus.lowercased()).
            """
            defer { isRunning = false }
            let streamResult = await streamingSession?.finish()
            let rawTranscript: String
            if let streamResult, !streamResult.text.isEmpty {
                rawTranscript = streamResult.text
                statusMessage = "Processed \(streamResult.chunkCount) streamed chunks"
            } else {
                rawTranscript = try await makeAudioTranscriber().transcribe(audioFile: audioURL)
            }
            transcript = rawTranscript
            await processTranscript(rawTranscript)
        } catch {
            isRunning = false
            overlayController.hide(after: 1.1)
            refreshSpeechEngineStatus()
            if isLikelyNoiseOnlyFailure(error) {
                output = "QuietType captured audio, but could not isolate speech from the background audio."
                statusMessage = "No clear speech detected"
            } else {
                output = "Captured local audio at:\n\(audioURL.path)"
                statusMessage = speechEngineReady ? "Transcription failed" : "Speech engine unavailable"
            }
            lastError = String(describing: error)
        }
    }

    private func isLikelyNoiseOnlyFailure(_ error: Error) -> Bool {
        if case AudioTranscriberError.noiseOnlyTranscript(_) = error {
            return true
        }
        if case AudioTranscriberError.emptyTranscript = error {
            return true
        }
        if case AudioTranscriberError.allBackendsFailed(let errors) = error {
            return errors.contains { value in
                value.contains("noiseOnlyTranscript")
                    || value.contains("emptyTranscript")
                    || value.localizedCaseInsensitiveContains("music")
            }
        }
        return false
    }

    private func makeAudioTranscriber() -> AudioFileTranscribing {
        var transcribers: [AudioFileTranscribing] = []
        if nativeSpeechServerReady {
            transcribers.append(WhisperKitServerTranscriber(timeoutSeconds: 10.0))
        }
        if let commandBackend = LocalASRDiscovery().commandBackend() {
            transcribers.append(commandBackend)
        }
        return CascadingAudioFileTranscriber(transcribers)
    }

    private func prepareNativeSpeechServerIfAvailable() async {
        if nativeSpeechServerReady {
            return
        }

        refreshSpeechEngineStatus()
        if !fallbackSpeechReady {
            startNativeSpeechWarmup()
        }
    }

    private func processTranscript(_ rawTranscript: String) async {
        do {
            let inserter: TextInserting = previewOnly ? BufferingTextInserter() : ClipboardTextInserter()
            let editor: SemanticEditor = editorMode.makeEditor(model: ollamaModel)
            let controller = DictationSessionController(
                profile: .development,
                asrBackend: TranscriptASRBackend(transcript: rawTranscript),
                contextCollector: StaticContextCollector(context: AppContext(appName: selectedProfile.appName, profile: selectedProfile.appProfile)),
                inserter: inserter,
                memoryStore: memoryStore,
                semanticEditor: editor
            )

            try await controller.begin()
            let result = try await controller.finishAndInsert()
            output = result.text
            lastLatencyMS = result.timing.keyReleaseToInsertMS
            didInsert = !previewOnly
            statusMessage = "Polished locally"
            if didInsert {
                overlayController.show(state: .inserted)
                overlayController.hide(after: 1.1)
            } else {
                overlayController.hide()
            }
        } catch {
            output = "Transcript: \(rawTranscript)"
            lastError = String(describing: error)
            overlayController.hide(after: 1.1)
        }
    }

    func saveCorrection() async {
        guard canSaveCorrection else {
            return
        }

        do {
            _ = try await memoryStore.put(
                DictationMemory(
                    type: .correction,
                    payload: [
                        "raw": teachRaw.trimmingCharacters(in: .whitespacesAndNewlines),
                        "corrected": teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
                    ],
                    contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue],
                    source: "gui_teach_correction",
                    confidence: 0.95
                )
            )
            statusMessage = "Saved correction"
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        statusMessage = "Copied output"
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case ruleBased
        case ollama

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ruleBased: "Rule"
            case .ollama: "Ollama"
            }
        }

        func makeEditor(model: String) -> SemanticEditor {
            switch self {
            case .ruleBased:
                return RuleBasedSemanticEditor()
            case .ollama:
                return OllamaSemanticEditor(model: model, fallback: RuleBasedSemanticEditor())
            }
        }
    }

    enum ProfileChoice: String, CaseIterable, Identifiable {
        case messaging
        case email
        case notes
        case code

        var id: String { rawValue }

        var label: String {
            switch self {
            case .messaging: "Slack"
            case .email: "Email"
            case .notes: "Notes"
            case .code: "Code"
            }
        }

        var appName: String {
            switch self {
            case .messaging: "Slack"
            case .email: "Mail"
            case .notes: "Notes"
            case .code: "Cursor"
            }
        }

        var appProfile: AppProfile {
            switch self {
            case .messaging: .messaging
            case .email: .email
            case .notes: .notes
            case .code: .codeEditor
            }
        }
    }

    enum Sample: String, CaseIterable, Identifiable {
        case sageBenchmark
        case shoppingList
        case correction
        case technicalTerms

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sageBenchmark: "SAGE benchmark"
            case .shoppingList: "Shopping list"
            case .correction: "Thursday -> Friday"
            case .technicalTerms: "Security terms"
            }
        }

        var transcript: String {
            switch self {
            case .sageBenchmark:
                "the sage benchmark needs to rerun the comet b f t latency numbers"
            case .shoppingList:
                "for the shopping list get milk eggs bread apples and greek yogurt"
            case .correction:
                "schedule a meeting with the tii team on thursday sorry friday at three pm about the sage benchmark results"
            case .technicalTerms:
                "the ultimate go see as e one hundred supports ed twenty five five nineteen and should route all llama through local inference"
            }
        }

        var profile: ProfileChoice {
            switch self {
            case .shoppingList: .notes
            case .technicalTerms: .code
            default: .messaging
            }
        }
    }
}
