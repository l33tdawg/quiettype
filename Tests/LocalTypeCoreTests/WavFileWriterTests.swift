import XCTest
@testable import LocalTypeCore

final class WavFileWriterTests: XCTestCase {
    func testWritesMonoPCM16Header() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try WavFileWriter.writeMonoPCM16(samples: [0, 0.5, -0.5], sampleRate: 16_000, to: url)

        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data[12..<16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(data.count, 44 + 3 * 2)
    }

    func testWritesOwnerOnlyWavFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }

        try WavFileWriter.writeMonoPCM16(samples: [0], sampleRate: 16_000, to: url)

        XCTAssertEqual(try permissions(at: url), 0o600)
    }

    func testPreparesOwnerOnlyDirectory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quiettype-secure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }

        try OwnerOnlyFileSecurity.prepareDirectory(url)

        XCTAssertEqual(try permissions(at: url), 0o700)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
