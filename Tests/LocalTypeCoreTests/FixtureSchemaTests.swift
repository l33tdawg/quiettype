import XCTest

final class FixtureSchemaTests: XCTestCase {
    func testDictationFixturesParseAndCoverRequiredVocabulary() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/dictation_cases.json")
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(DictationFixture.self, from: data)

        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(fixture.cases.count, 4)

        let expectedText = fixture.cases.map { $0.expected.editedText }.joined(separator: "\n")
        for term in ["SAGE", "CometBFT", "Ollama", "Utimaco", "CSe100", "Ed25519"] {
            XCTAssertTrue(expectedText.contains(term), "Missing fixture coverage for \(term)")
        }
    }
}

private struct DictationFixture: Decodable {
    var schemaVersion: Int
    var cases: [DictationCase]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case cases
    }
}

private struct DictationCase: Decodable {
    var id: String
    var expected: Expected
}

private struct Expected: Decodable {
    var editedText: String

    enum CodingKeys: String, CodingKey {
        case editedText = "edited_text"
    }
}
