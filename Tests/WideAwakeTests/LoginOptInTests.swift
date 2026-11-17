import Foundation
import XCTest
@testable import WideAwake

/// New and missing choices must not silently request a macOS login item.
final class LoginOptInTests: XCTestCase {
    func testNewConfigurationDoesNotRequestLoginRegistration() {
        XCTAssertFalse(Config().launchAtLogin)
    }
    func testLegacyConfigurationWithoutChoiceDoesNotOptIn() throws {
        let value = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertFalse(value.launchAtLogin)
    }
    func testExplicitExistingOptInIsPreserved() throws {
        let value = try JSONDecoder().decode(Config.self, from: Data("{\"launchAtLogin\":true}".utf8))
        XCTAssertTrue(value.launchAtLogin)
        XCTAssertTrue(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(value)).launchAtLogin)
    }
    func testExplicitOptOutIsPreserved() throws {
        let value = try JSONDecoder().decode(Config.self, from: Data("{\"launchAtLogin\":false}".utf8))
        XCTAssertFalse(value.launchAtLogin)
    }
}
