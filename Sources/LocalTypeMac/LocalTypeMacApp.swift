import LocalTypeCore
import AppKit
import AVFoundation
import CryptoKit
import Darwin
import Foundation
import Security
import SwiftUI
@preconcurrency import UserNotifications

@main
struct LocalTypeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        WindowGroup("QuietType") {
            TesterView(model: model)
        }
        .defaultSize(width: 1360, height: 900)
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
private final class DictationOverlayPanel: NSPanel {
    var cancelAction: (() -> Void)?
    var didMove: ((NSPoint) -> Void)?
    private var dragStartLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var didDrag = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if cancelAction == nil || !cancelHitRect.contains(event.locationInWindow) {
                beginPanelDrag()
            }
            super.sendEvent(event)
        case .leftMouseDragged:
            updatePanelDrag()
            if didDrag {
                return
            }
            super.sendEvent(event)
        case .leftMouseUp:
            if didDrag {
                finishPanelDrag(savePosition: true)
                return
            }
            if cancelAction != nil, cancelHitRect.contains(event.locationInWindow) {
                resetPanelDrag()
                cancelAction?()
                return
            }
            super.sendEvent(event)
            resetPanelDrag()
        default:
            super.sendEvent(event)
        }
    }

    private func beginPanelDrag() {
        dragStartLocation = NSEvent.mouseLocation
        dragStartOrigin = frame.origin
        didDrag = false
    }

    private func updatePanelDrag() {
        guard let dragStartLocation, let dragStartOrigin else {
            return
        }

        let currentLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: currentLocation.x - dragStartLocation.x,
            y: currentLocation.y - dragStartLocation.y
        )
        guard abs(delta.x) > 2 || abs(delta.y) > 2 else {
            return
        }

        didDrag = true
        setFrameOrigin(NSPoint(
            x: dragStartOrigin.x + delta.x,
            y: dragStartOrigin.y + delta.y
        ))
    }

    private func finishPanelDrag(savePosition: Bool) {
        if savePosition {
            didMove?(frame.origin)
        }
        resetPanelDrag()
    }

    private func resetPanelDrag() {
        dragStartLocation = nil
        dragStartOrigin = nil
        didDrag = false
    }

    private var cancelHitRect: NSRect {
        let size = frame.size
        return NSRect(x: size.width - 66, y: size.height - 66, width: 52, height: 52)
    }
}

@MainActor
final class DictationOverlayController {
    private var panel: DictationOverlayPanel?
    private var presentationID = 0
    private let chromeInset: CGFloat = 18
    private static let originXKey = "quiettype.overlayOriginX"
    private static let originYKey = "quiettype.overlayOriginY"

    func show(
        state: OverlayState,
        level: Double = 0,
        detail: String? = nil,
        transcript: String? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        presentationID += 1
        let panel = panel ?? makePanel()
        panel.alphaValue = 1
        let hasTranscript = !(transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAction = onCancel != nil
        panel.cancelAction = onCancel
        panel.ignoresMouseEvents = false
        let isTypingReminder = state.title == OverlayState.typingReminder.title
        let compactWidth: CGFloat = hasAction ? 328 : 280
        let contentSize: NSSize
        if isTypingReminder {
            contentSize = NSSize(width: 430, height: 112)
        } else if hasTranscript {
            contentSize = NSSize(width: 390, height: 154)
        } else {
            contentSize = NSSize(width: compactWidth, height: 82)
        }
        panel.setContentSize(NSSize(
            width: contentSize.width + chromeInset * 2,
            height: contentSize.height + chromeInset * 2
        ))
        let hostingView = NSHostingView(rootView: DictationOverlayView(
            state: state,
            level: level,
            detail: detail,
            transcript: transcript,
            onCancel: onCancel
        ))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide(after delay: TimeInterval = 0) {
        guard let panel else {
            return
        }

        presentationID += 1
        panel.cancelAction = nil
        let hideID = presentationID
        if delay <= 0 {
            panel.alphaValue = 1
            panel.orderOut(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak panel] in
                guard let self, self.presentationID == hideID, let panel else {
                    return
                }

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().alphaValue = 0
                } completionHandler: { [weak self, weak panel] in
                    Task { @MainActor in
                        guard let self, self.presentationID == hideID, let panel else {
                            return
                        }
                        panel.orderOut(nil)
                        panel.alphaValue = 1
                    }
                }
            }
        }
    }

    private func makePanel() -> DictationOverlayPanel {
        let panel = DictationOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let chromeInset = chromeInset
        panel.didMove = { origin in
            UserDefaults.standard.set(origin.x + chromeInset, forKey: Self.originXKey)
            UserDefaults.standard.set(origin.y + chromeInset, forKey: Self.originYKey)
        }
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let storedX = UserDefaults.standard.object(forKey: Self.originXKey) as? Double
        let storedY = UserDefaults.standard.object(forKey: Self.originYKey) as? Double
        if let storedX, let storedY {
            let panelOrigin = NSPoint(x: storedX - chromeInset, y: storedY - chromeInset)
            let storedFrame = NSRect(origin: panelOrigin, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(storedFrame) }) {
                panel.setFrameOrigin(panelOrigin)
                return
            }
        }
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.minY + 110 - chromeInset
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

    static let cancelled = OverlayState(
        title: "Cancelled",
        subtitle: "Discarded locally",
        icon: "xmark.circle.fill",
        tint: .secondary
    )

    static let typingReminder = OverlayState(
        title: "Press Fn and speak",
        subtitle: "QuietType can dictate this faster",
        icon: "keyboard",
        tint: .white
    )
}

private struct DictationOverlayView: View {
    var state: OverlayState
    var level: Double
    var detail: String?
    var transcript: String?
    var onCancel: (() -> Void)?
    @State private var copiedTranscript = false
    private let chromeInset: CGFloat = 18

    private var cleanedTranscript: String {
        (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if state.title == OverlayState.typingReminder.title {
                typingReminderBody
            } else {
                standardBody
            }
        }
        .padding(chromeInset)
    }

    private var typingReminderBody: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 54, height: 54)
                Image(systemName: state.icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(detail ?? state.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(state.subtitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .darkGray).opacity(0.96))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 22, y: 12)
    }

    private var standardBody: some View {
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

                if let onCancel {
                    Spacer(minLength: 0)
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .quickTooltip("Cancel this dictation without inserting text.")
                }
            }

            if !cleanedTranscript.isEmpty {
                Text(cleanedTranscript)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    if copyOverlayTranscript(cleanedTranscript) {
                        copiedTranscript = true
                    }
                } label: {
                    Label(copiedTranscript ? "Copied" : "Copy transcript", systemImage: copiedTranscript ? "checkmark" : "doc.on.doc")
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
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 20, y: 10)
    }

    private func copyOverlayTranscript(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

private struct OverlayWaveform: View {
    var level: Double
    var isActive: Bool

    private let bars = 18

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(opacity(for: index)))
                    .frame(width: 4, height: barHeight(index))
                    .animation(.easeOut(duration: 0.10), value: level)
            }
        }
        .opacity(isActive ? 1 : 0.28)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let phase = abs(Double(index) - Double(bars - 1) / 2.0)
        let shape = 1.0 - min(phase / Double(bars), 0.65)
        let base = isActive ? min(max(level, 0), 1) : 0
        return CGFloat(4 + (base * shape * 18))
    }

    private func opacity(for index: Int) -> Double {
        guard isActive else {
            return 0.20
        }
        let threshold = Int((min(max(level, 0), 1) * Double(bars)).rounded(.up))
        return index < threshold ? 0.78 : 0.16
    }
}

