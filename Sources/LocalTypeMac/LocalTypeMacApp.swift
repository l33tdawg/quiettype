import LocalTypeCore
import Darwin
import Foundation
import SwiftUI

@main
struct LocalTypeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        WindowGroup("QuietType") {
            TesterView(model: model)
        }
        .defaultSize(width: 1360, height: 860)
        .windowResizability(.contentSize)
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

    func show(state: OverlayState, level: Double = 0, detail: String? = nil, transcript: String? = nil) {
        let panel = panel ?? makePanel()
        let hasTranscript = !(transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        panel.ignoresMouseEvents = !hasTranscript
        panel.setContentSize(hasTranscript ? NSSize(width: 390, height: 154) : NSSize(width: 280, height: 82))
        panel.contentView = NSHostingView(rootView: DictationOverlayView(state: state, level: level, detail: detail, transcript: transcript))
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
    var detail: String?
    var transcript: String?

    private var cleanedTranscript: String {
        (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    Text(detail ?? state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    OverlayWaveform(level: level, isActive: state.title == OverlayState.listening.title)
                        .frame(width: 170, height: 14)
                }
            }

            if !cleanedTranscript.isEmpty {
                Text(cleanedTranscript)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyOverlayTranscript(cleanedTranscript)
                } label: {
                    Label("Copy transcript", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func copyOverlayTranscript(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct OverlayWaveform: View {
    var level: Double
    var isActive: Bool

    private let bars = 12

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(isActive ? 0.70 : 0.22))
                    .frame(width: 6, height: barHeight(index))
                    .animation(.easeOut(duration: 0.10), value: level)
            }
        }
        .opacity(isActive ? 1 : 0.35)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let phase = abs(Double(index) - Double(bars - 1) / 2.0)
        let shape = 1.0 - min(phase / Double(bars), 0.65)
        let base = isActive ? max(0.10, level) : 0.10
        return CGFloat(4 + (base * shape * 18))
    }
}

struct TesterView: View {
    @ObservedObject var model: MenuBarModel
    @AppStorage("quiettype.hasSeenGuide") private var hasSeenGuide = false
    @AppStorage("quiettype.firstRunAssistantComplete") private var firstRunAssistantComplete = false
    @AppStorage("quiettype.appearanceChoice") private var appearanceChoiceRaw = QuietTypeAppearanceChoice.system.rawValue
    @AppStorage("quiettype.textSizeChoice") private var textSizeChoiceRaw = QuietTypeTextSizeChoice.standard.rawValue
    @State private var selectedSection: QuietTypeSection = .home
    @State private var selectedSettingsTab: QuietTypeSettingsTab = .general
    @State private var selectedSetupTab: QuietTypeSetupTab = .overview
    @State private var showingTeachSheet = false
    @State private var showingRecognizedTerms = false
    @State private var editingTranscriptNote: DictionaryMemoryItem?
    @State private var guideStep: QuietTypeGuideStep?
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.setupComplete && firstRunAssistantComplete {
                appShell
            } else {
                firstRunSetupExperience
            }
        }
        .overlayPreferenceValue(GuideSpotlightPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if model.setupComplete, let guideStep {
                    GuidedOnboardingOverlay(
                        step: guideStep,
                        spotlightFrame: anchors[guideStep].map { proxy[$0] }
                    ) {
                        advanceGuide()
                    } skip: {
                        finishGuide()
                    }
                    .transition(.opacity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearanceChoice.colorScheme)
        .environment(\.quietTypeTypeDelta, textSizeChoice.pointDelta)
        .frame(width: 1360, height: 860)
        .animation(.easeInOut(duration: 0.22), value: selectedSection)
        .animation(.easeInOut(duration: 0.18), value: guideStep)
        .animation(.easeInOut(duration: 0.22), value: model.setupComplete)
        .sheet(item: $editingTranscriptNote) { memory in
            TranscriptNoteEditor(memory: memory, model: model)
        }
        .sheet(isPresented: $showingTeachSheet) {
            TeachQuietTypeSheet(model: model)
        }
        .onAppear {
            model.startAppServices()
            if model.setupComplete && firstRunAssistantComplete && !hasSeenGuide {
                guideStep = .welcome
            }
        }
        .onReceive(permissionTimer) { _ in
            Task {
                model.refreshSystemMetrics()
                await model.refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await model.refreshPermissions(verifyMicrophoneAccess: true)
            }
        }
    }

    private var appShell: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainContent
        }
    }

    private var appearanceChoice: QuietTypeAppearanceChoice {
        QuietTypeAppearanceChoice(rawValue: appearanceChoiceRaw) ?? .system
    }

    private var textSizeChoice: QuietTypeTextSizeChoice {
        QuietTypeTextSizeChoice(rawValue: textSizeChoiceRaw) ?? .standard
    }

    private var appearanceBinding: Binding<QuietTypeAppearanceChoice> {
        Binding(
            get: { appearanceChoice },
            set: { appearanceChoiceRaw = $0.rawValue }
        )
    }

    private var textSizeBinding: Binding<QuietTypeTextSizeChoice> {
        Binding(
            get: { textSizeChoice },
            set: { textSizeChoiceRaw = $0.rawValue }
        )
    }

    private var spellingPreferenceBinding: Binding<SpellingPreference> {
        Binding(
            get: { model.spellingPreference },
            set: { model.setSpellingPreference($0) }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "moonphase.waxing.crescent")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text("QuietType")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(model.appVersionLabel)
                        .font(.system(size: 12 + textSizeChoice.pointDelta, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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
                Label("SAGE memory", systemImage: "lock.fill")
                    .font(.callout.weight(.semibold))
                Text("Dictation lessons use local SAGE BFT-governed memory.")
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

            Button {
                selectedSection = .help
            } label: {
                SidebarItem(icon: QuietTypeSection.help.icon, title: QuietTypeSection.help.title, selected: selectedSection == .help)
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
                dictionaryPage
            case .setup:
                setupPage
            case .dictionary:
                dictionaryPage
            case .settings:
                settingsPage
            case .help:
                helpPage
            }
        }
        .id(selectedSection)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var firstRunStage: QuietTypeFirstRunStage {
        if !model.sageReady {
            return .sage
        }
        if !model.permissionsReady || !model.speechEngineReady {
            return .access
        }
        if !model.trainingComplete {
            return .training
        }
        return .experience
    }

    private var firstRunSetupExperience: some View {
        VStack(spacing: 0) {
            firstRunTopBar
            Divider()
            HStack(spacing: 0) {
                firstRunActionColumn
                    .frame(width: 610)
                    .padding(.horizontal, 56)
                    .padding(.vertical, 48)

                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 1)

                firstRunIllustrationColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.38))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var firstRunTopBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 26) {
                ForEach(QuietTypeFirstRunStage.allCases) { stage in
                    HStack(spacing: 12) {
                        Text(stage.topLabel)
                            .font(.system(size: 17 + textSizeChoice.pointDelta, weight: firstRunStage == stage ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(firstRunStage == stage ? Color.primary : Color.secondary)
                        if stage != QuietTypeFirstRunStage.allCases.last {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 54)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                    Rectangle()
                        .fill(Color.primary.opacity(0.72))
                        .frame(width: proxy.size.width * firstRunStage.progress)
                }
            }
            .frame(height: 4)
        }
    }

    private var firstRunActionColumn: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 14) {
                Text(firstRunStage.title)
                    .font(.system(size: 38 + textSizeChoice.pointDelta, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(firstRunStage.subtitle)
                    .font(.system(size: 18 + textSizeChoice.pointDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(firstRunActionItems) { item in
                    FirstRunActionCard(item: item)
                }
            }

            if firstRunStage == .training {
                firstRunTrainingStrip
            }

            Spacer()

            HStack {
                Label("SAGE memory required", systemImage: "lock.fill")
                    .font(.system(size: 13 + textSizeChoice.pointDelta, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Learn about SAGE") {
                    NSWorkspace.shared.open(URL(string: "https://l33tdawg.github.io/sage/")!)
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var firstRunActionItems: [FirstRunActionItem] {
        switch firstRunStage {
        case .sage:
            return [
                FirstRunActionItem(
                    title: "Set up SAGE governed memory",
                    detail: model.sageDetected ? "SAGE is installed. Complete SAGE setup, unlock it if needed, then connect quiettype-agent." : "QuietType uses SAGE as its local governed memory layer. Install SAGE before dictation starts.",
                    status: model.sageReady ? "Done" : model.sageDetected ? "Connect" : "Install",
                    isComplete: model.sageReady,
                    action: {
                        Task {
                            if model.sageDetected {
                                await model.registerSageAgentIfAvailable()
                            } else {
                                await model.installSage()
                            }
                        }
                    }
                ),
                FirstRunActionItem(
                    title: "Keep dictation lessons local",
                    detail: "Corrections, spellings, review notes, and training hints are committed to your local SAGE node. QuietType does not use a separate cloud memory.",
                    status: "Local",
                    isComplete: true,
                    action: {}
                )
            ]
        case .access:
            return [
                FirstRunActionItem(
                    title: "Allow QuietType to paste into text fields",
                    detail: "Accessibility lets QuietType insert polished text into the app you are already using.",
                    status: model.accessibilityPermission == .granted ? "Done" : "Allow",
                    isComplete: model.accessibilityPermission == .granted,
                    action: { model.requestAccessibility() }
                ),
                FirstRunActionItem(
                    title: "Allow QuietType to use your microphone",
                    detail: "QuietType only listens while you activate dictation. Audio stays on your Mac.",
                    status: model.microphonePermission == .granted ? "Done" : "Allow",
                    isComplete: model.microphonePermission == .granted,
                    action: {
                        Task {
                            await model.requestMicrophone()
                        }
                    }
                ),
                FirstRunActionItem(
                    title: "Warm the local speech engine",
                    detail: "The Apple Silicon speech path starts in the background so the first real dictation is fast.",
                    status: model.speechEngineReady ? "Ready" : "Starting",
                    isComplete: model.speechEngineReady,
                    action: { model.startAppServices() }
                )
            ]
        case .training:
            return [
                FirstRunActionItem(
                    title: "Read three short samples",
                    detail: "QuietType uses expected text to learn cadence and preserve names, dates, numbers, and list formatting.",
                    status: model.trainingProgressLabel,
                    isComplete: model.trainingComplete,
                    action: {
                        Task {
                            await model.toggleCalibrationRecording()
                        }
                    }
                )
            ]
        case .experience:
            return [
                FirstRunActionItem(
                    title: "QuietType is ready",
                    detail: "Press the shortcut or click the mic. The cleaned text appears in the active app, and a copy stays visible in QuietType.",
                    status: "Open",
                    isComplete: false,
                    action: {
                        firstRunAssistantComplete = true
                        selectedSection = .home
                        if !hasSeenGuide {
                            guideStep = .welcome
                        }
                    }
                )
            ]
        }
    }

    private var firstRunTrainingStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.currentCalibrationSet.title)
                .font(.system(size: 14 + textSizeChoice.pointDelta, weight: .semibold))
            Text(model.currentCalibrationSet.script)
                .font(.system(size: 18 + textSizeChoice.pointDelta, weight: .medium))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                OverlayWaveform(level: model.trainingInputLevel, isActive: model.isTrainingRecording)
                    .frame(width: 180, height: 22)
                Text(model.trainingStatusText)
                    .font(.system(size: 13 + textSizeChoice.pointDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task {
                        await model.toggleCalibrationRecording()
                    }
                } label: {
                    Label(model.trainingButtonTitle, systemImage: model.isTrainingRecording ? "stop.circle" : "mic")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var firstRunIllustrationColumn: some View {
        VStack(spacing: 26) {
            FirstRunMacIllustration(stage: firstRunStage, model: model)
                .frame(width: 390, height: 330)

            VStack(spacing: 8) {
                Text(firstRunStage.calloutTitle)
                    .font(.system(size: 21 + textSizeChoice.pointDelta, weight: .semibold, design: .rounded))
                Text(firstRunStage.calloutDetail)
                    .font(.system(size: 15 + textSizeChoice.pointDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 430)
            }
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homePage: some View {
        nativePage {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !model.setupComplete {
                    setupNudgePanel
                }
                metricsGrid
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        dictationPanel
                        outputPanel
                    }
                    .frame(maxWidth: .infinity)
                    securityPanel
                        .frame(width: 430)
                }
                if !model.permissionsReady {
                    permissionsPanel
                }
            }
            .padding(34)
        }
    }

    private var historyPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Review",
                    subtitle: "Recent SAGE review notes and insertion results."
                )

                historySummary
                EmptyStatePanel(
                    icon: "clock.arrow.circlepath",
                    title: "No review notes yet",
                    subtitle: "QuietType saves transcript review notes to SAGE when review notes are enabled."
                )
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
    }

    private var setupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(
                title: "Setup",
                subtitle: "Train QuietType for your voice, cadence, names, and technical terms."
            )

            QuietSegmentedControl(
                title: "Setup",
                selection: $selectedSetupTab,
                options: QuietTypeSetupTab.allCases
            ) { $0.label }

            Group {
                switch selectedSetupTab {
                case .overview:
                    setupOverviewPanel
                case .access:
                    setupAccessPanel
                case .training:
                    setupTrainingPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedSetupTab = suggestedSetupTab
        }
        .animation(.easeInOut(duration: 0.18), value: selectedSetupTab)
    }

    private var setupOverviewPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CompactStatPill(title: "Setup", value: model.personalizationLabel)
                CompactStatPill(title: "Training sets", value: model.trainingProgressLabel)
                CompactStatPill(title: "Samples", value: "\(model.trainingPairCount)")
                CompactStatPill(title: "Dictation", value: model.speechEngineReady ? "Ready" : "Starting")
            }

            setupChecklistPanel
            setupNextStepPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var setupAccessPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sageRequiredPanel
            permissionsPanel
            startupPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var setupNextStepPanel: some View {
        HStack(spacing: 16) {
            Image(systemName: model.setupComplete ? "checkmark.circle.fill" : "arrow.right.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.setupComplete ? "QuietType is ready" : "Finish the next setup step")
                    .font(.system(size: 18, weight: .semibold))
                Text(model.setupComplete ? "You can add more voice samples later when a term is missed." : "QuietType works best after permissions, engine warmup, and three short voice samples.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.setupComplete ? "Add training" : "Continue") {
                selectedSetupTab = suggestedSetupTab
            }
            .buttonStyle(QuietButtonStyle(prominence: .primary))
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var setupChecklistPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("First-time setup")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Four short steps. QuietType starts only after SAGE, permissions, speech, and training are ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.setupComplete {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                SetupStepCard(
                    number: "1",
                    title: "Enable SAGE",
                    detail: "Install SAGE and complete its setup so quiettype-agent can register.",
                    state: model.sageReady ? .done : .action,
                    actionTitle: model.sageDetected ? "Connect" : "Install"
                ) {
                    selectedSetupTab = .access
                    Task {
                        if model.sageDetected {
                            await model.registerSageAgentIfAvailable()
                        } else {
                            await model.installSage()
                        }
                    }
                }

                SetupStepCard(
                    number: "2",
                    title: "Allow access",
                    detail: "Use Microphone to hear you and Accessibility to insert text.",
                    state: model.permissionsReady ? .done : .action,
                    actionTitle: "Open"
                ) {
                    Task {
                        selectedSetupTab = .access
                        if model.microphonePermission != .granted {
                            await model.requestMicrophone()
                        }
                        if model.accessibilityPermission != .granted {
                            model.requestAccessibility()
                        }
                    }
                }

                SetupStepCard(
                    number: "3",
                    title: "Start dictation",
                    detail: "QuietType starts the local speech engine in the background.",
                    state: model.speechEngineReady ? .done : .working,
                    actionTitle: "Wait"
                ) {}

                SetupStepCard(
                    number: "4",
                    title: "Train your voice",
                    detail: "Read short scripts so names and technical terms are preserved.",
                    state: model.trainingComplete ? .done : .action,
                    actionTitle: "Train"
                ) {
                    selectedSection = .setup
                    selectedSetupTab = .training
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var dictionaryPage: some View {
        nativePage {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "Review",
                    subtitle: "Transcript notes, corrections, vocabulary, and SAGE governed memory."
                )

                dictionaryStats
                memoryLibraryPanel
                    .frame(maxHeight: .infinity)
            }
            .padding(34)
        }
        .overlay(alignment: .bottom) {
            if showingRecognizedTerms {
                RecognizedTermsDrawer(isPresented: $showingRecognizedTerms)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            Task {
                if model.dictionaryMemories.isEmpty {
                    await model.refreshDictionaryMemories()
                }
            }
        }
    }

    private var dictionaryStats: some View {
        HStack(spacing: 12) {
            MemoryStatPill(title: "Sessions today", value: "\(model.sessionsToday)")
            MemoryStatPill(title: "Last duration", value: model.lastDictationDurationLabel)
            MemoryStatPill(title: "Insert latency", value: model.lastLatencyMS.map { "\($0) ms" } ?? "Warm")
            MemoryStatPill(title: "Review notes", value: "\(model.transcriptNoteCount)")
        }
    }

    private var setupTrainingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(model.trainingComplete ? "Voice training" : "Finish voice setup")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                        Text(model.trainingProgressLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(model.trainingComplete ? "Add another local sample whenever QuietType misses a term." : "Read three short scripts so QuietType learns your cadence and preserves your terms.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.advanceCalibrationSet()
                } label: {
                    Label("New set", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(QuietButtonStyle())
            }

            HStack(alignment: .top, spacing: 16) {
                TrainingMeter(
                    level: model.trainingInputLevel,
                    isRecording: model.isTrainingRecording,
                    isAnalyzing: model.isTrainingAnalyzing,
                    durationText: model.trainingDurationText
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.currentCalibrationSet.title)
                        .font(.callout.weight(.semibold))
                    Text(model.currentCalibrationSet.script)
                        .font(.system(size: 18, weight: .regular))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.trainingStatusText)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(model.trainingCompletionText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: model.trainingSetupProgress)
                            .progressViewStyle(.linear)
                            .tint(.secondary)
                            .opacity(model.trainingComplete ? 0.45 : 1)
                    }

                    TrainingTermChips(
                        terms: model.currentCalibrationSet.terms,
                        transcript: model.trainingTranscriptDraft,
                        isRecording: model.isTrainingRecording
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            HStack {
                Text(model.trainingFootnote)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button {
                    Task {
                        await model.toggleCalibrationRecording()
                    }
                } label: {
                    Label(
                        model.trainingButtonTitle,
                        systemImage: model.isTrainingAnalyzing ? "checkmark.circle" : (model.isTrainingRecording ? "stop.circle" : "mic")
                    )
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(model.isTrainingAnalyzing)
                Button {
                    showingRecognizedTerms = true
                } label: {
                    Label("Terms", systemImage: "rectangle.stack.badge.person.crop")
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .anchorPreference(key: GuideSpotlightPreferenceKey.self, value: .bounds) { anchor in
            [.memory: anchor]
        }
    }

    private var memoryLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory library")
                        .font(.title3.weight(.semibold))
                    Text(model.sageAgentID.isEmpty ? model.sageAgentStatus : "quiettype-agent · \(model.sageAgentID.prefix(12))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isQueryingSage {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    showingTeachSheet = true
                } label: {
                    Label("Add lesson", systemImage: "square.and.pencil")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                Button("Refresh") {
                    Task {
                        await model.refreshDictionaryMemories()
                    }
                }
                .buttonStyle(QuietButtonStyle())
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search memories", text: $model.sageQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await model.searchDictionaryMemories()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            HStack(spacing: 8) {
                ForEach(MenuBarModel.MemoryFilter.visibleCases) { filter in
                    Button(filter.label) {
                        model.memoryFilter = filter
                    }
                    .buttonStyle(QuietButtonStyle(prominence: model.memoryFilter == filter ? .primary : .secondary))
                }
                Spacer()
            }

            if model.filteredDictionaryMemories.isEmpty {
                EmptyStatePanel(
                    icon: "text.bubble",
                    title: model.sageReady ? "No lessons yet" : "SAGE setup required",
                    subtitle: model.sageReady ? "Add a spelling, correction, or voice training set, then filter and review it here." : "QuietType needs SAGE BFT-governed memory before lessons, transcript notes, or dictation can run."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(model.filteredDictionaryMemories) { memory in
                        DictionaryMemoryRow(memory: memory) {
                            editingTranscriptNote = memory
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var settingsPage: some View {
        nativePage {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "Settings",
                    subtitle: "Controls for appearance, dictation, updates, and sharing."
                )
                settingsPanel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(34)
        }
    }

    private var helpPage: some View {
        nativePage {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader(
                    title: "Help",
                    subtitle: "Setup, SAGE memory, privacy, and quick fixes."
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HelpActionCard(
                            icon: "brain.head.profile",
                            title: "SAGE setup",
                            detail: "QuietType requires local SAGE governed memory before dictation starts.",
                            actionTitle: "Open Setup"
                        ) {
                            selectedSection = .setup
                            selectedSetupTab = .access
                        }

                        HelpActionCard(
                            icon: "checklist",
                            title: "Finish setup",
                            detail: "SAGE, permissions, local dictation, and voice training in one place.",
                            actionTitle: "Open Setup"
                        ) {
                            selectedSection = .setup
                        }
                    }

                    HStack {
                        HelpActionCard(
                            icon: "questionmark.circle",
                            title: "Guided tour",
                            detail: "Replay the short walkthrough for the main controls.",
                            actionTitle: "Show Tour"
                        ) {
                            hasSeenGuide = false
                            selectedSection = .home
                            guideStep = .welcome
                        }

                        HelpActionCard(
                            icon: "mic",
                            title: "Microphone stuck",
                            detail: "Recheck access after changing macOS privacy settings.",
                            actionTitle: "Recheck"
                        ) {
                            Task {
                                await model.refreshPermissions(verifyMicrophoneAccess: true)
                            }
                        }
                    }

                    HStack {
                        HelpInfoCard(
                            icon: "lock.shield",
                            title: "How SAGE helps",
                            detail: "SAGE is not a flat file. It is the governed local memory layer where QuietType commits approved spellings, corrections, transcript notes, and style preferences."
                        )

                        HelpActionCard(
                            icon: "brain.head.profile",
                            title: "Improve accuracy",
                            detail: "Add spellings, corrections, and preferred writing style.",
                            actionTitle: "Open Memory"
                        ) {
                            selectedSection = .dictionary
                        }
                    }
                }

                helpFAQPanel
            }
            .padding(34)
            .anchorPreference(key: GuideSpotlightPreferenceKey.self, value: .bounds) { anchor in
                [.help: anchor]
            }
        }
    }

    private func nativePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ViewThatFits(in: .vertical) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScrollView {
                content()
            }
            .scrollIndicators(.hidden)
        }
    }

    private var helpFAQPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Troubleshooting")
                .font(.title3.weight(.semibold))

            HelpFAQRow(
                question: "Why does QuietType require SAGE?",
                answer: "SAGE is QuietType's governed memory layer. It keeps corrections, vocabulary, training hints, and transcript notes auditable and portable with your SAGE identity. QuietType will not run with a separate local memory fallback."
            )
            HelpFAQRow(
                question: "What happens while SAGE is downloading?",
                answer: "QuietType downloads the SAGE installer from the SAGE GitHub release, opens it, and waits for you to install SAGE, launch it, and complete SAGE setup. After that, click Recheck so quiettype-agent can register."
            )
            HelpFAQRow(
                question: "QuietType says Microphone is needed, but macOS shows it is allowed.",
                answer: "Quit every copy of QuietType, open the app from /Applications, then click Recheck. If it still looks stale, remove the old QuietType entry in System Settings > Privacy & Security > Microphone, launch the current app, and allow it again."
            )
            HelpFAQRow(
                question: "Nothing is inserted after dictation.",
                answer: "Open Setup and make sure Accessibility is allowed. QuietType needs Accessibility to paste polished text into the active app."
            )
            HelpFAQRow(
                question: "The transcript misses names or technical terms.",
                answer: "Open Setup and complete voice training, then open Memory to teach exact spellings such as project names, acronyms, and product terms."
            )
            HelpFAQRow(
                question: "Does anything leave my Mac?",
                answer: "No dictation content is sent to cloud services. Dictation, cleanup, training samples, and SAGE memory stay local. Manual update checks contact GitHub only when you choose Check for updates or Install SAGE."
            )
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 40, weight: .bold))
            Text(subtitle)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func advanceGuide() {
        guard let guideStep else {
            return
        }
        if let next = guideStep.next {
            selectedSection = next.section
            if next == .memory {
                selectedSetupTab = .training
            }
            self.guideStep = next
        } else {
            finishGuide()
        }
    }

    private func finishGuide() {
        hasSeenGuide = true
        guideStep = nil
        selectedSection = .home
    }

    private func resumeSetup() {
        selectedSection = .setup
        selectedSetupTab = suggestedSetupTab
    }

    private var suggestedSetupTab: QuietTypeSetupTab {
        if !model.sageReady {
            return .access
        }
        if !model.permissionsReady {
            return .access
        }
        if !model.trainingComplete {
            return .training
        }
        return .overview
    }

    private var historySummary: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            MetricTile(icon: "text.bubble", value: "\(model.sessionsToday)", label: "Sessions today")
            MetricTile(icon: "timer", value: model.lastDictationDurationLabel, label: "Last duration")
            MetricTile(icon: "textformat.abc", value: model.wordsProcessedLabel, label: "Total words")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speak freely. Transcribe locally.")
                    .font(.system(size: 40, weight: .bold))
                Text("Nothing leaves your Mac.")
                    .font(.system(size: 20, weight: .medium))
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
            MetricTile(icon: "text.bubble", value: "\(model.sessionsToday)", label: "Sessions today")
            MetricTile(icon: "speedometer", value: model.currentWordsPerMinuteLabel, label: "Speaking pace")
            MetricTile(icon: "bolt.fill", value: model.lastLatencyMS.map { "\($0) ms" } ?? "Warm", label: "Release latency")
            MetricTile(icon: "textformat.abc", value: model.wordsProcessedLabel, label: "Total words")
        }
        .anchorPreference(key: GuideSpotlightPreferenceKey.self, value: .bounds) { anchor in
            [.privacy: anchor]
        }
    }

    private var setupNudgePanel: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 8)
                    .frame(width: 58, height: 58)
                Text(model.personalizationLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Finish setup for better transcription")
                    .font(.system(size: 20, weight: .semibold))
                Text(model.setupNudgeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                resumeSetup()
            } label: {
                Label(model.resumeSetupLabel, systemImage: "arrow.right.circle")
            }
            .buttonStyle(QuietButtonStyle(prominence: .primary))

            Button {
                hasSeenGuide = false
                selectedSection = .home
                guideStep = .welcome
            } label: {
                Label("Guide", systemImage: "questionmark.circle")
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 16) {
            if !model.permissionsReady {
                permissionWarningBanner
            }

            QuietSegmentedControl(
                title: "Section",
                selection: $selectedSettingsTab,
                options: QuietTypeSettingsTab.allCases
            ) { tab in
                tab.label
            }

            settingsTabContent
        }
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch selectedSettingsTab {
        case .general:
            generalSettingsLayout
        case .about:
            aboutSettingsLayout
        }
    }

    private var generalSettingsLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                appearancePanel
                dictationControlsPanel
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 16) {
                setupStatusPanel
                memoryBackendPanel
                quickUpdatePanel
            }
            .frame(width: 360, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var aboutSettingsLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            aboutPanel
                .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 16) {
                sharePanel
                advancedPanel
            }
            .frame(width: 420, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dictationControlsPanel: some View {
        settingsSection(title: "Dictation controls") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Insert polished text automatically", isOn: Binding(
                    get: { !model.previewOnly },
                    set: { model.previewOnly = !$0 }
                ))
                .toggleStyle(.checkbox)
                .tint(.primary)

                Toggle("Save transcript review notes to SAGE", isOn: Binding(
                    get: { model.historyReviewEnabled },
                    set: { model.setHistoryReviewEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .tint(.primary)

                QuietSegmentedControl(
                    title: "Spelling",
                    selection: spellingPreferenceBinding,
                    options: SpellingPreference.allCases
                ) { preference in
                    preference.label
                }

                ShortcutPicker(model: model)
            }
        }
    }

    private var sageRequiredPanel: some View {
        settingsSection(title: "SAGE memory") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.sageReady ? "checkmark.seal.fill" : "brain.head.profile")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.sageReady ? "SAGE is ready" : "SAGE is required")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(sageRequiredCopy)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !model.sageInstallStatus.isEmpty {
                            Text(model.sageInstallStatus)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    if !model.sageDetected {
                        Button {
                            Task {
                                await model.installSage()
                            }
                        } label: {
                            Label(model.isInstallingSage ? "Preparing SAGE" : "Install SAGE", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(QuietButtonStyle(prominence: .primary))
                        .disabled(model.isInstallingSage)
                    } else if !model.sageReady {
                        Button {
                            Task {
                                await model.registerSageAgentIfAvailable()
                            }
                        } label: {
                            Label("Register quiettype-agent", systemImage: "person.badge.key")
                        }
                        .buttonStyle(QuietButtonStyle(prominence: .primary))
                    }

                    Button {
                        Task {
                            await model.recheckSage()
                        }
                    } label: {
                        Label("Recheck", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(QuietButtonStyle())

                    Button("Learn about SAGE") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/l33tdawg/sage")!)
                    }
                    .buttonStyle(QuietButtonStyle())

                    Spacer()
                }
            }
        }
    }

    private var sageRequiredCopy: String {
        if model.sageReady {
            return "quiettype-agent is registered with your local SAGE node. Corrections, spellings, transcript notes, and training hints are committed to governed memory."
        }
        if model.sageDetected {
            if model.sageAgentStatus == "Unlock SAGE" {
                return "QuietType found SAGE, but its encrypted vault appears locked. Open SAGE, unlock your vault, complete any SAGE setup steps, then click Recheck."
            }
            if model.sageAgentStatus == "Starting SAGE" {
                return "QuietType found SAGE and is trying to start the local SAGE node. If SAGE opens, complete its setup and unlock it, then click Recheck."
            }
            return "QuietType found SAGE, but the agent is not registered yet. Launch SAGE, complete its setup steps, then register quiettype-agent here."
        }
        if model.isInstallingSage {
            return "QuietType is preparing SAGE. SAGE is not a flat file store: it is the governed local memory layer that keeps dictation teachings durable, auditable, and portable when your SAGE is moved to another Mac."
        }
        return "QuietType will not start without SAGE. SAGE provides BFT-governed local memory for vocabulary, corrections, transcript notes, and writing preferences. Nothing is sent to cloud services."
    }

    private var memoryBackendPanel: some View {
        settingsSection(title: "SAGE governed memory") {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: model.sageReady ? "checkmark.seal.fill" : "brain.head.profile")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sageReady ? "quiettype-agent registered" : model.sageDetected ? "SAGE setup incomplete" : "SAGE required")
                        .font(.callout.weight(.semibold))
                    Text(model.sageReady ? "Vocabulary, corrections, review notes, and training hints are committed through SAGE governed memory." : "QuietType does not use a standalone local memory fallback. Install SAGE, complete SAGE setup, then register quiettype-agent.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.sageAgentID.isEmpty {
                        Text("Agent \(model.sageAgentID.prefix(12))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if !model.sageDetected {
                    Button("Install SAGE") {
                        Task {
                            await model.installSage()
                        }
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                    .disabled(model.isInstallingSage)
                } else if !model.sageReady {
                    Button("Register") {
                        Task {
                            await model.registerSageAgentIfAvailable()
                        }
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                }

                Button("Recheck") {
                    Task {
                        await model.recheckSage()
                    }
                }
                .buttonStyle(QuietButtonStyle())
            }
        }
    }

    private var setupStatusPanel: some View {
        settingsSection(title: "Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                ReadinessLine(
                    title: "Microphone",
                    detail: model.microphonePermission == .granted ? "Audio capture is allowed." : "Required before QuietType can hear you.",
                    state: model.microphonePermission == .granted ? .ready : .needsAction
                )
                ReadinessLine(
                    title: "Accessibility",
                    detail: model.accessibilityPermission == .granted ? "Insertion into other apps is allowed." : "Required for automatic paste.",
                    state: model.accessibilityPermission == .granted ? .ready : .needsAction
                )
                ReadinessLine(
                    title: "SAGE memory",
                    detail: model.sageReady ? "quiettype-agent is registered with governed memory." : "Required before dictation can start.",
                    state: model.sageReady ? .ready : .needsAction
                )
            }
        }
    }

    private var quickUpdatePanel: some View {
        settingsSection(title: "Version") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.appVersionLabel)
                    .font(.callout.weight(.semibold))
                Text("Update checks only contact GitHub when you click the button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await model.checkForUpdatesAndInstall()
                    }
                } label: {
                    Label(model.isCheckingForUpdates ? "Checking" : "Check for updates", systemImage: "arrow.down.circle")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(model.isCheckingForUpdates)
            }
        }
    }

    private var appearancePanel: some View {
        settingsSection(title: "Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                QuietSegmentedControl(
                    title: "Theme",
                    selection: appearanceBinding,
                    options: QuietTypeAppearanceChoice.allCases
                ) { choice in
                    choice.label
                }

                QuietSegmentedControl(
                    title: "Text size",
                    selection: textSizeBinding,
                    options: QuietTypeTextSizeChoice.allCases
                ) { choice in
                    choice.label
                }

                Text("Text size adjusts labels, controls, and helper copy while keeping the main dictation surface stable.")
                    .font(.system(size: 13 + textSizeChoice.pointDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionWarningBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions needed")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(permissionWarningText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                if model.microphonePermission != .granted {
                    Button {
                        Task {
                            await model.requestMicrophone()
                        }
                    } label: {
                        Label(microphonePermissionButtonTitle, systemImage: "mic")
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                }

                if model.accessibilityPermission != .granted {
                    Button {
                        model.requestAccessibility()
                    } label: {
                        Label("Open Accessibility", systemImage: "accessibility")
                    }
                    .buttonStyle(QuietButtonStyle(prominence: model.microphonePermission == .granted ? .primary : .secondary))
                }

                Button {
                    Task {
                        await model.refreshPermissions(verifyMicrophoneAccess: true)
                    }
                } label: {
                    Label("Recheck", systemImage: "arrow.clockwise")
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private var permissionWarningText: String {
        switch (model.microphonePermission == .granted, model.accessibilityPermission == .granted) {
        case (false, false):
            return "QuietType needs Microphone to hear you and Accessibility to insert polished text into the active app."
        case (false, true):
            return "QuietType needs Microphone permission before it can capture local audio. If you just enabled it in System Settings, click Recheck."
        case (true, false):
            return "QuietType needs Accessibility permission to paste polished text into the app you are using. If you just enabled it in System Settings, click Recheck."
        case (true, true):
            return "Permissions are ready."
        }
    }

    private var microphonePermissionButtonTitle: String {
        model.microphonePermission == .notDetermined ? "Allow Microphone" : "Open Microphone"
    }

    private var updatesPanel: some View {
        settingsSection(title: "Updates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.appVersionLabel)
                            .font(.callout.weight(.semibold))
                        Text("Manual update checks contact GitHub only when you click the button.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        Task {
                            await model.checkForUpdatesAndInstall()
                        }
                    } label: {
                        if model.isCheckingForUpdates {
                            Label("Checking", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Check for updates", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                    .disabled(model.isCheckingForUpdates)
                }

                if !model.updateStatus.isEmpty {
                    Text(model.updateStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var aboutPanel: some View {
        settingsSection(title: "About QuietType") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Speak freely. Transcribe locally. Nothing leaves your Mac.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("QuietType is a local-first dictation assistant by Dhillon \"l33tdawg\" Kannabhiran. It uses on-device transcription and SAGE BFT-governed memory for corrections, vocabulary, transcript notes, and writing preferences. Contact: dhillon@levelupctf.com.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Show guided tour") {
                        hasSeenGuide = false
                        selectedSection = .home
                        guideStep = .welcome
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button("GitHub") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/l33tdawg/quiettype")!)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var sharePanel: some View {
        settingsSection(title: "Share QuietType") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Help privacy-conscious Mac users find local dictation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    ShareButton(title: "X", systemImage: "xmark") {
                        openShareURL(for: .x)
                    }
                    ShareButton(title: "LinkedIn", systemImage: "briefcase") {
                        openShareURL(for: .linkedin)
                    }
                    ShareButton(title: "Facebook", systemImage: "person.2") {
                        openShareURL(for: .facebook)
                    }
                }
            }
        }
    }

    private func openShareURL(for destination: QuietTypeShareDestination) {
        guard let url = destination.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .anchorPreference(key: GuideSpotlightPreferenceKey.self, value: .bounds) { anchor in
                [.dictate: anchor]
            }

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
                Text("Review signals")
                    .font(.title3.weight(.semibold))
                Spacer()
                StatusPill(icon: "lock.fill", text: "SAGE", tint: .secondary)
            }

            VStack(spacing: 10) {
                ActivityRow(icon: "timer", title: "Current dictation", value: model.lastDictationDurationLabel)
                ActivityRow(icon: "textformat.abc", title: "Current words", value: "\(model.currentSessionWordCount)")
                ActivityRow(icon: "speedometer", title: "Speaking pace", value: model.currentWordsPerMinuteLabel)
                ActivityRow(icon: "text.bubble", title: "Sessions today", value: "\(model.sessionsToday)")
                ActivityRow(icon: "brain.head.profile", title: "SAGE lessons", value: "\(model.sageLessonCount)")
                ActivityRow(icon: "checklist.checked", title: "Review notes", value: "\(model.transcriptNoteCount)")
                ActivityRow(icon: "wand.and.stars", title: "Correction signal", value: model.correctionSignalLabel)
                ActivityRow(icon: "textformat.abc", title: "Words translated", value: model.wordsProcessedLabel)
                ActivityMeterRow(icon: "speedometer", title: "Local CPU", value: "\(model.cpuUsagePercent)%", progress: Double(model.cpuUsagePercent) / 100.0)
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
                .font(.system(size: 19, weight: .regular))
                .lineSpacing(4)
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
                .buttonStyle(QuietButtonStyle())
                .disabled(model.output.isEmpty)

                Button {
                    model.clearOutput()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuietButtonStyle(prominence: .secondary))
                .disabled(model.output.isEmpty)
                .opacity(model.output.isEmpty ? 0 : 0.78)

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
                QuietSegmentedControl(
                    title: "Editor",
                    selection: $model.editorMode,
                    options: MenuBarModel.EditorMode.allCases
                ) { mode in
                    mode.label
                }

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
            }
            .padding(.top, 8)
        }
    }
}

private enum QuietTypeGuideStep: Int, CaseIterable, Identifiable {
    case welcome
    case dictate
    case privacy
    case memory
    case help

    var id: Int { rawValue }

    var section: QuietTypeSection {
        switch self {
        case .welcome, .dictate, .privacy: .home
        case .memory: .setup
        case .help: .help
        }
    }

    var eyebrow: String {
        "Step \(rawValue + 1) of \(Self.allCases.count)"
    }

    var title: String {
        switch self {
        case .welcome: "Welcome to QuietType"
        case .dictate: "Click the mic, then speak naturally"
        case .privacy: "Everything runs on your Mac"
        case .memory: "Train it once"
        case .help: "Help is built in"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "QuietType turns natural speech into polished writing without sending your audio or text to the cloud."
        case .dictate:
            return "Use the large mic button or the shortcut. When you stop, QuietType cleans the transcript and inserts the result into the active app."
        case .privacy:
            return "The speech engine, text cleanup, app context, and correction memory stay local. Your usage stats focus on transcription quality, speed, and words processed."
        case .memory:
            return "Read a few short scripts so QuietType can learn your cadence, preserve technical terms, and reuse those hints during dictation."
        case .help:
            return "If permissions, insertion, or accuracy feel off, Help gives you the shortest path to fix it without leaving QuietType."
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: "moonphase.waxing.crescent"
        case .dictate: "mic.fill"
        case .privacy: "lock.fill"
        case .memory: "waveform.and.mic"
        case .help: "questionmark.circle"
        }
    }

    var next: QuietTypeGuideStep? {
        QuietTypeGuideStep(rawValue: rawValue + 1)
    }
}

private struct GuideSpotlightPreferenceKey: PreferenceKey {
    static var defaultValue: [QuietTypeGuideStep: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [QuietTypeGuideStep: Anchor<CGRect>],
        nextValue: () -> [QuietTypeGuideStep: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GuidedOnboardingOverlay: View {
    var step: QuietTypeGuideStep
    var spotlightFrame: CGRect?
    var next: () -> Void
    var skip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()

                spotlight
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 12) {
                                Image(systemName: step.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(.primary)
                                    .frame(width: 34, height: 34)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.eyebrow)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(step.title)
                                        .font(.title2.weight(.semibold))
                                }
                            }

                            Text(step.body)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Button("Skip") {
                                    skip()
                                }
                                .buttonStyle(QuietButtonStyle(prominence: .ghost))
                                Spacer()
                                Button(step.next == nil ? "Finish" : "Continue") {
                                    next()
                                }
                                .keyboardShortcut(.defaultAction)
                                .buttonStyle(QuietButtonStyle(prominence: .primary))
                            }
                        }
                        .padding(24)
                        .frame(width: 430, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.10), lineWidth: 1))
                        .shadow(color: .black.opacity(0.28), radius: 30, y: 14)
                    }
                    .padding(.trailing, 52)
                    .padding(.bottom, 46)
                }
            }
        }
    }

    @ViewBuilder
    private var spotlight: some View {
        if step == .dictate, let spotlightFrame {
            let diameter = max(spotlightFrame.width, spotlightFrame.height) + 36
            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                Circle()
                    .stroke(Color.white.opacity(0.92), lineWidth: 4)
                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 13)
                    .frame(width: diameter - 36, height: diameter - 36)
                Image(systemName: "mic.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.20), radius: 28, y: 12)
            .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
        } else if let spotlightFrame, step != .welcome {
            let cornerRadius: CGFloat = step == .privacy ? 16 : 14
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.92), lineWidth: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        .padding(3)
                )
                .frame(
                    width: spotlightFrame.width + 28,
                    height: spotlightFrame.height + 24
                )
                .shadow(color: .black.opacity(0.20), radius: 26, y: 12)
                .position(x: spotlightFrame.midX, y: spotlightFrame.midY)
        }
    }
}

