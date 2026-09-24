import XCTest
@testable import DuoLogic
final class ContractTests: XCTestCase {
    func testJoypadABI() { XCTAssertEqual(DSButton.a.rawValue, 8); XCTAssertEqual(DSButton.r.rawValue, 11) }
}
