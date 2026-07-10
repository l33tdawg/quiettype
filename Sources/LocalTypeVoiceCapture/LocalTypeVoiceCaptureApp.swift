import AppKit
import AVFoundation
import Foundation
import LocalTypeCore
import SwiftUI

@main
struct LocalTypeVoiceCaptureApp: App {
    @StateObject private var model = VoiceCaptureModel()

    var body: some Scene {
        WindowGroup("QuietType Voice Capture") {
            VoiceCaptureView(model: model)
        }
        .defaultSize(width: 880, height: 720)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
private final class VoiceCaptureModel: ObservableObject {
    @Published private(set) var currentIndex = 0
    @Published private(set) var isRecording = false
    @Published private(set) var inputLevel = 0.0
    @Published private(set) var recordedDurations: [String: Double] = [:]
    @Published var statusMessage = "Ready to build a private local corpus"
    @Published var errorMessage: String?

    let suite = VoiceFlowCaptureSuite.quietTypeStandard
    let corpusDirectory: URL

    private let audioDirectory: URL
    private let manifestURL: URL
    private var captureService: AVAudioCaptureService?
    private var captureBuffer: LockedVoiceCaptureBuffer?

    init() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuietType/Benchmarks", isDirectory: true)
        corpusDirectory = root
        audioDirectory = root.appendingPathComponent("audio", isDirectory: true)
        manifestURL = root.appendingPathComponent("voice-flow.json")
        loadExistingManifest()
    }

    var currentPrompt: VoiceFlowCapturePrompt {
        suite.prompts[currentIndex]
    }

    var progressLabel: String {
        "Prompt \(currentIndex + 1) of \(suite.prompts.count)"
    }

    var savedCount: Int {
        recordedDurations.count
    }

    var currentPromptIsSaved: Bool {
        recordedDurations[currentPrompt.id] != nil
    }

    var currentDurationLabel: String? {
        recordedDurations[currentPrompt.id].map { String(format: "%.1f seconds saved", $0) }
    }

    var canGoBack: Bool {
        currentIndex > 0 && !isRecording
    }

    var canGoForward: Bool {
        currentIndex + 1 < suite.prompts.count && !isRecording
    }

    func startRecording() async {
        guard !isRecording else { return }
        errorMessage = nil

        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if permission == .denied || permission == .restricted {
            errorMessage = "Microphone access is blocked. Allow QuietType Voice Capture in System Settings > Privacy & Security > Microphone."
            return
        }
        if permission == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                errorMessage = "Microphone access was not granted. No recording was created."
                return
            }
        }

        let buffer = LockedVoiceCaptureBuffer()
        let service = AVAudioCaptureService(synchronousFrameHandler: { [weak self, weak buffer] frame in
            guard let level = buffer?.append(frame) else { return }
            Task { @MainActor [weak self] in
                self?.inputLevel = level
            }
        })

        do {
            try service.start()
            captureBuffer = buffer
            captureService = service
            isRecording = true
            inputLevel = 0
            statusMessage = "Recording locally — speak the script, then stop and save"
        } catch {
            captureBuffer = nil
            captureService = nil
            errorMessage = "Could not start the microphone: \(error.localizedDescription)"
        }
    }

    func stopAndSave() {
        guard isRecording else { return }
        captureService?.stop()
        captureService = nil
        isRecording = false
        inputLevel = 0

        guard let snapshot = captureBuffer?.snapshot() else {
            captureBuffer = nil
            errorMessage = "No microphone frames were captured."
            return
        }
        captureBuffer = nil

        let duration = Double(snapshot.samples.count) / Double(max(snapshot.sampleRate, 1))
        guard duration >= 0.6 else {
            errorMessage = "That recording was shorter than 0.6 seconds and was discarded. Please try again."
            statusMessage = "Short recording discarded locally"
            return
        }

        do {
            try OwnerOnlyFileSecurity.prepareDirectory(corpusDirectory)
            try OwnerOnlyFileSecurity.prepareDirectory(audioDirectory)
            let audioURL = audioDirectory.appendingPathComponent("\(currentPrompt.id).wav")
            try WavFileWriter.writeMonoPCM16(
                samples: snapshot.samples,
                sampleRate: snapshot.sampleRate,
                to: audioURL
            )
            recordedDurations[currentPrompt.id] = duration
            try writeManifest()
            statusMessage = "Saved \(String(format: "%.1f", duration)) seconds locally"
            errorMessage = nil
            if currentIndex + 1 < suite.prompts.count {
                currentIndex += 1
            }
        } catch {
            errorMessage = "Could not save the local recording: \(error.localizedDescription)"
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        captureService?.stop()
        captureService = nil
        captureBuffer = nil
        isRecording = false
        inputLevel = 0
        statusMessage = "Recording discarded locally"
    }

    func previousPrompt() {
        guard canGoBack else { return }
        currentIndex -= 1
        errorMessage = nil
        statusMessage = currentPromptIsSaved ? "Existing local recording" : "Ready to record"
    }

    func nextPrompt() {
        guard canGoForward else { return }
        currentIndex += 1
        errorMessage = nil
        statusMessage = currentPromptIsSaved ? "Existing local recording" : "Ready to record"
    }

    func openCorpusFolder() {
        do {
            try OwnerOnlyFileSecurity.prepareDirectory(corpusDirectory)
            NSWorkspace.shared.open(corpusDirectory)
        } catch {
            errorMessage = "Could not open the local corpus folder: \(error.localizedDescription)"
        }
    }

    private func loadExistingManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(VoiceFlowBenchmarkManifest.self, from: data) else {
            return
        }

        do {
            try manifest.validate()
        } catch {
            errorMessage = "The existing local benchmark manifest is invalid and was not loaded."
            return
        }

        let casesByID = Dictionary(uniqueKeysWithValues: manifest.cases.map { ($0.id, $0) })
        for prompt in suite.prompts {
            let caseID = prompt.keywordComparisonTerms.isEmpty ? prompt.id : "\(prompt.id)-baseline"
            guard let benchmarkCase = casesByID[caseID] else { continue }
            let audioURL = corpusDirectory.appendingPathComponent(benchmarkCase.audioPath)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                recordedDurations[prompt.id] = benchmarkCase.durationSeconds
            }
        }
    }

    private func writeManifest() throws {
        let cases = suite.prompts.flatMap { prompt -> [VoiceFlowBenchmarkCase] in
            guard let duration = recordedDurations[prompt.id] else { return [] }
            return prompt.benchmarkCases(
                audioPath: "audio/\(prompt.id).wav",
                durationSeconds: duration
            )
        }
        let manifest = VoiceFlowBenchmarkManifest(cases: cases)
        try manifest.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try OwnerOnlyFileSecurity.protectFile(manifestURL)
    }
}