private enum QuietTypeSection: String, CaseIterable, Identifiable {
    case home
    case history
    case setup
    case dictionary
    case settings
    case help

    var id: String { rawValue }

    static let primary: [QuietTypeSection] = [.home, .setup, .dictionary]

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .setup: "Setup"
        case .dictionary: "Review"
        case .settings: "Settings"
        case .help: "Help"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock.arrow.circlepath"
        case .setup: "waveform.and.mic"
        case .dictionary: "brain.head.profile"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

private enum QuietTypeAppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum QuietTypeTextSizeChoice: String, CaseIterable, Identifiable {
    case standard
    case large
    case larger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    var pointDelta: CGFloat {
        switch self {
        case .standard: 0
        case .large: 1
        case .larger: 2
        }
    }
}

private enum QuietTypeSettingsTab: String, CaseIterable, Identifiable {
    case general
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }
}

extension SpellingPreference: Identifiable {
    public var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .british: "British"
        case .american: "American"
        }
    }
}

private enum QuietTypeSetupTab: String, CaseIterable, Identifiable {
    case overview
    case access
    case training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: "Overview"
        case .access: "Access"
        case .training: "Training"
        }
    }
}

private enum QuietTypeFirstRunStage: String, CaseIterable, Identifiable {
    case sage
    case access
    case training
    case experience

