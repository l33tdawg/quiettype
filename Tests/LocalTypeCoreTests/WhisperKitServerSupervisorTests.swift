import Foundation
import XCTest
@testable import LocalTypeCore

final class WhisperKitServerSupervisorTests: XCTestCase {
    func testConcurrentWarmupRequestsLaunchOnlyOneProcess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quiettype-supervisor-tests")
            .appendingPathComponent(UUID().uuidString)
        let executableURL = root.appendingPathComponent("fake-argmax-cli")
        let launchLogURL = root.appendingPathComponent("launches.log")
        let serverLogURL = root.appendingPathComponent("server.log")
        let modelURL = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = """
        #!/bin/sh
        echo launched >> "\(launchLogURL.path)"
        exec /bin/sleep 30
        """
        try Data(script.utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        try createCompleteModel(at: modelURL)

        let supervisor = WhisperKitServerSupervisor(
            executableURL: executableURL,
            modelPath: modelURL,
            startupTimeoutSeconds: 0.1,
            logURL: serverLogURL
        )
        defer { supervisor.stop() }

        let requestCount = 24
        let startGate = DispatchSemaphore(value: 0)
        let requests = DispatchGroup()
        let failuresLock = NSLock()
        var failures: [Error] = []

        for _ in 0..<requestCount {
            requests.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                startGate.wait()
                do {
                    try supervisor.startWarming()
                } catch {
                    failuresLock.lock()
                    failures.append(error)
                    failuresLock.unlock()
                }
                requests.leave()
            }
        }
        for _ in 0..<requestCount {
            startGate.signal()
        }

        XCTAssertEqual(requests.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(failures.isEmpty, "Unexpected start failures: \(failures)")
        XCTAssertTrue(supervisor.isProcessRunning)

        let launchDeadline = Date().addingTimeInterval(2)
        var launches = 0
        while launches == 0, Date() < launchDeadline {
            launches = (try? String(contentsOf: launchLogURL, encoding: .utf8))?
                .split(whereSeparator: \.isNewline)
                .count ?? 0
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertEqual(launches, 1)
    }

    private func createCompleteModel(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for directory in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            try FileManager.default.createDirectory(
                at: url.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        for file in ["config.json", "generation_config.json", "tokenizer.json", "tokenizer_config.json"] {
            try Data("{}".utf8).write(to: url.appendingPathComponent(file))
        }
    }
}
