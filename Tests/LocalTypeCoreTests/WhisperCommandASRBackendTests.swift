import XCTest
@testable import LocalTypeCore

final class WhisperCommandASRBackendTests: XCTestCase {
    func testBuildsWhisperCLIArguments() throws {
        let model = try temporaryFile(named: "model.bin")
        let wav = try temporaryFile(named: "recording.wav")
        let backend = WhisperCommandASRBackend(
            executablePath: "/bin/echo",
            modelPath: model.path,
            language: "ms",
            extraArguments: ["--temperature", "0", "--no-timestamps"]
        )

        XCTAssertEqual(
            backend.commandArguments(wavFile: wav),
            [
                "-m",
                model.path,
                "-f",
                wav.path,
                "-l",
                "ms",
                "--temperature",
                "0",
                "--no-timestamps"
            ]
        )
    }

    func testTranscribesTimestampedWhisperOutputFromCommandStdout() async throws {
        let model = try temporaryFile(named: "model.bin")
        let wav = try temporaryFile(named: "recording.wav")
        let backend = WhisperCommandASRBackend(
            executablePath: "/bin/echo",
            modelPath: model.path,
            language: "en",
            extraArguments: [
                "[00:00:00.000 --> 00:00:01.500]",
                "hello",
                "local",
                "voice"
            ]
        )

        let transcript = try await backend.transcribe(wavFile: wav)

        XCTAssertEqual(transcript, "hello local voice")
    }

    func testReturnsProcessFailureForNonZeroCommandExit() async throws {
        let model = try temporaryFile(named: "fake-shell-model.sh", contents: "exit 7\n")
        let wav = try temporaryFile(named: "recording.wav")
        let backend = WhisperCommandASRBackend(
            executablePath: "/bin/sh",
            modelPath: model.path,
            language: nil
        )

        do {
            _ = try await backend.transcribe(wavFile: wav)
            XCTFail("Expected the shell-backed fake command to fail")
        } catch WhisperCommandASRError.processFailed(let exitCode, _, _) {
            XCTAssertNotEqual(exitCode, 0)
        } catch {
            XCTFail("Expected processFailed, got \(error)")
        }
    }

    func testParsesMultilineWhisperOutput() {
        let stdout = """
        whisper_init_from_file_with_params_no_state: loading model
        [00:00:00.000 --> 00:00:01.000] first segment
        [00:00:01.000 --> 00:00:02.000] second segment
        """

        XCTAssertEqual(
            WhisperCommandASRBackend.parseTranscript(stdout: stdout),
            "first segment second segment"
        )
    }

    func testRemovesNoiseMarkersFromWhisperOutput() {
        let stdout = """
        [00:00:00.000 --> 00:00:01.000] [Music]
        [00:00:01.000 --> 00:00:02.000] please send the note
        """

        XCTAssertEqual(
            WhisperCommandASRBackend.parseTranscript(stdout: stdout),
            "please send the note"
        )
    }

    func testDetectsNoiseOnlyTranscript() {
        XCTAssertTrue(WhisperCommandASRBackend.isNoiseOnlyTranscript("music"))
        XCTAssertTrue(WhisperCommandASRBackend.isNoiseOnlyTranscript("[Music]"))
        XCTAssertTrue(WhisperCommandASRBackend.isNoiseOnlyTranscript("♪♪♪"))
        XCTAssertFalse(WhisperCommandASRBackend.isNoiseOnlyTranscript("music is too loud here"))
    }

    private func temporaryFile(named name: String, contents: String = "") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperCommandASRBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent(name)
        try contents.data(using: .utf8)?.write(to: file)
        return file
    }
}