    var id: String { rawValue }

    var topLabel: String {
        switch self {
        case .sage: "SAGE"
        case .access: "Set up"
        case .training: "Train"
        case .experience: "Experience it"
        }
    }

    var title: String {
        switch self {
        case .sage: "Set up SAGE memory"
        case .access: "Set up QuietType on your Mac"
        case .training: "Train QuietType for your voice"
        case .experience: "Start dictating"
        }
    }

    var subtitle: String {
        switch self {
        case .sage:
            "QuietType uses SAGE as its governed local memory. Install it, finish SAGE setup, then connect quiettype-agent."
        case .access:
            "Allow paste access and microphone access. QuietType only listens when you activate dictation."
        case .training:
            "Read short, plain-language samples so names, numbers, dates, and lists work better from the first session."
        case .experience:
            "Press the shortcut or click the mic. QuietType transcribes locally, cleans the text, and inserts it where you are working."
        }
    }

    var calloutTitle: String {
        switch self {
        case .sage: "Private memory, locally governed"
        case .access: "macOS stays in control"
        case .training: "A few samples go a long way"
        case .experience: "Speak naturally"
        }
    }

    var calloutDetail: String {
        switch self {
        case .sage:
            "Your spellings, corrections, and review notes are committed to local SAGE memory under quiettype-agent."
        case .access:
            "Microphone and Accessibility permissions are requested through standard macOS prompts."
        case .training:
            "Training samples stay on your Mac and become local hints for cadence, vocabulary, and formatting."
        case .experience:
            "Nothing leaves your Mac. Your latest transcript remains visible if there is nowhere to paste."
        }
    }

    var progress: CGFloat {
        switch self {
        case .sage: 0.25
        case .access: 0.50
        case .training: 0.75
        case .experience: 1.0
        }
    }
}

private enum QuietTypeShareDestination {
    case x
    case linkedin
    case facebook

    private var shareURL: String {
        "https://github.com/l33tdawg/quiettype"
    }

    private var shareText: String {
        "QuietType: private local dictation for Mac. Speak freely. Transcribe locally. Nothing leaves your Mac."
    }

    var url: URL? {
        let encodedURL = shareURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shareURL
        let encodedText = shareText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shareText
        switch self {
        case .x:
            return URL(string: "https://twitter.com/intent/tweet?text=\(encodedText)&url=\(encodedURL)")
        case .linkedin:
            return URL(string: "https://www.linkedin.com/sharing/share-offsite/?url=\(encodedURL)")
        case .facebook:
            return URL(string: "https://www.facebook.com/sharer/sharer.php?u=\(encodedURL)")
        }
    }
}

private struct QuietTypeTypeDeltaKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var quietTypeTypeDelta: CGFloat {
        get { self[QuietTypeTypeDeltaKey.self] }
        set { self[QuietTypeTypeDeltaKey.self] = newValue }
    }
}

private struct FirstRunActionItem: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let status: String
    let isComplete: Bool
    let action: () -> Void
}