private final class LockedVoiceCaptureBuffer: @unchecked Sendable {
    struct Snapshot {
        var samples: [Float]
        var sampleRate: Int
    }

    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate = 0
    private var lastLevelUpdateAt: TimeInterval = 0

    /// Appends synchronously on the audio callback and returns a throttled level.
    func append(_ frame: AudioFrame) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        if sampleRate == 0 {
            sampleRate = frame.sampleRate
        }
        guard frame.sampleRate == sampleRate else { return nil }
        samples.append(contentsOf: frame.samples)
        guard frame.timestamp - lastLevelUpdateAt >= 0.08 else { return nil }
        lastLevelUpdateAt = frame.timestamp
        let rms = sqrt(
            frame.samples.reduce(0.0) { $0 + Double($1 * $1) }
                / Double(max(frame.samples.count, 1))
        )
        return min(1, max(0, (rms - 0.002) / 0.12))
    }

    func snapshot() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard sampleRate > 0, !samples.isEmpty else { return nil }
        return Snapshot(samples: samples, sampleRate: sampleRate)
    }
}

private struct VoiceCaptureView: View {
    @ObservedObject var model: VoiceCaptureModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    privacyNotice
                    progress
                    promptCard
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout.weight(.medium))
                            .textSelection(.enabled)
                    }
                    controls
                }
                .padding(28)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onDisappear {
            model.cancelRecording()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 28, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("QuietType Voice Capture")
                    .font(.title2.bold())
                Text("Build a repeatable, private speech corpus on this Mac")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open local folder") {
                model.openCorpusFolder()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Local capture only")
                    .font(.headline)
                Text("Recordings and references are written under QuietType's Application Support directory with owner-only permissions. Nothing is uploaded, and there is no cloud fallback.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(model.progressLabel)
                    .font(.headline)
                Spacer()
                Text("\(model.savedCount) saved")
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(model.currentIndex + 1),
                total: Double(model.suite.prompts.count)
            )
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(model.currentPrompt.category.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.currentPromptIsSaved {
                    Label(model.currentDurationLabel ?? "Saved", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(model.currentPrompt.deliveryInstruction)
                .font(.headline)

            Text(model.currentPrompt.expectedText)
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .lineSpacing(6)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(model.isRecording ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 9, height: 9)
                    Text(model.statusMessage)
                        .font(.callout.weight(.medium))
                    Spacer()
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.12))
                        Capsule()
                            .fill(model.isRecording ? Color.green : Color.secondary.opacity(0.35))
                            .frame(width: geometry.size.width * model.inputLevel)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Previous") {
                model.previousPrompt()
            }
            .disabled(!model.canGoBack)

            if model.isRecording {
                Button("Discard") {
                    model.cancelRecording()
                }
                Spacer()
                Button("Stop and save") {
                    model.stopAndSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            } else {
                Spacer()
                Button(model.currentPromptIsSaved ? "Record again" : "Start recording") {
                    Task {
                        await model.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Next") {
                    model.nextPrompt()
                }
                .disabled(!model.canGoForward)
            }
        }
    }
}
