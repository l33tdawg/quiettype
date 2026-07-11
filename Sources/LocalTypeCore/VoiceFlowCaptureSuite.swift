import Foundation

public struct VoiceFlowCapturePrompt: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var category: String
    public var deliveryInstruction: String
    public var expectedText: String
    public var requiredTerms: [String]
    public var keywordComparisonTerms: [String]

    public init(
        id: String,
        category: String,
        deliveryInstruction: String,
        expectedText: String,
        requiredTerms: [String] = [],
        keywordComparisonTerms: [String] = []
    ) {
        self.id = id
        self.category = category
        self.deliveryInstruction = deliveryInstruction
        self.expectedText = expectedText
        self.requiredTerms = requiredTerms
        self.keywordComparisonTerms = keywordComparisonTerms
    }

    public func benchmarkCases(audioPath: String, durationSeconds: Double) -> [VoiceFlowBenchmarkCase] {
        let baseline = VoiceFlowBenchmarkCase(
            id: keywordComparisonTerms.isEmpty ? id : "\(id)-baseline",
            audioPath: audioPath,
            expectedText: expectedText,
            durationSeconds: durationSeconds,
            requiredTerms: requiredTerms
        )
        guard !keywordComparisonTerms.isEmpty else {
            return [baseline]
        }
        return [
            baseline,
            VoiceFlowBenchmarkCase(
                id: "\(id)-keywords",
                audioPath: audioPath,
                expectedText: expectedText,
                durationSeconds: durationSeconds,
                requiredTerms: requiredTerms,
                promptKeywords: keywordComparisonTerms
            )
        ]
    }
}