private struct FirstRunActionCard: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var item: FirstRunActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(item.title)
                    .font(.system(size: 17 + typeDelta, weight: .semibold, design: .rounded))
                Text(item.detail)
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            Button {
                item.action()
            } label: {
                if item.isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14 + typeDelta, weight: .bold))
                        .frame(width: 22, height: 22)
                } else {
                    Text(item.status)
                }
            }
            .buttonStyle(QuietButtonStyle(prominence: item.isComplete ? .primary : .primary))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct FirstRunMacIllustration: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var stage: QuietTypeFirstRunStage
    @ObservedObject var model: MenuBarModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.10), radius: 16, y: 10)
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.primary.opacity(0.10), lineWidth: 1))

            VStack(spacing: 20) {
                HStack {
                    Circle().fill(Color.primary.opacity(0.16)).frame(width: 10, height: 10)
                    Circle().fill(Color.primary.opacity(0.16)).frame(width: 10, height: 10)
                    Circle().fill(Color.primary.opacity(0.16)).frame(width: 10, height: 10)
                    Spacer()
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.92))
                        .frame(width: 74, height: 74)
                    Image(systemName: stage.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 38, height: 38)
                        .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)
                        .overlay(
                            Image(systemName: stage.badgeIcon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        )
                        .offset(x: 16, y: 12)
                }

                VStack(spacing: 7) {
                    Text(stage.promptTitle(model: model))
                        .font(.system(size: 20 + typeDelta, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(stage.promptDetail(model: model))
                        .font(.system(size: 14 + typeDelta, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 270)
                }

                HStack(spacing: 10) {
                    Text(stage.secondaryAction)
                        .font(.system(size: 14 + typeDelta, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(stage.primaryAction(model: model))
                        .font(.system(size: 14 + typeDelta, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(28)
        }
    }
}

private extension QuietTypeFirstRunStage {
    var icon: String {
        switch self {
        case .sage: "brain.head.profile"
        case .access: "hand.raised.fill"
        case .training: "waveform"
        case .experience: "mic.fill"
        }
    }

    var badgeIcon: String {
        switch self {
        case .sage: "lock.fill"
        case .access: "mic.fill"
        case .training: "textformat.abc"
        case .experience: "doc.on.doc.fill"
        }
    }

    var secondaryAction: String {
        switch self {
        case .sage: "Learn"
        case .access: "Later"
        case .training: "Skip"
        case .experience: "Copy"
        }
    }

    @MainActor
    func primaryAction(model: MenuBarModel) -> String {
        switch self {
        case .sage:
            return model.sageDetected ? "Connect" : "Install"
        case .access:
            return "Allow"
        case .training:
            return model.isTrainingRecording ? "Stop" : "Record"
        case .experience:
            return "Start"
        }
    }

    @MainActor
    func promptTitle(model: MenuBarModel) -> String {
        switch self {
        case .sage:
            return model.sageDetected ? "Connect quiettype-agent" : "Install local SAGE"
        case .access:
            return "QuietType would like access"
        case .training:
            return "Read one short sample"
        case .experience:
            return "Ready to dictate"
        }
    }

    @MainActor
    func promptDetail(model: MenuBarModel) -> String {
        switch self {
        case .sage:
            return "SAGE stores transcription lessons as governed local memory."
        case .access:
            return "Use microphone for local audio and Accessibility for insertion."
        case .training:
            return "\(model.trainingProgressLabel) samples complete."
        case .experience:
            return "Speak freely. Transcribe locally."
        }
    }
}

private enum SetupStepCardState {
    case done
    case working
    case action
}

private struct SetupStepCard: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var number: String
    var title: String
    var detail: String
    var state: SetupStepCardState
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(number)
                    .font(.system(size: 12 + typeDelta, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                Spacer()
                statusView
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 17 + typeDelta, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if state == .action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .done:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
        case .working:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Starting")
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        case .action:
            Label("Open", systemImage: "arrow.right.circle")
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct HelpActionCard: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var icon: String
    var title: String
    var detail: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18 + typeDelta, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(actionTitle, action: action)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HelpInfoCard: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18 + typeDelta, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct HelpFAQRow: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var question: String
    var answer: String

    var body: some View {
        DisclosureGroup {
            Text(answer)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            Text(question)
                .font(.system(size: 14 + typeDelta, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct SidebarItem: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var icon: String
    var title: String
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 17 + typeDelta, weight: selected ? .semibold : .regular))
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
    @Environment(\.quietTypeTypeDelta) private var typeDelta
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
                .font(.system(size: 14 + typeDelta, weight: .regular))
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
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var term: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(term)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MemoryStatPill: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
            Text(title)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompactStatPill: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 12 + typeDelta, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrainingMeter: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var level: Double
    var isRecording: Bool
    var isAnalyzing: Bool
    var durationText: String

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                    .frame(width: 104, height: 104)
                Circle()
                    .trim(from: 0, to: isRecording ? max(0.08, clampedLevel) : (isAnalyzing ? 0.72 : 0))
                    .stroke(
                        Color.primary.opacity(isRecording || isAnalyzing ? 0.82 : 0.20),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 104, height: 104)
                    .animation(.easeOut(duration: 0.12), value: clampedLevel)
                Image(systemName: isAnalyzing ? "checkmark" : (isRecording ? "waveform" : "mic"))
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(isRecording || isAnalyzing ? Color.primary : Color.secondary)
            }

            Text(isAnalyzing ? "Learning" : (isRecording ? "Recording" : "Ready"))
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(isRecording || isAnalyzing ? .primary : .secondary)
            Text(durationText)
                .font(.system(size: 12 + typeDelta, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
        .padding(.top, 2)
    }
}

private struct TrainingTermChips: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var terms: [String]
    var transcript: String
    var isRecording: Bool

    private var normalizedTranscript: String {
        Self.normalize(transcript)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isRecording ? "Terms to listen for" : "Term check")
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 7, rowSpacing: 7) {
                ForEach(terms, id: \.self) { term in
                    let state = state(for: term)
                    HStack(spacing: 5) {
                        if state != .pending {
                            Image(systemName: state == .found ? "checkmark" : "minus")
                                .font(.system(size: 12 + typeDelta, weight: .bold))
                        }
                        Text(term)
                    }
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
                    .foregroundStyle(state.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(state.background)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(state.border, lineWidth: 1))
                }
            }
        }
    }

    private func state(for term: String) -> TrainingTermState {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isRecording else {
            return .pending
        }
        return normalizedTranscript.contains(Self.normalize(term)) ? .found : .missing
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private enum TrainingTermState {
    case pending
    case found
    case missing

    var foreground: Color {
        switch self {
        case .pending, .missing:
            return .secondary
        case .found:
            return .white
        }
    }

    var background: Color {
        switch self {
        case .pending:
            return Color(nsColor: .windowBackgroundColor)
        case .found:
            return Color.primary
        case .missing:
            return Color.primary.opacity(0.04)
        }
    }

    var border: Color {
        switch self {
        case .pending:
            return Color.primary.opacity(0.10)
        case .found:
            return Color.primary.opacity(0.08)
        case .missing:
            return Color.primary.opacity(0.14)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                maxWidth = max(maxWidth, x - spacing)
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        maxWidth = max(maxWidth, x > 0 ? x - spacing : 0)
        return CGSize(width: width > 0 ? width : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ShortcutPicker: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Shortcut")
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                Spacer()
                Text(model.hotKeyLabel)
                    .font(.system(size: 15 + typeDelta, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(MenuBarModel.HotKeyChoice.allCases) { choice in
                    Button {
                        model.setHotKeyChoice(choice)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.label)
                                .font(.system(size: 14 + typeDelta, weight: .semibold))
                            Text(model.hotKeyDetail(for: choice))
                                .font(.system(size: 12 + typeDelta, weight: .regular))
                                .foregroundStyle(model.hotKeyChoice == choice ? Color(nsColor: .windowBackgroundColor).opacity(0.72) : Color.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(QuietButtonStyle(prominence: model.hotKeyChoice == choice ? .primary : .secondary))
                }
            }

            if model.hotKeyChoice == .function && model.functionKeySystemUse.conflictsWithQuietType {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12 + typeDelta, weight: .semibold))
                    Text("macOS is also using Fn, so emoji or dictation may appear. Use the fallback shortcut, or set Keyboard > Press Fn key to Do Nothing.")
                        .font(.system(size: 12 + typeDelta, weight: .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct DictionaryMemoryItem: Identifiable, Equatable {
    var id: String
    var title: String
    var summary: String
    var kind: String
    var confidence: Double?
    var source: String
    var rawTranscript: String?
    var polishedText: String?
    var isEditableTranscript: Bool
}

private struct DictionaryMemoryRow: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var memory: DictionaryMemoryItem
    var editAction: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(memory.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let confidence = memory.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.system(size: 12 + typeDelta, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                if memory.isEditableTranscript {
                    Button("Edit") {
                        editAction()
                    }
                    .buttonStyle(QuietButtonStyle())
                    .controlSize(.small)
                }
            }

            Text(memory.summary)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(memory.kind)
                Text(memory.source)
                Text(memory.id.prefix(12))
            }
            .font(.caption)
            .font(.system(size: 12 + typeDelta, weight: .regular))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TranscriptNoteEditor: View {
    let memory: DictionaryMemoryItem
    @ObservedObject var model: MenuBarModel
    @Environment(\.dismiss) private var dismiss
    @State private var rawTranscript: String
    @State private var polishedText: String

    init(memory: DictionaryMemoryItem, model: MenuBarModel) {
        self.memory = memory
        self.model = model
        _rawTranscript = State(initialValue: memory.rawTranscript ?? "")
        _polishedText = State(initialValue: memory.polishedText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Review transcript")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Fix obvious mistakes here. QuietType learns clear one-word corrections as reusable local lessons.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Raw transcript")
                    .font(.headline)
                TextEditor(text: $rawTranscript)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Polished text")
                    .font(.headline)
                TextEditor(text: $polishedText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                Button("Save and learn") {
                    Task {
                        await model.updateTranscriptNote(memoryID: memory.id, rawTranscript: rawTranscript, polishedText: polishedText)
                        dismiss()
                    }
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TeachQuietTypeSheet: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.dismiss) private var dismiss

    private var teachingKindBinding: Binding<MenuBarModel.TeachingKind> {
        Binding(
            get: { model.teachingKind },
            set: { model.setTeachingKind($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add lesson")
                    .font(.largeTitle.weight(.semibold))
                Text(model.teachingKind.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                QuietSegmentedControl(
                    title: "Lesson",
                    selection: teachingKindBinding,
                    options: MenuBarModel.TeachingKind.allCases
                ) { kind in
                    kind.label
                }
                QuietTextField(label: model.teachingKind.rawLabel, text: $model.teachRaw)
                QuietTextField(label: model.teachingKind.correctedLabel, text: $model.teachCorrected)
                QuietTextField(label: "Context", text: $model.teachingContext)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.teachingKind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                Text(model.lessonPreviewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

            HStack {
                Text("Lessons are committed to SAGE governed memory under quiettype-agent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                Button("Save lesson") {
                    Task {
                        await model.saveCorrection()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(!model.canSaveCorrection)
            }
        }
        .padding(28)
        .frame(width: 560)
    }
}

private struct ShareButton: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24 + typeDelta, weight: .semibold))
                Text(title)
                    .font(.system(size: 13 + typeDelta, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(QuietButtonStyle())
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

private struct ActivityMeterRow: View {
    var icon: String
    var title: String
    var value: String
    var progress: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            ProgressView(value: min(max(progress, 0), 1))
                .progressViewStyle(.linear)
                .tint(.secondary)
                .frame(width: 82)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private enum ReadinessLineState: Equatable {
    case ready
    case needsAction
}

private struct ReadinessLine: View {
    var title: String
    var detail: String
    var state: ReadinessLineState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: state == .ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
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
                    .buttonStyle(QuietButtonStyle())
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

private struct CPUUsageSampler {
    private var previous: host_cpu_load_info_data_t?

    mutating func sample() -> Int {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        defer {
            previous = info
        }

        guard let previous else {
            return 0
        }

        let user = Double(info.cpu_ticks.0 - previous.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 - previous.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - previous.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - previous.cpu_ticks.3)
        let total = max(user + system + idle + nice, 1)
        let busy = user + system + nice

        return min(100, max(0, Int((busy / total) * 100.0)))
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
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var icon: String
    var text: String
    var tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 14 + typeDelta, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.quietTypeTypeDelta) private var typeDelta

    enum Prominence {
        case primary
        case secondary
        case ghost
    }

    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14 + typeDelta, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, prominence == .ghost ? 8 : 14)
            .padding(.vertical, prominence == .ghost ? 7 : 9)
            .background(background(configuration: configuration))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(border(configuration: configuration), lineWidth: prominence == .ghost ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch prominence {
        case .primary: Color(nsColor: .windowBackgroundColor)
        case .secondary, .ghost: .primary
        }
    }

    private func background(configuration: Configuration) -> Color {
        switch prominence {
        case .primary:
            Color.primary.opacity(configuration.isPressed ? 0.82 : 1)
        case .secondary:
            Color(nsColor: .windowBackgroundColor)
        case .ghost:
            Color.clear
        }
    }

    private func border(configuration: Configuration) -> Color {
        switch prominence {
        case .primary:
            Color.primary.opacity(0.12)
        case .secondary:
            Color.primary.opacity(configuration.isPressed ? 0.18 : 0.09)
        case .ghost:
            Color.clear
        }
    }
}

private struct QuietSegmentedControl<Option: Identifiable & Hashable>: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var title: String
    @Binding var selection: Option
    var options: [Option]
    var label: (Option) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 96, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                            .font(.system(size: 14 + typeDelta, weight: selection == option ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(selection == option ? Color(nsColor: .windowBackgroundColor) : Color.primary)
                            .frame(minWidth: 64)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selection == option ? Color.primary : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private struct QuietTextField: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15 + typeDelta, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private struct RecognizedTermsDrawer: View {
    @Binding var isPresented: Bool

    private let terms: [(String, String)] = [
        ("SAGE", "Governed memory"),
        ("CometBFT", "Consensus"),
        ("Ollama", "Local models"),
        ("Ed25519", "Crypto"),
        ("WhisperKit", "Apple Silicon ASR"),
        ("QuietType", "App name")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recognized terms")
                        .font(.title3.weight(.semibold))
                    Text("Seed vocabulary QuietType should preserve during transcription and cleanup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(QuietButtonStyle(prominence: .ghost))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(terms, id: \.0) { term in
                    DictionaryTerm(term: term.0, detail: term.1)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 24, y: 12)
    }
}

private struct QuietTypeUpdateResult {
    var message: String
}

private enum QuietTypeUpdaterError: LocalizedError {
    case releaseUnavailable(Int)
    case releaseDecodeFailed
    case noDMGAsset
    case downloadUnavailable(Int)
    case mountFailed
    case appMissingInDMG
    case bundleIdentifierMismatch(expected: String, actual: String)
    case installFailed(String)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .releaseUnavailable(let status):
            if status == 401 || status == 403 || status == 404 {
                return "GitHub release metadata is not accessible. Private beta releases require tester access or a public release asset."
            }
            return "GitHub release metadata returned HTTP \(status)."
        case .releaseDecodeFailed:
            return "GitHub returned release metadata QuietType could not read."
        case .noDMGAsset:
            return "No macOS arm64 DMG was found in the latest GitHub release."
        case .downloadUnavailable(let status):
            if status == 401 || status == 403 || status == 404 {
                return "GitHub blocked the DMG download. Private beta assets require tester access or a public release asset."
            }
            return "DMG download returned HTTP \(status)."
        case .mountFailed:
            return "The downloaded DMG could not be mounted."
        case .appMissingInDMG:
            return "The DMG did not contain QuietType.app."
        case .bundleIdentifierMismatch(let expected, let actual):
            return "The downloaded app has bundle identifier \(actual), expected \(expected). Update cancelled to preserve macOS permissions."
        case .installFailed(let reason):
            return reason
        case .commandFailed(let command, let code, let output):
            return "\(command) failed with exit code \(code). \(output)"
        }
    }
}

private struct QuietTypeGitHubRelease: Decodable {
    var tagName: String
    var name: String?
    var assets: [QuietTypeGitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case assets
    }
}

private struct QuietTypeGitHubAsset: Decodable {
    var name: String
    var browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

private struct SageInstallerResult {
    var message: String
}

private enum SageInstallerError: LocalizedError {
    case releaseUnavailable(Int)
    case releaseDecodeFailed
    case noDMGAsset
    case downloadUnavailable(Int)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .releaseUnavailable(let status):
            return "SAGE release metadata returned HTTP \(status)."
        case .releaseDecodeFailed:
            return "GitHub returned SAGE release metadata QuietType could not read."
        case .noDMGAsset:
            return "No SAGE macOS DMG was found in the latest GitHub release."
        case .downloadUnavailable(let status):
            return "SAGE DMG download returned HTTP \(status)."
        case .installFailed(let reason):
            return reason
        }
    }
}

private enum QuietTypeSageRequirementError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "SAGE is not connected."
        }
    }
}

private final class SageGitHubInstaller {
    private let releaseURL = URL(string: "https://api.github.com/repos/l33tdawg/sage/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/l33tdawg/sage/releases/latest")!
    private let fileManager = FileManager.default

    func downloadAndOpen() async throws -> SageInstallerResult {
        let release = try await fetchLatestRelease()
        guard let asset = release.assets.first(where: { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".dmg") && name.contains("sage")
        }) ?? release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw SageInstallerError.noDMGAsset
        }

        let dmgURL = try await download(asset)
        let opened = NSWorkspace.shared.open(dmgURL)
        if !opened {
            NSWorkspace.shared.activateFileViewerSelecting([dmgURL])
        }

        return SageInstallerResult(
            message: "Opened the SAGE installer. Drag SAGE into Applications, launch it once, complete its setup, then click Recheck in QuietType."
        )
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    private func fetchLatestRelease() async throws -> QuietTypeGitHubRelease {
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuietType-SAGE-Installer", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SageInstallerError.releaseUnavailable(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(QuietTypeGitHubRelease.self, from: data)
        } catch {
            throw SageInstallerError.releaseDecodeFailed
        }
    }

    private func download(_ asset: QuietTypeGitHubAsset) async throws -> URL {
        let directory = try applicationSupportDirectory()
            .appendingPathComponent("SAGE", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(asset.name)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("QuietType-SAGE-Installer", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SageInstallerError.downloadUnavailable(http.statusCode)
        }

        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SageInstallerError.installFailed("Could not locate Application Support.")
        }
        return directory.appendingPathComponent("QuietType", isDirectory: true)
    }
}

private struct QuietTypeReleaseVersion: Comparable {
    var major: Int
    var minor: Int
    var patch: Int
    var betaBuild: Int

    static func current() -> QuietTypeReleaseVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        return parse("v\(version)-beta.\(build)") ?? QuietTypeReleaseVersion(major: 0, minor: 1, patch: 0, betaBuild: build)
    }

    static func parse(_ value: String) -> QuietTypeReleaseVersion? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "quiettype-", with: "")
            .replacingOccurrences(of: "-macos-arm64.dmg", with: "")
            .replacingOccurrences(of: "v", with: "")
        let parts = normalized.components(separatedBy: "-beta.")
        let versionParts = parts[0].split(separator: ".").compactMap { Int($0) }
        guard versionParts.count >= 3 else {
            return nil
        }
        let build = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return QuietTypeReleaseVersion(
            major: versionParts[0],
            minor: versionParts[1],
            patch: versionParts[2],
            betaBuild: build
        )
    }

    static func < (lhs: QuietTypeReleaseVersion, rhs: QuietTypeReleaseVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return lhs.betaBuild < rhs.betaBuild
    }
}

private final class QuietTypeGitHubUpdater {
    private let releaseURL = URL(string: "https://api.github.com/repos/l33tdawg/quiettype/releases/latest")!
    private let fileManager = FileManager.default

    func checkDownloadBackupAndInstall() async throws -> QuietTypeUpdateResult {
        let release = try await fetchLatestRelease()
        guard let asset = release.assets.first(where: { asset in
            asset.name.localizedCaseInsensitiveContains("macOS-arm64.dmg")
                || asset.name.localizedCaseInsensitiveContains("macos-arm64.dmg")
        }) else {
            throw QuietTypeUpdaterError.noDMGAsset
        }

        let currentVersion = QuietTypeReleaseVersion.current()
        let latestVersion = QuietTypeReleaseVersion.parse(release.tagName)
            ?? QuietTypeReleaseVersion.parse(asset.name)
            ?? currentVersion

        guard latestVersion > currentVersion else {
            return QuietTypeUpdateResult(message: "QuietType is up to date. You are running \(display(currentVersion)).")
        }

        let dmgURL = try await download(asset)
        let mountedVolume = try mount(dmgURL)
        defer {
            _ = try? run("/usr/bin/hdiutil", arguments: ["detach", mountedVolume.path])
        }

        let sourceApp = mountedVolume.appendingPathComponent("QuietType.app", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceApp.path) else {
            throw QuietTypeUpdaterError.appMissingInDMG
        }

        try verifyBundleIdentity(sourceApp)
        try backupAndInstall(sourceApp: sourceApp)
        try verifyInstalledApp()

        return QuietTypeUpdateResult(
            message: "Installed \(display(latestVersion)) in /Applications. Quit and reopen QuietType to use the new version."
        )
    }

    private func fetchLatestRelease() async throws -> QuietTypeGitHubRelease {
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuietType-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuietTypeUpdaterError.releaseUnavailable(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(QuietTypeGitHubRelease.self, from: data)
        } catch {
            throw QuietTypeUpdaterError.releaseDecodeFailed
        }
    }

    private func download(_ asset: QuietTypeGitHubAsset) async throws -> URL {
        let updatesDirectory = try applicationSupportDirectory()
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)

        let destination = updatesDirectory.appendingPathComponent(asset.name)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("QuietType-Updater", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuietTypeUpdaterError.downloadUnavailable(http.statusCode)
        }

        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func mount(_ dmgURL: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil", arguments: ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"])
        guard let data = output.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw QuietTypeUpdaterError.mountFailed
        }
        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private func backupAndInstall(sourceApp: URL) throws {
        let destinationApp = URL(fileURLWithPath: "/Applications/QuietType.app", isDirectory: true)
        let temporaryInstall = URL(fileURLWithPath: "/Applications/QuietType.app.updating", isDirectory: true)

        if fileManager.fileExists(atPath: destinationApp.path) {
            let backupDirectory = try applicationSupportDirectory()
                .appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backupURL = backupDirectory.appendingPathComponent("QuietType-\(timestamp()).app", isDirectory: true)
            try fileManager.copyItem(at: destinationApp, to: backupURL)
        }

        if fileManager.fileExists(atPath: temporaryInstall.path) {
            try fileManager.removeItem(at: temporaryInstall)
        }
        try fileManager.copyItem(at: sourceApp, to: temporaryInstall)

        if fileManager.fileExists(atPath: destinationApp.path) {
            try fileManager.removeItem(at: destinationApp)
        }
        try fileManager.moveItem(at: temporaryInstall, to: destinationApp)
    }

    private func verifyBundleIdentity(_ appURL: URL) throws {
        let expectedBundleID = Bundle.main.bundleIdentifier ?? "local.quiettype.mac"
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              let actualBundleID = info["CFBundleIdentifier"] as? String
        else {
            throw QuietTypeUpdaterError.bundleIdentifierMismatch(expected: expectedBundleID, actual: "missing")
        }

        guard actualBundleID == expectedBundleID else {
            throw QuietTypeUpdaterError.bundleIdentifierMismatch(expected: expectedBundleID, actual: actualBundleID)
        }
    }

    private func verifyInstalledApp() throws {
        _ = try run("/usr/sbin/spctl", arguments: ["-a", "-t", "exec", "-vv", "/Applications/QuietType.app"])
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw QuietTypeUpdaterError.installFailed("Could not locate Application Support.")
        }
        return directory.appendingPathComponent("QuietType", isDirectory: true)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func display(_ version: QuietTypeReleaseVersion) -> String {
        "v\(version.major).\(version.minor).\(version.patch) beta.\(version.betaBuild)"
    }

    @discardableResult
    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw QuietTypeUpdaterError.commandFailed(
                URL(fileURLWithPath: executable).lastPathComponent,
                process.terminationStatus,
                output
            )
        }
        return output
    }
}

struct CalibrationSet: Identifiable, Equatable {
    var id: String
    var title: String
    var script: String
    var terms: [String]

    static let defaults: [CalibrationSet] = [
        CalibrationSet(
            id: "everyday-list",
            title: "Everyday list",
            script: "For the grocery list, get milk, eggs, bread, apples, and Greek yogurt.",
            terms: ["milk", "eggs", "bread", "apples", "Greek yogurt"]
        ),
        CalibrationSet(
            id: "dates-and-times",
            title: "Dates and times",
            script: "Schedule a meeting with Sarah next Friday at three thirty in the afternoon.",
            terms: ["Sarah", "Friday", "3:30", "afternoon"]
        ),
        CalibrationSet(
            id: "numbers-and-money",
            title: "Numbers and money",
            script: "The order total is twenty seven dollars and fifty cents for four items.",
            terms: ["$27.50", "4 items"]
        ),
        CalibrationSet(
            id: "natural-correction",
            title: "Natural correction",
            script: "Please remind me to call David on Thursday, sorry, make that Friday morning.",
            terms: ["David", "Thursday", "Friday morning"]
        )
    ]
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
    @Published var lastDictationDuration = 0.0
    @Published var sessionsToday = 0
    @Published var totalTranslatedWordCount = 0
    @Published var inputLevel = 0.0
    @Published var capturedFrameCount = 0
    @Published var lastRecordingURL: URL?
    @Published var partialChunkCount = 0
    @Published var lastLatencyMS: Int?
    @Published var lastError: String?
    @Published var previewOnly = false
    @Published var didInsert = false
    @Published var historyReviewEnabled = true
    @Published var selectedProfile = ProfileChoice.messaging
    @Published var editorMode = EditorMode.ruleBased
    @Published var ollamaModel = "qwen3:4b"
    @Published var spellingPreference = SpellingPreference.system
    @Published var teachRaw = "Steven"
    @Published var teachCorrected = "Stephen"
    @Published var teachingKind = TeachingKind.correction
    @Published var teachingContext = "names and spelling"
    @Published var localMemories: [DictationMemory] = []
    @Published var memoryFilter = MemoryFilter.all
    @Published var didSaveTeachingMemory = false
    @Published var calibrationSetIndex = 0
    @Published var calibrationSavedCount = 0
    @Published var isTrainingRecording = false
    @Published var isTrainingAnalyzing = false
    @Published var trainingDuration = 0.0
    @Published var trainingInputLevel = 0.0
    @Published var trainingTranscriptDraft = ""
    @Published var trainingPairCount = 0
    @Published var statusMessage = ""
    @Published var hotKeyLabel = "⌃⇧D"
    @Published var hotKeyChoice = HotKeyChoice.function
    @Published var functionKeySystemUse = FunctionKeySystemUse.current
    @Published var microphonePermission: PermissionState = .unknown
    @Published var accessibilityPermission: PermissionState = .unknown
    @Published var cpuUsagePercent = 0
    @Published var isCheckingForUpdates = false
    @Published var updateStatus = ""
    @Published var isInstallingSage = false
    @Published var sageInstallStatus = ""

    private let permissionService = MacOSPermissionService()
    private let memoryStore = SQLiteMemoryStore.persistentDefault()
    private let updateService = QuietTypeGitHubUpdater()
    private let sageInstaller = SageGitHubInstaller()
    private var sageDirectClient: SageDirectClient?
    private var sageServeProcess: Process?
    private var whisperKitSupervisor: WhisperKitServerSupervisor?
    private var didStartAppServices = false
    private var nativeSpeechStartupTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var captureService: AVAudioCaptureService?
    private var trainingCaptureService: AVAudioCaptureService?
    private var recordingStartedAt: Date?
    private var trainingStartedAt: Date?
    private var recordedSamples: [Float] = []
    private var trainingSamples: [Float] = []
    private var recordingSampleRate = 16_000
    private var trainingSampleRate = 16_000
    private var peakInputLevel = 0.0
    private var peakTrainingInputLevel = 0.0
    private var trainingFrameCount = 0
    private var lastTrainingAudioURL: URL?
    private var chunker = StreamingWavChunker()
    private let chunkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("quiettype-stream")
    private var streamingTranscriptionSession: StreamingAudioTranscriptionSession?
    private var pendingStreamingChunks: [WavAudioChunk] = []
    private var activeTranscriptionOptions = AudioTranscriptionOptions.none
    private var hotKeyController: CarbonHotKeyController?
    private var functionKeyMonitor: FunctionKeyToggleMonitor?
    private var lastHotKeyToggleAt: Date?
    private let overlayController = DictationOverlayController()
    private var cpuSampler = CPUUsageSampler()
    private var microphoneAccessVerified = false
    private static let hotKeyChoiceKey = "quiettype.hotKeyChoice"
    private static let spellingPreferenceKey = "quiettype.spellingPreference"
    private static let calibrationSavedCountKey = "quiettype.calibrationSavedCount"
    private static let trainingPairCountKey = "quiettype.trainingPairCount"
    private static let sessionsTodayKey = "quiettype.sessionsToday"
    private static let sessionsTodayDateKey = "quiettype.sessionsTodayDate"
    private static let totalTranslatedWordCountKey = "quiettype.totalTranslatedWordCount"
    private static let historyReviewEnabledKey = "quiettype.historyReviewEnabled"
    private static let requiredCalibrationSets = 3
    private static let maxDictationDurationSeconds = 300.0
    private static let maxTrainingPairCount = 10
    private static let streamingTranscriptMinimumDuration = 8.0

    init() {
        calibrationSavedCount = UserDefaults.standard.integer(forKey: Self.calibrationSavedCountKey)
        trainingPairCount = UserDefaults.standard.integer(forKey: Self.trainingPairCountKey)
        sessionsToday = Self.loadSessionsToday()
        totalTranslatedWordCount = UserDefaults.standard.integer(forKey: Self.totalTranslatedWordCountKey)
        if UserDefaults.standard.object(forKey: Self.historyReviewEnabledKey) == nil {
            historyReviewEnabled = true
        } else {
            historyReviewEnabled = UserDefaults.standard.bool(forKey: Self.historyReviewEnabledKey)
        }
        if let storedSpelling = UserDefaults.standard.string(forKey: Self.spellingPreferenceKey),
           let preference = SpellingPreference(rawValue: storedSpelling) {
            spellingPreference = preference
        }
        if let storedHotKey = UserDefaults.standard.string(forKey: Self.hotKeyChoiceKey),
           let choice = HotKeyChoice(rawValue: storedHotKey) {
            hotKeyChoice = choice
            hotKeyLabel = choice.label
        } else {
            hotKeyChoice = functionKeySystemUse.conflictsWithQuietType ? .controlShiftD : .function
            hotKeyLabel = hotKeyChoice.label
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.shutdownAppServices()
            }
        }

        Task { @MainActor [weak self] in
            self?.startAppServices()
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

    var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if build.isEmpty {
            return "v\(version)"
        }
        return "v\(version) beta.\(build)"
    }

    var primaryPrompt: String {
        if !sageReady {
            return "Install SAGE to finish setup"
        }
        if !permissionsReady {
            return "Click the mic to finish setup"
        }
        if !trainingComplete {
            return "Click the mic to dictate"
        }
        if isRecording {
            return "Listening... \(String(format: "%.1f", recordingDuration))s"
        }
        return "Press \(hotKeyLabel) or click the mic"
    }

    var primaryButtonTitle: String {
        if !sageReady {
            return sageDetected ? "Connect SAGE" : "Install SAGE"
        }
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
        if !sageReady {
            return sageDetected
                ? "Launch SAGE, complete its setup, then click Recheck so QuietType can register quiettype-agent."
                : "QuietType requires SAGE BFT-governed memory before dictation can start."
        }
        if !permissionsReady {
            return "QuietType will ask macOS for the permissions it needs."
        }
        if !trainingComplete {
            return "Voice training is still open. You can dictate now, but training improves names, acronyms, and technical terms."
        }
        if isRecording {
            return "Speak naturally, then press \(hotKeyLabel) or click the mic again to insert."
        }
        if nativeSpeechServerReady {
            return "Ready for private Apple Silicon dictation. Text inserts automatically."
        }
        if fallbackSpeechReady {
            return "Native speech is warming. QuietType will wait instead of using the lower-quality fallback."
        }
        return "Secure transcription is starting in the background."
    }

    var startupSummary: String {
        if nativeSpeechServerReady {
            return "Native speech ready"
        }
        if fallbackSpeechReady {
            return "Native warming"
        }
        return "Startup running"
    }

    var permissionsReady: Bool {
        microphonePermission == .granted && accessibilityPermission == .granted
    }

    var sageReady: Bool {
        sageDetected && sageDirectClient != nil && sageAgentStatus == "Registered"
    }

    var canSaveCorrection: Bool {
        !teachRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var lessonPreviewText: String {
        let raw = teachRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !corrected.isEmpty else {
            return teachingKind.emptyPreview
        }
        switch teachingKind {
        case .correction, .translation:
            return "Next time QuietType hears \"\(raw)\", it will prefer \"\(corrected)\" during local cleanup."
        case .vocabulary:
            return "\"\(corrected)\" will be treated as the exact spelling. \"\(raw)\" is saved as a spoken form."
        case .style:
            return "QuietType will remember this writing preference for future local dictation."
        }
    }

    var currentCalibrationSet: CalibrationSet {
        CalibrationSet.defaults[calibrationSetIndex % CalibrationSet.defaults.count]
    }

    var trainingComplete: Bool {
        calibrationSavedCount >= Self.requiredCalibrationSets
    }

    var setupComplete: Bool {
        sageReady && permissionsReady && speechEngineReady && trainingComplete
    }

    var trainingProgressLabel: String {
        "\(min(calibrationSavedCount, Self.requiredCalibrationSets)) of \(Self.requiredCalibrationSets)"
    }

    var trainingSetupProgress: Double {
        Double(min(calibrationSavedCount, Self.requiredCalibrationSets)) / Double(Self.requiredCalibrationSets)
    }

    var trainingCompletionText: String {
        if trainingComplete {
            return "Setup training complete"
        }
        let remaining = max(0, Self.requiredCalibrationSets - calibrationSavedCount)
        return "\(remaining) \(remaining == 1 ? "set" : "sets") left"
    }

    var personalizationLabel: String {
        "\(personalizationPercent)%"
    }

    var wordsProcessedLabel: String {
        abbreviatedCount(processedWordCount)
    }

    var lastDictationDurationLabel: String {
        if isRecording {
            return String(format: "%.1fs", recordingDuration)
        }
        guard lastDictationDuration > 0 else {
            return "Ready"
        }
        return String(format: "%.1fs", lastDictationDuration)
    }

    var currentSessionWordCount: Int {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : wordCount(trimmed)
    }

    var currentWordsPerMinuteLabel: String {
        let words = currentSessionWordCount
        let duration = isRecording ? recordingDuration : lastDictationDuration
        guard words > 0, duration > 0.25 else {
            return "Ready"
        }
        return "\(Int((Double(words) / duration) * 60.0)) WPM"
    }

    var correctionSignalLabel: String {
        let corrections = sageCorrectionCount
        let notes = max(transcriptNoteCount, 1)
        guard transcriptNoteCount > 0 else {
            return "No reviews"
        }
        let rate = min(100, Int((Double(corrections) / Double(notes)) * 100.0))
        return "\(rate)% reviewed"
    }

    var setupNudgeText: String {
        if !sageReady {
            return sageDetected
                ? "Launch SAGE, complete its setup, and register quiettype-agent before dictation starts."
                : "Install SAGE first. QuietType uses SAGE BFT-governed memory for corrections, vocabulary, and transcript notes."
        }
        if !permissionsReady {
            return "Grant Microphone and Accessibility, then complete \(Self.requiredCalibrationSets) short voice training sets."
        }
        if !trainingComplete {
            let remaining = max(0, Self.requiredCalibrationSets - calibrationSavedCount)
            return "Complete \(remaining) more voice training \(remaining == 1 ? "set" : "sets") so QuietType can preserve your terms and corrections."
        }
        if !speechEngineReady {
            return "The local speech engine is still warming. QuietType will finish setup when it is ready."
        }
        return "Setup is complete."
    }

    var resumeSetupLabel: String {
        if !sageReady {
            return sageDetected ? "Connect SAGE" : "Install SAGE"
        }
        if !permissionsReady {
            return "Start setup"
        }
        if !speechEngineReady {
            return "Continue setup"
        }
        if !trainingComplete {
            return "Resume training"
        }
        return "Review setup"
    }

    var trainingButtonTitle: String {
        if isTrainingAnalyzing {
            return "Saving"
        }
        if isTrainingRecording {
            return "Stop training"
        }
        return "Record training"
    }

    var trainingStatusText: String {
        if isTrainingAnalyzing {
            return "Learning locally"
        }
        if isTrainingRecording {
            return "Listening locally"
        }
        if !trainingTranscriptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Last sample analyzed locally"
        }
        return "Ready to record"
    }

    var trainingDurationText: String {
        if isTrainingRecording || trainingDuration > 0 {
            return String(format: "%.1fs", trainingDuration)
        }
        return "0.0s"
    }

    var trainingFootnote: String {
        let kept = min(trainingPairCount, Self.maxTrainingPairCount)
        if isTrainingAnalyzing {
            return "Checking terms and saving your local sample."
        }
        if isTrainingRecording {
            return "Audio stays local. Stop when you finish the script."
        }
        if kept == 0 {
            return "QuietType keeps up to \(Self.maxTrainingPairCount) local training pairs."
        }
        return "\(kept) of \(Self.maxTrainingPairCount) local training pairs kept."
    }

    private var personalizationPercent: Int {
        var score = sageReady ? 20 : 0
        if permissionsReady {
            score += 20
        }
        if speechEngineReady {
            score += 20
        }
        let training = min(calibrationSavedCount, Self.requiredCalibrationSets)
        score += Int((Double(training) / Double(Self.requiredCalibrationSets)) * 40.0)
        return min(100, score)
    }

    var sageLessonCount: Int {
        localMemories.filter { $0.type != .transcriptNote }.count
            + sageMemories.filter { $0.domain != "quiettype.transcripts" }.count
    }

    var sageCorrectionCount: Int {
        localMemories.filter { $0.type == .correction }.count
            + sageMemories.filter { $0.content.localizedCaseInsensitiveContains("correction") }.count
    }

    var transcriptNoteCount: Int {
        localMemories.filter { $0.type == .transcriptNote }.count
            + sageMemories.filter { $0.domain == "quiettype.transcripts" }.count
    }

    private var processedWordCount: Int {
        totalTranslatedWordCount
    }

    var dictionaryMemories: [DictionaryMemoryItem] {
        let localItems = localMemories.map { memory in
            DictionaryMemoryItem(
                id: memory.id ?? UUID().uuidString,
                title: memory.payload["corrected"]
                    ?? memory.payload["preferred"]
                    ?? memory.payload["polished_text"]?.prefix(64).description
                    ?? memory.type.rawValue,
                summary: memorySummary(from: memory),
                kind: memory.type.rawValue.replacingOccurrences(of: "dictation.", with: "").replacingOccurrences(of: "_", with: " ").capitalized,
                confidence: memory.confidence,
                source: memory.source.isEmpty ? "SAGE · QuietType" : memory.source,
                rawTranscript: memory.payload["raw_transcript"],
                polishedText: memory.payload["polished_text"],
                isEditableTranscript: memory.type == .transcriptNote
            )
        }

        let sageItems = sageMemories.map { memory in
            DictionaryMemoryItem(
                id: memory.id,
                title: memoryTitle(from: memory.content),
                summary: memory.content.isEmpty ? "Memory content unavailable." : memory.content,
                kind: memory.domain.replacingOccurrences(of: "quiettype.", with: "").capitalized,
                confidence: memory.confidence,
                source: memory.submittingAgent == sageAgentID ? "SAGE · QuietType" : "SAGE",
                rawTranscript: nil,
                polishedText: nil,
                isEditableTranscript: false
            )
        }

        return localItems + sageItems
    }

    var filteredDictionaryMemories: [DictionaryMemoryItem] {
        switch memoryFilter {
        case .all:
            return dictionaryMemories
        case .vocabulary:
            return dictionaryMemories.filter { $0.kind.localizedCaseInsensitiveContains("Vocabulary") }
        case .corrections:
            return dictionaryMemories.filter {
                $0.kind.localizedCaseInsensitiveContains("Correction")
                    || $0.summary.localizedCaseInsensitiveContains("prefer")
            }
        case .sage:
            return dictionaryMemories.filter { $0.source.localizedCaseInsensitiveContains("SAGE") }
        case .local:
            return dictionaryMemories.filter { $0.source.localizedCaseInsensitiveContains("Session") }
        }
    }

    private static let defaultMemorySearchQuery = "QuietType dictation translation correction vocabulary spelling style transcript transcription spoken phrase preferred wording"

    private func memoryTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Memory"
        }
        if let arrowRange = trimmed.range(of: "prefer ") {
            let preferred = trimmed[arrowRange.upperBound...]
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if !preferred.isEmpty {
                return preferred
            }
        }
        let firstSentence = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        return String(firstSentence.prefix(64))
    }

    private func memorySummary(from memory: DictationMemory) -> String {
        switch memory.type {
        case .correction:
            let raw = memory.payload["raw"] ?? ""
            let corrected = memory.payload["corrected"] ?? ""
            return "When spoken text sounds like \"\(raw)\", prefer \"\(corrected)\"."
        case .vocabulary:
            let term = memory.payload["preferred"] ?? memory.payload["term"] ?? ""
            return "Preserve the spelling \"\(term)\" when it appears in dictation."
        case .styleProfile:
            return memory.payload["rule"] ?? "Writing style preference."
        case .formattingPreference:
            return memory.payload["rule"] ?? "Formatting preference."
        case .transcriptNote:
            let raw = memory.payload["raw_transcript"] ?? ""
            let polished = memory.payload["polished_text"] ?? ""
            return "Raw: \"\(raw)\". Polished: \"\(polished)\"."
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split { character in
            character.isWhitespace || character.isNewline
        }.count
    }

    private func abbreviatedCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return "\(value / 1_000)K"
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    private static func loadSessionsToday() -> Int {
        let today = sessionDateString()
        guard UserDefaults.standard.string(forKey: sessionsTodayDateKey) == today else {
            UserDefaults.standard.set(today, forKey: sessionsTodayDateKey)
            UserDefaults.standard.set(0, forKey: sessionsTodayKey)
            return 0
        }
        return UserDefaults.standard.integer(forKey: sessionsTodayKey)
    }

    private static func sessionDateString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func recordStartedSession() {
        let today = Self.sessionDateString()
        if UserDefaults.standard.string(forKey: Self.sessionsTodayDateKey) != today {
            sessionsToday = 0
            UserDefaults.standard.set(today, forKey: Self.sessionsTodayDateKey)
        }
        sessionsToday += 1
        UserDefaults.standard.set(sessionsToday, forKey: Self.sessionsTodayKey)
    }

    func setHistoryReviewEnabled(_ enabled: Bool) {
        historyReviewEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.historyReviewEnabledKey)
    }

    func refreshSageStatus() {
        let installation = SageDetector().detect()
        sageDetected = installation.isInstalled
        if !installation.isInstalled {
            sageDirectClient = nil
            sageAgentStatus = "SAGE required"
        }
        sageStatus = installation.isInstalled ? "SAGE detected · registration pending" : "SAGE required"
        updateStartupStep(
            id: "sage",
            detail: installation.isInstalled ? "SAGE app detected. quiettype-agent registration is pending." : "SAGE not found. QuietType requires SAGE governed memory.",
            state: installation.isInstalled ? .ready : .warning
        )
    }

    func refreshSpeechEngineStatus() {
        fallbackSpeechReady = LocalASRDiscovery().commandBackend() != nil

        speechEngineReady = nativeSpeechServerReady

        if nativeSpeechServerReady {
            speechEngineStatus = "Native speech ready"
        } else if fallbackSpeechReady {
            speechEngineStatus = "Native speech warming"
        } else if WhisperKitServerBundleLocator.bundledExecutable() != nil {
            speechEngineStatus = "Native speech starting"
        } else {
            speechEngineStatus = "Native speech unavailable"
        }

        updateStartupStep(
            id: "fallbackSpeech",
            detail: fallbackSpeechReady ? "Diagnostic fallback is installed, but normal dictation waits for native WhisperKit." : "No diagnostic fallback found.",
            state: fallbackSpeechReady ? .warning : .warning
        )
    }

    func refreshPermissions(promptForAccessibility: Bool = false, verifyMicrophoneAccess: Bool = false) async {
        let snapshot = await permissionService.snapshot(
            promptForAccessibility: promptForAccessibility,
            verifyMicrophoneAccess: verifyMicrophoneAccess
        )
        if snapshot.microphone == .granted {
            microphoneAccessVerified = true
            microphonePermission = .granted
        } else {
            microphoneAccessVerified = false
            microphonePermission = snapshot.microphone
        }
        accessibilityPermission = snapshot.accessibility
        updatePermissionsStartupStep()
    }

    func refreshSystemMetrics() {
        cpuUsagePercent = cpuSampler.sample()
    }

    func requestMicrophone() async {
        microphonePermission = await permissionService.requestMicrophone()
        await refreshPermissions(promptForAccessibility: false, verifyMicrophoneAccess: true)
    }

    func requestAccessibility() {
        accessibilityPermission = permissionService.requestAccessibility()
        Task {
            await refreshPermissions(promptForAccessibility: true)
        }
    }

    func checkForUpdatesAndInstall() async {
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        updateStatus = "Checking GitHub Releases..."
        defer { isCheckingForUpdates = false }

        do {
            let result = try await updateService.checkDownloadBackupAndInstall()
            updateStatus = result.message
        } catch {
            updateStatus = "Update check failed: \(error.localizedDescription)"
        }
    }

    func installSage() async {
        guard !isInstallingSage else {
            return
        }

        isInstallingSage = true
        defer { isInstallingSage = false }

        let installation = SageDetector().detect()
        if installation.isInstalled {
            sageInstallStatus = "Starting bundled SAGE. Complete SAGE setup or unlock its vault, then QuietType will register quiettype-agent."
            startSageIfInstalled(at: installation.appPath)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await registerSageAgentIfAvailable()
            return
        }

        sageInstallStatus = "Downloading SAGE from the official GitHub release..."

        do {
            let result = try await sageInstaller.downloadAndOpen()
            sageInstallStatus = result.message
            refreshSageStatus()
        } catch {
            sageInstallStatus = "Could not download SAGE automatically: \(error.localizedDescription). Opening the SAGE release page."
            sageInstaller.openReleasesPage()
        }
    }

    func recheckSage() async {
        refreshSageStatus()
        await registerSageAgentIfAvailable()
    }

    func startAppServices() {
        guard !didStartAppServices else {
            return
        }
        didStartAppServices = true
        isBooting = true

        Task {
            refreshSystemMetrics()
            refreshSageStatus()
            await registerSageAgentIfAvailable()
            await refreshPermissions(promptForAccessibility: false)
            refreshSpeechEngineStatus()
            registerGlobalHotKey()
            startNativeSpeechWarmup()
        }
    }

    func shutdownAppServices() {
        trainingCaptureService?.stop()
        trainingCaptureService = nil
        hotKeyController?.unregister()
        hotKeyController = nil
        functionKeyMonitor?.unregister()
        functionKeyMonitor = nil
        overlayController.hide()
        nativeSpeechStartupTask?.cancel()
        nativeSpeechStartupTask = nil
        whisperKitSupervisor?.stop()
        whisperKitSupervisor = nil
        nativeSpeechServerReady = false
    }

    func setHotKeyChoice(_ choice: HotKeyChoice) {
        guard hotKeyChoice != choice else {
            return
        }
        functionKeySystemUse = FunctionKeySystemUse.current
        hotKeyChoice = choice
        hotKeyLabel = choice.label
        UserDefaults.standard.set(choice.rawValue, forKey: Self.hotKeyChoiceKey)
        registerGlobalHotKey(force: true)
    }

    func setSpellingPreference(_ preference: SpellingPreference) {
        guard spellingPreference != preference else {
            return
        }
        spellingPreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: Self.spellingPreferenceKey)
    }

    func setTeachingKind(_ kind: TeachingKind) {
        guard teachingKind != kind else {
            return
        }

        let previous = teachingKind
        let raw = teachRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
        let isStillDefault = raw.isEmpty
            || (raw == previous.defaultRaw && corrected == previous.defaultCorrected)

        teachingKind = kind
        if isStillDefault {
            teachRaw = kind.defaultRaw
            teachCorrected = kind.defaultCorrected
            teachingContext = kind.defaultContext
        }
    }

    func hotKeyDetail(for choice: HotKeyChoice) -> String {
        switch choice {
        case .function:
            return functionKeySystemUse.conflictsWithQuietType ? "macOS also uses this" : "Recommended"
        case .controlShiftD:
            return functionKeySystemUse.conflictsWithQuietType ? "Recommended fallback" : "Fallback"
        }
    }

    private func registerGlobalHotKey(force: Bool = false) {
        functionKeySystemUse = FunctionKeySystemUse.current

        if force {
            hotKeyController?.unregister()
            hotKeyController = nil
            functionKeyMonitor?.unregister()
            functionKeyMonitor = nil
        }

        guard hotKeyController == nil && functionKeyMonitor == nil else {
            return
        }

        switch hotKeyChoice {
        case .function:
            let monitor = FunctionKeyToggleMonitor { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.toggleFromHotKey()
                }
            }

            do {
                try monitor.register()
                functionKeyMonitor = monitor
                hotKeyLabel = HotKeyChoice.function.label
                statusMessage = functionKeySystemUse.conflictsWithQuietType ? "Fn is shared with macOS" : "Fn shortcut ready"
            } catch {
                lastError = "Could not register Fn shortcut: \(error)"
                hotKeyChoice = .controlShiftD
                hotKeyLabel = HotKeyChoice.controlShiftD.label
                UserDefaults.standard.set(hotKeyChoice.rawValue, forKey: Self.hotKeyChoiceKey)
                registerGlobalHotKey(force: true)
            }

        case .controlShiftD:
            let controller = CarbonHotKeyController(descriptor: .controlShiftD) { [weak self] phase in
                guard phase == .pressed else {
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.toggleFromHotKey()
                }
            }

            do {
                try controller.register()
                hotKeyController = controller
                hotKeyLabel = HotKeyChoice.controlShiftD.label
                statusMessage = "Shortcut ready"
            } catch {
                lastError = "Could not register shortcut: \(error)"
            }
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
            sageDirectClient = nil
            sageDetected = false
            sageAgentStatus = "SAGE required"
            sageStatus = "SAGE required"
            updateStartupStep(
                id: "sage",
                detail: "Install SAGE and complete its setup before using QuietType.",
                state: .warning
            )
            return
        }

        sageDetected = true
        var candidateClient: SageDirectClient?

        do {
            let identity = try SageSigningIdentity.loadOrCreate()
            let client = try SageDirectClient(endpoint: installation.localEndpoint, identity: identity)
            candidateClient = client
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
            await refreshDictionaryMemories()
        } catch {
            sageDirectClient = nil
            let sageHealthReachable = await candidateClient?.isHealthy() ?? false
            if isSageVaultLocked(error) {
                sageAgentStatus = "Unlock SAGE"
                sageStatus = "SAGE locked · unlock required"
            } else if isSageNotRunning(error) {
                if let candidateClient, sageHealthReachable {
                    sageDirectClient = candidateClient
                    sageAgentStatus = "SAGE setup needed"
                    sageStatus = "SAGE running · setup needed"
                } else {
                    sageAgentStatus = "Starting SAGE"
                    sageStatus = "SAGE installed · starting local node"
                    startSageIfInstalled(at: installation.appPath)
                }
            } else {
                sageAgentStatus = "Registration needed"
                sageStatus = "SAGE detected · registration failed"
            }
            updateStartupStep(
                id: "sage",
                detail: sageRegistrationFailureDetail(error, healthy: sageHealthReachable),
                state: .warning
            )
        }
    }

    private func sageRegistrationFailureDetail(_ error: Error, healthy: Bool = false) -> String {
        if isSageVaultLocked(error) {
            return "SAGE is running, but its encrypted vault appears locked. Open SAGE and unlock it, then click Recheck."
        }
        if isSageNotRunning(error) {
            if healthy {
                return "SAGE is running, but setup or the memory API is not ready. Open SAGE, finish setup, then click Recheck."
            }
            return "SAGE is installed but the local node is not responding. QuietType is attempting to start SAGE."
        }
        return "SAGE detected, but quiettype-agent registration failed: \(error.localizedDescription)"
    }

    private func isSageVaultLocked(_ error: Error) -> Bool {
        if case SageDirectClientError.requestFailed(let status, let body) = error {
            let lowered = body.lowercased()
            return status == 401
                || status == 423
                || lowered.contains("locked")
                || lowered.contains("unlock")
                || lowered.contains("vault")
                || lowered.contains("encrypted")
        }
        return false
    }

    private func handleSageMemoryRefreshFailure(_ error: Error) {
        if isSageVaultLocked(error) {
            sageDirectClient = nil
            sageAgentStatus = "Unlock SAGE"
            sageStatus = "SAGE locked · unlock required"
            statusMessage = "Unlock SAGE"
            lastError = nil
            updateStartupStep(
                id: "sage",
                detail: "Open SAGE and unlock its vault before QuietType can load dictation memory.",
                state: .warning
            )
            return
        }

        if isSageNotRunning(error) {
            sageDirectClient = nil
            sageAgentStatus = "Starting SAGE"
            sageStatus = "SAGE installed · starting local node"
            statusMessage = "Starting SAGE memory"
            lastError = nil
            let installation = SageDetector().detect()
            if installation.isInstalled {
                startSageIfInstalled(at: installation.appPath)
            }
            updateStartupStep(
                id: "sage",
                detail: "SAGE is installed, but the local memory node is not responding yet. QuietType is starting it.",
                state: .warning
            )
            return
        }

        if case SageDirectClientError.requestFailed(let status, _) = error {
            sageAgentStatus = "SAGE setup needed"
            sageStatus = "SAGE memory unavailable"
            statusMessage = "SAGE setup needed"
            lastError = status == 404
                ? "SAGE is running, but its memory API is not ready. Open SAGE and finish setup, then click Recheck."
                : "SAGE memory is not ready. Open SAGE, finish setup or unlock its vault, then click Recheck."
            updateStartupStep(
                id: "sage",
                detail: lastError ?? "SAGE memory is not ready.",
                state: .warning
            )
            return
        }

        statusMessage = "SAGE memory not ready"
        lastError = "SAGE memory is not ready. Open SAGE, finish setup or unlock its vault, then click Recheck."
    }

    private func isSageNotRunning(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorNotConnectedToInternet
            ].contains(nsError.code)
        }
        if case SageDirectClientError.requestFailed(let status, _) = error {
            return status == 0 || status == 502 || status == 503
        }
        return false
    }

    private func startSageIfInstalled(at appPath: String) {
        guard sageServeProcess == nil else {
            return
        }

        let appURL = URL(fileURLWithPath: appPath)
        let bundledExecutable = appURL.appendingPathComponent("Contents/MacOS/sage-gui").path
        let candidates = [
            bundledExecutable,
            "/opt/homebrew/bin/sage-gui",
            "/usr/local/bin/sage-gui"
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            if FileManager.default.fileExists(atPath: appURL.path) {
                NSWorkspace.shared.open(appURL)
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            sageServeProcess = process
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await self?.registerSageAgentIfAvailable()
            }
        } catch {
            lastError = "Could not start SAGE automatically: \(error.localizedDescription)"
        }
    }

    func refreshSageMemories() async {
        guard sageReady, let sageDirectClient else {
            if sageDetected {
                await registerSageAgentIfAvailable()
            }
            return
        }
        isQueryingSage = true
        defer {
            isQueryingSage = false
        }

        do {
            sageMemories = try await sageDirectClient.searchMemories(query: Self.defaultMemorySearchQuery, limit: 16)
            if sageMemories.isEmpty {
                sageMemories = try await sageDirectClient.listMemories(limit: 16)
            }
            if lastError?.hasPrefix("SAGE memory") == true {
                lastError = nil
            }
        } catch {
            handleSageMemoryRefreshFailure(error)
        }
    }

    func refreshLocalMemories() async {
        localMemories = []
    }

    func refreshDictionaryMemories() async {
        if sageDirectClient == nil {
            await registerSageAgentIfAvailable()
        } else {
            await refreshSageMemories()
        }
    }

    func searchSageMemories() async {
        guard sageReady, let sageDirectClient else {
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
            sageMemories = try await sageDirectClient.searchMemories(query: query, limit: 16)
        } catch {
            handleSageMemoryRefreshFailure(error)
        }
    }

    func searchDictionaryMemories() async {
        await searchSageMemories()
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
        speechEngineStatus = "Native speech starting"

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
                    ? "Native engine is warming in the background. Diagnostic fallback is installed but not used for normal dictation."
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
                detail: fallbackSpeechReady ? "Native engine is not ready yet. QuietType will wait instead of using the diagnostic fallback." : detail,
                state: .failed
            )
            lastError = fallbackSpeechReady ? "Native WhisperKit is unavailable. QuietType did not use the lower-quality fallback." : detail
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
        await refreshPermissions(promptForAccessibility: false, verifyMicrophoneAccess: true)
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

        output = ""
        lastError = nil
        statusMessage = ""
        capturedFrameCount = 0
        partialChunkCount = 0
        inputLevel = 0
        peakInputLevel = 0
        recordingDuration = 0
        recordedSamples = []
        recordingSampleRate = 16_000
        chunker = StreamingWavChunker(sampleRate: recordingSampleRate, chunkDurationSeconds: 1.0, maxDurationSeconds: Self.maxDictationDurationSeconds)
        activeTranscriptionOptions = currentTranscriptionOptions()
        streamingTranscriptionSession = nil
        pendingStreamingChunks = []
        try? FileManager.default.removeItem(at: chunkDirectory)
        lastRecordingURL = nil
        recordingStartedAt = Date()

        let service = AVAudioCaptureService { [weak self] frame in
            await self?.record(frame)
        }

        do {
            try service.start()
            captureService = service
            microphoneAccessVerified = true
            microphonePermission = .granted
            updatePermissionsStartupStep()
            isRecording = true
            recordStartedSession()
            statusMessage = "Listening locally"
            overlayController.show(state: .listening, level: inputLevel, detail: listeningOverlayDetail)
        } catch {
            captureService = nil
            recordingStartedAt = nil
            isRecording = false
            microphoneAccessVerified = false
            microphonePermission = .denied
            updatePermissionsStartupStep()
            lastError = "Could not start microphone: \(error)"
            statusMessage = "Microphone permission needed"
        }
    }

    private func prepareForDictation() async -> Bool {
        lastError = nil
        statusMessage = "Checking setup"

        guard await ensureSageReadyForDictation() else {
            return false
        }

        if microphonePermission != .granted {
            microphonePermission = await permissionService.requestMicrophone()
        }

        if accessibilityPermission != .granted {
            accessibilityPermission = permissionService.requestAccessibility()
        }

        await refreshPermissions(promptForAccessibility: true, verifyMicrophoneAccess: true)

        guard microphonePermission == .granted else {
            statusMessage = "Waiting for microphone"
            lastError = "Allow Microphone in System Settings so QuietType can capture local audio."
            return false
        }

        guard accessibilityPermission == .granted else {
            statusMessage = "Waiting for macOS permissions"
            lastError = "Allow Accessibility so QuietType can insert polished text into the active app."
            return false
        }

        await prepareNativeSpeechServerIfAvailable()
        guard nativeSpeechServerReady else {
            statusMessage = "Native speech warming"
            lastError = "QuietType is waiting for the Apple Silicon speech engine. It will not use the lower-quality fallback for normal dictation."
            return false
        }

        return true
    }

    private func ensureSageReadyForDictation() async -> Bool {
        if sageReady {
            return true
        }

        await recheckSage()
        if sageReady {
            return true
        }

        if sageDetected {
            statusMessage = "SAGE setup needed"
            if sageAgentStatus == "Unlock SAGE" {
                lastError = "QuietType requires SAGE governed memory. Open SAGE and unlock the encrypted vault, then click Recheck."
            } else {
                lastError = "QuietType requires SAGE governed memory. Launch SAGE, complete its setup, then click Recheck so quiettype-agent can register."
            }
        } else {
            statusMessage = "Install SAGE"
            lastError = "QuietType requires SAGE governed memory before dictation can start. Install SAGE, complete its setup, then return to QuietType."
        }
        return false
    }

    func stopRecording() async {
        captureService?.stop()
        captureService = nil
        isRecording = false
        lastDictationDuration = recordingDuration
        overlayController.show(state: .processing)

        let durationText = String(format: "%.1f", recordingDuration)
        if capturedFrameCount == 0 {
            output = "I could not detect microphone audio. Check your input device and microphone permission."
            statusMessage = "No audio captured"
            overlayController.hide()
            return
        }
        if peakInputLevel < 0.003 {
            output = "QuietType could open the microphone, but the input signal was too low to transcribe."
            statusMessage = "No usable microphone signal"
            lastError = "Check the selected input device in macOS Sound settings, then try again."
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
                pendingStreamingChunks.append(finalChunk)
                await activateStreamingIfUseful()
            } else {
                statusMessage = "Saved \(url.lastPathComponent)"
            }
            lastError = nil
            let session = recordingDuration >= Self.streamingTranscriptMinimumDuration ? streamingTranscriptionSession : nil
            await transcribeAndProcess(url, streamingSession: session)
            streamingTranscriptionSession = nil
            pendingStreamingChunks = []
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
        if let recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        inputLevel = min(1.0, rms * 24)
        peakInputLevel = max(peakInputLevel, inputLevel)

        do {
            let chunks = try chunker.append(frame, outputDirectory: chunkDirectory)
            partialChunkCount += chunks.count
            if let last = chunks.last {
                lastRecordingURL = last.url
                statusMessage = "Streaming chunk \(last.sequence + 1)"
            }
            pendingStreamingChunks.append(contentsOf: chunks)
            await activateStreamingIfUseful()
        } catch {
            lastError = "Could not write audio chunk: \(error)"
        }

        if chunker.reachedMaxDuration && isRecording {
            statusMessage = "5 minute limit reached"
            await stopRecording()
            return
        }

        if isRecording {
            overlayController.show(state: .listening, level: inputLevel, detail: listeningOverlayDetail)
        }
    }

    private var listeningOverlayDetail: String {
        "Listening · \(String(format: "%.1f", recordingDuration))s"
    }

    private func activateStreamingIfUseful() async {
        guard nativeSpeechServerReady, recordingDuration >= Self.streamingTranscriptMinimumDuration else {
            return
        }

        if streamingTranscriptionSession == nil {
            streamingTranscriptionSession = StreamingAudioTranscriptionSession(
                transcriber: WhisperKitServerTranscriber(timeoutSeconds: 10.0),
                options: .none
            )
        }

        guard let streamingTranscriptionSession else {
            return
        }

        let chunks = pendingStreamingChunks
        pendingStreamingChunks.removeAll(keepingCapacity: true)
        for chunk in chunks {
            await streamingTranscriptionSession.enqueue(chunk)
        }
    }

    private func transcribeAndProcess(_ audioURL: URL, streamingSession: StreamingAudioTranscriptionSession? = nil) async {
        do {
            isRunning = true
            await prepareNativeSpeechServerIfAvailable()
            guard nativeSpeechServerReady else {
                throw AudioTranscriberError.allBackendsFailed([
                    "Native WhisperKit is unavailable. QuietType did not use the lower-quality diagnostic fallback."
                ])
            }
            statusMessage = "Transcribing locally"
            overlayController.show(state: .processing)
            output = """
            Transcribing local audio...

            QuietType captured \(String(format: "%.1f", recordingDuration))s of audio and is running \(speechEngineStatus.lowercased()).
            """
            defer { isRunning = false }
            let streamResult = await streamingSession?.finish()
            let rawTranscript: String
            if let streamResult, isUsableStreamingTranscript(streamResult.text, chunkCount: streamResult.chunkCount) {
                rawTranscript = streamResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                statusMessage = "Processed \(streamResult.chunkCount) streamed chunks"
            } else {
                if let streamResult, !streamResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusMessage = "Resolving full audio"
                }
                rawTranscript = try await makeAudioTranscriber().transcribe(audioFile: audioURL, options: activeTranscriptionOptions)
            }
            guard !isLikelyNoiseTranscript(rawTranscript) else {
                throw AudioTranscriberError.noiseOnlyTranscript(rawTranscript)
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
            } else if isEmptyTranscriptFailure(error) {
                output = "QuietType captured audio, but native speech returned no transcript."
                statusMessage = "No transcript returned"
            } else {
                output = "Captured local audio at:\n\(audioURL.path)"
                statusMessage = speechEngineReady ? "Transcription failed" : "Speech engine unavailable"
            }
            lastError = String(describing: error)
        }
    }

    private func isUsableStreamingTranscript(_ text: String, chunkCount: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        guard recordingDuration >= 6.0 else {
            return false
        }

        let words = wordCount(trimmed)
        if recordingDuration >= 2.5 && words <= 1 {
            return false
        }
        if chunkCount >= 3 && words <= 1 {
            return false
        }
        if recordingDuration >= 4.0 && words < max(2, Int(recordingDuration / 3.0)) {
            return false
        }
        return !isLikelyNoiseTranscript(trimmed)
    }

    private func isLikelyNoiseTranscript(_ text: String) -> Bool {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        guard !trimmed.isEmpty else {
            return true
        }

        if WhisperCommandASRBackend.isNoiseOnlyTranscript(trimmed) {
            return true
        }

        let lowered = trimmed.lowercased()
        let tinyHallucinations: Set<String> = [
            "you",
            "yeah",
            "yes",
            "no",
            "uh",
            "um",
            "hmm",
            "okay",
            "ok",
            "thanks",
            "thank you"
        ]
        return recordingDuration >= 2.5 && tinyHallucinations.contains(lowered)
    }

    private func isLikelyNoiseOnlyFailure(_ error: Error) -> Bool {
        if case AudioTranscriberError.noiseOnlyTranscript(_) = error {
            return true
        }
        if case AudioTranscriberError.allBackendsFailed(let errors) = error {
            return errors.contains { value in
                value.contains("noiseOnlyTranscript")
                    || value.localizedCaseInsensitiveContains("music")
            }
        }
        return false
    }

    private func isEmptyTranscriptFailure(_ error: Error) -> Bool {
        if case AudioTranscriberError.emptyTranscript = error {
            return true
        }
        if case AudioTranscriberError.allBackendsFailed(let errors) = error {
            return errors.contains { value in
                value.contains("emptyTranscript")
            }
        }
        return false
    }

    private func makeAudioTranscriber() -> AudioFileTranscribing {
        guard nativeSpeechServerReady else {
            return CascadingAudioFileTranscriber([])
        }
        return CascadingAudioFileTranscriber([
            WhisperKitServerTranscriber(timeoutSeconds: 10.0)
        ])
    }

    private func currentDictationProfile() -> DictationProfile {
        var profile = ProfileMemoryCompiler.enrich(.development, with: localMemories)
        profile.spellingPreference = spellingPreference
        return profile
    }

    private func currentTranscriptionOptions() -> AudioTranscriptionOptions {
        AudioTranscriptionOptions(
            initialPrompt: ASRPromptBuilder().prompt(
                for: currentDictationProfile(),
                appName: selectedProfile.appName
            )
        )
    }

    private func prepareNativeSpeechServerIfAvailable() async {
        if nativeSpeechServerReady {
            return
        }

        refreshSpeechEngineStatus()
        startNativeSpeechWarmup()
    }

    private func processTranscript(_ rawTranscript: String) async {
        do {
            let context = AppContext(appName: selectedProfile.appName, profile: selectedProfile.appProfile)
            let bufferInserter = BufferingTextInserter()
            let editor: SemanticEditor = editorMode.makeEditor(model: ollamaModel)
            let controller = DictationSessionController(
                profile: currentDictationProfile(),
                asrBackend: TranscriptASRBackend(transcript: rawTranscript),
                contextCollector: StaticContextCollector(context: context),
                inserter: bufferInserter,
                memoryStore: memoryStore,
                semanticEditor: editor
            )

            try await controller.begin()
            let result = try await controller.finishAndInsert()
            output = result.text
            didInsert = false

            let insertStarted = Date()
            if !previewOnly {
                do {
                    try await ClipboardTextInserter().insert(result.text, into: context)
                    didInsert = true
                    lastError = nil
                } catch {
                    lastError = "Could not insert into the active app. Use Copy transcript."
                }
            }

            let insertLatency = Int(Date().timeIntervalSince(insertStarted) * 1000)
            lastLatencyMS = result.timing.keyReleaseToInsertMS.map { $0 + insertLatency } ?? insertLatency
            let translatedWords = wordCount(result.text)
            totalTranslatedWordCount += translatedWords
            UserDefaults.standard.set(totalTranslatedWordCount, forKey: Self.totalTranslatedWordCountKey)
            statusMessage = didInsert ? "Inserted or ready to copy" : "Ready to copy"
            await saveTranscriptNote(rawTranscript: rawTranscript, polishedText: result.text, inserted: didInsert, latencyMS: result.timing.keyReleaseToInsertMS)
            overlayController.show(state: .inserted, detail: "Ready to copy", transcript: result.text)
            overlayController.hide(after: 18.0)
        } catch {
            output = "Transcript: \(rawTranscript)"
            lastError = String(describing: error)
            overlayController.hide(after: 1.1)
        }
    }

    private func saveTranscriptNote(rawTranscript: String, polishedText: String, inserted: Bool, latencyMS: Int?) async {
        guard historyReviewEnabled else {
            return
        }
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty || !polished.isEmpty else {
            return
        }

        let content = """
        QuietType transcript note for review. App: \(selectedProfile.appName). Inserted: \(inserted ? "yes" : "no"). Raw transcript: "\(raw)". Polished output: "\(polished)". This is review history committed to SAGE, not an automatic correction rule.
        """

        do {
            guard let sageDirectClient else {
                throw QuietTypeSageRequirementError.notConnected
            }
            let submission = try await sageDirectClient.submitTranscriptNote(content: content)
            let memory = DictationMemory(
                id: submission.memoryID,
                type: .transcriptNote,
                payload: [
                    "raw_transcript": raw,
                    "polished_text": polished,
                    "app": selectedProfile.appName,
                    "style": selectedProfile.appProfile.rawValue,
                    "inserted": inserted ? "true" : "false",
                    "latency_ms": latencyMS.map(String.init) ?? "",
                    "created_at": ISO8601DateFormatter().string(from: Date())
                ],
                contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, "dictation_review"],
                source: "SAGE · quiettype-agent",
                confidence: 0.82
            )
            localMemories.insert(memory, at: 0)
            sageMemories.insert(
                SageMemoryRecord(
                    id: submission.memoryID,
                    content: content,
                    domain: "quiettype.transcripts",
                    type: "observation",
                    confidence: 0.82,
                    createdAt: nil,
                    submittingAgent: sageAgentID
                ),
                at: 0
            )
        } catch {
            lastError = "SAGE transcript note failed: \(error.localizedDescription)"
        }
    }

    func updateTranscriptNote(memoryID: String, rawTranscript: String, polishedText: String) async {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            guard let sageDirectClient else {
                throw QuietTypeSageRequirementError.notConnected
            }

            if let index = localMemories.firstIndex(where: { $0.id == memoryID }) {
                localMemories[index].payload["raw_transcript"] = raw
                localMemories[index].payload["polished_text"] = polished
                localMemories[index].payload["reviewed_at"] = ISO8601DateFormatter().string(from: Date())
                localMemories[index].payload["reviewed_by_user"] = "true"
            }

            let content = """
            QuietType reviewed transcript note. SAGE note: \(memoryID). Corrected raw transcript: "\(raw)". Corrected polished output: "\(polished)". User-reviewed notes may create compact correction lessons only when the change is obvious and conservative.
            """
            let submission = try await sageDirectClient.submitTranscriptNote(content: content, confidence: 0.9)
            sageMemories.insert(
                SageMemoryRecord(
                    id: submission.memoryID,
                    content: content,
                    domain: "quiettype.transcripts",
                    type: "observation",
                    confidence: 0.9,
                    createdAt: nil,
                    submittingAgent: sageAgentID
                ),
                at: 0
            )

            if let lesson = await saveDerivedCorrectionLesson(fromRaw: raw, polished: polished, memoryID: memoryID) {
                statusMessage = "Review saved and learned \(lesson.corrected)"
            } else {
                statusMessage = "Transcript review saved"
            }
            lastError = nil
        } catch {
            lastError = "Transcript review failed: \(error.localizedDescription)"
        }
    }

    private func saveDerivedCorrectionLesson(fromRaw raw: String, polished: String, memoryID: String) async -> (raw: String, corrected: String)? {
        guard let correction = deriveSingleCorrection(raw: raw, polished: polished) else {
            return nil
        }

        do {
            guard let sageDirectClient else {
                throw QuietTypeSageRequirementError.notConnected
            }
            let content = "QuietType correction: when spoken text is \"\(correction.raw)\", prefer \"\(correction.corrected)\". Source: reviewed transcript \(memoryID). Apply during local dictation cleanup only."
            let submission = try await sageDirectClient.submitTranslationMemory(content: content, confidence: 0.93)
            let memory = DictationMemory(
                id: submission.memoryID,
                type: .correction,
                payload: [
                    "raw": correction.raw,
                    "corrected": correction.corrected,
                    "kind": "review_correction",
                    "context": "reviewed transcript \(memoryID)"
                ],
                contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, "review_correction"],
                source: "SAGE · quiettype-agent",
                confidence: 0.93
            )
            localMemories.insert(memory, at: 0)
            sageMemories.insert(
                SageMemoryRecord(
                    id: submission.memoryID,
                    content: content,
                    domain: "quiettype.translation",
                    type: "fact",
                    confidence: 0.93,
                    createdAt: nil,
                    submittingAgent: sageAgentID
                ),
                at: 0
            )

            return correction
        } catch {
            return nil
        }
    }

    private func deriveSingleCorrection(raw: String, polished: String) -> (raw: String, corrected: String)? {
        let rawTokens = correctionTokens(from: raw)
        let polishedTokens = correctionTokens(from: polished)
        guard rawTokens.count == polishedTokens.count, !rawTokens.isEmpty else {
            return nil
        }

        let differences = zip(rawTokens, polishedTokens).filter { $0.0 != $0.1 }
        guard differences.count == 1, let difference = differences.first else {
            return nil
        }

        let heard = difference.0
        let corrected = difference.1
        guard heard.count >= 2, corrected.count >= 2 else {
            return nil
        }

        if heard.caseInsensitiveCompare(corrected) == .orderedSame,
           !looksLikePreferredTerm(corrected) {
            return nil
        }

        return (heard, corrected)
    }

    private func correctionTokens(from text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }
            .map { token in
                String(token).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            }
            .filter { !$0.isEmpty }
    }

    private func looksLikePreferredTerm(_ value: String) -> Bool {
        value.uppercased() == value && value.count > 1
            || value.dropFirst().contains { $0.isUppercase }
    }

    func saveCorrection() async {
        guard canSaveCorrection else {
            return
        }

        do {
            guard let sageDirectClient else {
                throw QuietTypeSageRequirementError.notConnected
            }
            let raw = teachRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let corrected = teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = teachingContext.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = "QuietType \(teachingKind.label.lowercased()): when spoken text is \"\(raw)\", prefer \"\(corrected)\". Context: \(context.isEmpty ? selectedProfile.appName : context). Apply this during local dictation cleanup without adding unsupported content."
            let submission = try await sageDirectClient.submitTranslationMemory(content: content)
            let memory = DictationMemory(
                id: submission.memoryID,
                type: teachingKind.memoryType,
                payload: teachingPayload(raw: raw, corrected: corrected, context: context),
                contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, context].filter { !$0.isEmpty },
                source: "SAGE · quiettype-agent",
                confidence: 0.95
            )
            localMemories.insert(memory, at: 0)
            sageMemories.insert(
                SageMemoryRecord(
                    id: submission.memoryID,
                    content: content,
                    domain: "quiettype.translation",
                    type: "fact",
                    confidence: 0.95,
                    createdAt: nil,
                    submittingAgent: sageAgentID
                ),
                at: 0
            )
            statusMessage = "Saved to SAGE"
            didSaveTeachingMemory = true
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    private func teachingPayload(raw: String, corrected: String, context: String) -> [String: String] {
        switch teachingKind {
        case .vocabulary:
            return [
                "term": corrected,
                "preferred": corrected,
                "preferred_spelling": corrected,
                "spoken_forms": raw,
                "kind": teachingKind.rawValue,
                "context": context
            ]
        case .style:
            return [
                "rule": corrected,
                "raw": raw,
                "corrected": corrected,
                "kind": teachingKind.rawValue,
                "context": context
            ]
        case .correction, .translation:
            return [
                "raw": raw,
                "corrected": corrected,
                "kind": teachingKind.rawValue,
                "context": context
            ]
        }
    }

    func advanceCalibrationSet() {
        calibrationSetIndex = (calibrationSetIndex + 1) % CalibrationSet.defaults.count
        trainingDuration = 0
        trainingInputLevel = 0
        peakTrainingInputLevel = 0
        trainingTranscriptDraft = ""
        lastTrainingAudioURL = nil
        statusMessage = "Loaded \(currentCalibrationSet.title)"
    }

    func toggleCalibrationRecording() async {
        if isTrainingRecording {
            await stopCalibrationRecording()
        } else {
            await startCalibrationRecording()
        }
    }

    private func startCalibrationRecording() async {
        guard !isRecording else {
            lastError = "Stop dictation before starting voice training."
            return
        }

        guard await ensureSageReadyForDictation() else {
            return
        }

        if microphonePermission != .granted {
            microphonePermission = await permissionService.requestMicrophone()
            await refreshPermissions(promptForAccessibility: false, verifyMicrophoneAccess: true)
        }

        trainingSamples = []
        trainingSampleRate = 16_000
        trainingFrameCount = 0
        trainingDuration = 0
        trainingInputLevel = 0
        trainingTranscriptDraft = ""
        lastTrainingAudioURL = nil
        trainingStartedAt = Date()

        let service = AVAudioCaptureService { [weak self] frame in
            await self?.recordTraining(frame)
        }

        do {
            try service.start()
            trainingCaptureService = service
            microphoneAccessVerified = true
            microphonePermission = .granted
            updatePermissionsStartupStep()
            isTrainingRecording = true
            statusMessage = "Training locally"
            lastError = nil
        } catch {
            trainingCaptureService = nil
            trainingStartedAt = nil
            isTrainingRecording = false
            microphoneAccessVerified = false
            microphonePermission = .denied
            updatePermissionsStartupStep()
            lastError = "Could not start training microphone: \(error)"
            statusMessage = "Microphone permission needed"
        }
    }

    private func stopCalibrationRecording() async {
        trainingCaptureService?.stop()
        trainingCaptureService = nil
        isTrainingRecording = false

        guard trainingFrameCount > 0 else {
            statusMessage = "No training audio captured"
            lastError = "QuietType could not detect microphone audio for training."
            return
        }
        guard peakTrainingInputLevel >= 0.003 else {
            statusMessage = "No usable training signal"
            lastError = "QuietType could open the microphone, but the input signal was too low for training."
            return
        }

        isTrainingAnalyzing = true
        defer {
            isTrainingAnalyzing = false
        }

        do {
            let directory = trainingDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeID = currentCalibrationSet.id.replacingOccurrences(of: "/", with: "-")
            let audioURL = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(safeID).wav")
            try WavFileWriter.writeMonoPCM16(samples: trainingSamples, sampleRate: trainingSampleRate, to: audioURL)
            lastTrainingAudioURL = audioURL
            statusMessage = "Learning locally"
            let rawTranscript = try? await makeAudioTranscriber().transcribe(audioFile: audioURL, options: currentTranscriptionOptions())
            trainingTranscriptDraft = rawTranscript ?? ""
            await saveCalibrationSet(audioURL: audioURL, rawTranscript: rawTranscript)
        } catch {
            statusMessage = "Training save failed"
            lastError = "Could not save training audio: \(error.localizedDescription)"
        }
    }

    private func recordTraining(_ frame: AudioFrame) async {
        trainingFrameCount += 1
        trainingSampleRate = frame.sampleRate
        trainingSamples.append(contentsOf: frame.samples)

        if let trainingStartedAt {
            trainingDuration = Date().timeIntervalSince(trainingStartedAt)
        }

        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        trainingInputLevel = min(1.0, rms * 24)
        peakTrainingInputLevel = max(peakTrainingInputLevel, trainingInputLevel)

        if trainingDuration >= Self.maxDictationDurationSeconds && isTrainingRecording {
            statusMessage = "5 minute training limit reached"
            await stopCalibrationRecording()
        }
    }

    private func saveCalibrationSet(audioURL: URL? = nil, rawTranscript: String? = nil) async {
        let set = currentCalibrationSet
        do {
            guard let sageDirectClient else {
                throw QuietTypeSageRequirementError.notConnected
            }
            let duration = max(trainingDuration, 0.1)
            let wordCount = Double(set.script.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count)
            let estimatedWPM = Int((wordCount / duration) * 60.0)

            let content = "QuietType voice training set \"\(set.title)\" expects the user to read: \"\(set.script)\". Estimated speech rate: \(estimatedWPM) WPM. Preserve these terms during dictation cleanup: \(set.terms.joined(separator: ", ")). Source: user-approved local calibration committed to SAGE."
            let submission = try await sageDirectClient.submitTranslationMemory(content: content, confidence: 0.93)
            sageMemories.insert(
                SageMemoryRecord(
                    id: submission.memoryID,
                    content: content,
                    domain: "quiettype.translation",
                    type: "fact",
                    confidence: 0.93,
                    createdAt: nil,
                    submittingAgent: sageAgentID
                ),
                at: 0
            )

            let savedMemories = set.terms.enumerated().map { index, term in
                DictationMemory(
                    id: "\(submission.memoryID)-term-\(index)",
                    type: .vocabulary,
                    payload: [
                        "term": term,
                        "preferred": term,
                        "script": set.script,
                        "calibration_set": set.id,
                        "audio_path": audioURL?.path ?? "",
                        "raw_transcript": rawTranscript ?? "",
                        "duration_seconds": String(format: "%.2f", duration),
                        "estimated_wpm": "\(estimatedWPM)"
                    ],
                    contexts: ["voice_calibration", set.title, selectedProfile.appName],
                    source: "SAGE · quiettype-agent",
                    confidence: 0.93
                )
            }
            localMemories.insert(contentsOf: savedMemories.reversed(), at: 0)

            if set.id == "everyday-list" {
                let memory = DictationMemory(
                    id: "\(submission.memoryID)-formatting",
                    type: .formattingPreference,
                    payload: [
                        "rule": "When the user says shopping list, grocery list, we need, or numbered list, prefer clean list formatting with numeric quantities.",
                        "script": set.script,
                        "raw_transcript": rawTranscript ?? "",
                        "estimated_wpm": "\(estimatedWPM)"
                    ],
                    contexts: ["voice_calibration", "list_formatting", selectedProfile.appName],
                    source: "SAGE · quiettype-agent",
                    confidence: 0.94
                )
                localMemories.insert(memory, at: 0)
            }

            if let rawTranscript, !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let note = "QuietType training transcript note for review. Set: \(set.title). Expected script: \"\(set.script)\". Raw local ASR heard: \"\(rawTranscript)\". This is review history, not an automatic correction rule."
                let noteSubmission = try await sageDirectClient.submitTranscriptNote(content: note, confidence: 0.82)
                sageMemories.insert(
                    SageMemoryRecord(
                        id: noteSubmission.memoryID,
                        content: note,
                        domain: "quiettype.transcripts",
                        type: "observation",
                        confidence: 0.82,
                        createdAt: nil,
                        submittingAgent: sageAgentID
                    ),
                    at: 0
                )
                let memory = DictationMemory(
                    id: noteSubmission.memoryID,
                    type: .transcriptNote,
                    payload: [
                        "raw_transcript": rawTranscript,
                        "polished_text": set.script,
                        "app": "Training",
                        "style": "calibration",
                        "inserted": "false",
                        "calibration_set": set.id,
                        "audio_path": audioURL?.path ?? "",
                        "created_at": ISO8601DateFormatter().string(from: Date())
                    ],
                    contexts: ["voice_calibration", "dictation_review", set.title],
                    source: "SAGE · quiettype-agent",
                    confidence: 0.82
                )
                localMemories.insert(memory, at: 0)
            }

            calibrationSavedCount += 1
            UserDefaults.standard.set(calibrationSavedCount, forKey: Self.calibrationSavedCountKey)
            if audioURL != nil {
                trainingPairCount = min(Self.maxTrainingPairCount, trainingPairCount + 1)
                UserDefaults.standard.set(trainingPairCount, forKey: Self.trainingPairCountKey)
                pruneTrainingPairs()
            }

            statusMessage = "Training saved to SAGE"
            lastError = nil
            advanceCalibrationSet()
        } catch {
            lastError = "Training save failed: \(error.localizedDescription)"
        }
    }

    private func trainingDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuietType/Training", isDirectory: true)
    }

    private func pruneTrainingPairs() {
        let directory = trainingDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let sorted = files
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        for file in sorted.dropFirst(Self.maxTrainingPairCount) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        statusMessage = "Copied output"
    }

    func clearOutput() {
        output = ""
        transcript = ""
        didInsert = false
        lastError = nil
        statusMessage = ""
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

    enum HotKeyChoice: String, CaseIterable, Identifiable {
        case function
        case controlShiftD

        var id: String { rawValue }

        var label: String {
            switch self {
            case .function:
                return "Fn"
            case .controlShiftD:
                return "⌃⇧D"
            }
        }

        var detail: String {
            switch self {
            case .function:
                return "Recommended"
            case .controlShiftD:
                return "Fallback"
            }
        }
    }

    enum TeachingKind: String, CaseIterable, Identifiable {
        case correction
        case vocabulary
        case style
        case translation

        var id: String { rawValue }

        var label: String {
            switch self {
            case .correction: "Correction"
            case .vocabulary: "Vocabulary"
            case .style: "Writing style"
            case .translation: "Translation behavior"
            }
        }

        var memoryType: DictationMemoryType {
            switch self {
            case .correction, .translation: .correction
            case .vocabulary: .vocabulary
            case .style: .styleProfile
            }
        }

        var explanation: String {
            switch self {
            case .correction:
                return "Teach QuietType a phrase it heard incorrectly and the spelling or wording it should prefer."
            case .vocabulary:
                return "Add a name, acronym, product, or technical term with the way you usually say it."
            case .style:
                return "Save a reusable writing preference for how QuietType should shape your output."
            case .translation:
                return "Teach a cleanup rule for turning rough dictated phrasing into polished text."
            }
        }

        var rawLabel: String {
            switch self {
            case .correction:
                return "Heard as"
            case .vocabulary:
                return "Spoken form"
            case .style:
                return "Context"
            case .translation:
                return "Rough phrase"
            }
        }

        var correctedLabel: String {
            switch self {
            case .correction:
                return "Prefer"
            case .vocabulary:
                return "Exact spelling"
            case .style:
                return "Preference"
            case .translation:
                return "Polished form"
            }
        }

        var emptyPreview: String {
            switch self {
            case .correction:
                return "Add what QuietType heard and the corrected spelling."
            case .vocabulary:
                return "Add the spoken form and exact spelling."
            case .style:
                return "Add the context and the writing preference."
            case .translation:
                return "Add the rough phrase and preferred polished form."
            }
        }

        var systemImage: String {
            switch self {
            case .correction:
                return "wand.and.stars"
            case .vocabulary:
                return "textformat.abc"
            case .style:
                return "slider.horizontal.3"
            case .translation:
                return "arrow.left.arrow.right"
            }
        }

        var defaultRaw: String {
            switch self {
            case .correction:
                return "Steven"
            case .vocabulary:
                return "steven"
            case .style:
                return "Slack messages"
            case .translation:
                return "rough dictation"
            }
        }

        var defaultCorrected: String {
            switch self {
            case .correction, .vocabulary:
                return "Stephen"
            case .style:
                return "Keep messages concise, direct, and natural."
            case .translation:
                return "Keep the meaning, remove filler, and format cleanly."
            }
        }

        var defaultContext: String {
            switch self {
            case .correction, .vocabulary:
                return "names and spelling"
            case .style:
                return "writing style"
            case .translation:
                return "dictation cleanup"
            }
        }
    }

    enum MemoryFilter: String, CaseIterable, Identifiable {
        case all
        case vocabulary
        case corrections
        case sage
        case local

        static var visibleCases: [MemoryFilter] {
            [.all, .vocabulary, .corrections, .sage]
        }

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .vocabulary: "Vocabulary"
            case .corrections: "Corrections"
            case .sage: "SAGE"
            case .local: "Session"
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
