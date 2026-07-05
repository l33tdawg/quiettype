import XCTest
@testable import LocalTypeCore

final class ModelsTests: XCTestCase {
    func testDecodesLegacyDictationProfileWithoutSpellingPreference() throws {
        let json = """
        {
          "language": "en",
          "speechRateWPM": 152,
          "pauseThresholdMS": 390,
          "vadSensitivity": 0.7,
          "activeASRBackend": "whisperkit",
          "activeEditorModel": "local",
          "vocabulary": [],
          "confusions": []
        }
        """

        let profile = try JSONDecoder().decode(DictationProfile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.speechRateWPM, 152)
        XCTAssertEqual(profile.spellingPreference, .system)
    }
}