public struct VoiceFlowCaptureSuite: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var prompts: [VoiceFlowCapturePrompt]

    public init(schemaVersion: Int = 1, name: String, prompts: [VoiceFlowCapturePrompt]) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.prompts = prompts
    }

    public static let quietTypeStandard = VoiceFlowCaptureSuite(
        name: "QuietType standard local voice corpus",
        prompts: [
            VoiceFlowCapturePrompt(
                id: "clean-local-dictation",
                category: "Clean speech",
                deliveryInstruction: "Use your normal speaking voice and pace.",
                expectedText: "QuietType transcribes this sentence locally and inserts it into the active app.",
                requiredTerms: ["QuietType"]
            ),
            VoiceFlowCapturePrompt(
                id: "clean-review-request",
                category: "Clean speech",
                deliveryInstruction: "Speak naturally, as if assigning work to a coding agent.",
                expectedText: "Please review the authentication changes, run the focused tests, and summarize any security regressions before merging."
            ),
            VoiceFlowCapturePrompt(
                id: "clean-email",
                category: "Clean speech",
                deliveryInstruction: "Use a friendly email tone.",
                expectedText: "Hi Maya, thanks for the detailed update. I reviewed the proposal and the revised timeline works for me. Best, Dhillon."
            ),
            VoiceFlowCapturePrompt(
                id: "clean-notes",
                category: "Clean speech",
                deliveryInstruction: "Speak like you are capturing a quick private note.",
                expectedText: "The launch felt smooth today. Keep the onboarding concise, make the privacy promise visible, and test the first run experience again tomorrow."
            ),
            VoiceFlowCapturePrompt(
                id: "clean-agent-plan",
                category: "Clean speech",
                deliveryInstruction: "Speak one complete instruction without rushing.",
                expectedText: "Inspect the current implementation, preserve unrelated user changes, add regression coverage, and show me the exact performance difference before changing the default behavior."
            ),
            VoiceFlowCapturePrompt(
                id: "clean-multisentence",
                category: "Clean speech",
                deliveryInstruction: "Pause briefly between the three sentences.",
                expectedText: "The microphone is ready. The local speech engine is warm. We can start dictating without waiting for a network connection."
            ),
            VoiceFlowCapturePrompt(
                id: "technical-products",
                category: "Technical vocabulary",
                deliveryInstruction: "Say each product name clearly but naturally.",
                expectedText: "QuietType stores governed correction memories in SAGE and measures CometBFT performance locally.",
                requiredTerms: ["QuietType", "SAGE", "CometBFT"],
                keywordComparisonTerms: ["QuietType", "SAGE", "CometBFT"]
            ),
            VoiceFlowCapturePrompt(
                id: "technical-cryptography",
                category: "Technical vocabulary",
                deliveryInstruction: "Read the identifiers as you normally would in a technical discussion.",
                expectedText: "Verify the Ed25519 signature, rotate the X25519 session key, and keep the SHA256 checksum in the release notes.",
                requiredTerms: ["Ed25519", "X25519", "SHA256"],
                keywordComparisonTerms: ["Ed25519", "X25519", "SHA256"]
            ),
            VoiceFlowCapturePrompt(
                id: "technical-swift",
                category: "Technical vocabulary",
                deliveryInstruction: "Use a normal engineering-review cadence.",
                expectedText: "The SwiftUI view starts an AVAudioEngine capture session and writes owner only PCM16 WAV files.",
                requiredTerms: ["SwiftUI", "AVAudioEngine", "PCM16", "WAV"],
                keywordComparisonTerms: ["SwiftUI", "AVAudioEngine", "PCM16", "WAV"]
            ),
            VoiceFlowCapturePrompt(
                id: "technical-local-models",
                category: "Technical vocabulary",
                deliveryInstruction: "Speak the model and runtime names without spelling them letter by letter.",
                expectedText: "WhisperKit runs the Core ML speech model while Ollama handles optional local semantic cleanup.",
                requiredTerms: ["WhisperKit", "Core ML", "Ollama"],
                keywordComparisonTerms: ["WhisperKit", "Core ML", "Ollama"]
            ),
            VoiceFlowCapturePrompt(
                id: "technical-versioning",
                category: "Technical vocabulary",
                deliveryInstruction: "Read version numbers and units naturally.",
                expectedText: "Pin SAGE to version eleven point four point eleven and keep the streaming overlap at two hundred fifty milliseconds.",
                requiredTerms: ["SAGE"]
            ),
            VoiceFlowCapturePrompt(
                id: "correction-day",
                category: "Corrections and restarts",
                deliveryInstruction: "Include the correction exactly as written.",
                expectedText: "Schedule the benchmark review for Thursday, sorry, Friday at three PM, and invite the speech performance team."
            ),
            VoiceFlowCapturePrompt(
                id: "correction-name",
                category: "Corrections and restarts",
                deliveryInstruction: "Correct the name mid-sentence without starting over.",
                expectedText: "Send the release summary to Dylan, correction, Dhillon, and ask him to verify the notarized build.",
                requiredTerms: ["Dhillon"]
            ),
            VoiceFlowCapturePrompt(
                id: "restart-deployment",
                category: "Corrections and restarts",
                deliveryInstruction: "Stop after the first phrase, then restart naturally.",
                expectedText: "The deployment should use the old image. Let me restart. The deployment should use the newly signed image after all checks pass."
            ),
            VoiceFlowCapturePrompt(
                id: "fillers-natural",
                category: "Corrections and restarts",
                deliveryInstruction: "Keep the filler words instead of reading too formally.",
                expectedText: "I think we should, um, measure the cold start first and then, you know, compare it with the next five warm runs."
            ),
            VoiceFlowCapturePrompt(
                id: "pause-middle",
                category: "Pause survival",
                deliveryInstruction: "Pause silently for two seconds after the word locally.",
                expectedText: "The first transcript is processed locally before the final polished result appears in the target application."
            ),
            VoiceFlowCapturePrompt(
                id: "pause-list",
                category: "Pause survival",
                deliveryInstruction: "Pause for one second between each item.",
                expectedText: "First check microphone access. Second warm the native engine. Third verify local memory. Fourth begin dictation."
            ),
            VoiceFlowCapturePrompt(
                id: "quiet-speech",
                category: "Delivery variation",
                deliveryInstruction: "Speak quietly, but do not whisper.",
                expectedText: "Quiet speech should remain complete even when the room is calm and the microphone level is lower than usual."
            ),
            VoiceFlowCapturePrompt(
                id: "fast-speech",
                category: "Delivery variation",
                deliveryInstruction: "Speak noticeably faster than normal while staying understandable.",
                expectedText: "Run the tests, inspect the diff, verify the privacy boundary, update the documentation, and report the result when every check is green."
            ),
            VoiceFlowCapturePrompt(
                id: "distant-speech",
                category: "Delivery variation",
                deliveryInstruction: "Move about one arm's length farther from the microphone.",
                expectedText: "A useful local dictation tool should still recognize a complete sentence when the speaker is not directly beside the laptop."
            ),
            VoiceFlowCapturePrompt(
                id: "noise-keyboard",
                category: "Background noise",
                deliveryInstruction: "Type lightly on the keyboard while speaking.",
                expectedText: "Keyboard noise must not create extra words or hide the technical terms in this local benchmark.",
                requiredTerms: ["local benchmark"]
            ),
            VoiceFlowCapturePrompt(
                id: "noise-fan",
                category: "Background noise",
                deliveryInstruction: "Record near a fan or steady ventilation noise if available.",
                expectedText: "Steady background noise should not cause a false insertion after the speaker finishes the sentence."
            ),
            VoiceFlowCapturePrompt(
                id: "numbers-formatting",
                category: "Numbers and formatting",
                deliveryInstruction: "Read the quantities, time, and date naturally.",
                expectedText: "Create three tasks for July tenth, set the timeout to forty five seconds, and schedule the review for three thirty PM."
            ),
            VoiceFlowCapturePrompt(
                id: "casing-short-names",
                category: "Casing regressions",
                deliveryInstruction: "Say Amy and Amanda naturally. Do not spell either name letter by letter.",
                expectedText: "I asked Amy to send Amanda the updated review notes before lunch.",
                requiredTerms: ["Amy", "Amanda"]
            ),
            VoiceFlowCapturePrompt(
                id: "casing-bro-but",
                category: "Casing regressions",
                deliveryInstruction: "Use a casual tone and clearly say both bro and but mid-sentence.",
                expectedText: "I understand the concern, bro, but we still need the complete benchmark before release.",
                requiredTerms: ["bro", "but"]
            ),
            VoiceFlowCapturePrompt(
                id: "casing-names-and-time",
                category: "Casing regressions",
                deliveryInstruction: "Read the names and times naturally, without emphasizing capitalization.",
                expectedText: "Amy will call Amanda at nine AM, and Maya will send the final update at three PM.",
                requiredTerms: ["Amy", "Amanda", "Maya", "AM", "PM"]
            ),
            VoiceFlowCapturePrompt(
                id: "fn-tail-release",
                category: "FN tail latency",
                deliveryInstruction: "Press FN to start. Speak naturally, then press FN again immediately after the final word benchmark.",
                expectedText: "We checked the model, the memory, the insertion path, and the final local benchmark.",
                requiredTerms: ["benchmark"]
            ),
            VoiceFlowCapturePrompt(
                id: "medium-natural-pauses",
                category: "FN tail latency",
                deliveryInstruction: "Speak at your normal dictation pace. Pause naturally after each sentence and press FN immediately after the last word.",
                expectedText: "This release candidate needs to feel immediate in ordinary use. A short request should appear almost as soon as I finish speaking. A longer planning note should be processed while I am still talking, without showing unstable preview text. Natural pauses must not lose the word before the pause or the word after it. If the incremental result is incomplete, QuietType should use the full local recording. The final decision depends on repeatable accuracy and release to insertion latency.",
                requiredTerms: ["QuietType"]
            ),
            VoiceFlowCapturePrompt(
                id: "long-product-plan",
                category: "Long form",
                deliveryInstruction: "Read at a comfortable pace. Take natural pauses between paragraphs.",
                expectedText: """
                The next QuietType milestone should make local dictation feel immediate without weakening the privacy promise. Start by measuring what users actually experience from the moment they press the shortcut until polished text appears in the active application. Separate the first run after an installation or upgrade from later warm sessions because model startup can dominate the first result. Track the first useful partial transcript, the number of revisions, the work waiting in the streaming queue, the delay after key release, and the final insertion time. None of those measurements need the transcript itself, the audio file name, or the identity of the target application.

                Use a representative set of local recordings instead of tuning against one clean microphone sample. Include quiet speech, quick instructions, natural pauses, self corrections, technical vocabulary, keyboard sounds, steady fan noise, and longer planning notes. Keep the same recordings for every candidate so a faster result cannot hide a loss in word accuracy. When a change helps only one category, place it behind a narrow experiment flag until the tradeoff is understood.

                Adaptive speech detection should begin conservatively. Preserve a short buffer before detected speech, keep a generous hangover after the signal drops, and always retain the complete recording until the final local transcription succeeds. Stable partial text can improve perceived speed, but uncertain trailing words should remain editable until the final pass. If the fast path becomes unreliable, fall back to the complete local recording rather than sending anything to a hosted service. The release decision should be based on repeatable evidence: no meaningful word error regression, no lost first or last words, no increase in noise hallucinations, and a clear improvement in median or tail latency.
                """,
                requiredTerms: ["QuietType"]
            ),
            VoiceFlowCapturePrompt(
                id: "long-technical-review",
                category: "Long form",
                deliveryInstruction: "Read naturally as if presenting an engineering review.",
                expectedText: """
                This engineering review covers the complete on device speech path. The macOS application captures microphone frames through AVAudioEngine and retains them only for the local dictation session. Rolling WAV chunks feed a loopback WhisperKit service so the interface can display advisory partial text while the user is still speaking. After key release, QuietType resolves the complete recording with the local Core ML model, applies conservative vocabulary repair, performs optional semantic cleanup through a loopback runtime, and inserts the result into the application that originally owned keyboard focus.

                The security boundary is intentionally simple. Audio, partial transcripts, final transcripts, prompt hints, correction memories, and benchmark references remain on the Mac. There is no configurable hosted speech endpoint and no cloud fallback. SAGE provides governed local memory for preferred spellings and approved corrections. Benchmark reports contain numeric measurements and neutral case identifiers, but they do not contain recognized text, expected text, audio paths, application names, document context, or filenames. Private corpus directories and report files use owner only permissions.

                Performance work must preserve those boundaries. Candidate profiles may adjust chunk duration, overlap, pre roll, speech activation thresholds, hangover duration, stable prefix handling, or final tail decoding. Each candidate runs against the exact same corpus and hardware state. Compare word error rate, required term accuracy, first run latency, steady state latency, queue depth, preview churn, pause survival, and noise only behavior. Reject a candidate when it truncates quiet speech, loses words beside a pause, increases false insertions, or makes tail latency materially worse. Promote a new default only when the measurements are repeatable and the full local fallback remains intact.
                """,
                requiredTerms: ["AVAudioEngine", "WAV", "WhisperKit", "QuietType", "Core ML", "SAGE"],
                keywordComparisonTerms: ["AVAudioEngine", "WhisperKit", "QuietType", "Core ML", "SAGE"]
            )
        ]
    )
}