struct TesterView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: MenuBarModel
    @AppStorage("quiettype.hasSeenGuide") private var hasSeenGuide = false
    @AppStorage("quiettype.firstRunAssistantComplete") private var firstRunAssistantComplete = false
    @AppStorage("quiettype.appearanceChoice") private var appearanceChoiceRaw = QuietTypeAppearanceChoice.system.rawValue
    @AppStorage("quiettype.textSizeChoice") private var textSizeChoiceRaw = QuietTypeTextSizeChoice.standard.rawValue
    @AppStorage("quiettype.showTooltips") private var showTooltips = true
    @State private var selectedSection: QuietTypeSection = .home
    @State private var selectedSettingsTab: QuietTypeSettingsTab = .general
    @State private var selectedSetupTab: QuietTypeSetupTab = .overview
    @State private var showingTeachSheet = false
    @State private var showingRecognizedTerms = false
    @State private var pendingReviewDeleteMemory: DictionaryMemoryItem?
    @State private var isDeletingReviewMemory = false
    @State private var guideStep: QuietTypeGuideStep?
    @State private var launchHeroMessageIndex = QuietTypeHeroMessage.randomIndex()
    @State private var launchHeroTextVisible = true
    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let heroMessageTimer = Timer.publish(every: 90, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.setupComplete || firstRunAssistantComplete {
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
        .overlay {
            if model.isUpdateOverlayVisible {
                UpdateInstallOverlay(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearanceChoice.colorScheme)
        .environment(\.quietTypeTypeDelta, textSizeChoice.pointDelta)
        .frame(width: 1360, height: 900)
        .animation(.easeInOut(duration: 0.22), value: selectedSection)
        .animation(.easeInOut(duration: 0.18), value: guideStep)
        .animation(.easeInOut(duration: 0.22), value: model.setupComplete)
        .sheet(isPresented: $showingTeachSheet) {
            TeachQuietTypeSheet(model: model)
        }
        .onAppear {
            model.startAppServices()
            if model.setupComplete {
                firstRunAssistantComplete = true
            }
            if model.setupComplete && firstRunAssistantComplete && !hasSeenGuide {
                guideStep = .welcome
            }
        }
        .onChange(of: model.setupComplete) { isComplete in
            if isComplete {
                firstRunAssistantComplete = true
            }
        }
        .onReceive(permissionTimer) { _ in
            Task {
                model.refreshSystemMetrics()
                await model.refreshPermissions()
            }
        }
        .onReceive(heroMessageTimer) { _ in
            rotateLaunchHeroMessage()
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

    private var launchHeroMessage: QuietTypeHeroMessage {
        QuietTypeHeroMessage.message(at: launchHeroMessageIndex)
    }

    private func rotateLaunchHeroMessage() {
        guard QuietTypeHeroMessage.all.count > 1 else {
            return
        }
        withAnimation(.easeInOut(duration: 0.42)) {
            launchHeroTextVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            launchHeroMessageIndex = QuietTypeHeroMessage.nextIndex(after: launchHeroMessageIndex)
            withAnimation(.easeInOut(duration: 0.48)) {
                launchHeroTextVisible = true
            }
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

    private var isDarkAppearance: Bool {
        colorScheme == .dark
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                appBrandIcon
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
                ForEach(sidebarPrimarySections) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        SidebarItem(icon: section.icon, title: section.title, selected: selectedSection == section)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            sidebarDisplayControls

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
    private var appBrandIcon: some View {
        if let url = Bundle.main.url(forResource: "QuietTypeIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 30, weight: .semibold))
        }
    }

    private var sidebarDisplayControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Display")
                .font(.system(size: 10 + textSizeChoice.pointDelta, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(QuietTypeAppearanceChoice.allCases) { choice in
                        SidebarIconToggle(
                            label: choice.label,
                            selected: appearanceChoice == choice
                        ) {
                            Image(systemName: choice.sidebarSymbol)
                                .font(.system(size: 13, weight: .semibold))
                        } action: {
                            appearanceChoiceRaw = choice.rawValue
                        }
                    }
                }
                .padding(2)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.05), lineWidth: 1))

                HStack(spacing: 2) {
                    ForEach(QuietTypeTextSizeChoice.allCases) { choice in
                        SidebarIconToggle(
                            label: choice.label,
                            selected: textSizeChoice == choice
                        ) {
                            Text("A")
                                .font(.system(size: choice.sidebarGlyphSize, weight: .semibold, design: .rounded))
                        } action: {
                            textSizeChoiceRaw = choice.rawValue
                        }
                    }
                }
                .padding(2)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.05), lineWidth: 1))
            }
        }
        .padding(.bottom, 4)
    }

    private var sidebarPrimarySections: [QuietTypeSection] {
        QuietTypeSection.primary
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            updateAvailableBanner

            ZStack {
                switch selectedSection {
                case .home:
                    homePage
                case .voiceNotes:
                    voiceNotesPage
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var updateAvailableBanner: some View {
        if let update = model.availableUpdate {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("QuietType \(update.versionLabel) is available")
                        .font(.system(size: 14 + textSizeChoice.pointDelta, weight: .semibold))
                    Text("Download and install the signed update when you are ready.")
                        .font(.system(size: 12 + textSizeChoice.pointDelta))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task {
                        await model.checkForUpdatesAndInstall()
                    }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(model.isCheckingForUpdates)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.green.opacity(colorScheme == .dark ? 0.24 : 0.16))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.green.opacity(0.28))
                    .frame(height: 1)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
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
                    title: model.sageReady ? "SAGE memory is ready" : "Set up SAGE governed memory",
                    detail: model.sageReady ? "quiettype-agent is registered. Continue to permissions, speech, and voice training." : model.sageDetected ? "SAGE is installed. Complete SAGE setup, unlock it if needed, then connect quiettype-agent." : "QuietType uses SAGE as its local governed memory layer. Install SAGE before dictation starts.",
                    status: model.sageReady ? "Continue" : model.sageDetected ? "Connect" : "Install",
                    isComplete: false,
                    action: {
                        Task {
                            if model.sageReady {
                                firstRunAssistantComplete = true
                                selectedSection = .home
                            } else if model.sageDetected {
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
            FirstRunMacIllustration(
                stage: firstRunStage,
                model: model,
                primaryAction: firstRunPrimaryIllustrationAction,
                secondaryAction: firstRunSecondaryIllustrationAction
            )
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

    private func firstRunPrimaryIllustrationAction() {
        switch firstRunStage {
        case .sage:
            Task {
                if model.sageReady {
                    firstRunAssistantComplete = true
                    selectedSection = .home
                } else if model.sageDetected {
                    await model.registerSageAgentIfAvailable()
                } else {
                    await model.installSage()
                }
            }
        case .access:
            Task {
                if model.microphonePermission != .granted {
                    await model.requestMicrophone()
                }
                if model.accessibilityPermission != .granted {
                    model.requestAccessibility()
                }
                model.startAppServices()
            }
        case .training:
            Task {
                await model.toggleCalibrationRecording()
            }
        case .experience:
            firstRunAssistantComplete = true
            selectedSection = .home
            if !hasSeenGuide {
                guideStep = .welcome
            }
        }
    }

    private func firstRunSecondaryIllustrationAction() {
        switch firstRunStage {
        case .sage:
            NSWorkspace.shared.open(URL(string: "https://l33tdawg.github.io/sage/")!)
        case .access:
            selectedSection = .help
        case .training:
            model.discardCalibrationRecording()
            firstRunAssistantComplete = true
            selectedSection = .home
        case .experience:
            model.copyOutput()
        }
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
            selectedSetupTab = guideStep == .memory ? .training : suggestedSetupTab
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
                selectedSetupTab = model.setupComplete ? .training : suggestedSetupTab
            }
            .buttonStyle(QuietButtonStyle(prominence: .primary))
            .quickTooltip(model.setupComplete ? "Open voice training so you can add another local sample set." : "Jump to the next setup area QuietType needs before dictation is ready.")
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
                        .foregroundStyle(.primary)
                }
            }

            if model.setupComplete {
                HStack(spacing: 10) {
                    SetupCompletePill(number: "1", title: "SAGE", detail: "Connected")
                    SetupCompletePill(number: "2", title: "Access", detail: "Allowed")
                    SetupCompletePill(number: "3", title: "Engine", detail: "Warm")
                    SetupCompletePill(number: "4", title: "Training", detail: "\(model.trainingProgressLabel) sets")
                }
            } else {
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
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var dictionaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "Review",
                    subtitle: "Review transcripts and teach QuietType corrections."
                )

                dictionaryStats
                memoryLibraryPanel
                    .frame(maxHeight: .infinity)
            }
            .padding(34)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if showingRecognizedTerms {
                RecognizedTermsDrawer(isPresented: $showingRecognizedTerms)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            reviewDeleteConfirmationOverlay
        }
        .task {
            guard model.dictionaryMemories.isEmpty else {
                return
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, model.dictionaryMemories.isEmpty else {
                return
            }
            await model.refreshDictionaryMemories()
        }
    }

    @ViewBuilder
    private var reviewDeleteConfirmationOverlay: some View {
        if let deleteMemory = pendingReviewDeleteMemory {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !isDeletingReviewMemory else {
                            return
                        }
                        pendingReviewDeleteMemory = nil
                    }

                DeleteMemoryConfirmPopover(
                    title: "Remove this memory?",
                    isDeleting: isDeletingReviewMemory,
                    message: "QuietType will ask SAGE to forget this \(deleteMemory.kind.lowercased()) memory and remove it from Review.",
                    onCancel: {
                        pendingReviewDeleteMemory = nil
                    },
                    onDelete: {
                        Task {
                            isDeletingReviewMemory = true
                            await model.deleteReviewMemory(
                                memoryID: deleteMemory.id,
                                hasLocalCopy: deleteMemory.hasLocalCopy,
                                hasSageMemory: deleteMemory.hasSageMemory
                            )
                            isDeletingReviewMemory = false
                            pendingReviewDeleteMemory = nil
                        }
                    }
                )
                .padding(24)
            }
            .transition(.opacity)
            .zIndex(50)
        }
    }

    private var voiceNotesPage: some View {
        nativePage {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    title: "Voice Notes",
                    subtitle: "Record, transcribe, and keep long-term notes on this Mac."
                )

                if model.voiceNotes.isEmpty {
                    VoiceNotesIntroPanel(model: model)
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    voiceNotesWorkspace
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(34)
        }
        .onAppear {
            Task {
                await model.refreshVoiceNotes()
            }
        }
    }

    private var voiceNotesWorkspace: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(model.filteredVoiceNotes.count) notes")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(model.saveVoiceNotesToSage ? "New transcripts copy to SAGE" : "Local encrypted store")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .quickTooltip(model.saveVoiceNotesToSage ? "New voice-note transcripts are copied to SAGE governed memory. Audio remains encrypted locally." : "Voice notes stay in QuietType's encrypted local store unless you manually send a transcript to SAGE.")
                    }
                    Spacer()
                    if model.isVoiceNoteTranscribing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    TextField("Search notes", text: $model.voiceNoteQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.07), lineWidth: 1))
                .quickTooltip("Search saved note titles, raw transcripts, and polished note text.")

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.filteredVoiceNotes) { note in
                            VoiceNoteListRow(
                                note: note,
                                isSelected: model.selectedVoiceNoteID == note.id
                            ) {
                                model.selectedVoiceNoteID = note.id
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .frame(width: 310)
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.58))

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VoiceNoteRecorderStatus(model: model)
                    Spacer()
                    Button {
                        Task {
                            await model.toggleVoiceNoteRecording()
                        }
                    } label: {
                        Label(
                            model.isVoiceNoteRecording ? "Stop" : "Record note",
                            systemImage: model.isVoiceNoteRecording ? "stop.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                    .disabled(model.isVoiceNoteTranscribing || model.isRecording || model.isTrainingRecording || model.isTeachingRecording)
                    .quickTooltip(model.isVoiceNoteRecording ? "Stop recording and transcribe this voice note locally." : "Record a long-form note. Audio is encrypted on this Mac after capture.")
                }

                if let note = model.selectedVoiceNote {
                    VoiceNoteDetailPanel(
                        note: note,
                        isPlaying: model.playingVoiceNoteID == note.id && model.isVoiceNotePlaying,
                        playbackProgress: model.playingVoiceNoteID == note.id ? model.voiceNotePlaybackProgress : 0,
                        playbackDuration: model.playingVoiceNoteID == note.id ? model.voiceNotePlaybackDuration : note.durationSeconds,
                        playbackVolume: model.voiceNotePlaybackVolume,
                        savesToSageByDefault: model.saveVoiceNotesToSage,
                        saveAction: { title, rawTranscript, polishedText in
                            await model.updateVoiceNote(id: note.id, title: title, rawTranscript: rawTranscript, polishedText: polishedText)
                        },
                        deleteAction: {
                            await model.deleteVoiceNote(id: note.id)
                        },
                        sendToSageAction: {
                            await model.sendVoiceNoteToSage(id: note.id)
                        },
                        playAction: {
                            await model.playVoiceNoteAudio(id: note.id)
                        },
                        stopAction: {
                            model.stopCurrentVoiceNoteAudio()
                        },
                        volumeAction: { volume in
                            model.setVoiceNotePlaybackVolume(volume)
                        }
                    )
                    .id(note.id)
                } else {
                    EmptyStatePanel(
                        icon: "waveform.badge.mic",
                        title: "Select a voice note",
                        subtitle: "Choose a saved local note to edit its transcript or send a copy to SAGE."
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var dictionaryStats: some View {
        HStack(spacing: 12) {
            MemoryStatPill(title: "Sessions today", value: "\(model.sessionsToday)", tooltip: "Completed dictation sessions recorded today.")
            MemoryStatPill(title: "Last duration", value: model.lastDictationDurationLabel, tooltip: "Duration of the most recent dictation session.")
            MemoryStatPill(title: "Insert latency", value: model.lastLatencyMS.map { "\($0) ms" } ?? "Warm", tooltip: "Time from finishing dictation to having polished text ready for insertion.")
            MemoryStatPill(title: "Transcriptions", value: "\(model.transcriptNoteCount)", tooltip: "Transcript review notes available for correction and inspection.")
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
                .quickTooltip("Rotate to a different voice-training script with different names, dates, numbers, and terms.")
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
                .quickTooltip(model.isTrainingRecording ? "Stop recording this training sample and analyze it locally." : "Record the visible script so QuietType can learn your cadence and preserve terms.")
                Button {
                    showingRecognizedTerms = true
                } label: {
                    Label("Terms", systemImage: "rectangle.stack.badge.person.crop")
                }
                .buttonStyle(QuietButtonStyle())
                .quickTooltip("Open the recognized-terms drawer to inspect which training terms QuietType detected.")
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
        let reviewMemories = model.filteredDictionaryMemories

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transcript review")
                        .font(.title3.weight(.semibold))
                    Text("Edit transcripts when QuietType hears something wrong.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isQueryingSage {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    model.setTeachingKind(.correction)
                    showingTeachSheet = true
                } label: {
                    Label("Add correction", systemImage: "square.and.pencil")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .quickTooltip("Teach QuietType an exact spelling or correction so future dictation can preserve it.")
                Button("Refresh") {
                    Task {
                        await model.refreshDictionaryMemories()
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .quickTooltip("Reload review memories from local SAGE and QuietType's local transcript index.")
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
                    .onChange(of: model.sageQuery) { _ in
                        model.scheduleDictionarySearch()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .quickTooltip("Search transcripts, correction memories, and SAGE-backed review notes.")

            if reviewMemories.isEmpty {
                EmptyStatePanel(
                    icon: "text.bubble",
                    title: model.sageReady ? "No transcripts yet" : "SAGE setup required",
                    subtitle: model.sageReady ? "QuietType will show transcript reviews and corrections here after dictation." : "QuietType needs SAGE BFT-governed memory before transcript review can run."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(reviewMemories) { memory in
                        DictionaryMemoryRow(memory: memory, saveAction: { rawTranscript, polishedText in
                            await model.updateTranscriptNote(
                                memoryID: memory.id,
                                rawTranscript: rawTranscript,
                                polishedText: polishedText,
                                hasLocalCopy: memory.hasLocalCopy,
                                hasSageMemory: memory.hasSageMemory
                            )
                        }, deleteAction: {
                            pendingReviewDeleteMemory = memory
                        })
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
                    subtitle: "Controls for dictation, SAGE memory, updates, and sharing."
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

                helpFAQPanel

                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
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
                            selectedSection = .setup
                            selectedSetupTab = .access
                            Task {
                                await model.refreshPermissions(verifyMicrophoneAccess: true)
                            }
                        }

                        HelpInfoCard(
                            icon: "lock.shield",
                            title: "How SAGE helps",
                            detail: "SAGE is not a flat file. It is the governed local memory layer where QuietType commits approved spellings, corrections, transcript notes, and style preferences."
                        )

                        HelpActionCard(
                            icon: "brain.head.profile",
                            title: "Improve accuracy",
                            detail: "Add spellings, corrections, and preferred writing style.",
                            actionTitle: "Open Review"
                        ) {
                            selectedSection = .dictionary
                        }
                    }
                }
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
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                Text("Troubleshooting")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                HelpFAQRow(
                    question: "Does anything leave my Mac?",
                    answer: "No dictation content is sent to cloud services. Dictation, cleanup, training samples, and SAGE memory stay local. QuietType contacts GitHub only for signed app/SAGE update checks and downloads."
                )
                HelpFAQRow(
                    question: "Why does QuietType require SAGE?",
                    answer: "SAGE keeps corrections, vocabulary, training hints, and transcript notes auditable and portable with your SAGE identity."
                )
                HelpFAQRow(
                    question: "Microphone is allowed, but QuietType still asks.",
                    answer: "Quit every copy of QuietType, open the app from /Applications, then click Recheck. If it still looks stale, remove the old QuietType entry in macOS Privacy settings and allow it again."
                )
                HelpFAQRow(
                    question: "Nothing is inserted after dictation.",
                    answer: "Open Setup and make sure Accessibility is allowed. QuietType needs Accessibility to paste polished text into the active app."
                )
                HelpFAQRow(
                    question: "Names or technical terms are wrong.",
                    answer: "Open Setup for voice training, then teach exact spellings in Review for project names, acronyms, and product terms."
                )
                HelpFAQRow(
                    question: "What happens while SAGE downloads?",
                    answer: "QuietType opens the SAGE installer and waits for you to install SAGE, launch it, and complete setup. After that, click Recheck."
                )
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
            if next == .memory {
                DispatchQueue.main.async {
                    selectedSetupTab = .training
                }
            }
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
                Text(launchHeroMessage.title)
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(launchHeroMessage.subtitle)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .id(launchHeroMessage.id)
            .opacity(launchHeroTextVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.48), value: launchHeroTextVisible)
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Text(model.hotKeyLabel)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .quickTooltip("Use this shortcut anywhere on your Mac to start or stop QuietType dictation.")
                    Text("start / stop")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                StatusPill(icon: model.speechEngineReady ? "waveform" : "waveform.slash", text: model.speechEngineStatus, tint: .secondary)
                    .quickTooltip("Shows whether the local speech engine is warmed and ready for dictation.")
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            MetricTile(icon: "text.bubble", value: "\(model.sessionsToday)", label: "Sessions today", tooltip: "Completed dictation sessions recorded today on this Mac.")
            MetricTile(icon: "speedometer", value: model.currentWordsPerMinuteLabel, label: "Speaking pace", tooltip: "Words per minute from the current or most recent dictation session.")
            MetricTile(icon: "brain.head.profile", value: "\(model.sageLessonCount)", label: "Reviews", tooltip: "Correction and review memories available through local SAGE.")
            MetricTile(icon: "checklist.checked", value: "\(model.transcriptNoteCount)", label: "Transcriptions", tooltip: "Transcript review notes QuietType can use for correction and inspection.")
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

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    QuietSegmentedControl(
                        title: "",
                        selection: $selectedSettingsTab,
                        options: QuietTypeSettingsTab.allCases
                    ) { tab in
                        tab.label
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.58))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }

                settingsTabContent
                    .padding(18)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.03), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    private var settingsTabContent: some View {
        switch selectedSettingsTab {
        case .general:
            generalSettingsLayout
        case .privacy:
            privacySettingsLayout
        case .about:
            aboutSettingsLayout
        }
    }

    private var generalSettingsLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            dictationControlsPanel

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                setupStatusPanel
                memoryBackendPanel
                quickUpdatePanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var aboutSettingsLayout: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 0)
            aboutPanel
                .frame(maxWidth: 840, alignment: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var privacySettingsLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            privacyNetworkPanel

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                storageOverviewPanel
                storageCleanupPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.refreshStorageSnapshot()
        }
    }

    private var dictationControlsPanel: some View {
        settingsSection(title: "Dictation controls") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    Toggle("Insert polished text automatically", isOn: Binding(
                        get: { !model.previewOnly },
                        set: { model.previewOnly = !$0 }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(.primary)
                    .quickTooltip("When on, QuietType inserts the cleaned-up version of your dictation. When off, it leaves the result in QuietType so you can copy or review it first.")

                    Toggle("Save voice notes to SAGE", isOn: Binding(
                        get: { model.saveVoiceNotesToSage },
                        set: { model.setSaveVoiceNotesToSage($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(.primary)
                    .quickTooltip("When on, new voice notes also send a transcript copy to SAGE. Audio remains encrypted on this Mac, and local transcript edits stay in QuietType's encrypted memory store.")

                    Toggle("Filter profanity", isOn: Binding(
                        get: { model.profanityFilterEnabled },
                        set: { model.setProfanityFilterEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(.primary)
                    .quickTooltip("Masks common explicit words in polished output. Turn this off when you want QuietType to preserve exactly what you said.")

                    Toggle("Keyboard reminders", isOn: Binding(
                        get: { model.typingReminderEnabled },
                        set: { model.setTypingReminderEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .tint(.primary)
                    .quickTooltip("When you type several words with the keyboard, QuietType can occasionally show a local overlay reminding you to press Fn and speak. It is capped at 3 reminders per week with at least 48 hours between reminders.")

                    Spacer(minLength: 0)
                }

                QuietSegmentedControl(
                    title: "Spelling",
                    selection: spellingPreferenceBinding,
                    options: SpellingPreference.allCases
                ) { preference in
                    preference.label
                }
                .quickTooltip("Choose the spelling convention QuietType should prefer when it cleans up ambiguous words. System follows your macOS language settings.")

                ShortcutPicker(model: model)

                Toggle("Show tooltips", isOn: $showTooltips)
                    .toggleStyle(.checkbox)
                    .tint(.primary)
                    .quickTooltip("Show short hover explanations on controls, status cards, and storage actions. Turn this off when the interface feels familiar.")
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
                        NSWorkspace.shared.open(URL(string: "https://l33tdawg.github.io/sage/")!)
                    }
                    .buttonStyle(QuietButtonStyle())

                    Spacer()
                }
            }
        }
        .quickTooltip("SAGE is required before QuietType starts dictation. It keeps vocabulary, corrections, transcript notes, and training hints in governed local memory.")
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.sageReady ? "checkmark.seal.fill" : "brain.head.profile")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sageReady ? "quiettype-agent registered" : model.sageDetected ? "SAGE setup incomplete" : "SAGE required")
                        .font(.callout.weight(.semibold))
                    Text(model.sageReady ? "Corrections, review notes, and training hints are committed through SAGE governed memory." : "Install SAGE, finish setup, then connect quiettype-agent.")
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
                }

                HStack(spacing: 10) {
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
                    Spacer()
                }
            }
        }
        .quickTooltip("SAGE is QuietType's governed local memory layer. It stores approved spellings, correction patterns, review notes, and training hints so dictation can improve without cloud memory.")
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

                Button {
                    selectedSection = .setup
                    selectedSetupTab = model.setupComplete ? .overview : suggestedSetupTab
                } label: {
                    Label(model.setupComplete ? "Run setup again" : "Finish setup", systemImage: "waveform.and.mic")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle(prominence: model.setupComplete ? .secondary : .primary))
            }
        }
        .quickTooltip("Readiness combines macOS Microphone permission, Accessibility insertion permission, and SAGE registration. Use setup again when one of these checks changes.")
    }

    private var quickUpdatePanel: some View {
        settingsSection(title: "Version") {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.appVersionLabel)
                    .font(.callout.weight(.semibold))
                Text("QuietType checks GitHub for signed updates when the app opens. Downloads happen only when you click Update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    performUpdateAction()
                } label: {
                    Label(updateActionButtonTitle, systemImage: updateActionButtonIcon)
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(model.isCheckingForUpdates)
            }
        }
        .quickTooltip("QuietType checks GitHub metadata for signed releases. It only downloads and installs an update after you click the update button.")
    }

    private var privacyNetworkPanel: some View {
        settingsSection(title: "Privacy and network") {
            VStack(alignment: .leading, spacing: 12) {
                PrivacyFlowRow(
                    icon: "waveform",
                    title: "Dictation",
                    detail: "Microphone audio is transcribed locally. The bundled WhisperKit server listens on 127.0.0.1:50060 and does not send dictation audio or transcripts to cloud services."
                )
                .quickTooltip("The normal dictation path is local audio capture, local transcription, local cleanup, and local insertion into the active app.")
                PrivacyFlowRow(
                    icon: "brain.head.profile",
                    title: "SAGE memory",
                    detail: "Corrections, vocabulary, training hints, and optional voice-note transcript copies are committed to local SAGE through localhost. Voice-note audio stays encrypted on this Mac."
                )
                .quickTooltip("QuietType writes eligible memory events to your local SAGE node through localhost. Audio stays in QuietType's encrypted local store.")
                PrivacyFlowRow(
                    icon: "sparkles",
                    title: "Optional local editor",
                    detail: "Rule cleanup runs in QuietType. If you select Ollama mode, cleanup calls your local Ollama service on 127.0.0.1:11434."
                )
                .quickTooltip("The default cleanup path is built in. Ollama is only used when you choose a local Ollama editor mode.")
                PrivacyFlowRow(
                    icon: "arrow.down.circle",
                    title: "Updates",
                    detail: "QuietType checks GitHub releases for signed app and SAGE updates in the background. DMGs download only when you choose Update or Install SAGE."
                )
                .quickTooltip("Update checks fetch release metadata. Installers are downloaded only after an explicit update or SAGE install action.")
            }
        }
    }

    private var storageOverviewPanel: some View {
        settingsSection(title: "Storage") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(model.storageSnapshot.updatedAtLabel)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.refreshStorageSnapshot()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .quickTooltip("Rescan QuietType's local storage locations and refresh the size estimates shown below.")
                }

                ForEach(model.storageSnapshot.entries) { entry in
                    StorageUsageRow(entry: entry)
                }
            }
        }
    }

    private var storageCleanupPanel: some View {
        settingsSection(title: "Cleanup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleanup actions leave encrypted voice-note audio, local transcript records, and SAGE memory records intact unless the button names that storage explicitly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            model.cleanupReviewAudioCache()
                        } label: {
                            Label("Review audio", systemImage: "waveform.slash")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .quickTooltip("Remove temporary review audio cache files. This does not delete encrypted voice notes or SAGE memory.")

                        Button {
                            model.cleanupTrainingSamples()
                        } label: {
                            Label("Training samples", systemImage: "trash")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .quickTooltip("Remove local voice-training sample files. Saved corrections and SAGE memories are left intact.")
                    }

                    HStack(spacing: 8) {
                        Button {
                            model.cleanupUpdateCache()
                        } label: {
                            Label("Update downloads", systemImage: "externaldrive.badge.minus")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(model.isCheckingForUpdates)
                        .quickTooltip("Remove cached update downloads. QuietType can download a signed update again when you choose Update.")

                        Button {
                            model.trimSageLog()
                        } label: {
                            Label("Trim SAGE log", systemImage: "scissors")
                        }
                        .buttonStyle(QuietButtonStyle())
                        .quickTooltip("Ask QuietType to trim its local SAGE integration log. Governed SAGE memory records are not deleted.")
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.openQuietTypeStorageFolder()
                    } label: {
                        Label("QuietType folder", systemImage: "folder")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .quickTooltip("Open QuietType's Application Support folder for local logs, encrypted stores, and caches.")

                    Button {
                        model.openSageStorageFolder()
                    } label: {
                        Label("SAGE folder", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .quickTooltip("Open the local SAGE storage folder when available. This is for inspection and troubleshooting.")
                }

                if !model.storageCleanupStatus.isEmpty {
                    Text(model.storageCleanupStatus)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        Text("QuietType checks GitHub for signed updates when the app opens. Downloads happen only when you click Update.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        performUpdateAction()
                    } label: {
                        Label(updateActionButtonTitle, systemImage: updateActionButtonIcon)
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                    .disabled(model.isCheckingForUpdates)
                }
            }
        }
    }

    private var updateActionButtonTitle: String {
        if model.updateInstallRequiresRestart {
            return "Restart"
        }
        if model.updateInstallFailed {
            return "Retry"
        }
        guard model.isCheckingForUpdates else {
            return "Check for updates"
        }
        switch quietUpdateStage(status: model.updateStatus, messages: model.updateProgressMessages) {
        case .checking:
            return "Checking"
        case .updating:
            return "Updating"
        case .installing:
            return "Installing"
        }
    }

    private var updateActionButtonIcon: String {
        if model.updateInstallRequiresRestart {
            return "arrow.clockwise"
        }
        if model.updateInstallFailed {
            return "exclamationmark.arrow.triangle.2.circlepath"
        }
        if model.isCheckingForUpdates {
            return "arrow.triangle.2.circlepath"
        }
        return "arrow.down.circle"
    }

    private func performUpdateAction() {
        if model.updateInstallRequiresRestart {
            model.restartInstalledApp()
            return
        }
        Task {
            await model.checkForUpdatesAndInstall()
        }
    }

    private var aboutPanel: some View {
        VStack(alignment: .center, spacing: 16) {
            appBrandIcon
                .frame(width: 44, height: 44)

            Text("Speak freely. Transcribe locally. Nothing leaves your Mac.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("QuietType is a local-first dictation assistant by Dhillon \"l33tdawg\" Kannabhiran. It uses on-device transcription and SAGE BFT-governed memory for corrections, vocabulary, transcript notes, and writing preferences. Contact: dhillon@levelupctf.com.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640)

            HStack(spacing: 10) {
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

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .center, spacing: 8) {
                Text("Share QuietType")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Help privacy-conscious Mac users find local dictation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
            .frame(maxWidth: 520)
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity, alignment: .top)
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
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }

    private struct PrivacyFlowRow: View {
        var icon: String
        var title: String
        var detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct StorageUsageRow: View {
        var entry: QuietTypeStorageEntry

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(entry.displaySize)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
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
                        .fill(model.isRecording ? Color.black : (isDarkAppearance ? Color.white.opacity(0.92) : Color(nsColor: .windowBackgroundColor)))
                        .frame(width: 156, height: 156)
                    Circle()
                        .stroke(model.isRecording ? Color.red.opacity(0.34) : (isDarkAppearance ? Color.white.opacity(0.55) : Color.black.opacity(0.10)), lineWidth: 13)
                        .frame(width: 190, height: 190)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(model.isRecording ? .white : (isDarkAppearance ? Color.black.opacity(0.70) : Color.secondary))
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning && !model.isRecording)
            .quickTooltip(model.isRecording ? "Stop listening, polish the transcript, and insert the result according to your settings." : "Start local dictation. QuietType listens only while this session is active.")
            .anchorPreference(key: GuideSpotlightPreferenceKey.self, value: .bounds) { anchor in
                [.dictate: anchor]
            }

            Text(model.primaryPrompt)
                .font(.system(size: 25, weight: .semibold, design: .rounded))

            SegmentedLevelMeter(level: model.inputLevel, isActive: model.isRecording)
                .frame(width: 285)

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
                    .quickTooltip("Duration of the current or most recent dictation session.")
                ActivityRow(icon: "textformat.abc", title: "Current words", value: "\(model.currentSessionWordCount)")
                    .quickTooltip("Words captured in the active session before cleanup and insertion.")
                ActivityRow(icon: "speedometer", title: "Speaking pace", value: model.currentWordsPerMinuteLabel)
                    .quickTooltip("Estimated words per minute for the current or most recent session.")
                ActivityRow(icon: "text.bubble", title: "Sessions today", value: "\(model.sessionsToday)")
                    .quickTooltip("How many dictation sessions QuietType has completed today.")
                ActivityRow(icon: "brain.head.profile", title: "Reviews", value: "\(model.sageLessonCount)")
                    .quickTooltip("SAGE-backed correction and review memories available to QuietType.")
                ActivityRow(icon: "checklist.checked", title: "Transcriptions", value: "\(model.transcriptNoteCount)")
                    .quickTooltip("Transcript notes available for review and correction.")
                ActivityRow(icon: "wand.and.stars", title: "Correction signal", value: model.correctionSignalLabel)
                    .quickTooltip("A compact status for whether QuietType has useful correction memory to apply.")
                ActivityRow(icon: "textformat.abc", title: "Words translated", value: model.wordsProcessedLabel)
                    .quickTooltip("Total words processed through QuietType's local pipeline.")
                ActivityMeterRow(icon: "speedometer", title: "Local CPU", value: "\(model.cpuUsagePercent)%", progress: Double(model.cpuUsagePercent) / 100.0)
                    .quickTooltip("Approximate local CPU usage sampled by QuietType while the app is open.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDarkAppearance ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1))
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
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

                Button {
                    model.copyOutput()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(model.output.isEmpty)
                .quickTooltip("Copy the latest polished output without inserting it into another app.")

                if !model.output.isEmpty {
                    Button {
                        model.clearOutput()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .secondary))
                    .opacity(0.78)
                    .quickTooltip("Clear the visible polished output from this panel.")
                }
            }

            Text(model.output.isEmpty ? "Your polished text will appear here." : model.output)
                .font(.system(size: 19, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
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
    case voiceNotes
    case history
    case setup
    case dictionary
    case settings
    case help

    var id: String { rawValue }

    static let primary: [QuietTypeSection] = [.home, .voiceNotes, .dictionary]

    var title: String {
        switch self {
        case .home: "Home"
        case .voiceNotes: "Voice Notes"
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
        case .voiceNotes: "waveform.badge.mic"
        case .history: "clock.arrow.circlepath"
        case .setup: "waveform.and.mic"
        case .dictionary: "brain.head.profile"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

private struct QuietTypeHeroMessage: Identifiable {
    var id: String { title }
    var title: String
    var subtitle: String

    static let all: [QuietTypeHeroMessage] = [
        QuietTypeHeroMessage(
            title: "Speak freely. Transcribe locally.",
            subtitle: "Nothing leaves your Mac."
        ),
        QuietTypeHeroMessage(
            title: "Your voice stays on your Mac.",
            subtitle: "Private dictation, local cleanup, no cloud handoff."
        ),
        QuietTypeHeroMessage(
            title: "Dictate without sending it away.",
            subtitle: "QuietType listens locally and keeps review notes in SAGE."
        ),
        QuietTypeHeroMessage(
            title: "Say it once. Keep it private.",
            subtitle: "Local speech, local memory, local control."
        ),
        QuietTypeHeroMessage(
            title: "Fast words. Private by design.",
            subtitle: "Built for Apple Silicon and governed local memory."
        ),
        QuietTypeHeroMessage(
            title: "Voice input for secure work.",
            subtitle: "Transcribe, polish, and insert without cloud dictation."
        ),
        QuietTypeHeroMessage(
            title: "Think out loud. Keep it local.",
            subtitle: "Long agent prompts become clean text on your Mac."
        ),
        QuietTypeHeroMessage(
            title: "More context. Less typing.",
            subtitle: "Give Codex and Claude the full brief without uploading speech."
        ),
        QuietTypeHeroMessage(
            title: "Your prompt, not their server.",
            subtitle: "Local transcription for source paths, bugs, names, and plans."
        ),
        QuietTypeHeroMessage(
            title: "Talk like a person. Paste like a pro.",
            subtitle: "QuietType turns messy speech into usable instructions."
        ),
        QuietTypeHeroMessage(
            title: "Private words for real work.",
            subtitle: "Built for terminals, editors, agents, notes, and Slack."
        )
    ]

    static func message(at index: Int) -> QuietTypeHeroMessage {
        guard !all.isEmpty else {
            return QuietTypeHeroMessage(title: "Speak freely. Transcribe locally.", subtitle: "Nothing leaves your Mac.")
        }
        return all[index % all.count]
    }

    static func randomIndex() -> Int {
        guard !all.isEmpty else {
            return 0
        }
        return Int.random(in: 0..<all.count)
    }

    static func nextIndex(after index: Int) -> Int {
        guard !all.isEmpty else {
            return 0
        }
        return (index + 1) % all.count
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

    var shortLabel: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var sidebarSymbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
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

    var shortLabel: String {
        switch self {
        case .standard: "A"
        case .large: "A+"
        case .larger: "A++"
        }
    }

    var sidebarGlyphSize: CGFloat {
        switch self {
        case .standard: 12
        case .large: 14
        case .larger: 16
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
    case privacy
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }
}

struct QuietTypeStorageSnapshot: Equatable {
    var entries: [QuietTypeStorageEntry]
    var updatedAt: Date?

    static let empty = QuietTypeStorageSnapshot(entries: [], updatedAt: nil)

    var updatedAtLabel: String {
        guard let updatedAt else {
            return "Storage not scanned yet."
        }
        return "Updated \(updatedAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct QuietTypeStorageEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var bytes: Int64
    var exists: Bool

    var displaySize: String {
        guard exists else {
            return "0 KB"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
        "https://l33tdawg.github.io/quiettype/"
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
    var primaryAction: () -> Void
    var secondaryAction: () -> Void

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
                    Button(action: secondaryAction) {
                        Text(stage.secondaryAction)
                            .font(.system(size: 14 + typeDelta, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle())

                    Button(action: primaryAction) {
                        Text(stage.primaryAction(model: model))
                            .font(.system(size: 14 + typeDelta, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
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

private struct SetupCompletePill: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var number: String
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11 + typeDelta, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14 + typeDelta, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12 + typeDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
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
    @State private var isHovering = false
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
        .background(isHovering ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(isHovering ? 0.16 : 0.06), lineWidth: 1))
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct HelpInfoCard: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    @State private var isHovering = false
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
        .background(isHovering ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(isHovering ? 0.16 : 0.06), lineWidth: 1))
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct HelpFAQRow: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    @State private var isHovering = false
    var question: String
    var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.system(size: 14 + typeDelta, weight: .semibold))
                .foregroundStyle(.primary)
            Text(answer)
                .font(.system(size: 14 + typeDelta, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.04) : Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(isHovering ? 0.12 : 0.05), lineWidth: 1))
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct SidebarItem: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var icon: String
    var title: String
    var selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 23 + typeDelta, weight: selected ? .bold : .semibold))
                .frame(width: 28, height: 28)
            Text(title)
                .font(.system(size: 20 + typeDelta, weight: selected ? .bold : .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(selected ? .primary : .secondary)
        .background(selected ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SidebarPillButton: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12 + typeDelta, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .secondaryLabelColor))
                .background(selected ? Color(nsColor: .labelColor) : Color(nsColor: .windowBackgroundColor).opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
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
    var tooltip: String? = nil

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
        .quickTooltip(tooltip)
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

            SegmentedLevelMeter(level: level, isActive: isRecording)
                .frame(width: 104)

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

private struct SegmentedLevelMeter: View {
    var level: Double
    var isActive: Bool

    private let segments = 34

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    private var activeCount: Int {
        guard isActive, clampedLevel > 0 else {
            return 0
        }
        return max(1, Int((clampedLevel * Double(segments)).rounded(.up)))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(index < activeCount ? 0.58 : 0.08))
                    .frame(width: 5, height: 8)
            }
        }
        .opacity(isActive ? 1 : 0.42)
        .animation(.easeOut(duration: 0.10), value: activeCount)
        .accessibilityLabel("Input level")
        .accessibilityValue(activeCount == 0 ? "Silent" : "\(Int(clampedLevel * 100)) percent")
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
                    .quickTooltip(choice == .function ? "Use the Fn key as the dictation shortcut. If macOS also uses Fn, emoji or Apple dictation can appear." : "Use the fallback shortcut when Fn conflicts with macOS keyboard settings.")
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
                .quickTooltip("macOS is already using Fn. The fallback shortcut avoids that collision without changing your system keyboard setting.")
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
    var audioPath: String?
    var createdAt: Date?
    var isEditableTranscript: Bool
    var hasLocalCopy: Bool
    var hasSageMemory: Bool
}

struct VoiceNoteItem: Identifiable, Equatable {
    var id: String
    var title: String
    var rawTranscript: String
    var polishedText: String
    var audioPath: String?
    var durationSeconds: Double
    var createdAt: Date?
    var sentToSage: Bool
    var sageMemoryID: String?
    var sentToSageAt: String?

    var displayDate: String {
        guard let createdAt else {
            return "Local note"
        }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var durationLabel: String {
        guard durationSeconds > 0 else {
            return "Encrypted audio"
        }
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    var wordCountLabel: String {
        let count = polishedText
            .split { $0.isWhitespace || $0.isNewline }
            .count
        return "\(count) words"
    }
}

private struct TranscriptMemoryParts: Equatable {
    var rawTranscript: String?
    var polishedText: String?
    var appName: String?
    var audioPath: String?
    var wordTimingsBase64: String?
}

private struct DerivedWordCorrection: Equatable {
    var raw: String
    var corrected: String
    var tokenIndex: Int
    var source: CorrectionTextSource
}

private enum CorrectionTextSource: String, Equatable {
    case rawTranscript
    case polishedText
}

private struct AudioWordOffset: Codable, Equatable {
    var heard: String
    var corrected: String
    var word: String
    var startSeconds: Double
    var endSeconds: Double
    var wordIndex: Int
    var source: String
}

private actor EncryptedVoiceNoteAudioStore {
    private static let encryptedFilePrefix = Data("QTVA1".utf8)
    private static let keychainService = "QuietType.VoiceNotes"
    private static let keychainAccount = "quiettype-voice-notes-aes-gcm-key"

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func saveWAVData(_ data: Data, date: Date = Date()) throws -> URL {
        try OwnerOnlyFileSecurity.prepareDirectory(directory)
        let sealed = try AES.GCM.seal(data, using: Self.audioKey())
        guard let combined = sealed.combined else {
            throw MemoryStoreError.encryptionFailed
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "voice-note-\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).qtvoice"
        let url = directory.appendingPathComponent(filename)
        try (Self.encryptedFilePrefix + combined).write(to: url, options: [.atomic])
        try OwnerOnlyFileSecurity.protectFile(url)
        return url
    }

    func decryptAudio(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.starts(with: Self.encryptedFilePrefix) else {
            throw MemoryStoreError.encryptionFailed
        }
        let encryptedPayload = data.dropFirst(Self.encryptedFilePrefix.count)
        let sealed = try AES.GCM.SealedBox(combined: Data(encryptedPayload))
        return try AES.GCM.open(sealed, using: Self.audioKey())
    }

    private static func audioKey() throws -> SymmetricKey {
        if let data = try keychainKeyData() {
            return SymmetricKey(data: data)
        }
        let data = Data((0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
        try saveKeyDataToKeychain(data)
        return SymmetricKey(data: data)
    }

    private static func keychainKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw MemoryStoreError.encryptionFailed
        }
        return data
    }

    private static func saveKeyDataToKeychain(_ data: Data) throws {
        guard data.count == 32 else {
            throw MemoryStoreError.encryptionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw MemoryStoreError.encryptionFailed
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw MemoryStoreError.encryptionFailed
        }
    }
}

@MainActor
private final class TypingReminderMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var characterCountInCurrentWord = 0
    private var wordCount = 0
    private var burstStartedAt: Date?
    private var lastKeyAt: Date?

    var shouldRemind: (() -> Bool)?
    var onReminder: (() -> Void)?
    var shortcutLabel = "Fn"

    private let wordsBeforeReminder = 5
    private let idleResetSeconds: TimeInterval = 8
    private let burstWindowSeconds: TimeInterval = 45
    private let reminderCooldownSeconds: TimeInterval = 60 * 60 * 48
    private let reminderWindowSeconds: TimeInterval = 60 * 60 * 24 * 7
    private let maxRemindersPerWindow = 3
    private let reminderHistoryKey = "quiettype.typingReminderHistory"

    func register() {
        guard globalMonitor == nil && localMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        resetBurst()
    }

    private func handle(_ event: NSEvent) {
        guard shouldRemind?() == true else {
            resetBurst()
            return
        }
        guard isPlainTypingEvent(event) else {
            return
        }

        let now = Date()
        if let lastKeyAt, now.timeIntervalSince(lastKeyAt) > idleResetSeconds {
            resetBurst()
        }
        if burstStartedAt == nil {
            burstStartedAt = now
        }
        lastKeyAt = now

        if isWordBoundary(event) {
            if characterCountInCurrentWord >= 2 {
                wordCount += 1
            }
            characterCountInCurrentWord = 0
        } else if isPrintableKey(event) {
            characterCountInCurrentWord += 1
        }

        guard wordCount >= wordsBeforeReminder,
              let burstStartedAt,
              now.timeIntervalSince(burstStartedAt) <= burstWindowSeconds,
              shouldPassCooldown(now) else {
            return
        }

        recordReminder(at: now)
        resetBurst(keepingCooldown: true)
        showReminder()
    }

    private func isPlainTypingEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        return flags.isEmpty
    }

    private func isWordBoundary(_ event: NSEvent) -> Bool {
        [36, 49, 76].contains(Int(event.keyCode))
    }

    private func isPrintableKey(_ event: NSEvent) -> Bool {
        let ignored: Set<Int> = [
            36, 48, 49, 51, 53, 76,
            123, 124, 125, 126
        ]
        return !ignored.contains(Int(event.keyCode))
    }

    private func shouldPassCooldown(_ now: Date) -> Bool {
        let recent = reminderHistory(now: now)
        if recent.count >= maxRemindersPerWindow {
            return false
        }
        guard let lastReminderAt = recent.max() else {
            return true
        }
        return now.timeIntervalSince(lastReminderAt) >= reminderCooldownSeconds
    }

    private func reminderHistory(now: Date = Date()) -> [Date] {
        let timestamps = UserDefaults.standard.array(forKey: reminderHistoryKey) as? [TimeInterval] ?? []
        let cutoff = now.addingTimeInterval(-reminderWindowSeconds)
        let dates = timestamps
            .map(Date.init(timeIntervalSince1970:))
            .filter { $0 >= cutoff }
        persistReminderHistory(dates)
        return dates
    }

    private func recordReminder(at date: Date) {
        var dates = reminderHistory(now: date)
        dates.append(date)
        persistReminderHistory(dates)
    }

    private func persistReminderHistory(_ dates: [Date]) {
        UserDefaults.standard.set(
            dates.map(\.timeIntervalSince1970),
            forKey: reminderHistoryKey
        )
    }

    private func resetBurst(keepingCooldown: Bool = false) {
        characterCountInCurrentWord = 0
        wordCount = 0
        burstStartedAt = nil
        lastKeyAt = nil
        if !keepingCooldown {
            // Keep lastReminderAt intact for normal idle resets.
        }
    }

    private func showReminder() {
        onReminder?()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var cleanedTranscriptMemoryValue: String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        while value.first == "\"" {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while value.last == "\"" {
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

private extension Array {
    func ifEmpty(_ fallback: () -> [Element]) -> [Element] {
        isEmpty ? fallback() : self
    }
}

private struct QuickTooltipModifier: ViewModifier {
    let text: String
    @AppStorage("quiettype.showTooltips") private var showTooltips = true
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        Group {
            if showTooltips {
                content
                    .onHover { hovering in
                        hoverTask?.cancel()
                        if hovering {
                            hoverTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else {
                                    return
                                }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    isPresented = true
                                }
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.08)) {
                                isPresented = false
                            }
                        }
                    }
                    .popover(isPresented: $isPresented, arrowEdge: .top) {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 300, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
            } else {
                content
                    .onAppear {
                        hoverTask?.cancel()
                        isPresented = false
                    }
            }
        }
        .onChange(of: showTooltips) { enabled in
            if !enabled {
                hoverTask?.cancel()
                isPresented = false
            }
        }
    }
}

private extension View {
    func quickTooltip(_ text: String) -> some View {
        modifier(QuickTooltipModifier(text: text))
    }

    @ViewBuilder
    func quickTooltip(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            quickTooltip(text)
        } else {
            self
        }
    }
}

private struct VoiceNotesIntroPanel: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.quietTypeTypeDelta) private var typeDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VoiceNoteSignalGlyph(level: model.voiceNoteInputLevel, isActive: model.isVoiceNoteRecording)
                .frame(height: 112)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("Voice Notes")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Record private thoughts, diary entries, rough plans, and long-form ideas. Audio is encrypted on this Mac, and transcript edits live in QuietType's encrypted local memory store. When SAGE copy is on, QuietType sends only the transcript as governed memory.")
                    .font(.system(size: 16 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                VoiceNoteFeatureRow(icon: "lock.shield", title: "Encrypted locally", detail: "Audio is saved as an encrypted blob. Transcript edits live in QuietType's encrypted local memory store.")
                VoiceNoteFeatureRow(icon: "pencil.and.scribble", title: "Editable transcript", detail: "Correct the raw transcript and polished note whenever you revisit it.")
                VoiceNoteFeatureRow(icon: "brain.head.profile", title: "SAGE transcript copy", detail: "New notes copy their transcript to SAGE by default. The audio file remains encrypted on this Mac.")
            }

            HStack {
                VoiceNoteRecorderStatus(model: model)
                Spacer()
                Button {
                    Task {
                        await model.toggleVoiceNoteRecording()
                    }
                } label: {
                    Label(
                        model.isVoiceNoteRecording ? "Stop" : "Record first note",
                        systemImage: model.isVoiceNoteRecording ? "stop.circle" : "mic.circle"
                    )
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(model.isVoiceNoteTranscribing || model.isRecording || model.isTrainingRecording || model.isTeachingRecording)
                .quickTooltip(model.isVoiceNoteRecording ? "Stop recording and transcribe this voice note locally." : "Start an encrypted local voice note. Transcript copies go to SAGE only when that setting is on.")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 36)
        .frame(minHeight: 620, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 28, x: 0, y: 14)
    }
}

private struct VoiceNoteFeatureRow: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct VoiceNoteRecorderStatus: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        HStack(spacing: 10) {
            VoiceNoteLevelMeter(level: model.voiceNoteInputLevel, isActive: model.isVoiceNoteRecording)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.voiceNoteStatusTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(model.voiceNoteStatusDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct VoiceNoteSignalGlyph: View {
    var level: Double
    var isActive: Bool
    private let bars = 34

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(opacity(for: index)))
                    .frame(width: 4, height: height(for: index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        .animation(.easeOut(duration: 0.16), value: level)
        .animation(.easeOut(duration: 0.16), value: isActive)
    }

    private func height(for index: Int) -> CGFloat {
        let center = Double(bars - 1) / 2.0
        let distance = abs(Double(index) - center) / center
        let base = 10 + (1.0 - distance) * 32
        let ripple = sin(Double(index) * 0.82) * 8
        let activeBoost = isActive ? min(max(level, 0), 1) * 26 : 0
        return CGFloat(max(10, base + ripple + activeBoost * (1.0 - distance * 0.35)))
    }

    private func opacity(for index: Int) -> Double {
        let center = Double(bars - 1) / 2.0
        let distance = abs(Double(index) - center) / center
        return isActive ? 0.32 + (1.0 - distance) * 0.52 : 0.12 + (1.0 - distance) * 0.18
    }
}

private struct VoiceNoteLevelMeter: View {
    var level: Double
    var isActive: Bool
    private let bars = 7

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(opacity(for: index)))
                    .frame(width: 4, height: height(for: index))
            }
        }
        .frame(width: 48, height: 34)
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private func height(for index: Int) -> CGFloat {
        let normalizedLevel = min(max(level, 0), 1)
        let wave = sin(Double(index) * 0.95) * 4
        let boost = isActive ? normalizedLevel * 18 : 0
        return CGFloat(max(6, 9 + index * 2 + Int(wave) + Int(boost)))
    }

    private func opacity(for index: Int) -> Double {
        guard isActive else {
            return 0.20
        }
        let threshold = Int((min(max(level, 0), 1) * Double(bars)).rounded(.up))
        return index < threshold ? 0.82 : 0.16
    }
}

private struct VoiceNoteListRow: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var note: VoiceNoteItem
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(note.title)
                        .font(.system(size: 14 + typeDelta, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    if note.sentToSage {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(note.polishedText.isEmpty ? note.rawTranscript : note.polishedText)
                    .font(.system(size: 12 + typeDelta, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    VoiceNoteTinyPill(text: note.durationLabel, icon: "waveform")
                    VoiceNoteTinyPill(text: note.wordCountLabel, icon: "text.word.spacing")
                }
                Text(note.displayDate)
                    .font(.system(size: 10 + typeDelta, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.primary.opacity(0.09) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct VoiceNoteTinyPill: View {
    var text: String
    var icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(Capsule())
    }
}

private struct VoiceNotePlayerControl: View {
    var isPlaying: Bool
    var progress: Double
    var duration: Double
    var volume: Double
    var isEnabled: Bool
    var playAction: () -> Void
    var stopAction: () -> Void
    var volumeAction: (Double) -> Void

    private var elapsed: Double {
        duration * min(max(progress, 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: playAction) {
                    Label("Play", systemImage: "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 38, height: 38)
                        .background(Color.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.42)
                .quickTooltip("Play the encrypted local audio for this note from the beginning.")

                Button(action: stopAction) {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.075))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || (!isPlaying && progress <= 0))
                .opacity(isEnabled ? 1 : 0.42)
                .quickTooltip("Stop local audio playback for this note.")

                VStack(spacing: 8) {
                    VoiceNotePlaybackWaveform(progress: progress, isPlaying: isPlaying, isEnabled: isEnabled)
                        .frame(height: 28)
                    HStack {
                        Text(formatTime(elapsed))
                        Spacer()
                        Text(formatTime(duration))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            HStack(spacing: 9) {
                Image(systemName: volume <= 0.02 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Slider(
                    value: Binding(
                        get: { min(max(volume, 0), 1) },
                        set: { volumeAction($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                Text("\(Int((min(max(volume, 0), 1) * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .disabled(!isEnabled)
            .quickTooltip("Adjust playback volume for local note audio.")

            if !isEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Audio file is unavailable")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite, value > 0 else {
            return "0:00"
        }
        let total = Int(value.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

private struct VoiceNotePlaybackWaveform: View {
    var progress: Double
    var isPlaying: Bool
    var isEnabled: Bool
    private let bars = 56

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { index in
                    Capsule()
                        .fill(fill(for: index))
                        .frame(width: max(2, (proxy.size.width - CGFloat(bars - 1) * 2) / CGFloat(bars)), height: height(for: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.12), value: progress)
        .animation(.easeOut(duration: 0.12), value: isPlaying)
    }

    private func height(for index: Int) -> CGFloat {
        let base = 9 + abs(sin(Double(index) * 0.58)) * 18
        let pulse = isPlaying ? abs(sin(Double(index) * 0.37 + progress * 12.0)) * 5 : 0
        return CGFloat(base + pulse)
    }

    private func fill(for index: Int) -> Color {
        guard isEnabled else {
            return Color.primary.opacity(0.12)
        }
        let played = Double(index) / Double(max(bars - 1, 1)) <= min(max(progress, 0), 1)
        return Color.primary.opacity(played ? 0.78 : 0.18)
    }
}

private struct VoiceNoteDetailPanel: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    @State private var draftTitle: String
    @State private var draftRawTranscript: String
    @State private var draftPolishedText: String
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var isSendingToSage = false
    @State private var showingDeleteConfirm = false
    var note: VoiceNoteItem
    var isPlaying: Bool
    var playbackProgress: Double
    var playbackDuration: Double
    var playbackVolume: Double
    var savesToSageByDefault: Bool
    var saveAction: (String, String, String) async -> Void
    var deleteAction: () async -> Void
    var sendToSageAction: () async -> Void
    var playAction: () async -> Void
    var stopAction: () -> Void
    var volumeAction: (Double) -> Void

    init(
        note: VoiceNoteItem,
        isPlaying: Bool,
        playbackProgress: Double,
        playbackDuration: Double,
        playbackVolume: Double,
        savesToSageByDefault: Bool,
        saveAction: @escaping (String, String, String) async -> Void,
        deleteAction: @escaping () async -> Void,
        sendToSageAction: @escaping () async -> Void,
        playAction: @escaping () async -> Void,
        stopAction: @escaping () -> Void,
        volumeAction: @escaping (Double) -> Void
    ) {
        self.note = note
        self.isPlaying = isPlaying
        self.playbackProgress = playbackProgress
        self.playbackDuration = playbackDuration
        self.playbackVolume = playbackVolume
        self.savesToSageByDefault = savesToSageByDefault
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        self.sendToSageAction = sendToSageAction
        self.playAction = playAction
        self.stopAction = stopAction
        self.volumeAction = volumeAction
        _draftTitle = State(initialValue: note.title)
        _draftRawTranscript = State(initialValue: note.rawTranscript)
        _draftPolishedText = State(initialValue: note.polishedText)
    }

    private var hasChanges: Bool {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) != note.title
            || draftRawTranscript.trimmingCharacters(in: .whitespacesAndNewlines) != note.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            || draftPolishedText.trimmingCharacters(in: .whitespacesAndNewlines) != note.polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowManualSageSend: Bool {
        !savesToSageByDefault && !note.sentToSage
    }

    private var deleteIncludesSageMemory: Bool {
        savesToSageByDefault || note.sentToSage || note.sageMemoryID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    TextField("Title", text: $draftTitle)
                        .font(.system(size: 24 + typeDelta, weight: .bold, design: .rounded))
                        .textFieldStyle(.plain)
                    HStack(spacing: 7) {
                        VoiceNoteMetadataPill(text: note.durationLabel, icon: "lock.shield")
                        VoiceNoteMetadataPill(text: note.displayDate, icon: "calendar")
                        VoiceNoteMetadataPill(text: note.wordCountLabel, icon: "text.word.spacing")
                    }
                }
                Spacer()
                Button {
                    showingDeleteConfirm.toggle()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showingDeleteConfirm ? Color.red : Color.secondary)
                .background((showingDeleteConfirm ? Color.red : Color.primary).opacity(showingDeleteConfirm ? 0.11 : 0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isDeleting)
                .quickTooltip(deleteIncludesSageMemory ? "Remove the encrypted local note and ask SAGE to forget the linked transcript memory when one exists." : "Remove the encrypted local note and audio from this Mac.")
            }

            VoiceNotePlayerControl(
                isPlaying: isPlaying,
                progress: playbackProgress,
                duration: playbackDuration,
                volume: playbackVolume,
                isEnabled: note.audioPath != nil
            ) {
                Task {
                    await playAction()
                }
            } stopAction: {
                stopAction()
            } volumeAction: { volume in
                volumeAction(volume)
            }

            VoiceNoteTranscriptEditor(
                title: "Polished note",
                text: $draftPolishedText,
                minHeight: 230,
                fontSize: 15 + typeDelta
            )

            DisclosureGroup {
                VoiceNoteTranscriptEditor(
                    title: "Captured transcript",
                    text: $draftRawTranscript,
                    minHeight: 112,
                    fontSize: 13 + typeDelta,
                    showsHeader: false
                )
                .padding(.top, 6)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Raw transcript")
                        .font(.system(size: 12 + typeDelta, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }

            HStack {
                Label(
                    note.sentToSage ? "Saved to SAGE memory" : (savesToSageByDefault ? "Will save to SAGE after recording" : "Local encrypted transcript"),
                    systemImage: note.sentToSage ? "checkmark.seal" : "lock"
                )
                    .font(.system(size: 12 + typeDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if shouldShowManualSageSend {
                    Button {
                        Task {
                            isSendingToSage = true
                            await sendToSageAction()
                            isSendingToSage = false
                        }
                    } label: {
                        Label(isSendingToSage ? "Sending" : "Send to SAGE", systemImage: "brain.head.profile")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isSendingToSage)
                    .quickTooltip("Copy this note's transcript into local SAGE governed memory. The audio file is not sent to SAGE.")
                }
                Button {
                    Task {
                        isSaving = true
                        await saveAction(draftTitle, draftRawTranscript, draftPolishedText)
                        isSaving = false
                    }
                } label: {
                    Label(isSaving ? "Saving" : "Save", systemImage: "checkmark")
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(!hasChanges || isSaving)
                .quickTooltip("Save edits to this note's local encrypted transcript record.")
            }
            .padding(.top, 2)

            if savesToSageByDefault || note.sentToSage {
                VoiceNoteSageDetailsPanel(
                    note: note,
                    savesToSageByDefault: savesToSageByDefault,
                    isSendingToSage: isSendingToSage,
                    sendAction: {
                        Task {
                            isSendingToSage = true
                            await sendToSageAction()
                            isSendingToSage = false
                        }
                    }
                )
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if showingDeleteConfirm {
                DeleteMemoryConfirmPopover(
                    title: deleteIncludesSageMemory ? "Remove note and memory?" : "Remove note?",
                    isDeleting: isDeleting,
                    message: deleteIncludesSageMemory
                        ? "QuietType will remove the encrypted local transcript record and encrypted audio, then ask SAGE to forget the linked memory if one exists."
                        : "QuietType will remove the encrypted local transcript record and encrypted audio.",
                    confirmTitle: deleteIncludesSageMemory ? "Remove note and memory" : "Remove note",
                    onCancel: {
                        showingDeleteConfirm = false
                    },
                    onDelete: {
                        Task {
                            isDeleting = true
                            await deleteAction()
                            isDeleting = false
                            showingDeleteConfirm = false
                        }
                    }
                )
                .padding(.top, 54)
                .padding(.trailing, 16)
                .zIndex(10)
            }
        }
    }
}

private struct VoiceNoteMetadataPill: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var text: String
    var icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11 + typeDelta, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
    }
}

private struct VoiceNoteSageDetailsPanel: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    var note: VoiceNoteItem
    var savesToSageByDefault: Bool
    var isSendingToSage: Bool
    var sendAction: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                VoiceNoteSageDetailRow(
                    label: "Status",
                    value: note.sentToSage ? "Transcript copied to SAGE" : (savesToSageByDefault ? "Next saved voice note will copy to SAGE" : "SAGE copy is off")
                )
                VoiceNoteSageDetailRow(label: "Local audio", value: "Encrypted on this Mac")
                VoiceNoteSageDetailRow(label: "Local transcript", value: "Editable in Voice Notes")
                if let sageMemoryID = note.sageMemoryID {
                    VoiceNoteSageDetailRow(label: "SAGE memory", value: sageMemoryID)
                }
                if let sentToSageAt = note.sentToSageAt {
                    VoiceNoteSageDetailRow(label: "Sent", value: sentToSageAt)
                }
                if !savesToSageByDefault && !note.sentToSage {
                    Button {
                        sendAction()
                    } label: {
                        Label(isSendingToSage ? "Sending" : "Send this transcript now", systemImage: "brain.head.profile")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isSendingToSage)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: note.sentToSage ? "link.badge.plus" : "link")
                    .font(.system(size: 11, weight: .semibold))
                Text("SAGE memory details")
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07), lineWidth: 1))
        .quickTooltip("Shows what was saved locally versus what was copied to SAGE. SAGE stores transcript memory, not the encrypted audio file.")
    }
}

private struct VoiceNoteSageDetailRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 94, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct VoiceNoteTranscriptEditor: View {
    var title: String
    @Binding var text: String
    var minHeight: CGFloat
    var fontSize: CGFloat
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsHeader {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: fontSize, weight: .regular))
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private enum QuietUpdateStage {
    case checking
    case updating
    case installing
}

private func quietUpdateStage(status: String, messages: [String]) -> QuietUpdateStage {
    let text = ([status] + messages).joined(separator: " ").lowercased()
    if text.contains("backing up")
        || text.contains("installing")
        || text.contains("installed")
        || text.contains("applications") {
        return .installing
    }
    if text.contains("found")
        || text.contains("download")
        || text.contains("verif")
        || text.contains("dmg") {
        return .updating
    }
    return .checking
}

private func quietUpdateProgressValue(
    status: String,
    messages: [String],
    isChecking: Bool,
    completed: Bool,
    failed: Bool,
    requiresRestart: Bool
) -> Double {
    if failed {
        return 1.0
    }
    if completed || requiresRestart {
        return 1.0
    }
    guard isChecking else {
        return messages.isEmpty && status.isEmpty ? 0.0 : 1.0
    }
    switch quietUpdateStage(status: status, messages: messages) {
    case .checking:
        return 0.18
    case .updating:
        return 0.56
    case .installing:
        return 0.84
    }
}

private func quietUpdateInstruction(
    isChecking: Bool,
    completed: Bool,
    failed: Bool,
    requiresRestart: Bool
) -> String {
    if failed {
        return "The update did not finish. Try again when your connection is ready."
    }
    if requiresRestart {
        return "Restart QuietType to use the updated app in Applications."
    }
    if completed {
        return "QuietType finished checking for updates."
    }
    if isChecking {
        return "Keep QuietType open while the signed update is downloaded, verified, and installed."
    }
    return "QuietType will only download updates when you choose Update."
}

private struct UpdateInstallOverlay: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    private let cardSurface = Color(nsColor: .textBackgroundColor)

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(iconBackground)
                        Image(systemName: iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(iconForeground)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayTitle)
                            .font(.system(size: 22 + typeDelta, weight: .bold, design: .rounded))
                        Text(model.updateOverlayDetail)
                            .font(.system(size: 13 + typeDelta, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(model.updateProgressMessages.enumerated()), id: \.offset) { index, message in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: stepIcon(for: index))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(stepForeground(for: index))
                                .frame(width: 16)
                            Text(message)
                                .font(.system(size: 13 + typeDelta, weight: .medium))
                                .foregroundStyle(index == model.updateProgressMessages.count - 1 ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: quietUpdateProgressValue(
                        status: model.updateStatus,
                        messages: model.updateProgressMessages,
                        isChecking: model.isCheckingForUpdates,
                        completed: model.updateInstallCompleted,
                        failed: model.updateInstallFailed,
                        requiresRestart: model.updateInstallRequiresRestart
                    ))
                    .progressViewStyle(.linear)

                    Text(quietUpdateInstruction(
                        isChecking: model.isCheckingForUpdates,
                        completed: model.updateInstallCompleted,
                        failed: model.updateInstallFailed,
                        requiresRestart: model.updateInstallRequiresRestart
                    ))
                    .font(.system(size: 12 + typeDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()

                    if model.updateInstallRequiresRestart {
                        Button {
                            model.restartInstalledApp()
                        } label: {
                            Label("Restart QuietType", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(QuietButtonStyle(prominence: .primary))
                    } else if !model.isCheckingForUpdates {
                        Button("Close") {
                            model.dismissUpdateOverlay()
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .padding(22)
            .frame(width: 520)
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.82), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.34), radius: 34, y: 20)
        }
        .animation(.easeInOut(duration: 0.18), value: model.updateProgressMessages)
        .animation(.easeInOut(duration: 0.18), value: model.updateInstallCompleted)
        .animation(.easeInOut(duration: 0.18), value: model.updateInstallFailed)
    }

    private var iconName: String {
        if model.updateInstallFailed {
            return "exclamationmark.triangle.fill"
        }
        if model.updateInstallCompleted {
            return model.updateInstallRequiresRestart ? "checkmark.circle.fill" : "info.circle.fill"
        }
        return "arrow.down.circle.fill"
    }

    private var displayTitle: String {
        guard model.isCheckingForUpdates,
              !model.updateInstallCompleted,
              !model.updateInstallFailed else {
            return model.updateOverlayTitle
        }
        switch quietUpdateStage(status: model.updateStatus, messages: model.updateProgressMessages) {
        case .checking:
            return "Checking for update"
        case .updating:
            return "Updating QuietType"
        case .installing:
            return "Installing update"
        }
    }

    private var iconBackground: Color {
        if model.updateInstallFailed {
            return Color.red.opacity(0.12)
        }
        if model.updateInstallCompleted {
            return Color.green.opacity(0.14)
        }
        return Color.primary.opacity(0.08)
    }

    private var iconForeground: Color {
        if model.updateInstallFailed {
            return .red
        }
        return .primary
    }

    private func stepIcon(for index: Int) -> String {
        guard index == model.updateProgressMessages.count - 1,
              model.isCheckingForUpdates,
              !model.updateInstallCompleted,
              !model.updateInstallFailed else {
            return "checkmark.circle"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func stepForeground(for index: Int) -> Color {
        if model.updateInstallFailed, index == model.updateProgressMessages.count - 1 {
            return .red
        }
        return index == model.updateProgressMessages.count - 1 ? .primary : .secondary
    }
}

private struct DictionaryMemoryRow: View {
    @Environment(\.quietTypeTypeDelta) private var typeDelta
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var draftRawTranscript: String
    @State private var draftPolishedText: String
    var memory: DictionaryMemoryItem
    var saveAction: (String, String) async -> Void
    var deleteAction: () -> Void

    init(memory: DictionaryMemoryItem, saveAction: @escaping (String, String) async -> Void, deleteAction: @escaping () -> Void) {
        self.memory = memory
        self.saveAction = saveAction
        self.deleteAction = deleteAction
        _draftRawTranscript = State(initialValue: memory.rawTranscript ?? "")
        _draftPolishedText = State(initialValue: memory.polishedText ?? "")
    }

    private var confidenceText: String {
        guard let confidence = memory.confidence else {
            return "Reviewed"
        }
        return "\(Int((confidence * 100).rounded()))%"
    }

    private var primaryText: String {
        if let polished = memory.polishedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !polished.isEmpty {
            return polished
        }
        return memory.summary
    }

    private var secondaryText: String {
        if let raw = memory.rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           raw != primaryText {
            return "Heard: \(raw)"
        }
        return memory.source
    }

    private var hasChanges: Bool {
        draftRawTranscript.trimmingCharacters(in: .whitespacesAndNewlines) != (memory.rawTranscript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            || draftPolishedText.trimmingCharacters(in: .whitespacesAndNewlines) != (memory.polishedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(memory.kind)
                        .font(.system(size: 11 + typeDelta, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Capsule())
                    Text(memory.source)
                        .font(.system(size: 11 + typeDelta, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                if isEditing {
                    inlineEditor
                } else {
                    Text(primaryText)
                        .font(.system(size: 15 + typeDelta, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(secondaryText)
                        .font(.system(size: 13 + typeDelta, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 10) {
                Text(confidenceText)
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if memory.isEditableTranscript && !isEditing {
                    Button {
                        draftRawTranscript = memory.rawTranscript ?? ""
                        draftPolishedText = memory.polishedText ?? ""
                        isEditing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14 + typeDelta, weight: .semibold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .quickTooltip("Edit the raw and polished transcript text for this review item.")
                    .accessibilityLabel("Edit transcript")
                }
                if !isEditing {
                    Button {
                        deleteAction()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13 + typeDelta, weight: .semibold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .quickTooltip("Remove this review item locally and ask SAGE to forget its memory when available.")
                    .accessibilityLabel("Remove memory")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Color.primary.opacity(0.025) : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.leading, 18)
        }
        .onHover { isHovering = $0 }
    }

    private var inlineEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Polished text")
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $draftPolishedText)
                    .font(.system(size: 14 + typeDelta, weight: .medium))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            DisclosureGroup {
                TextEditor(text: $draftRawTranscript)
                    .font(.system(size: 13 + typeDelta, weight: .regular))
                    .frame(minHeight: 58)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } label: {
                Text("Raw transcript")
                    .font(.system(size: 12 + typeDelta, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .disclosureGroupStyle(.automatic)

            HStack {
                Text("Saving replaces this note and deprecates the old memory.")
                    .font(.system(size: 12 + typeDelta, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    draftRawTranscript = memory.rawTranscript ?? ""
                    draftPolishedText = memory.polishedText ?? ""
                    isEditing = false
                }
                .buttonStyle(QuietButtonStyle(prominence: .ghost))
                Button(isSaving ? "Saving" : "Save") {
                    Task {
                        isSaving = true
                        await saveAction(draftRawTranscript, draftPolishedText)
                        isSaving = false
                        isEditing = false
                    }
                }
                .buttonStyle(QuietButtonStyle(prominence: .primary))
                .disabled(!hasChanges || isSaving)
            }
        }
        .padding(.top, 2)
    }
}

private struct DeleteMemoryConfirmPopover: View {
    var title: String = "Remove memory?"
    var isDeleting: Bool
    var message: String = "QuietType will ask SAGE to forget it and remove it from Review."
    var confirmTitle: String = "Remove"
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.red.opacity(0.92))
                    .clipShape(Circle())
                    .shadow(color: Color.red.opacity(0.18), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This does not delete unrelated dictation history.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(QuietButtonStyle(prominence: .ghost))
                    .disabled(isDeleting)
                Button(action: onDelete) {
                    HStack(spacing: 8) {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(isDeleting ? "Removing" : confirmTitle)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Color.red.opacity(isDeleting ? 0.68 : 0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
        }
        .padding(18)
        .frame(width: 390)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 26, y: 14)
    }
}

private struct TeachQuietTypeSheet: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.dismiss) private var dismiss

    private var hasTeachingDetection: Bool {
        !model.teachingDetectedForms.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .center, spacing: 14) {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 108, height: 108)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("Teach pronunciation")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Say the word three times, then enter the spelling QuietType should write.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 28)
            .frame(width: 240)
            .frame(minHeight: 500)
            .background(Color.black)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add correction")
                        .font(.largeTitle.weight(.semibold))
                    Text("Record the word, then save the spelling QuietType should use.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("\(model.teachingSampleCount)/3 samples")
                        .font(.system(size: 13, weight: .semibold))
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(Color.primary.opacity(0.65))
                                .frame(width: proxy.size.width * CGFloat(Double(model.teachingSampleCount) / 3.0))
                        }
                    }
                    .frame(height: 6)
                }

                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { sample in
                        let isCaptured = model.teachingSampleCount >= sample
                        HStack(spacing: 6) {
                            Image(systemName: isCaptured ? "checkmark" : "waveform")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Sample \(sample)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(isCaptured ? Color(nsColor: .controlBackgroundColor) : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isCaptured ? Color.primary : Color(nsColor: .controlBackgroundColor))
                        .clipShape(Capsule())
                    }
                    Spacer()
                    Button {
                        Task {
                            await model.toggleTeachingSampleRecording()
                        }
                    } label: {
                        Label(model.teachingRecordButtonTitle, systemImage: model.isTeachingRecording ? "stop.circle.fill" : "mic.fill")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(QuietButtonStyle(prominence: .primary))
                }
                Text(model.teachingSampleStatus)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 7) {
                    Text("QuietType heard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Group {
                        if hasTeachingDetection {
                            Text(model.teachingDetectedForms.joined(separator: " / "))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        } else {
                            Text("Record a sample to detect the spoken form.")
                                .font(.system(size: 13, weight: .medium))
                                .italic()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
                        }
                    }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                QuietTextField(
                    label: "Should write",
                    placeholder: "Exact spelling or phrase",
                    text: $model.teachCorrected
                )

                HStack {
                    Text("Saved lessons apply during local cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(QuietButtonStyle())
                    Button("Save correction") {
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
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 820)
        .frame(minHeight: 500)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onAppear {
            model.setTeachingKind(.correction)
            model.resetTeachingDraft()
        }
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
    @Environment(\.colorScheme) private var colorScheme
    var icon: String
    var value: String
    var label: String
    var tooltip: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                Spacer()
            }
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
        }
        .padding(20)
        .frame(minHeight: 140, alignment: .topLeading)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
        .quickTooltip(tooltip)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var cardColor: Color {
        isDark ? Color.white.opacity(0.92) : Color.black
    }

    private var foregroundColor: Color {
        isDark ? .black : .white
    }

    private var secondaryColor: Color {
        isDark ? Color.black.opacity(0.58) : Color.white.opacity(0.68)
    }

    private var iconColor: Color {
        isDark ? Color.black.opacity(0.50) : Color.white.opacity(0.62)
    }

    private var borderColor: Color {
        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
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
        StartupStep(id: "nativeSpeech", title: "Secure transcription engine", detail: "Waiting to start the Apple Silicon engine.", state: .pending)
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

private struct SidebarIconToggle<Content: View>: View {
    var label: String
    var selected: Bool
    @ViewBuilder var content: () -> Content
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(selected ? Color(nsColor: .controlBackgroundColor) : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(selected ? Color.primary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .quickTooltip(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14 + typeDelta, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 96, alignment: .leading)
            }

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
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12 + typeDelta, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder.isEmpty ? label : placeholder, text: $text, axis: .vertical)
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
    var requiresRestart: Bool
}

struct QuietTypeUpdateAvailability: Codable, Equatable {
    var versionLabel: String
    var tagName: String
}

private enum QuietTypeUpdaterError: LocalizedError {
    case releaseUnavailable(Int)
    case releaseDecodeFailed
    case noDMGAsset
    case downloadUnavailable(Int)
    case mountFailed
    case appMissingInDMG
    case bundleIdentifierMismatch(expected: String, actual: String)
    case signingTeamMismatch(expected: String, actual: String)
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
        case .signingTeamMismatch(let expected, let actual):
            return "The downloaded app is signed by team \(actual), expected \(expected). Update cancelled."
        case .installFailed(let reason):
            return reason
        case .commandFailed(let command, let code, let output):
            return "\(command) failed with exit code \(code). \(output)"
        }
    }

    var shouldOpenReleasesPage: Bool {
        switch self {
        case .releaseUnavailable(let status), .downloadUnavailable(let status):
            return status == 401 || status == 403 || status == 404
        case .noDMGAsset:
            return true
        default:
            return false
        }
    }
}

private struct QuietTypeGitHubRelease: Decodable {
    var tagName: String
    var name: String?
    var prerelease: Bool?
    var draft: Bool?
    var assets: [QuietTypeGitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
        case draft
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        return parse("v\(version)-beta.\(build)") ?? QuietTypeReleaseVersion(major: 1, minor: 0, patch: 0, betaBuild: build)
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
    private let releasesURL = URL(string: "https://api.github.com/repos/l33tdawg/quiettype/releases?per_page=20")!
    private let releasesPageURL = URL(string: "https://github.com/l33tdawg/quiettype/releases/latest")!
    private let expectedSigningTeamID = "2N7GKZ8D8Z"
    private let fileManager = FileManager.default

    func openReleasesPage() {
        NSWorkspace.shared.open(releasesPageURL)
    }

    func checkAvailability() async throws -> QuietTypeUpdateAvailability? {
        let (release, _, latestVersion) = try await latestReleaseAsset()
        let currentVersion = QuietTypeReleaseVersion.current()
        guard latestVersion > currentVersion else {
            return nil
        }
        return QuietTypeUpdateAvailability(
            versionLabel: display(latestVersion),
            tagName: release.tagName
        )
    }

    func checkDownloadBackupAndInstall(progress: @escaping @MainActor (String) -> Void) async throws -> QuietTypeUpdateResult {
        await progress("Checking GitHub Releases...")
        let (release, asset, latestVersion) = try await latestReleaseAsset()
        let currentVersion = QuietTypeReleaseVersion.current()
        guard latestVersion > currentVersion else {
            return QuietTypeUpdateResult(
                message: "QuietType is up to date. You are running \(display(currentVersion)).",
                requiresRestart: false
            )
        }

        await progress("Found \(display(latestVersion)). Downloading the Apple Silicon DMG...")
        let dmgURL = try await download(asset)
        await progress("Downloaded \(asset.name) from \(release.tagName). Verifying the installer...")
        let mountedVolume = try mount(dmgURL)
        defer {
            _ = try? run("/usr/bin/hdiutil", arguments: ["detach", mountedVolume.path])
        }

        let sourceApp = mountedVolume.appendingPathComponent("QuietType.app", isDirectory: true)
        guard fileManager.fileExists(atPath: sourceApp.path) else {
            throw QuietTypeUpdaterError.appMissingInDMG
        }

        try verifyBundleIdentity(sourceApp)
        try verifyCandidateApp(sourceApp)
        await progress("Verified \(display(latestVersion)). Backing up the current app before installing...")
        let backupURL = try backupAndInstall(sourceApp: sourceApp)
        do {
            try verifyInstalledApp()
        } catch {
            var restoreDetail = ""
            if let backupURL {
                do {
                    try restoreBackup(from: backupURL)
                    restoreDetail = " The previous app was restored from backup."
                } catch {
                    restoreDetail = " Restore failed; the backup is at \(backupURL.path)."
                }
            }
            throw QuietTypeUpdaterError.installFailed("Update verification failed.\(restoreDetail) \(error.localizedDescription)")
        }

        return QuietTypeUpdateResult(
            message: "Installed \(display(latestVersion)) in /Applications. Restart QuietType to use the new version.",
            requiresRestart: true
        )
    }

    private func latestReleaseAsset() async throws -> (QuietTypeGitHubRelease, QuietTypeGitHubAsset, QuietTypeReleaseVersion) {
        let releases = try await fetchReleases()
        let candidates: [(QuietTypeGitHubRelease, QuietTypeGitHubAsset, QuietTypeReleaseVersion)] = releases.compactMap { release in
            guard release.draft != true,
                  let asset = release.assets.first(where: Self.isMacOSArm64DMG),
                  let version = QuietTypeReleaseVersion.parse(release.tagName) ?? QuietTypeReleaseVersion.parse(asset.name) else {
                return nil
            }
            return (release, asset, version)
        }

        guard let best = candidates.max(by: { $0.2 < $1.2 }) else {
            throw QuietTypeUpdaterError.noDMGAsset
        }
        return best
    }

    private static func isMacOSArm64DMG(_ asset: QuietTypeGitHubAsset) -> Bool {
        asset.name.localizedCaseInsensitiveContains("macOS-arm64.dmg")
            || asset.name.localizedCaseInsensitiveContains("macos-arm64.dmg")
    }

    private func fetchReleases() async throws -> [QuietTypeGitHubRelease] {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuietType-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuietTypeUpdaterError.releaseUnavailable(http.statusCode)
        }
        do {
            return try JSONDecoder().decode([QuietTypeGitHubRelease].self, from: data)
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

    private func backupAndInstall(sourceApp: URL) throws -> URL? {
        let destinationApp = URL(fileURLWithPath: "/Applications/QuietType.app", isDirectory: true)
        let temporaryInstall = URL(fileURLWithPath: "/Applications/QuietType.app.updating", isDirectory: true)
        var backupURL: URL?

        if fileManager.fileExists(atPath: destinationApp.path) {
            let backupDirectory = try applicationSupportDirectory()
                .appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let appBackupURL = backupDirectory.appendingPathComponent("QuietType-\(timestamp()).app", isDirectory: true)
            try fileManager.copyItem(at: destinationApp, to: appBackupURL)
            backupURL = appBackupURL
        }

        if fileManager.fileExists(atPath: temporaryInstall.path) {
            try fileManager.removeItem(at: temporaryInstall)
        }
        do {
            try fileManager.copyItem(at: sourceApp, to: temporaryInstall)
            if fileManager.fileExists(atPath: destinationApp.path) {
                try fileManager.removeItem(at: destinationApp)
            }
            try fileManager.moveItem(at: temporaryInstall, to: destinationApp)
            return backupURL
        } catch {
            if fileManager.fileExists(atPath: temporaryInstall.path) {
                try? fileManager.removeItem(at: temporaryInstall)
            }
            if let backupURL, !fileManager.fileExists(atPath: destinationApp.path) {
                try? fileManager.copyItem(at: backupURL, to: destinationApp)
            }
            throw QuietTypeUpdaterError.installFailed("Update install failed. \(error.localizedDescription)")
        }
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

    private func verifyCandidateApp(_ appURL: URL) throws {
        _ = try run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", "--verbose=2", appURL.path])
        let signature = try run("/usr/bin/codesign", arguments: ["-dv", "--verbose=4", appURL.path])
        try verifySigningTeam(in: signature)
        _ = try run("/usr/sbin/spctl", arguments: ["-a", "-t", "exec", "-vv", appURL.path])
    }

    private func verifySigningTeam(in codesignOutput: String) throws {
        let actual = codesignOutput
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
            ?? "missing"
        guard actual == expectedSigningTeamID else {
            throw QuietTypeUpdaterError.signingTeamMismatch(expected: expectedSigningTeamID, actual: actual)
        }
    }

    private func restoreBackup(from backupURL: URL) throws {
        let destinationApp = URL(fileURLWithPath: "/Applications/QuietType.app", isDirectory: true)
        let failedInstall = URL(fileURLWithPath: "/Applications/QuietType.app.failed-\(timestamp())", isDirectory: true)
        if fileManager.fileExists(atPath: failedInstall.path) {
            try fileManager.removeItem(at: failedInstall)
        }
        if fileManager.fileExists(atPath: destinationApp.path) {
            try fileManager.moveItem(at: destinationApp, to: failedInstall)
        }
        try fileManager.copyItem(at: backupURL, to: destinationApp)
        try verifyInstalledApp()
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
    @Published var hiddenReviewMemoryIDs: Set<String> = []
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
    @Published var lastWordsPerMinute = 0
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
    @Published var profanityFilterEnabled = true
    @Published var typingReminderEnabled = true
    @Published var teachRaw = ""
    @Published var teachCorrected = ""
    @Published var teachingKind = TeachingKind.correction
    @Published var teachingContext = ""
    @Published var isTeachingRecording = false
    @Published var teachingSampleCount = 0
    @Published var teachingSampleStatus = "Record a sample so QuietType can hear the word."
    @Published var teachingInputLevel = 0.0
    @Published var teachingDetectedForms: [String] = []
    @Published var localMemories: [DictationMemory] = []
    @Published var memoryFilter = MemoryFilter.all
    @Published var didSaveTeachingMemory = false
    @Published var voiceNoteQuery = ""
    @Published var selectedVoiceNoteID: String?
    @Published var isVoiceNoteRecording = false
    @Published var isVoiceNoteTranscribing = false
    @Published var voiceNoteDuration = 0.0
    @Published var voiceNoteInputLevel = 0.0
    @Published var saveVoiceNotesToSage = false
    @Published var playingVoiceNoteID: String?
    @Published var isVoiceNotePlaying = false
    @Published var voiceNotePlaybackProgress = 0.0
    @Published var voiceNotePlaybackDuration = 0.0
    @Published var voiceNotePlaybackVolume = 0.82
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
    @Published var availableUpdate: QuietTypeUpdateAvailability?
    @Published var isUpdateOverlayVisible = false
    @Published var updateOverlayTitle = "Updating QuietType"
    @Published var updateOverlayDetail = "Preparing the signed update."
    @Published var updateProgressMessages: [String] = []
    @Published var updateInstallCompleted = false
    @Published var updateInstallFailed = false
    @Published var updateInstallRequiresRestart = false
    @Published var isInstallingSage = false
    @Published var sageInstallStatus = ""
    @Published var storageSnapshot = QuietTypeStorageSnapshot.empty
    @Published var storageCleanupStatus = ""

    private let permissionService = MacOSPermissionService()
    private let memoryStore = SQLiteMemoryStore.persistentDefault()
    private let updateService = QuietTypeGitHubUpdater()
    private let sageInstaller = SageGitHubInstaller()
    private var sageDirectClient: SageDirectClient?
    private var sageServeProcess: Process?
    private var whisperKitSupervisor: WhisperKitServerSupervisor?
    private var nativeInferencePrewarmed = false
    private var didStartAppServices = false
    private var nativeSpeechStartupTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var dictionarySearchTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var captureService: AVAudioCaptureService?
    private var trainingCaptureService: AVAudioCaptureService?
    private var teachingCaptureService: AVAudioCaptureService?
    private var voiceNoteCaptureService: AVAudioCaptureService?
    private var recordingStartedAt: Date?
    private var trainingStartedAt: Date?
    private var teachingStartedAt: Date?
    private var voiceNoteStartedAt: Date?
    private var recordedSamples: [Float] = []
    private var trainingSamples: [Float] = []
    private var teachingSamples: [Float] = []
    private var voiceNoteSamples: [Float] = []
    private var recordingSampleRate = 16_000
    private var trainingSampleRate = 16_000
    private var teachingSampleRate = 16_000
    private var voiceNoteSampleRate = 16_000
    private var peakInputLevel = 0.0
    private var peakTrainingInputLevel = 0.0
    private var peakInputRMS = 0.0
    private var peakTrainingInputRMS = 0.0
    private var peakTeachingInputRMS = 0.0
    private var peakVoiceNoteInputRMS = 0.0
    private var inputNoiseFloorRMS = 0.006
    private var trainingNoiseFloorRMS = 0.006
    private var teachingNoiseFloorRMS = 0.006
    private var voiceNoteNoiseFloorRMS = 0.006
    private var trainingFrameCount = 0
    private var teachingFrameCount = 0
    private var voiceNoteFrameCount = 0
    private var lastTrainingAudioURL: URL?
    private var voiceNoteAudioPlayer: AVAudioPlayer?
    private var voiceNotePlaybackTimer: Timer?
    private var voiceNotePlaybackTempURL: URL?
    private lazy var voiceNoteAudioStore = EncryptedVoiceNoteAudioStore(directory: voiceNoteAudioDirectory)
    private var chunker = StreamingWavChunker()
    private let chunkDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("quiettype-stream")
    private var streamingTranscriptionSession: StreamingAudioTranscriptionSession?
    private var pendingStreamingChunks: [WavAudioChunk] = []
    private var activeTranscriptionOptions = AudioTranscriptionOptions.none
    private var hotKeyController: CarbonHotKeyController?
    private var functionKeyMonitor: FunctionKeyToggleMonitor?
    private var typingReminderMonitor: TypingReminderMonitor?
    private var cancelKeyGlobalMonitor: Any?
    private var cancelKeyLocalMonitor: Any?
    private var lastHotKeyToggleAt: Date?
    private let overlayController = DictationOverlayController()
    private var cpuSampler = CPUUsageSampler()
    private var microphoneAccessVerified = false
    private static let hotKeyChoiceKey = "quiettype.hotKeyChoice"
    private static let spellingPreferenceKey = "quiettype.spellingPreference"
    private static let profanityFilterEnabledKey = "quiettype.profanityFilterEnabled"
    private static let typingReminderEnabledKey = "quiettype.typingReminderEnabled"
    private static let calibrationSavedCountKey = "quiettype.calibrationSavedCount"
    private static let trainingPairCountKey = "quiettype.trainingPairCount"
    private static let sessionsTodayKey = "quiettype.sessionsToday"
    private static let sessionsTodayDateKey = "quiettype.sessionsTodayDate"
    private static let totalTranslatedWordCountKey = "quiettype.totalTranslatedWordCount"
    private static let lastWordsPerMinuteKey = "quiettype.lastWordsPerMinute"
    private static let historyReviewEnabledKey = "quiettype.historyReviewEnabled"
    private static let saveVoiceNotesToSageKey = "quiettype.saveVoiceNotesToSage"
    private static let hiddenReviewMemoryIDsKey = "quiettype.hiddenReviewMemoryIDs"
    private static let availableUpdateKey = "quiettype.availableUpdate"
    private static let notifiedUpdateTagKey = "quiettype.notifiedUpdateTag"
    private static let backgroundUpdateRefreshInterval: UInt64 = 60 * 60 * 1_000_000_000
    private static let requiredCalibrationSets = 3
    private static let maxDictationDurationSeconds = 300.0
    private static let maxTrainingPairCount = 10
    private static let maxReviewAudioFiles = 10
    private static let streamingTranscriptMinimumDuration = 8.0
    private static let minimumUsableRMS = 0.0015

    init() {
        calibrationSavedCount = UserDefaults.standard.integer(forKey: Self.calibrationSavedCountKey)
        trainingPairCount = UserDefaults.standard.integer(forKey: Self.trainingPairCountKey)
        sessionsToday = Self.loadSessionsToday()
        totalTranslatedWordCount = UserDefaults.standard.integer(forKey: Self.totalTranslatedWordCountKey)
        lastWordsPerMinute = UserDefaults.standard.integer(forKey: Self.lastWordsPerMinuteKey)
        availableUpdate = Self.loadAvailableUpdate()
        hiddenReviewMemoryIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenReviewMemoryIDsKey) ?? [])
        historyReviewEnabled = true
        UserDefaults.standard.set(true, forKey: Self.historyReviewEnabledKey)
        if UserDefaults.standard.object(forKey: Self.saveVoiceNotesToSageKey) == nil {
            saveVoiceNotesToSage = true
            UserDefaults.standard.set(true, forKey: Self.saveVoiceNotesToSageKey)
        } else {
            saveVoiceNotesToSage = UserDefaults.standard.bool(forKey: Self.saveVoiceNotesToSageKey)
        }
        if let storedSpelling = UserDefaults.standard.string(forKey: Self.spellingPreferenceKey),
           let preference = SpellingPreference(rawValue: storedSpelling) {
            spellingPreference = preference
        }
        if UserDefaults.standard.object(forKey: Self.profanityFilterEnabledKey) == nil {
            profanityFilterEnabled = true
        } else {
            profanityFilterEnabled = UserDefaults.standard.bool(forKey: Self.profanityFilterEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.typingReminderEnabledKey) == nil {
            typingReminderEnabled = true
        } else {
            typingReminderEnabled = UserDefaults.standard.bool(forKey: Self.typingReminderEnabledKey)
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
        dictionarySearchTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    var statusIcon: String {
        isRunning ? "waveform" : "mic"
    }

    var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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
            return "Speak naturally, then press \(hotKeyLabel) or click the mic again to insert. Press Esc or X to cancel."
        }
        if nativeSpeechServerReady {
            return "Ready for private Apple Silicon dictation. Text inserts automatically."
        }
        if fallbackSpeechReady {
            return "Native speech is warming. QuietType will start when the Apple Silicon engine is ready."
        }
        return "Secure transcription is starting in the background."
    }

    var startupSummary: String {
        if nativeSpeechServerReady {
            return "Native speech ready"
        }
        if fallbackSpeechReady {
            return "Native speech starting"
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
        !teachingDetectedForms.isEmpty
            && !teachRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var teachingRecordButtonTitle: String {
        if isTeachingRecording {
            return "Stop"
        }
        return "Record sample \(min(teachingSampleCount + 1, 3))"
    }

    var lessonPreviewText: String {
        let raw = teachRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let corrected = teachCorrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !corrected.isEmpty else {
            return teachingSampleCount == 0 ? "Record the word first. QuietType will show what it heard here." : "Enter the spelling QuietType should write."
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
        if let currentWPM = Self.wordsPerMinute(wordCount: words, duration: duration) {
            return "\(currentWPM) WPM"
        }
        if lastWordsPerMinute > 0 {
            return "\(lastWordsPerMinute) WPM"
        }
        if calibrationSavedCount > 0 {
            return "\(currentDictationProfile().speechRateWPM) WPM"
        }
        return "Ready"
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
        Set(
            localMemories.compactMap { lessonID(from: $0) }
                + sageMemories.compactMap { lessonID(from: $0) }
        ).count
    }

    var sageCorrectionCount: Int {
        localMemories.filter { $0.type == .correction }.count
            + sageMemories.filter { $0.content.localizedCaseInsensitiveContains("correction") }.count
    }

    var transcriptNoteCount: Int {
        let localIDs = localMemories
            .filter { $0.type == .transcriptNote }
            .compactMap { $0.payload["sage_memory_id"]?.nilIfBlank ?? $0.id }
        let sageIDs = sageMemories
            .filter { $0.domain == "quiettype.transcripts" }
            .map(\.id)
        return Set(localIDs + sageIDs).count
    }

    private func lessonID(from memory: DictationMemory) -> String? {
        guard memory.type != .transcriptNote || isReviewedTranscriptLesson(memory) else {
            return nil
        }
        return memory.id
    }

    private func lessonID(from memory: SageMemoryRecord) -> String? {
        guard memory.domain != "quiettype.transcripts" || isReviewedTranscriptLesson(memory) else {
            return nil
        }
        return memory.id
    }

    private func isReviewedTranscriptLesson(_ memory: DictationMemory) -> Bool {
        memory.payload["reviewed_by_user"] == "true"
    }

    private func isReviewedTranscriptLesson(_ memory: SageMemoryRecord) -> Bool {
        memory.content.localizedCaseInsensitiveContains("QuietType reviewed transcript note")
            || memory.content.localizedCaseInsensitiveContains("Corrected raw transcript:")
            || memory.content.localizedCaseInsensitiveContains("Corrected polished output:")
    }

    private var processedWordCount: Int {
        totalTranslatedWordCount
    }

    private var reviewAudioDirectory: URL {
        quietTypeApplicationSupportDirectory
            .appendingPathComponent("ReviewAudio", isDirectory: true)
    }

    private var voiceNoteAudioDirectory: URL {
        quietTypeApplicationSupportDirectory
            .appendingPathComponent("VoiceNotes", isDirectory: true)
    }

    private var quietTypeApplicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuietType", isDirectory: true)
    }

    private var updateDownloadsDirectory: URL {
        quietTypeApplicationSupportDirectory
            .appendingPathComponent("Updates", isDirectory: true)
    }

    private var updateBackupsDirectory: URL {
        quietTypeApplicationSupportDirectory
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private var sageHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sage", isDirectory: true)
    }

    private var sageLogURL: URL {
        sageHomeDirectory.appendingPathComponent("sage.log")
    }

    var voiceNotes: [VoiceNoteItem] {
        localMemories
            .filter { $0.type == .voiceNote }
            .map(voiceNoteItem)
            .sorted { lhs, rhs in
                (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
    }

    var filteredVoiceNotes: [VoiceNoteItem] {
        let query = voiceNoteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return voiceNotes
        }

        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return voiceNotes.filter { note in
            let haystack = [
                note.title,
                note.rawTranscript,
                note.polishedText,
                note.displayDate
            ].joined(separator: " ")
            return terms.allSatisfy { term in
                haystack.localizedCaseInsensitiveContains(term)
            }
        }
    }

    var selectedVoiceNote: VoiceNoteItem? {
        let notes = filteredVoiceNotes
        if let selectedVoiceNoteID,
           let selected = notes.first(where: { $0.id == selectedVoiceNoteID }) {
            return selected
        }
        return notes.first
    }

    var voiceNoteStatusTitle: String {
        if isVoiceNoteRecording {
            return "Recording locally"
        }
        if isVoiceNoteTranscribing {
            return "Transcribing"
        }
        return saveVoiceNotesToSage ? "SAGE copy on" : "Local only"
    }

    var voiceNoteStatusDetail: String {
        if isVoiceNoteRecording {
            return "\(String(format: "%.1f", voiceNoteDuration))s captured"
        }
        if isVoiceNoteTranscribing {
            return "Encrypting audio and saving transcript"
        }
        return saveVoiceNotesToSage ? "Audio stays on this Mac" : "New notes stay on this Mac"
    }

    var dictionaryMemories: [DictionaryMemoryItem] {
        let localIDs = Set(localMemories.compactMap(\.id))
        let localSageIDs = Set(localMemories.compactMap { $0.payload["sage_memory_id"]?.nilIfBlank })
        let sageIDs = Set(sageMemories.map(\.id))
        let localItems = localMemories
            .filter { $0.type == .transcriptNote && !hiddenReviewMemoryIDs.contains($0.id ?? "") }
            .map { memory in
            let createdAt = memory.payload["created_at"].flatMap { ISO8601DateFormatter().date(from: $0) }
            let sageMemoryID = memory.payload["sage_memory_id"]?.nilIfBlank
            return DictionaryMemoryItem(
                id: memory.id ?? UUID().uuidString,
                title: memory.payload["corrected"]
                    ?? memory.payload["preferred"]
                    ?? memory.payload["polished_text"]?.prefix(64).description
                    ?? memory.type.rawValue,
                summary: memorySummary(from: memory),
                kind: "Transcript",
                confidence: memory.confidence,
                source: memory.payload["app"]?.nilIfBlank ?? "QuietType",
                rawTranscript: memory.payload["raw_transcript"],
                polishedText: memory.payload["polished_text"],
                audioPath: memory.payload["audio_path"]?.nilIfBlank,
                createdAt: createdAt,
                isEditableTranscript: true,
                hasLocalCopy: true,
                hasSageMemory: sageMemoryID != nil || memory.id.map { sageIDs.contains($0) } ?? false
            )
        }

        let sageItems = sageMemories
            .filter {
                $0.domain == "quiettype.transcripts"
                    && !hiddenReviewMemoryIDs.contains($0.id)
                    && !localSageIDs.contains($0.id)
            }
            .map { memory in
            let transcript = transcriptMemoryParts(from: memory.content)
            return DictionaryMemoryItem(
                id: memory.id,
                title: memoryTitle(from: memory.content),
                summary: memory.content.isEmpty ? "Memory content unavailable." : memory.content,
                kind: "Transcript",
                confidence: memory.confidence,
                source: transcript.appName?.nilIfBlank ?? "QuietType",
                rawTranscript: transcript.rawTranscript,
                polishedText: transcript.polishedText,
                audioPath: transcript.audioPath,
                createdAt: memory.createdAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                isEditableTranscript: true,
                hasLocalCopy: localIDs.contains(memory.id),
                hasSageMemory: true
            )
        }

        return (localItems + sageItems).sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    var filteredDictionaryMemories: [DictionaryMemoryItem] {
        var seenMemoryIDs = Set<String>()
        let reviewMemories = dictionaryMemories.filter { memory in
            seenMemoryIDs.insert(memory.id).inserted
        }

        let query = sageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return reviewMemories
        }

        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return reviewMemories.filter { memory in
            let haystack = [
                memory.title,
                memory.summary,
                memory.kind,
                memory.source,
                memory.id,
                memory.rawTranscript ?? "",
                memory.polishedText ?? ""
            ].joined(separator: " ")

            return terms.allSatisfy { term in
                haystack.localizedCaseInsensitiveContains(term)
            }
        }
    }

    private static let reviewMemoryLimit = 100
    private static let defaultMemorySearchQuery = "QuietType dictation translation correction vocabulary spelling style transcript transcription spoken phrase preferred wording"

    private func transcriptMemoryParts(from content: String) -> TranscriptMemoryParts {
        let raw = labeledQuotedValue(
            from: content,
            labels: [
                "Corrected raw transcript:",
                "Raw transcript:",
                "Raw local ASR heard:"
            ],
            terminators: [
                "\". Corrected polished output:",
                "\". Polished output:",
                "\". This is",
                "\". User-reviewed",
                "\"."
            ]
        )
        let polished = labeledQuotedValue(
            from: content,
            labels: [
                "Corrected polished output:",
                "Polished output:",
                "Expected script:"
            ],
            terminators: [
                "\". User-reviewed",
                "\". This is",
                "\"."
            ]
        )
        let app = labeledPlainValue(from: content, label: "App:")
        let audioPath = labeledQuotedValue(
            from: content,
            labels: ["Audio path:"],
            terminators: [
                "\". Word timings base64:",
                "\". Raw transcript:",
                "\". Corrected raw transcript:",
                "\". This is",
                "\"."
            ]
        )
        let wordTimingsBase64 = labeledQuotedValue(
            from: content,
            labels: ["Word timings base64:"],
            terminators: [
                "\". Raw transcript:",
                "\". Corrected raw transcript:",
                "\". This is",
                "\"."
            ]
        )

        return TranscriptMemoryParts(
            rawTranscript: raw,
            polishedText: polished,
            appName: app,
            audioPath: audioPath,
            wordTimingsBase64: wordTimingsBase64
        )
    }

    private func labeledQuotedValue(from content: String, labels: [String], terminators: [String]) -> String? {
        for label in labels {
            guard let labelRange = content.range(of: label, options: [.caseInsensitive]) else {
                continue
            }

            var remainder = String(content[labelRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.first == "\"" {
                remainder.removeFirst()
            }

            let endIndex = terminators
                .compactMap { remainder.range(of: $0)?.lowerBound }
                .min()
            let value = endIndex.map { String(remainder[..<$0]) } ?? remainder
            let cleaned = value.cleanedTranscriptMemoryValue
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
    }

    private func labeledPlainValue(from content: String, label: String) -> String? {
        guard let labelRange = content.range(of: label, options: [.caseInsensitive]) else {
            return nil
        }

        let remainder = String(content[labelRange.upperBound...])
        let end = remainder.firstIndex(of: ".") ?? remainder.endIndex
        let cleaned = String(remainder[..<end]).cleanedTranscriptMemoryValue
        return cleaned.isEmpty ? nil : cleaned
    }

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
        case .voiceNote:
            return memory.payload["polished_text"] ?? memory.payload["raw_transcript"] ?? "Encrypted local voice note."
        }
    }

    private func voiceNoteItem(from memory: DictationMemory) -> VoiceNoteItem {
        let raw = memory.payload["raw_transcript"] ?? ""
        let polished = memory.payload["polished_text"] ?? raw
        let createdAt = memory.payload["created_at"]
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let title = memory.payload["title"]?.nilIfBlank
            ?? Self.defaultVoiceNoteTitle(from: polished.nilIfBlank ?? raw, createdAt: createdAt)
        return VoiceNoteItem(
            id: memory.id ?? UUID().uuidString,
            title: title,
            rawTranscript: raw,
            polishedText: polished,
            audioPath: memory.payload["audio_path"]?.nilIfBlank,
            durationSeconds: Double(memory.payload["duration_seconds"] ?? "") ?? 0,
            createdAt: createdAt,
            sentToSage: memory.payload["sent_to_sage"] == "true",
            sageMemoryID: memory.payload["sage_memory_id"]?.nilIfBlank,
            sentToSageAt: memory.payload["sent_to_sage_at"]?.nilIfBlank
        )
    }

    private static func defaultVoiceNoteTitle(from text: String, createdAt: Date?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(48))
        }
        if let createdAt {
            return "Voice note \(createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Voice note"
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

    private static func wordsPerMinute(wordCount: Int, duration: TimeInterval) -> Int? {
        guard wordCount > 0, duration > 0.25 else {
            return nil
        }
        return Int((Double(wordCount) / duration) * 60.0)
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

    private static func loadAvailableUpdate() -> QuietTypeUpdateAvailability? {
        guard let data = UserDefaults.standard.data(forKey: availableUpdateKey),
              let update = try? JSONDecoder().decode(QuietTypeUpdateAvailability.self, from: data) else {
            return nil
        }
        return update
    }

    private static func saveAvailableUpdate(_ update: QuietTypeUpdateAvailability?) {
        if let update,
           let data = try? JSONEncoder().encode(update) {
            UserDefaults.standard.set(data, forKey: availableUpdateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: availableUpdateKey)
        }
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
            sageStatus = "SAGE required"
            updateStartupStep(
                id: "sage",
                detail: "SAGE not found. QuietType requires SAGE governed memory.",
                state: .warning
            )
            return
        }

        if sageAgentStatus == "Registered", sageDirectClient != nil {
            sageStatus = "SAGE connected · quiettype-agent"
            sageInstallStatus = ""
            updateStartupStep(
                id: "sage",
                detail: "quiettype-agent registered with local SAGE.",
                state: .ready
            )
            return
        }

        sageStatus = "SAGE detected · registration pending"
        updateStartupStep(
            id: "sage",
            detail: "SAGE app detected. quiettype-agent registration is pending.",
            state: .ready
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

        startupSteps.removeAll { $0.id == "fallbackSpeech" }
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

    private func startBackgroundUpdateChecks() {
        guard updateCheckTask == nil else {
            return
        }

        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAvailableUpdateInBackground()
                try? await Task.sleep(nanoseconds: Self.backgroundUpdateRefreshInterval)
            }
        }
    }

    private func refreshAvailableUpdateInBackground() async {
        do {
            if let update = try await updateService.checkAvailability() {
                availableUpdate = update
                Self.saveAvailableUpdate(update)
                await notifyUpdateAvailableIfNeeded(update)
            } else {
                availableUpdate = nil
                Self.saveAvailableUpdate(nil)
            }
        } catch {
            // Background checks should never interrupt dictation or setup.
        }
    }

    private func notifyUpdateAvailableIfNeeded(_ update: QuietTypeUpdateAvailability) async {
        guard UserDefaults.standard.string(forKey: Self.notifiedUpdateTagKey) != update.tagName else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "QuietType update available"
        content.body = "\(update.versionLabel) is ready to install."
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "quiettype.update.\(update.tagName)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(update.tagName, forKey: Self.notifiedUpdateTagKey)
        } catch {
            // Notification delivery is best-effort; the in-app banner remains visible.
        }
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

        beginUpdateOverlay()
        isCheckingForUpdates = true
        recordUpdateProgress("Preparing QuietType for update.")
        await suspendAppForUpdateInstall()
        recordUpdateProgress("Checking GitHub Releases.")
        defer {
            isCheckingForUpdates = false
        }

        do {
            let result = try await updateService.checkDownloadBackupAndInstall { [weak self] message in
                self?.recordUpdateProgress(message)
            }
            updateStatus = result.message
            updateOverlayDetail = result.message
            updateInstallCompleted = true
            updateInstallRequiresRestart = result.requiresRestart
            updateOverlayTitle = result.requiresRestart ? "Update installed" : "No update found"
            recordUpdateProgress(result.message)
            if result.requiresRestart {
                availableUpdate = nil
                Self.saveAvailableUpdate(nil)
            } else {
                resumeAppServicesAfterUpdateIfNeeded()
            }
        } catch let error as QuietTypeUpdaterError where error.shouldOpenReleasesPage {
            updateStatus = "Update check needs GitHub release access: \(error.localizedDescription) Opening the QuietType releases page."
            updateOverlayTitle = "Update needs release access"
            updateOverlayDetail = error.localizedDescription
            updateInstallFailed = true
            recordUpdateProgress(updateStatus)
            resumeAppServicesAfterUpdateIfNeeded()
            updateService.openReleasesPage()
        } catch {
            updateStatus = "Update check failed: \(error.localizedDescription)"
            updateOverlayTitle = "Update failed"
            updateOverlayDetail = error.localizedDescription
            updateInstallFailed = true
            recordUpdateProgress(updateStatus)
            resumeAppServicesAfterUpdateIfNeeded()
        }
    }

    private func beginUpdateOverlay() {
        isUpdateOverlayVisible = true
        updateOverlayTitle = "Updating QuietType"
        updateOverlayDetail = "Downloading and verifying the signed update."
        updateProgressMessages = []
        updateInstallCompleted = false
        updateInstallFailed = false
        updateInstallRequiresRestart = false
        updateStatus = ""
    }

    private func recordUpdateProgress(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        updateStatus = trimmed
        updateOverlayDetail = trimmed
        if updateProgressMessages.last != trimmed {
            updateProgressMessages.append(trimmed)
        }
    }

    func dismissUpdateOverlay() {
        guard !isCheckingForUpdates else {
            return
        }
        isUpdateOverlayVisible = false
    }

    func restartInstalledApp() {
        let script = "sleep 0.6; open -a '/Applications/QuietType.app'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApplication.shared.terminate(nil)
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
        sageInstallStatus = "Checking local SAGE..."
        statusMessage = "Checking SAGE memory"
        refreshSageStatus()
        await registerSageAgentIfAvailable()
        if sageReady {
            sageInstallStatus = ""
            if statusMessage.localizedCaseInsensitiveContains("sage") {
                statusMessage = ""
            }
        }
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
            await refreshLocalMemories()
            await registerSageAgentIfAvailable()
            await refreshPermissions(promptForAccessibility: false)
            refreshSpeechEngineStatus()
            registerGlobalHotKey()
            registerCancelKeyMonitor()
            registerTypingReminderMonitor()
            startNativeSpeechWarmup()
            startBackgroundUpdateChecks()
            repairSensitiveStoragePermissions()
            refreshStorageSnapshot()
        }
    }

    private func repairSensitiveStoragePermissions() {
        let directories = [
            reviewAudioDirectory,
            voiceNoteAudioDirectory,
            trainingDirectory()
        ]
        Task.detached(priority: .utility) {
            for directory in directories {
                Self.repairOwnerOnlyStorage(at: directory)
            }
        }
    }

    func refreshStorageSnapshot() {
        let reviewAudioDirectory = reviewAudioDirectory
        let voiceNoteAudioDirectory = voiceNoteAudioDirectory
        let trainingDirectory = trainingDirectory()
        let updateDownloadsDirectory = updateDownloadsDirectory
        let updateBackupsDirectory = updateBackupsDirectory
        let sageHomeDirectory = sageHomeDirectory
        let sageLogURL = sageLogURL
        let maxReviewAudioFiles = Self.maxReviewAudioFiles

        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                let entries = [
                    Self.storageEntry(
                        id: "review-audio",
                        title: "Review audio cache",
                        detail: "Plain WAV review clips, capped at \(maxReviewAudioFiles) recent dictations.",
                        urls: [reviewAudioDirectory]
                    ),
                    Self.storageEntry(
                        id: "voice-notes",
                        title: "Encrypted voice notes",
                        detail: "Encrypted .qtvoice files for saved local voice notes.",
                        urls: [voiceNoteAudioDirectory]
                    ),
                    Self.storageEntry(
                        id: "training",
                        title: "Training samples",
                        detail: "Local WAV samples used for calibration and spelling corrections.",
                        urls: [trainingDirectory]
                    ),
                    Self.storageEntry(
                        id: "updates",
                        title: "Update downloads",
                        detail: "Downloaded DMGs and app backups from the signed updater.",
                        urls: [updateDownloadsDirectory, updateBackupsDirectory]
                    ),
                    Self.storageEntry(
                        id: "sage-home",
                        title: "SAGE home",
                        detail: "Local governed memory, snapshots, indexes, and logs under ~/.sage.",
                        urls: [sageHomeDirectory]
                    ),
                    Self.storageEntry(
                        id: "sage-log",
                        title: "Current SAGE log",
                        detail: "The active ~/.sage/sage.log file. This row is included so log growth is visible.",
                        urls: [sageLogURL]
                    )
                ]
                return QuietTypeStorageSnapshot(entries: entries, updatedAt: Date())
            }.value
            self?.storageSnapshot = snapshot
        }
    }

    func cleanupReviewAudioCache() {
        do {
            try removeFiles(in: reviewAudioDirectory) { $0.pathExtension.lowercased() == "wav" }
            storageCleanupStatus = "Review audio cache cleared."
        } catch {
            storageCleanupStatus = "Could not clear review audio: \(error.localizedDescription)"
        }
        refreshStorageSnapshot()
    }

    func cleanupTrainingSamples() {
        do {
            try removeDirectoryContents(trainingDirectory())
            trainingPairCount = 0
            lastTrainingAudioURL = nil
            UserDefaults.standard.set(trainingPairCount, forKey: Self.trainingPairCountKey)
            storageCleanupStatus = "Training samples cleared."
        } catch {
            storageCleanupStatus = "Could not clear training samples: \(error.localizedDescription)"
        }
        refreshStorageSnapshot()
    }

    func cleanupUpdateCache() {
        guard !isCheckingForUpdates else {
            storageCleanupStatus = "Wait for the current update operation to finish."
            return
        }
        do {
            try removeDirectoryContents(updateDownloadsDirectory)
            try removeDirectoryContents(updateBackupsDirectory)
            storageCleanupStatus = "Update downloads and app backups cleared."
        } catch {
            storageCleanupStatus = "Could not clear update downloads: \(error.localizedDescription)"
        }
        refreshStorageSnapshot()
    }

    func trimSageLog() {
        do {
            try OwnerOnlyFileSecurity.prepareDirectory(sageHomeDirectory)
            if FileManager.default.fileExists(atPath: sageLogURL.path) {
                try Data().write(to: sageLogURL, options: [.atomic])
                try OwnerOnlyFileSecurity.protectFile(sageLogURL)
                storageCleanupStatus = "SAGE log trimmed. SAGE may continue writing a new log."
            } else {
                storageCleanupStatus = "No SAGE log found."
            }
        } catch {
            storageCleanupStatus = "Could not trim SAGE log: \(error.localizedDescription)"
        }
        refreshStorageSnapshot()
    }

    func openQuietTypeStorageFolder() {
        try? OwnerOnlyFileSecurity.prepareDirectory(quietTypeApplicationSupportDirectory)
        NSWorkspace.shared.open(quietTypeApplicationSupportDirectory)
    }

    func openSageStorageFolder() {
        NSWorkspace.shared.open(sageHomeDirectory)
    }

    nonisolated private static func storageEntry(
        id: String,
        title: String,
        detail: String,
        urls: [URL]
    ) -> QuietTypeStorageEntry {
        var total: Int64 = 0
        var exists = false
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) {
                exists = true
                total += sizeOnDisk(url)
            }
        }
        return QuietTypeStorageEntry(id: id, title: title, detail: detail, bytes: total, exists: exists)
    }

    nonisolated private static func sizeOnDisk(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            return fileSize(url)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Self.fileSize(fileURL)
        }
        return total
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile != false else {
            return 0
        }
        return Int64(values?.fileSize ?? 0)
    }

    nonisolated private static func repairOwnerOnlyStorage(at directory: URL) {
        let fileManager = FileManager.default
        try? OwnerOnlyFileSecurity.prepareDirectory(directory, fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            if values?.isDirectory == true {
                try? OwnerOnlyFileSecurity.prepareDirectory(url, fileManager: fileManager)
            } else if values?.isRegularFile == true {
                try? OwnerOnlyFileSecurity.protectFile(url, fileManager: fileManager)
            }
        }
    }

    private func removeFiles(in directory: URL, where shouldRemove: (URL) -> Bool) throws {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files where shouldRemove(file) {
            try fileManager.removeItem(at: file)
        }
    }

    private func removeDirectoryContents(_ directory: URL) throws {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files {
            try fileManager.removeItem(at: file)
        }
    }

    private func suspendAppForUpdateInstall() async {
        if isRecording {
            await cancelRecording()
        }
        if isVoiceNoteRecording {
            voiceNoteCaptureService?.stop()
            voiceNoteCaptureService = nil
            isVoiceNoteRecording = false
            voiceNoteSamples = []
            voiceNoteFrameCount = 0
            voiceNoteDuration = 0
            voiceNoteInputLevel = 0
            voiceNoteStartedAt = nil
        }
        if isTrainingRecording {
            trainingCaptureService?.stop()
            trainingCaptureService = nil
            isTrainingRecording = false
            trainingSamples = []
            trainingDuration = 0
            trainingInputLevel = 0
            trainingStartedAt = nil
        }
        if isTeachingRecording {
            resetTeachingDraft()
        }

        stopVoiceNotePlayback()
        hotKeyController?.unregister()
        hotKeyController = nil
        functionKeyMonitor?.unregister()
        functionKeyMonitor = nil
        typingReminderMonitor?.unregister()
        typingReminderMonitor = nil
        unregisterCancelKeyMonitor()
        overlayController.hide()
        nativeSpeechStartupTask?.cancel()
        nativeSpeechStartupTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        whisperKitSupervisor?.stop()
        whisperKitSupervisor = nil
        nativeSpeechServerReady = false
        nativeInferencePrewarmed = false
        refreshSpeechEngineStatus()
    }

    private func resumeAppServicesAfterUpdateIfNeeded() {
        guard !updateInstallRequiresRestart else {
            return
        }
        registerGlobalHotKey()
        registerCancelKeyMonitor()
        registerTypingReminderMonitor()
        startNativeSpeechWarmup()
        startBackgroundUpdateChecks()
    }

    func shutdownAppServices() {
        voiceNoteCaptureService?.stop()
        voiceNoteCaptureService = nil
        stopVoiceNotePlayback()
        trainingCaptureService?.stop()
        trainingCaptureService = nil
        hotKeyController?.unregister()
        hotKeyController = nil
        functionKeyMonitor?.unregister()
        functionKeyMonitor = nil
        typingReminderMonitor?.unregister()
        typingReminderMonitor = nil
        unregisterCancelKeyMonitor()
        overlayController.hide()
        nativeSpeechStartupTask?.cancel()
        nativeSpeechStartupTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        whisperKitSupervisor?.stop()
        whisperKitSupervisor = nil
        nativeSpeechServerReady = false
        nativeInferencePrewarmed = false
    }

    func setHotKeyChoice(_ choice: HotKeyChoice) {
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

    func setProfanityFilterEnabled(_ enabled: Bool) {
        profanityFilterEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.profanityFilterEnabledKey)
    }

    func setTypingReminderEnabled(_ enabled: Bool) {
        typingReminderEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.typingReminderEnabledKey)
    }

    func setTeachingKind(_ kind: TeachingKind) {
        guard teachingKind != kind else {
            return
        }

        teachingKind = kind
    }

    func resetTeachingDraft() {
        if isTeachingRecording {
            teachingCaptureService?.stop()
            teachingCaptureService = nil
            isTeachingRecording = false
        }
        teachRaw = ""
        teachCorrected = ""
        teachingContext = ""
        teachingSampleCount = 0
        teachingSampleStatus = "Record a sample so QuietType can hear the word."
        teachingInputLevel = 0
        teachingDetectedForms = []
        teachingSamples = []
        teachingFrameCount = 0
        peakTeachingInputRMS = 0
        teachingNoiseFloorRMS = 0.006
        teachingStartedAt = nil
        didSaveTeachingMemory = false
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
                typingReminderMonitor?.shortcutLabel = hotKeyLabel
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
                typingReminderMonitor?.shortcutLabel = hotKeyLabel
                statusMessage = "Shortcut ready"
            } catch {
                lastError = "Could not register shortcut: \(error)"
            }
        }
    }

    private func registerCancelKeyMonitor() {
        guard cancelKeyGlobalMonitor == nil && cancelKeyLocalMonitor == nil else {
            return
        }

        let handleEscape: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else {
                    return
                }
                await self.cancelRecording()
            }
        }

        cancelKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handleEscape(event)
        }
        cancelKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleEscape(event)
            return event
        }
    }

    private func unregisterCancelKeyMonitor() {
        if let cancelKeyGlobalMonitor {
            NSEvent.removeMonitor(cancelKeyGlobalMonitor)
            self.cancelKeyGlobalMonitor = nil
        }
        if let cancelKeyLocalMonitor {
            NSEvent.removeMonitor(cancelKeyLocalMonitor)
            self.cancelKeyLocalMonitor = nil
        }
    }

    private func registerTypingReminderMonitor() {
        guard typingReminderMonitor == nil else {
            typingReminderMonitor?.shortcutLabel = hotKeyLabel
            return
        }

        let monitor = TypingReminderMonitor()
        monitor.shortcutLabel = hotKeyLabel
        monitor.shouldRemind = { [weak self] in
            guard let self else {
                return false
            }
            return self.shouldShowTypingReminder
        }
        monitor.onReminder = { [weak self] in
            self?.showTypingReminderOverlay()
        }
        monitor.register()
        typingReminderMonitor = monitor
    }

    private func showTypingReminderOverlay() {
        let prompt = hotKeyLabel == "Fn" ? "Press Fn and speak" : "Press \(hotKeyLabel) and speak"
        overlayController.show(
            state: .typingReminder,
            detail: prompt
        )
        overlayController.hide(after: 3.5)
    }

    private var shouldShowTypingReminder: Bool {
        guard typingReminderEnabled,
              sageReady,
              permissionsReady,
              speechEngineReady,
              !isRecording,
              !isRunning,
              !isTrainingRecording,
              !isTeachingRecording else {
            return false
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }

        let appName = frontmost?.localizedName?.lowercased() ?? ""
        let skippedApps = [
            "1password",
            "bitwarden",
            "keychain",
            "password",
            "system settings"
        ]
        return !skippedApps.contains { appName.contains($0) }
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
            var client = try SageDirectClient(endpoint: installation.localEndpoint, identity: identity)
            candidateClient = client
            sageDirectClient = client
            sageAgentID = identity.agentID

            let registration: SageAgentRegistration
            if let existing = try? await client.registeredAgent(agentID: identity.agentID) {
                registration = existing
            } else {
                registration = try await client.registerQuietTypeAgent()
            }
            client = try client.usingRegisteredAgentID(registration.agentID)
            candidateClient = client
            sageDirectClient = client

            markSageRegistered(agentID: registration.agentID)
            await refreshDictionaryMemoriesPreservingRegistration(using: client)
        } catch {
            sageDirectClient = nil
            let sageHealthReachable = await candidateClient?.isHealthy() ?? false
            if sageHealthReachable,
               let candidateClient,
               let identity = try? SageSigningIdentity.loadOrCreate(),
               let existing = try? await candidateClient.registeredAgent(agentID: identity.agentID),
               let recoveredClient = try? candidateClient.usingRegisteredAgentID(existing.agentID) {
                sageDirectClient = recoveredClient
                markSageRegistered(agentID: existing.agentID)
            } else if isSageVaultLocked(error) {
                sageAgentStatus = "Unlock SAGE"
                sageStatus = "SAGE locked · unlock required"
            } else if sageHealthReachable, let candidateClient {
                sageDirectClient = candidateClient
                sageAgentStatus = "Registration needed"
                sageStatus = "SAGE running · registration needed"
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

    private func markSageRegistered(agentID: String) {
        sageAgentID = agentID
        sageAgentStatus = "Registered"
        sageStatus = "SAGE connected · quiettype-agent"
        sageInstallStatus = ""
        if statusMessage.localizedCaseInsensitiveContains("sage")
            || statusMessage.localizedCaseInsensitiveContains("unlock") {
            statusMessage = ""
        }
        lastError = nil
        updateStartupStep(
            id: "sage",
            detail: "quiettype-agent registered with local SAGE.",
            state: .ready
        )
    }

    private func refreshDictionaryMemoriesPreservingRegistration(using client: SageDirectClient) async {
        do {
            await flushPendingSageTranscriptNotes(using: client)
            sageMemories = try await loadSageMemories(using: client, limit: Self.reviewMemoryLimit)
            if lastError?.hasPrefix("SAGE memory") == true || lastError?.hasPrefix("SAGE setup") == true {
                lastError = nil
            }
        } catch {
            // Registration is the first-run gate. Review-memory listing can fail
            // while SAGE is still healthy, already set up, or warming its memory API.
            // Keep the user moving and let Review/Refresh surface memory-specific
            // errors without trapping onboarding.
            sageDirectClient = client
            sageAgentStatus = "Registered"
            sageStatus = "SAGE connected · quiettype-agent"
        }
    }

    private func loadSageMemories(using client: SageDirectClient, limit: Int) async throws -> [SageMemoryRecord] {
        var memories = try await client.listMemories(limit: limit)
        do {
            let searched = try await client.searchMemories(query: Self.defaultMemorySearchQuery, limit: limit)
            for memory in searched where !memories.contains(where: { $0.id == memory.id }) {
                memories.append(memory)
            }
        } catch {
            guard SageDirectClientError.isTextSearchUnavailable(error) else {
                throw error
            }
        }
        return Array(memories.filter { !hiddenReviewMemoryIDs.contains($0.id) }.prefix(limit))
    }

    private func hideReviewMemoryID(_ memoryID: String) {
        hiddenReviewMemoryIDs.insert(memoryID)
        UserDefaults.standard.set(Array(hiddenReviewMemoryIDs), forKey: Self.hiddenReviewMemoryIDsKey)
    }

    private func unhideReviewMemoryID(_ memoryID: String) {
        guard hiddenReviewMemoryIDs.remove(memoryID) != nil else {
            return
        }
        UserDefaults.standard.set(Array(hiddenReviewMemoryIDs), forKey: Self.hiddenReviewMemoryIDsKey)
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
            if status == 423 {
                return true
            }
            if status == 401 {
                return lowered.contains("vault locked")
                    || lowered.contains("vault is locked")
                    || lowered.contains("encrypted vault locked")
                    || lowered.contains("encrypted vault is locked")
                    || lowered.contains("unlock required")
                    || lowered.contains("requires unlock")
                    || lowered.contains("authentication required")
                    || lowered.contains("unauthorized")
            }
            return lowered.contains("vault locked")
                || lowered.contains("vault is locked")
                || lowered.contains("encrypted vault locked")
                || lowered.contains("encrypted vault is locked")
                || lowered.contains("unlock required")
                || lowered.contains("requires unlock")
        }
        return false
    }

    private func handleSageMemoryRefreshFailure(_ error: Error) {
        if SageDirectClientError.isTextSearchUnavailable(error), sageAgentStatus == "Registered", sageDirectClient != nil {
            sageStatus = "SAGE connected · semantic search mode"
            if lastError?.hasPrefix("SAGE memory") == true {
                lastError = nil
            }
            updateStartupStep(
                id: "sage",
                detail: "quiettype-agent is registered. SAGE is in semantic-only memory mode, so text search is skipped.",
                state: .ready
            )
            return
        }

        if sageAgentStatus == "Registered", sageDirectClient != nil {
            lastError = "SAGE memory refresh failed: \(error.localizedDescription)"
            sageStatus = "SAGE connected · memory refresh failed"
            updateStartupStep(
                id: "sage",
                detail: "quiettype-agent is registered. SAGE memory refresh will retry when you click Refresh.",
                state: .ready
            )
            return
        }

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
            await flushPendingSageTranscriptNotes(using: sageDirectClient)
            sageMemories = try await loadSageMemories(using: sageDirectClient, limit: Self.reviewMemoryLimit)
            if lastError?.hasPrefix("SAGE memory") == true {
                lastError = nil
            }
        } catch {
            handleSageMemoryRefreshFailure(error)
        }
    }

    func refreshLocalMemories() async {
        do {
            localMemories = try await memoryStore.search(
                MemorySearchQuery(
                    text: "",
                    types: [.vocabulary, .correction, .styleProfile, .formattingPreference, .transcriptNote, .voiceNote],
                    limit: 500,
                    localOnly: true
                )
            )
            ensureSelectedVoiceNote()
        } catch {
            lastError = "Local memory refresh failed: \(error.localizedDescription)"
        }
    }

    func refreshVoiceNotes() async {
        await refreshLocalMemories()
    }

    func refreshDictionaryMemories() async {
        await refreshLocalMemories()
        if sageDirectClient == nil {
            await registerSageAgentIfAvailable()
        } else {
            await refreshSageMemories()
        }
    }

    func scheduleDictionarySearch() {
        dictionarySearchTask?.cancel()
        dictionarySearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            await self.searchDictionaryMemories()
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
            await flushPendingSageTranscriptNotes(using: sageDirectClient)
            sageMemories = try await sageDirectClient.searchMemories(query: query, limit: Self.reviewMemoryLimit)
                .filter { !hiddenReviewMemoryIDs.contains($0.id) }
        } catch {
            handleSageMemoryRefreshFailure(error)
        }
    }

    func searchDictionaryMemories() async {
        await searchSageMemories()
    }

    private func flushPendingSageTranscriptNotes(using client: SageDirectClient) async {
        let pending = localMemories.filter { memory in
            guard memory.type == .transcriptNote else {
                return false
            }
            return memory.payload["sage_sync_status"] != "synced"
        }
        guard !pending.isEmpty else {
            return
        }

        var syncedCount = 0
        for memory in pending {
            guard let localID = memory.id else {
                continue
            }
            let content = sageTranscriptContent(from: memory)
            do {
                let submission = try await client.submitTranscriptNote(
                    content: content,
                    confidence: memory.confidence
                )
                let syncedAt = ISO8601DateFormatter().string(from: Date())
                if let supersededID = memory.payload["sage_memory_id"]?.nilIfBlank,
                   supersededID != submission.memoryID,
                   memory.payload["reviewed_by_user"] == "true" {
                    _ = try? await client.deprecateMemory(
                        id: supersededID,
                        reason: "Superseded by retried QuietType reviewed transcript note \(submission.memoryID)."
                    )
                    hideReviewMemoryID(supersededID)
                }
                let patch = [
                    "sage_memory_id": submission.memoryID,
                    "sage_sync_status": "synced",
                    "sage_synced_at": syncedAt
                ]
                try await memoryStore.update(memoryID: localID, patch: patch)
                if let index = localMemories.firstIndex(where: { $0.id == localID }) {
                    for (key, value) in patch {
                        localMemories[index].payload[key] = value
                    }
                }
                if !sageMemories.contains(where: { $0.id == submission.memoryID }) {
                    sageMemories.insert(
                        SageMemoryRecord(
                            id: submission.memoryID,
                            content: content,
                            domain: "quiettype.transcripts",
                            type: "observation",
                            confidence: memory.confidence,
                            createdAt: memory.payload["created_at"],
                            submittingAgent: sageAgentID
                        ),
                        at: 0
                    )
                }
                syncedCount += 1
            } catch {
                let patch = [
                    "sage_sync_status": "pending",
                    "sage_last_error": error.localizedDescription,
                    "sage_last_attempt_at": ISO8601DateFormatter().string(from: Date())
                ]
                try? await memoryStore.update(memoryID: localID, patch: patch)
                if let index = localMemories.firstIndex(where: { $0.id == localID }) {
                    for (key, value) in patch {
                        localMemories[index].payload[key] = value
                    }
                }
            }
        }

        if syncedCount > 0 {
            statusMessage = syncedCount == 1 ? "Synced 1 review note to SAGE" : "Synced \(syncedCount) review notes to SAGE"
            if lastError?.hasPrefix("SAGE transcript note sync failed") == true {
                lastError = nil
            }
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
        speechEngineStatus = "Native speech starting"

        do {
            if await whisperKitSupervisor?.isServerHealthy() == true {
                let didPrewarm = await warmNativeSpeechInferenceIfNeeded()
                nativeSpeechServerReady = true
                isBooting = false
                updateStartupStep(
                    id: "nativeSpeech",
                    detail: didPrewarm ? "Apple Silicon transcription server is ready for first dictation." : "Apple Silicon transcription server is reachable. First dictation may finish warming it.",
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
                    let didPrewarm = await warmNativeSpeechInferenceIfNeeded()
                    nativeSpeechServerReady = true
                    updateStartupStep(
                        id: "nativeSpeech",
                        detail: didPrewarm ? "Apple Silicon transcription server is ready for first dictation." : "Apple Silicon transcription server is reachable. First dictation may finish warming it.",
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
                let detail = "Native engine is warming in the background. First launch can take a few minutes."
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
                detail: fallbackSpeechReady ? "Native speech is not ready yet. QuietType will wait for the Apple Silicon engine." : detail,
                state: .failed
            )
            lastError = fallbackSpeechReady ? "Native WhisperKit is unavailable. QuietType will wait for the Apple Silicon speech engine." : detail
        }

        refreshSpeechEngineStatus()
        isBooting = false
    }

    @discardableResult
    private func warmNativeSpeechInferenceIfNeeded() async -> Bool {
        guard !nativeInferencePrewarmed else {
            return true
        }
        guard await whisperKitSupervisor?.isServerHealthy() == true else {
            return false
        }

        statusMessage = "Preparing native speech"
        updateStartupStep(
            id: "nativeSpeech",
            detail: "Preparing the first local transcription.",
            state: .running
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-native-warmup-\(UUID().uuidString).wav")
        let sampleRate = 16_000
        let samples = (0..<sampleRate).map { index -> Float in
            let seconds = Double(index) / Double(sampleRate)
            let taper = min(seconds / 0.08, (1.0 - seconds) / 0.08, 1.0)
            let phase = seconds * 2.0 * Double.pi * 440.0
            return Float(sin(phase) * max(taper, 0.0) * 0.025)
        }

        do {
            try WavFileWriter.writeMonoPCM16(samples: samples, sampleRate: sampleRate, to: tempURL)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }
            _ = try await WhisperKitServerTranscriber(timeoutSeconds: WhisperKitServerTranscriber.warmupTimeoutSeconds)
                .transcribe(audioFile: tempURL, options: .none)
            nativeInferencePrewarmed = true
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            if isEmptyTranscriptFailure(error) || isLikelyNoiseOnlyFailure(error) {
                nativeInferencePrewarmed = true
                return true
            }
            return false
        }
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
        peakInputRMS = 0
        inputNoiseFloorRMS = 0.006
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
            showListeningOverlay()
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

    func cancelRecording() async {
        guard isRecording else {
            return
        }

        captureService?.stop()
        captureService = nil
        isRecording = false
        lastDictationDuration = recordingDuration
        await streamingTranscriptionSession?.cancel()
        streamingTranscriptionSession = nil
        pendingStreamingChunks = []
        recordedSamples = []
        capturedFrameCount = 0
        partialChunkCount = 0
        lastRecordingURL = nil
        recordingStartedAt = nil
        inputLevel = 0
        peakInputLevel = 0
        peakInputRMS = 0
        inputNoiseFloorRMS = 0.006
        try? FileManager.default.removeItem(at: chunkDirectory)
        statusMessage = "Dictation cancelled"
        lastError = nil
        overlayController.show(state: .cancelled, detail: "Discarded locally")
        overlayController.hide(after: 0.9)
    }

    func setSaveVoiceNotesToSage(_ enabled: Bool) {
        saveVoiceNotesToSage = enabled
        UserDefaults.standard.set(enabled, forKey: Self.saveVoiceNotesToSageKey)
    }

    func setVoiceNotePlaybackVolume(_ volume: Double) {
        voiceNotePlaybackVolume = min(max(volume, 0), 1)
        voiceNoteAudioPlayer?.volume = Float(voiceNotePlaybackVolume)
    }

    func toggleVoiceNoteRecording() async {
        if isVoiceNoteRecording {
            await stopVoiceNoteRecording()
        } else {
            await startVoiceNoteRecording()
        }
    }

    private func startVoiceNoteRecording() async {
        guard !isRecording, !isTrainingRecording, !isTeachingRecording else {
            lastError = "Stop the current recording before starting a voice note."
            return
        }
        guard !isVoiceNoteTranscribing else {
            return
        }

        if microphonePermission != .granted {
            microphonePermission = await permissionService.requestMicrophone()
        }
        await refreshPermissions(promptForAccessibility: false, verifyMicrophoneAccess: true)
        guard microphonePermission == .granted else {
            statusMessage = "Waiting for microphone"
            lastError = "Allow Microphone in System Settings so QuietType can capture local audio."
            return
        }
        guard await ensureNativeSpeechServerReadyForTranscription() else {
            statusMessage = "Native speech warming"
            lastError = "QuietType is waiting for the Apple Silicon speech engine before voice notes can transcribe."
            return
        }

        voiceNoteSamples = []
        voiceNoteFrameCount = 0
        voiceNoteDuration = 0
        voiceNoteInputLevel = 0
        voiceNoteSampleRate = 16_000
        peakVoiceNoteInputRMS = 0
        voiceNoteNoiseFloorRMS = 0.006
        voiceNoteStartedAt = Date()
        lastError = nil
        statusMessage = "Recording voice note"

        let service = AVAudioCaptureService { [weak self] frame in
            await self?.recordVoiceNote(frame)
        }

        do {
            try service.start()
            voiceNoteCaptureService = service
            microphoneAccessVerified = true
            microphonePermission = .granted
            updatePermissionsStartupStep()
            isVoiceNoteRecording = true
        } catch {
            voiceNoteCaptureService = nil
            voiceNoteStartedAt = nil
            isVoiceNoteRecording = false
            microphoneAccessVerified = false
            microphonePermission = .denied
            updatePermissionsStartupStep()
            lastError = "Could not start microphone: \(error)"
            statusMessage = "Microphone permission needed"
        }
    }

    private func stopVoiceNoteRecording() async {
        guard isVoiceNoteRecording else {
            return
        }

        voiceNoteCaptureService?.stop()
        voiceNoteCaptureService = nil
        isVoiceNoteRecording = false
        isVoiceNoteTranscribing = true
        defer {
            isVoiceNoteTranscribing = false
            voiceNoteInputLevel = 0
            voiceNoteStartedAt = nil
        }

        let duration = voiceNoteDuration
        guard voiceNoteFrameCount > 0 else {
            statusMessage = "No audio captured"
            lastError = nil
            voiceNoteSamples = []
            return
        }
        guard peakVoiceNoteInputRMS >= Self.minimumUsableRMS else {
            statusMessage = "No usable microphone signal"
            lastError = "Check the selected input device in macOS Sound settings, then try again."
            voiceNoteSamples = []
            return
        }

        do {
            statusMessage = "Transcribing voice note"
            activeTranscriptionOptions = currentTranscriptionOptions(appName: "Voice Notes")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("quiettype-voice-note-\(UUID().uuidString).wav")
            try WavFileWriter.writeMonoPCM16(samples: voiceNoteSamples, sampleRate: voiceNoteSampleRate, to: tempURL)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
                voiceNoteSamples = []
            }

            let timedResult = try await transcribeFullAudioWithTiming(tempURL)
            let rawTranscript = timedResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isLikelyNoiseTranscript(rawTranscript, duration: duration) else {
                throw AudioTranscriberError.noiseOnlyTranscript(rawTranscript)
            }

            let polishedText = try await polishVoiceNoteTranscript(rawTranscript)
            let encryptedAudioURL = try await voiceNoteAudioStore.saveWAVData(Data(contentsOf: tempURL))
            let id = try await saveVoiceNote(
                rawTranscript: rawTranscript,
                polishedText: polishedText,
                audioURL: encryptedAudioURL,
                duration: duration
            )
            selectedVoiceNoteID = id
            statusMessage = "Voice note saved locally"
            lastError = nil
            if saveVoiceNotesToSage {
                await sendVoiceNoteToSage(id: id)
            }
        } catch {
            if isLikelyNoiseOnlyFailure(error) {
                statusMessage = "No clear speech detected"
                lastError = nil
            } else if isEmptyTranscriptFailure(error) {
                statusMessage = "No transcript returned"
                lastError = nil
            } else {
                statusMessage = "Voice note failed"
                lastError = String(describing: error)
            }
            voiceNoteSamples = []
        }
    }

    private func recordVoiceNote(_ frame: AudioFrame) async {
        guard isVoiceNoteRecording else {
            return
        }

        voiceNoteFrameCount += 1
        voiceNoteSampleRate = frame.sampleRate
        voiceNoteSamples.append(contentsOf: frame.samples)
        if let voiceNoteStartedAt {
            voiceNoteDuration = Date().timeIntervalSince(voiceNoteStartedAt)
        }
        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        peakVoiceNoteInputRMS = max(peakVoiceNoteInputRMS, rms)
        voiceNoteNoiseFloorRMS = Self.updatedNoiseFloor(currentFloor: voiceNoteNoiseFloorRMS, rms: rms)
        voiceNoteInputLevel = Self.displayLevel(rms: rms, noiseFloor: voiceNoteNoiseFloorRMS, previous: voiceNoteInputLevel)

        if voiceNoteDuration >= Self.maxDictationDurationSeconds && isVoiceNoteRecording {
            statusMessage = "5 minute note limit reached"
            await stopVoiceNoteRecording()
        }
    }

    private func polishVoiceNoteTranscript(_ rawTranscript: String) async throws -> String {
        let context = AppContext(appName: "Voice Notes", profile: .notes)
        let controller = DictationSessionController(
            profile: currentDictationProfile(),
            asrBackend: TranscriptASRBackend(transcript: rawTranscript),
            contextCollector: StaticContextCollector(context: context),
            inserter: BufferingTextInserter(),
            memoryStore: memoryStore,
            semanticEditor: editorMode.makeEditor(model: ollamaModel)
        )
        try await controller.begin()
        return try await controller.finishAndInsert().text
    }

    private func saveVoiceNote(rawTranscript: String, polishedText: String, audioURL: URL, duration: Double) async throws -> String {
        let createdAt = Date()
        let title = Self.defaultVoiceNoteTitle(from: polishedText.nilIfBlank ?? rawTranscript, createdAt: createdAt)
        let memory = DictationMemory(
            type: .voiceNote,
            payload: [
                "title": title,
                "raw_transcript": rawTranscript,
                "polished_text": polishedText,
                "audio_path": audioURL.path,
                "duration_seconds": String(format: "%.3f", duration),
                "created_at": ISO8601DateFormatter().string(from: createdAt),
                "encrypted_audio": "aes-gcm-keychain",
                "sent_to_sage": "false"
            ],
            contexts: ["voice_notes", "local_long_term"],
            source: "QuietType Voice Notes",
            confidence: 1.0,
            privacy: "local_encrypted"
        )
        let id = try await memoryStore.put(memory)
        var stored = memory
        stored.id = id
        localMemories.removeAll { $0.id == id }
        localMemories.insert(stored, at: 0)
        ensureSelectedVoiceNote()
        return id
    }

    func updateVoiceNote(id: String, title: String, rawTranscript: String, polishedText: String) async {
        do {
            try await memoryStore.update(memoryID: id, patch: [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Voice note",
                "raw_transcript": rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
                "polished_text": polishedText.trimmingCharacters(in: .whitespacesAndNewlines),
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            await refreshVoiceNotes()
            selectedVoiceNoteID = id
            statusMessage = "Voice note saved"
            lastError = nil
        } catch {
            lastError = "Voice note save failed: \(error.localizedDescription)"
        }
    }

    func deleteVoiceNote(id: String) async {
        guard let memory = localMemories.first(where: { $0.id == id }) else {
            lastError = "Voice note not found."
            return
        }
        let audioPath = memory.payload["audio_path"]
        let sageMemoryID = memory.payload["sage_memory_id"]?.nilIfBlank
        do {
            if let sageMemoryID {
                if sageDirectClient == nil {
                    await registerSageAgentIfAvailable()
                }
                guard let sageDirectClient else {
                    lastError = "Connect SAGE before removing the linked voice note memory."
                    return
                }
                _ = try await sageDirectClient.deprecateMemory(
                    id: sageMemoryID,
                    reason: "QuietType voice note deleted by user."
                )
                sageMemories.removeAll { $0.id == sageMemoryID }
            }
            try await memoryStore.delete(memoryID: id)
            if let audioPath {
                try? FileManager.default.removeItem(atPath: audioPath)
            }
            localMemories.removeAll { $0.id == id }
            selectedVoiceNoteID = nil
            ensureSelectedVoiceNote()
            statusMessage = sageMemoryID == nil ? "Voice note removed" : "Voice note and SAGE memory removed"
            lastError = nil
        } catch {
            lastError = "Voice note delete failed: \(error.localizedDescription)"
        }
    }

    func sendVoiceNoteToSage(id: String) async {
        guard let memory = localMemories.first(where: { $0.id == id && $0.type == .voiceNote }) else {
            lastError = "Voice note not found."
            return
        }
        guard let sageDirectClient else {
            await registerSageAgentIfAvailable()
            guard let sageDirectClient else {
                lastError = "Connect SAGE before sending a voice note."
                return
            }
            await submitVoiceNote(memory, using: sageDirectClient)
            return
        }
        await submitVoiceNote(memory, using: sageDirectClient)
    }

    private func submitVoiceNote(_ memory: DictationMemory, using client: SageDirectClient) async {
        do {
            guard let memoryID = memory.id else {
                throw MemoryStoreError.notFound("voice note")
            }
            let title = memory.payload["title"]?.nilIfBlank ?? "Voice note"
            let raw = memory.payload["raw_transcript"] ?? ""
            let polished = memory.payload["polished_text"] ?? ""
            let createdAt = memory.payload["created_at"] ?? ""
            let duration = memory.payload["duration_seconds"] ?? ""
            let content = """
            QuietType voice note for long-term recall. Title: \(title). Created locally: \(createdAt). Duration seconds: \(duration). Transcript: "\(polished)". Raw transcript: "\(raw)". Audio remains encrypted on the user's Mac and is not attached to this SAGE memory.
            """
            let submission = try await client.submitTranscriptNote(content: content, confidence: 0.9)
            try await memoryStore.update(memoryID: memoryID, patch: [
                "sent_to_sage": "true",
                "sage_memory_id": submission.memoryID,
                "sent_to_sage_at": ISO8601DateFormatter().string(from: Date())
            ])
            await refreshVoiceNotes()
            selectedVoiceNoteID = memoryID
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
            statusMessage = "Voice note copied to SAGE"
            lastError = nil
        } catch {
            lastError = "Voice note SAGE send failed: \(error.localizedDescription)"
        }
    }

    func playVoiceNoteAudio(id: String) async {
        if playingVoiceNoteID == id, let player = voiceNoteAudioPlayer {
            if player.isPlaying {
                player.currentTime = 0
            } else {
                player.currentTime = 0
                player.play()
                isVoiceNotePlaying = true
                statusMessage = "Playing voice note"
                startVoiceNotePlaybackTimer()
            }
            return
        }

        stopVoiceNotePlayback()
        guard let note = voiceNotes.first(where: { $0.id == id }),
              let audioPath = note.audioPath else {
            lastError = "Voice note audio is unavailable."
            return
        }

        do {
            let data = try await voiceNoteAudioStore.decryptAudio(at: URL(fileURLWithPath: audioPath))
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("quiettype-playback-\(UUID().uuidString).wav")
            try data.write(to: tempURL, options: [.atomic])
            let player = try AVAudioPlayer(contentsOf: tempURL)
            player.prepareToPlay()
            player.volume = Float(voiceNotePlaybackVolume)
            voiceNoteAudioPlayer = player
            voiceNotePlaybackTempURL = tempURL
            playingVoiceNoteID = id
            voiceNotePlaybackDuration = player.duration
            voiceNotePlaybackProgress = 0
            player.play()
            isVoiceNotePlaying = true
            startVoiceNotePlaybackTimer()
            statusMessage = "Playing voice note"
            lastError = nil
        } catch {
            lastError = "Could not play encrypted audio: \(error.localizedDescription)"
        }
    }

    func stopCurrentVoiceNoteAudio() {
        stopVoiceNotePlayback()
        statusMessage = "Voice note stopped"
    }

    private func startVoiceNotePlaybackTimer() {
        voiceNotePlaybackTimer?.invalidate()
        voiceNotePlaybackTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVoiceNotePlaybackProgress()
            }
        }
    }

    private func updateVoiceNotePlaybackProgress() {
        guard let player = voiceNoteAudioPlayer else {
            stopVoiceNotePlayback()
            return
        }
        voiceNotePlaybackDuration = player.duration
        voiceNotePlaybackProgress = player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0
        if !player.isPlaying {
            isVoiceNotePlaying = false
            voiceNotePlaybackTimer?.invalidate()
            voiceNotePlaybackTimer = nil
            if player.currentTime >= player.duration {
                playingVoiceNoteID = nil
                voiceNotePlaybackProgress = 0
                try? voiceNotePlaybackTempURL.map { try FileManager.default.removeItem(at: $0) }
                voiceNotePlaybackTempURL = nil
                voiceNoteAudioPlayer = nil
            }
        }
    }

    private func stopVoiceNotePlayback() {
        voiceNotePlaybackTimer?.invalidate()
        voiceNotePlaybackTimer = nil
        voiceNoteAudioPlayer?.stop()
        voiceNoteAudioPlayer = nil
        playingVoiceNoteID = nil
        isVoiceNotePlaying = false
        voiceNotePlaybackProgress = 0
        voiceNotePlaybackDuration = 0
        try? voiceNotePlaybackTempURL.map { try FileManager.default.removeItem(at: $0) }
        voiceNotePlaybackTempURL = nil
    }

    private func ensureSelectedVoiceNote() {
        let notes = voiceNotes
        if let selectedVoiceNoteID,
           notes.contains(where: { $0.id == selectedVoiceNoteID }) {
            return
        }
        selectedVoiceNoteID = notes.first?.id
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

        guard await ensureNativeSpeechServerReadyForTranscription() else {
            statusMessage = "Native speech warming"
            lastError = "QuietType is waiting for the Apple Silicon speech engine before dictation starts."
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
        if peakInputRMS < Self.minimumUsableRMS {
            output = "QuietType could open the microphone, but the input signal was too low to transcribe."
            statusMessage = "No usable microphone signal"
            lastError = "Check the selected input device in macOS Sound settings, then try again."
            overlayController.hide()
            return
        }

        do {
            let url = reviewAudioURL()
            try OwnerOnlyFileSecurity.prepareDirectory(url.deletingLastPathComponent())
            try WavFileWriter.writeMonoPCM16(samples: recordedSamples, sampleRate: recordingSampleRate, to: url)
            pruneReviewAudioCache(keeping: url)
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

    private func reviewAudioURL(date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "dictation-\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).wav"
        return reviewAudioDirectory.appendingPathComponent(filename)
    }

    private func pruneReviewAudioCache(keeping keptURL: URL? = nil) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: reviewAudioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let keptPath = keptURL?.path
        let wavFiles = files.filter { $0.pathExtension.lowercased() == "wav" }
        let sorted = wavFiles.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        let removable = sorted.dropFirst(Self.maxReviewAudioFiles).filter { $0.path != keptPath }
        for url in removable {
            try? fileManager.removeItem(at: url)
        }
    }

    private func record(_ frame: AudioFrame) async {
        guard isRecording else {
            return
        }

        capturedFrameCount += 1
        recordingSampleRate = frame.sampleRate
        recordedSamples.append(contentsOf: frame.samples)
        if let recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        peakInputRMS = max(peakInputRMS, rms)
        inputNoiseFloorRMS = Self.updatedNoiseFloor(currentFloor: inputNoiseFloorRMS, rms: rms)
        inputLevel = Self.displayLevel(rms: rms, noiseFloor: inputNoiseFloorRMS, previous: inputLevel)
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
            showListeningOverlay()
        }
    }

    private var listeningOverlayDetail: String {
        "Listening · \(String(format: "%.1f", recordingDuration))s · Esc cancels"
    }

    private static func updatedNoiseFloor(currentFloor: Double, rms: Double) -> Double {
        let clampedRMS = min(max(rms, 0.0004), 0.08)
        if clampedRMS < currentFloor * 1.45 {
            return min(0.04, (currentFloor * 0.94) + (clampedRMS * 0.06))
        }
        return currentFloor
    }

    private static func displayLevel(rms: Double, noiseFloor: Double, previous: Double) -> Double {
        let gate = max(0.0045, noiseFloor * 1.9)
        guard rms > gate else {
            let decayed = previous * 0.42
            return decayed < 0.035 ? 0 : decayed
        }

        let ceiling = max(gate + 0.03, noiseFloor * 9.0)
        let normalized = min(max((rms - gate) / (ceiling - gate), 0), 1)
        let shaped = sqrt(normalized)
        let smoothed = shaped > previous
            ? (previous * 0.45) + (shaped * 0.55)
            : (previous * 0.68) + (shaped * 0.32)
        return smoothed < 0.035 ? 0 : min(smoothed, 1)
    }

    private func showListeningOverlay() {
        overlayController.show(
            state: .listening,
            level: inputLevel,
            detail: listeningOverlayDetail,
            onCancel: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.cancelRecording()
                }
            }
        )
    }

    private func activateStreamingIfUseful() async {
        guard nativeSpeechServerReady, recordingDuration >= Self.streamingTranscriptMinimumDuration else {
            return
        }

        if streamingTranscriptionSession == nil {
            streamingTranscriptionSession = StreamingAudioTranscriptionSession(
                transcriber: WhisperKitServerTranscriber(timeoutSeconds: WhisperKitServerTranscriber.streamingTimeoutSeconds),
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
            guard await ensureNativeSpeechServerReadyForTranscription() else {
                throw AudioTranscriberError.allBackendsFailed([
                    "Native WhisperKit is unavailable. QuietType is waiting for the Apple Silicon speech engine."
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
            let wordTimings: [TranscribedWordTiming]
            if let streamResult, isUsableStreamingTranscript(streamResult.text, chunkCount: streamResult.chunkCount) {
                rawTranscript = streamResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                wordTimings = []
                statusMessage = "Processed \(streamResult.chunkCount) streamed chunks"
            } else {
                if let streamResult, !streamResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusMessage = "Resolving full audio"
                }
                let timedResult = try await transcribeFullAudioWithTiming(audioURL)
                rawTranscript = timedResult.text
                wordTimings = timedResult.words
            }
            guard !isLikelyNoiseTranscript(rawTranscript) else {
                throw AudioTranscriberError.noiseOnlyTranscript(rawTranscript)
            }
            transcript = rawTranscript
            await processTranscript(rawTranscript, audioURL: audioURL, wordTimings: wordTimings)
        } catch {
            isRunning = false
            overlayController.hide(after: 1.1)
            refreshSpeechEngineStatus()
            if isLikelyNoiseOnlyFailure(error) {
                output = "QuietType captured audio, but could not isolate speech from the background audio."
                statusMessage = "No clear speech detected"
                lastError = nil
            } else if isEmptyTranscriptFailure(error) {
                output = "QuietType captured audio, but native speech returned no transcript."
                statusMessage = "No transcript returned"
                lastError = nil
            } else {
                output = "Captured local audio at:\n\(audioURL.path)"
                statusMessage = speechEngineReady ? "Transcription failed" : "Speech engine unavailable"
                lastError = String(describing: error)
            }
        }
    }

    private func transcribeFullAudio(_ audioURL: URL) async throws -> String {
        let transcriber = makeAudioTranscriber()
        do {
            return try await transcriber.transcribe(audioFile: audioURL, options: activeTranscriptionOptions)
        } catch {
            guard isEmptyTranscriptFailure(error), activeTranscriptionOptions != .none else {
                throw error
            }
            statusMessage = "Retrying native speech"
            return try await transcriber.transcribe(audioFile: audioURL, options: .none)
        }
    }

    private func transcribeFullAudioWithTiming(_ audioURL: URL) async throws -> TimedTranscriptionResult {
        let transcriber = makeAudioTranscriber()
        do {
            return try await transcriber.transcribeWithTiming(audioFile: audioURL, options: activeTranscriptionOptions)
        } catch {
            if isEmptyTranscriptFailure(error), activeTranscriptionOptions != .none {
                statusMessage = "Retrying native speech"
                return try await transcriber.transcribeWithTiming(audioFile: audioURL, options: .none)
            }
            let text = try await transcribeFullAudio(audioURL)
            return TimedTranscriptionResult(text: text)
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
        if recordingDuration >= 12.0 {
            let minimumCoveredChunks = max(3, Int((recordingDuration * 0.45).rounded(.down)))
            if chunkCount < minimumCoveredChunks {
                return false
            }
        }
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

    private func isLikelyNoiseTranscript(_ text: String, duration: Double? = nil) -> Bool {
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
        return (duration ?? recordingDuration) >= 2.5 && tinyHallucinations.contains(lowered)
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
            WhisperKitServerTranscriber(timeoutSeconds: WhisperKitServerTranscriber.timeoutForFullAudio(durationSeconds: recordingDuration))
        ])
    }

    private func currentDictationProfile() -> DictationProfile {
        var profile = ProfileMemoryCompiler.enrich(.development, with: localMemories)
        profile.spellingPreference = spellingPreference
        profile.profanityFilterEnabled = profanityFilterEnabled
        return profile
    }

    private func currentTranscriptionOptions(appName: String? = nil) -> AudioTranscriptionOptions {
        AudioTranscriptionOptions(
            initialPrompt: ASRPromptBuilder().prompt(
                for: currentDictationProfile(),
                appName: appName ?? selectedProfile.appName
            )
        )
    }

    private func prepareNativeSpeechServerIfAvailable() async {
        if nativeSpeechServerReady,
           await whisperKitSupervisor?.isServerHealthy() == true {
            _ = await warmNativeSpeechInferenceIfNeeded()
            return
        }

        nativeSpeechServerReady = false
        nativeInferencePrewarmed = false
        refreshSpeechEngineStatus()
        startNativeSpeechWarmup()
    }

    private func ensureNativeSpeechServerReadyForTranscription() async -> Bool {
        if nativeSpeechServerReady,
           await whisperKitSupervisor?.isServerHealthy() == true {
            _ = await warmNativeSpeechInferenceIfNeeded()
            return true
        }

        nativeSpeechServerReady = false
        nativeInferencePrewarmed = false
        refreshSpeechEngineStatus()

        guard let executableURL = WhisperKitServerBundleLocator.bundledExecutable(),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            updateStartupStep(
                id: "nativeSpeech",
                detail: "Native engine is not bundled in this build.",
                state: .failed
            )
            speechEngineStatus = "Native speech unavailable"
            lastError = "QuietType requires the bundled Apple Silicon speech engine."
            return false
        }

        if whisperKitSupervisor == nil {
            whisperKitSupervisor = WhisperKitServerSupervisor(executableURL: executableURL)
        }

        statusMessage = "Starting native speech"
        speechEngineStatus = "Native speech starting"
        updateStartupStep(
            id: "nativeSpeech",
            detail: "Starting the Apple Silicon speech engine.",
            state: .running
        )

        do {
            try await whisperKitSupervisor?.ensureRunning(stopOnTimeout: false)
            let didPrewarm = await warmNativeSpeechInferenceIfNeeded()
            nativeSpeechServerReady = true
            speechEngineReady = true
            speechEngineStatus = "Native speech ready"
            statusMessage = "Native speech ready"
            updateStartupStep(
                id: "nativeSpeech",
                detail: didPrewarm ? "Apple Silicon transcription server is ready for first dictation." : "Apple Silicon transcription server is reachable. First dictation may finish warming it.",
                state: .ready
            )
            return true
        } catch {
            nativeSpeechServerReady = false
            nativeInferencePrewarmed = false
            speechEngineReady = false
            let detail = String(describing: error)
            speechEngineStatus = "Native speech starting"
            lastError = detail
            updateStartupStep(
                id: "nativeSpeech",
                detail: "Native speech is not ready yet. QuietType will wait for the Apple Silicon engine.",
                state: .failed
            )
            return false
        }
    }

    private func processTranscript(_ rawTranscript: String, audioURL: URL? = nil, wordTimings: [TranscribedWordTiming] = []) async {
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
            if let measuredWPM = Self.wordsPerMinute(wordCount: translatedWords, duration: lastDictationDuration) {
                lastWordsPerMinute = measuredWPM
                UserDefaults.standard.set(measuredWPM, forKey: Self.lastWordsPerMinuteKey)
            }
            totalTranslatedWordCount += translatedWords
            UserDefaults.standard.set(totalTranslatedWordCount, forKey: Self.totalTranslatedWordCountKey)
            statusMessage = didInsert ? "Inserted or ready to copy" : "Ready to copy"
            await saveTranscriptNote(rawTranscript: rawTranscript, polishedText: result.text, inserted: didInsert, latencyMS: result.timing.keyReleaseToInsertMS, audioURL: audioURL, wordTimings: wordTimings)
            overlayController.show(state: .inserted, detail: "Ready to copy", transcript: result.text)
            overlayController.hide(after: 3.0)
        } catch {
            output = "Transcript: \(rawTranscript)"
            lastError = String(describing: error)
            overlayController.hide(after: 1.1)
        }
    }

    private func saveTranscriptNote(rawTranscript: String, polishedText: String, inserted: Bool, latencyMS: Int?, audioURL: URL?, wordTimings: [TranscribedWordTiming]) async {
        guard historyReviewEnabled else {
            return
        }
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty || !polished.isEmpty else {
            return
        }

        let audioPath = audioURL?.path ?? ""
        let wordTimingsJSON = encodedWordTimings(wordTimings)
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let localID = UUID().uuidString
        let memory = DictationMemory(
            id: localID,
            type: .transcriptNote,
            payload: [
                "raw_transcript": raw,
                "polished_text": polished,
                "app": selectedProfile.appName,
                "style": selectedProfile.appProfile.rawValue,
                "inserted": inserted ? "true" : "false",
                "audio_path": audioPath,
                "audio_word_offsets": wordTimingsJSON.isEmpty ? "unavailable" : wordTimingsJSON,
                "latency_ms": latencyMS.map(String.init) ?? "",
                "created_at": createdAt,
                "sage_sync_status": "pending"
            ],
            contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, "dictation_review"],
            source: "QuietType local review",
            confidence: 0.82
        )

        do {
            _ = try await memoryStore.put(memory)
            localMemories.insert(memory, at: 0)
        } catch {
            lastError = "Local transcript note failed: \(error.localizedDescription)"
            return
        }

        guard let sageDirectClient else {
            statusMessage = "Review saved locally"
            lastError = nil
            return
        }

        await flushPendingSageTranscriptNotes(using: sageDirectClient)
        if localMemories.first(where: { $0.id == localID })?.payload["sage_sync_status"] != "synced" {
            statusMessage = "Review saved locally"
        }
    }

    private func sageTranscriptContent(from memory: DictationMemory) -> String {
        let raw = (memory.payload["raw_transcript"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = (memory.payload["polished_text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let app = memory.payload["app"] ?? selectedProfile.appName
        let inserted = memory.payload["inserted"] == "true" ? "yes" : "no"
        let audioPath = memory.payload["audio_path"] ?? ""
        let wordTimings = memory.payload["audio_word_offsets"] ?? ""
        let wordTimingsBase64 = wordTimings == "unavailable" ? "" : Data(wordTimings.utf8).base64EncodedString()

        if memory.payload["reviewed_by_user"] == "true" {
            let supersedes = memory.payload["supersedes"] ?? memory.payload["sage_memory_id"] ?? memory.id ?? "local"
            let lessonCount = memory.payload["derived_word_lesson_count"] ?? "0"
            return """
            QuietType reviewed transcript note. Supersedes SAGE note: \(supersedes). Audio path: "\(audioPath)". Word timings base64: "\(wordTimingsBase64)". Derived word lessons: \(lessonCount). Corrected raw transcript: "\(raw)". Corrected polished output: "\(polished)". User-reviewed notes create one compact correction lesson per edited word when the change is obvious and conservative.
            """
        }

        return """
        QuietType transcript note for review. App: \(app). Inserted: \(inserted). Audio path: "\(audioPath)". Word timings base64: "\(wordTimingsBase64)". Raw transcript: "\(raw)". Polished output: "\(polished)". This is review history committed to SAGE, not an automatic correction rule.
        """
    }

    func updateTranscriptNote(
        memoryID: String,
        rawTranscript: String,
        polishedText: String,
        hasLocalCopy: Bool,
        hasSageMemory: Bool
    ) async {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let polished = polishedText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let reviewedAt = ISO8601DateFormatter().string(from: Date())
            let existingLocalMemory = localMemories.first(where: { $0.id == memoryID })
            let remoteSageMemoryID = existingLocalMemory?.payload["sage_memory_id"]?.nilIfBlank ?? memoryID
            let existingSageMemory = sageMemories.first(where: { $0.id == remoteSageMemoryID })
            let localBacked = hasLocalCopy || existingLocalMemory != nil
            let sageBacked = hasSageMemory || existingSageMemory != nil
            let existingSageParts = existingSageMemory.map { transcriptMemoryParts(from: $0.content) }
            let originalRaw = existingLocalMemory?.payload["raw_transcript"]
                ?? existingSageParts?.rawTranscript
                ?? ""
            let originalPolished = existingLocalMemory?.payload["polished_text"]
                ?? existingSageParts?.polishedText
                ?? ""
            let audioPath = existingLocalMemory?.payload["audio_path"]?.nilIfBlank
                ?? existingSageParts?.audioPath?.nilIfBlank
            let wordTimings = decodedWordTimings(from: existingLocalMemory?.payload["audio_word_offsets"])
                .ifEmpty { decodedWordTimings(base64: existingSageParts?.wordTimingsBase64) }
            let plannedLessons = derivedWordCorrections(
                originalRaw: originalRaw,
                originalPolished: originalPolished,
                reviewedRaw: raw,
                reviewedPolished: polished
            )
            let localPatch = [
                "raw_transcript": raw,
                "polished_text": polished,
                "reviewed_at": reviewedAt,
                "reviewed_by_user": "true",
                "derived_word_lesson_count": "\(plannedLessons.count)",
                "sage_sync_status": "pending"
            ]

            if localBacked {
                do {
                    try await memoryStore.update(memoryID: memoryID, patch: localPatch)
                } catch MemoryStoreError.notFound {
                    guard var recoveredMemory = existingLocalMemory else {
                        throw MemoryStoreError.notFound(memoryID)
                    }
                    for (key, value) in localPatch {
                        recoveredMemory.payload[key] = value
                    }
                    _ = try await memoryStore.put(recoveredMemory)
                }
                if let index = localMemories.firstIndex(where: { $0.id == memoryID }) {
                    for (key, value) in localPatch {
                        localMemories[index].payload[key] = value
                    }
                }
            } else if sageDirectClient == nil {
                throw QuietTypeSageRequirementError.notConnected
            }

            let content = """
            QuietType reviewed transcript note. Supersedes SAGE note: \(remoteSageMemoryID). Audio path: "\(audioPath ?? "")". Word timings base64: "\(encodedWordTimingsBase64(wordTimings))". Derived word lessons: \(plannedLessons.count). Corrected raw transcript: "\(raw)". Corrected polished output: "\(polished)". User-reviewed notes create one compact correction lesson per edited word when the change is obvious and conservative.
            """

            guard let sageDirectClient else {
                statusMessage = "Transcript review saved locally"
                lastError = nil
                return
            }

            let submission = try await sageDirectClient.submitTranscriptNote(content: content, confidence: 0.9)
            if sageBacked {
                do {
                    _ = try await sageDirectClient.deprecateMemory(
                        id: remoteSageMemoryID,
                        reason: "Superseded by corrected QuietType transcript note \(submission.memoryID)."
                    )
                } catch {
                    statusMessage = "Review saved; old SAGE note will be hidden locally"
                }
            }

            let correctedMemory = DictationMemory(
                id: existingLocalMemory?.id ?? submission.memoryID,
                type: .transcriptNote,
                payload: [
                    "raw_transcript": raw,
                    "polished_text": polished,
                    "reviewed_at": reviewedAt,
                    "reviewed_by_user": "true",
                    "supersedes": remoteSageMemoryID,
                    "sage_memory_id": submission.memoryID,
                    "sage_sync_status": "synced",
                    "sage_synced_at": ISO8601DateFormatter().string(from: Date()),
                    "audio_path": audioPath ?? "",
                    "audio_word_offsets": encodedWordTimings(wordTimings).nilIfBlank ?? "unavailable",
                    "derived_word_lesson_count": "\(plannedLessons.count)",
                    "app": existingLocalMemory?.payload["app"] ?? selectedProfile.appName,
                    "style": existingLocalMemory?.payload["style"] ?? selectedProfile.appProfile.rawValue
                ],
                contexts: existingLocalMemory?.contexts ?? [selectedProfile.appName, selectedProfile.appProfile.rawValue, "dictation_review"],
                source: "QuietType",
                confidence: 0.9
            )
            _ = try await memoryStore.put(correctedMemory)
            localMemories.removeAll { $0.id == memoryID || $0.id == submission.memoryID }
            sageMemories.removeAll { $0.id == remoteSageMemoryID || $0.id == submission.memoryID }
            localMemories.insert(correctedMemory, at: 0)
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
            hideReviewMemoryID(remoteSageMemoryID)
            unhideReviewMemoryID(correctedMemory.id ?? submission.memoryID)

            let lessons = await saveDerivedCorrectionLessons(
                plannedLessons,
                memoryID: submission.memoryID,
                audioPath: audioPath,
                wordTimings: wordTimings
            )
            if lessons.isEmpty {
                statusMessage = "Transcript review saved and old note deprecated"
            } else if lessons.count == 1, let lesson = lessons.first {
                statusMessage = "Review saved, trained \(lesson.corrected), and deprecated the old note"
            } else {
                statusMessage = "Review saved, trained \(lessons.count) words, and deprecated the old note"
            }
            lastError = nil
        } catch {
            lastError = "Transcript review failed: \(error.localizedDescription)"
        }
    }

    func deleteReviewMemory(memoryID: String, hasLocalCopy: Bool, hasSageMemory: Bool) async {
        do {
            let localMemory = localMemories.first(where: { $0.id == memoryID })
            let remoteSageMemoryID = localMemory?.payload["sage_memory_id"]?.nilIfBlank ?? memoryID
            let localBacked = hasLocalCopy || localMemory != nil
            let sageBacked = hasSageMemory || sageMemories.contains(where: { $0.id == remoteSageMemoryID })

            if localBacked {
                do {
                    try await memoryStore.delete(memoryID: memoryID)
                } catch MemoryStoreError.notFound {
                    // Older in-memory review rows may predate durable local transcript persistence.
                }
                localMemories.removeAll { $0.id == memoryID }
            }

            if sageBacked {
                if sageDirectClient == nil {
                    await registerSageAgentIfAvailable()
                }
                if let sageDirectClient {
                    do {
                        _ = try await sageDirectClient.deprecateMemory(
                            id: remoteSageMemoryID,
                            reason: "Removed by user from QuietType Review."
                        )
                    } catch {
                        if !localBacked {
                            throw error
                        }
                    }
                } else if !localBacked {
                    throw QuietTypeSageRequirementError.notConnected
                }
            }

            sageMemories.removeAll { $0.id == remoteSageMemoryID }
            hideReviewMemoryID(memoryID)
            if remoteSageMemoryID != memoryID {
                hideReviewMemoryID(remoteSageMemoryID)
            }
            statusMessage = "Memory removed"
            lastError = nil
        } catch {
            lastError = "Memory removal failed: \(error.localizedDescription)"
        }
    }

    private func saveDerivedCorrectionLessons(
        _ corrections: [DerivedWordCorrection],
        memoryID: String,
        audioPath: String?,
        wordTimings: [TranscribedWordTiming]
    ) async -> [DerivedWordCorrection] {
        guard !corrections.isEmpty else {
            return []
        }

        var saved: [DerivedWordCorrection] = []
        for correction in corrections {
            do {
                guard let sageDirectClient else {
                    throw QuietTypeSageRequirementError.notConnected
                }
                let wordOffset = audioWordOffset(for: correction, in: wordTimings)
                let wordOffsetJSON = encodedAudioWordOffset(wordOffset)
                let content = "QuietType correction training: when spoken text is \"\(correction.raw)\", prefer \"\(correction.corrected)\". Source: reviewed transcript \(memoryID). Audio path: \"\(audioPath ?? "")\". Audio word offsets: \(wordOffsetJSON.nilIfBlank ?? "unavailable"). Apply during local dictation cleanup only."
                let submission = try await sageDirectClient.submitTranslationMemory(content: content, confidence: 0.93)
                let memory = DictationMemory(
                    id: submission.memoryID,
                    type: .correction,
                    payload: [
                        "raw": correction.raw,
                        "corrected": correction.corrected,
                        "kind": "review_word_correction",
                        "context": "reviewed transcript \(memoryID)",
                        "audio_path": audioPath ?? "",
                        "audio_word_offsets": wordOffsetJSON.nilIfBlank ?? "unavailable"
                    ],
                    contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, "review_word_correction"],
                    source: "SAGE · quiettype-agent",
                    confidence: 0.93
                )
                _ = try await memoryStore.put(memory)
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

                saved.append(correction)
            } catch {
                continue
            }
        }
        return saved
    }

    private func derivedWordCorrections(
        originalRaw: String,
        originalPolished: String,
        reviewedRaw: String,
        reviewedPolished: String
    ) -> [DerivedWordCorrection] {
        var corrections: [DerivedWordCorrection] = []
        corrections.append(contentsOf: tokenCorrections(from: originalPolished, to: reviewedPolished, source: .polishedText))
        corrections.append(contentsOf: tokenCorrections(from: originalRaw, to: reviewedRaw, source: .rawTranscript))

        var seen = Set<String>()
        return corrections.filter { correction in
            let key = "\(correction.raw.lowercased())->\(correction.corrected.lowercased())"
            return seen.insert(key).inserted
        }
    }

    private func tokenCorrections(from original: String, to reviewed: String, source: CorrectionTextSource) -> [DerivedWordCorrection] {
        let rawTokens = correctionTokens(from: original)
        let polishedTokens = correctionTokens(from: reviewed)
        guard rawTokens.count == polishedTokens.count, !rawTokens.isEmpty else {
            return []
        }

        let differences = zip(rawTokens.indices, zip(rawTokens, polishedTokens)).filter { $0.1.0 != $0.1.1 }
        guard !differences.isEmpty, differences.count <= 8 else {
            return []
        }

        return differences.compactMap { difference in
            let heard = difference.1.0
            let corrected = difference.1.1
            guard heard.count >= 2, corrected.count >= 2 else {
                return nil
            }

            if heard.caseInsensitiveCompare(corrected) == .orderedSame,
               !looksLikePreferredTerm(corrected) {
                return nil
            }

            return DerivedWordCorrection(
                raw: heard,
                corrected: corrected,
                tokenIndex: difference.0,
                source: source
            )
        }
    }

    private func audioWordOffset(for correction: DerivedWordCorrection, in wordTimings: [TranscribedWordTiming]) -> AudioWordOffset? {
        guard !wordTimings.isEmpty else {
            return nil
        }

        let normalizedRaw = normalizedCorrectionToken(correction.raw)
        if correction.source == .rawTranscript,
           wordTimings.indices.contains(correction.tokenIndex),
           normalizedCorrectionToken(wordTimings[correction.tokenIndex].word) == normalizedRaw {
            return audioWordOffset(from: wordTimings[correction.tokenIndex], index: correction.tokenIndex, correction: correction)
        }

        guard let match = wordTimings.enumerated().first(where: { _, timing in
            normalizedCorrectionToken(timing.word) == normalizedRaw
        }) else {
            return nil
        }

        return audioWordOffset(from: match.element, index: match.offset, correction: correction)
    }

    private func audioWordOffset(from timing: TranscribedWordTiming, index: Int, correction: DerivedWordCorrection) -> AudioWordOffset {
        AudioWordOffset(
            heard: correction.raw,
            corrected: correction.corrected,
            word: timing.word,
            startSeconds: timing.startSeconds,
            endSeconds: timing.endSeconds,
            wordIndex: index,
            source: "native_word_timestamps"
        )
    }

    private func encodedAudioWordOffset(_ offset: AudioWordOffset?) -> String {
        guard let offset,
              let data = try? JSONEncoder().encode(offset) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func encodedWordTimings(_ wordTimings: [TranscribedWordTiming]) -> String {
        guard !wordTimings.isEmpty,
              let data = try? JSONEncoder().encode(wordTimings) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func encodedWordTimingsBase64(_ wordTimings: [TranscribedWordTiming]) -> String {
        let json = encodedWordTimings(wordTimings)
        guard !json.isEmpty else {
            return ""
        }
        return Data(json.utf8).base64EncodedString()
    }

    private func decodedWordTimings(from value: String?) -> [TranscribedWordTiming] {
        guard let value,
              value != "unavailable",
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([TranscribedWordTiming].self, from: data) else {
            return []
        }
        return decoded
    }

    private func decodedWordTimings(base64 value: String?) -> [TranscribedWordTiming] {
        guard let value,
              let data = Data(base64Encoded: value),
              let decoded = try? JSONDecoder().decode([TranscribedWordTiming].self, from: data) else {
            return []
        }
        return decoded
    }

    private func normalizedCorrectionToken(_ text: String) -> String {
        text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            .lowercased()
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

    func toggleTeachingSampleRecording() async {
        if isTeachingRecording {
            await stopTeachingSampleRecording()
        } else {
            await startTeachingSampleRecording()
        }
    }

    private func startTeachingSampleRecording() async {
        guard !isRecording, !isTrainingRecording else {
            lastError = "Stop the current recording before teaching a correction."
            return
        }

        guard await ensureSageReadyForDictation() else {
            return
        }

        if microphonePermission != .granted {
            microphonePermission = await permissionService.requestMicrophone()
            await refreshPermissions(promptForAccessibility: false, verifyMicrophoneAccess: true)
        }

        teachingSamples = []
        teachingSampleRate = 16_000
        teachingFrameCount = 0
        teachingInputLevel = 0
        peakTeachingInputRMS = 0
        teachingNoiseFloorRMS = 0.006
        teachingStartedAt = Date()

        let service = AVAudioCaptureService { [weak self] frame in
            await self?.recordTeachingSample(frame)
        }

        do {
            try service.start()
            teachingCaptureService = service
            microphoneAccessVerified = true
            microphonePermission = .granted
            updatePermissionsStartupStep()
            isTeachingRecording = true
            teachingSampleStatus = "Listening for sample \(min(teachingSampleCount + 1, 3))..."
            lastError = nil
        } catch {
            teachingCaptureService = nil
            teachingStartedAt = nil
            isTeachingRecording = false
            microphoneAccessVerified = false
            microphonePermission = .denied
            updatePermissionsStartupStep()
            teachingSampleStatus = "Microphone permission needed"
            lastError = "Could not start correction microphone: \(error.localizedDescription)"
        }
    }

    private func stopTeachingSampleRecording() async {
        teachingCaptureService?.stop()
        teachingCaptureService = nil
        isTeachingRecording = false

        guard teachingFrameCount > 0 else {
            teachingSampleStatus = "No sample captured"
            lastError = "QuietType could not detect microphone audio for this sample."
            return
        }
        guard peakTeachingInputRMS >= Self.minimumUsableRMS else {
            teachingSampleStatus = "No usable sample"
            lastError = "QuietType could open the microphone, but the input signal was too low."
            return
        }

        do {
            let directory = trainingDirectory().appendingPathComponent("Corrections", isDirectory: true)
            try OwnerOnlyFileSecurity.prepareDirectory(directory)
            let sampleNumber = min(teachingSampleCount + 1, 3)
            let audioURL = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-correction-\(sampleNumber).wav")
            try WavFileWriter.writeMonoPCM16(samples: teachingSamples, sampleRate: teachingSampleRate, to: audioURL)
            let detected = try await makeAudioTranscriber()
                .transcribe(audioFile: audioURL, options: currentTranscriptionOptions())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detected.isEmpty else {
                throw AudioTranscriberError.emptyTranscript
            }

            if !teachingDetectedForms.contains(where: { $0.caseInsensitiveCompare(detected) == .orderedSame }) {
                teachingDetectedForms.append(detected)
            }
            teachRaw = teachingDetectedForms.first ?? detected
            teachingSampleCount = min(3, teachingSampleCount + 1)
            teachingSampleStatus = teachingSampleCount >= 3 ? "Three samples captured. Enter the spelling to save." : "Sample \(teachingSampleCount) captured. Record another for better coverage."
            lastError = nil
        } catch {
            teachingSampleStatus = "Could not transcribe sample"
            lastError = "Correction sample failed: \(error.localizedDescription)"
        }
    }

    private func recordTeachingSample(_ frame: AudioFrame) async {
        teachingFrameCount += 1
        teachingSampleRate = frame.sampleRate
        teachingSamples.append(contentsOf: frame.samples)

        let rms = sqrt(frame.samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(frame.samples.count, 1)))
        peakTeachingInputRMS = max(peakTeachingInputRMS, rms)
        teachingNoiseFloorRMS = Self.updatedNoiseFloor(currentFloor: teachingNoiseFloorRMS, rms: rms)
        teachingInputLevel = Self.displayLevel(rms: rms, noiseFloor: teachingNoiseFloorRMS, previous: teachingInputLevel)

        if let teachingStartedAt,
           Date().timeIntervalSince(teachingStartedAt) >= 6.0,
           isTeachingRecording {
            await stopTeachingSampleRecording()
        }
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
            let spokenForms = teachingDetectedForms.isEmpty ? raw : teachingDetectedForms.joined(separator: ", ")
            let content = "QuietType \(teachingKind.label.lowercased()): when spoken text sounds like \(spokenForms), prefer \"\(corrected)\". Apply this during local dictation cleanup without adding unsupported content."
            let submission = try await sageDirectClient.submitTranslationMemory(content: content)
            let memory = DictationMemory(
                id: submission.memoryID,
                type: teachingKind.memoryType,
                payload: teachingPayload(raw: raw, corrected: corrected, context: context, spokenForms: spokenForms),
                contexts: [selectedProfile.appName, selectedProfile.appProfile.rawValue, "pronunciation_training"],
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

    private func teachingPayload(raw: String, corrected: String, context: String, spokenForms: String) -> [String: String] {
        switch teachingKind {
        case .vocabulary:
            return [
                "term": corrected,
                "preferred": corrected,
                "preferred_spelling": corrected,
                "spoken_forms": spokenForms,
                "kind": teachingKind.rawValue,
                "context": context
            ]
        case .style:
            return [
                "rule": corrected,
                "raw": raw,
                "corrected": corrected,
                "kind": teachingKind.rawValue,
                "context": context,
                "spoken_forms": spokenForms
            ]
        case .correction, .translation:
            return [
                "raw": raw,
                "corrected": corrected,
                "kind": teachingKind.rawValue,
                "context": context,
                "spoken_forms": spokenForms
            ]
        }
    }

    func advanceCalibrationSet() {
        calibrationSetIndex = (calibrationSetIndex + 1) % CalibrationSet.defaults.count
        trainingDuration = 0
        trainingInputLevel = 0
        peakTrainingInputLevel = 0
        peakTrainingInputRMS = 0
        trainingNoiseFloorRMS = 0.006
        trainingTranscriptDraft = ""
        lastTrainingAudioURL = nil
        statusMessage = "Loaded \(currentCalibrationSet.title)"
    }

    func discardCalibrationRecording() {
        trainingCaptureService?.stop()
        trainingCaptureService = nil
        trainingStartedAt = nil
        isTrainingRecording = false
        trainingSamples = []
        trainingSampleRate = 16_000
        trainingFrameCount = 0
        trainingDuration = 0
        trainingInputLevel = 0
        peakTrainingInputLevel = 0
        peakTrainingInputRMS = 0
        trainingNoiseFloorRMS = 0.006
        trainingTranscriptDraft = ""
        lastTrainingAudioURL = nil
        statusMessage = "Voice training skipped"
        lastError = nil
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
        peakTrainingInputLevel = 0
        peakTrainingInputRMS = 0
        trainingNoiseFloorRMS = 0.006
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
        guard peakTrainingInputRMS >= Self.minimumUsableRMS else {
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
            try OwnerOnlyFileSecurity.prepareDirectory(directory)
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
        peakTrainingInputRMS = max(peakTrainingInputRMS, rms)
        trainingNoiseFloorRMS = Self.updatedNoiseFloor(currentFloor: trainingNoiseFloorRMS, rms: rms)
        trainingInputLevel = Self.displayLevel(rms: rms, noiseFloor: trainingNoiseFloorRMS, previous: trainingInputLevel)
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
                return "Where this applies"
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

        var rawPlaceholder: String {
            switch self {
            case .correction:
                return "Example: Dylan"
            case .vocabulary:
                return "Example: comet bee eff tee"
            case .style:
                return "Example: Slack messages, emails, code review notes"
            case .translation:
                return "Example: we need apples bananas and milk"
            }
        }

        var correctedPlaceholder: String {
            switch self {
            case .correction:
                return "Example: Dhillon"
            case .vocabulary:
                return "Example: CometBFT"
            case .style:
                return "Example: Keep messages concise, direct, and natural."
            case .translation:
                return "Example: - Apples\n- Bananas\n- Milk"
            }
        }

        var contextPlaceholder: String {
            switch self {
            case .correction:
                return "Example: names, Slack, coding agents"
            case .vocabulary:
                return "Example: technical terms, crypto, benchmarks"
            case .style:
                return ""
            case .translation:
                return "Example: grocery lists, notes, numbered steps"
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
