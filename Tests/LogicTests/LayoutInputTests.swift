import XCTest
import CoreGraphics
@testable import DuoLogic

final class LayoutInputTests: XCTestCase {
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private func assertScreen(_ screen: CGRect, inside safe: CGRect, avoiding barriers: [CGRect],
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(screen.width, 0, file: file, line: line)
        XCTAssertTrue(safe.contains(screen), file: file, line: line)
        XCTAssertEqual(screen.width / screen.height, 4.0 / 3.0, accuracy: 0.001, file: file, line: line)
        for barrier in barriers { XCTAssertFalse(screen.intersects(barrier), file: file, line: line) }
    }

    func testSafeAreaAndCameraOcclusion() {
        let safe = rect(12, 42, 366, 760)
        let camera = rect(160, 42, 70, 40)
        let environment = DisplayEnvironment(bounds: rect(0, 0, 390, 844), safeBounds: safe,
            reservedRegions: [ReservedRegion(frame: camera, kind: .occlusion)])
        let result = ScreenLayoutSolver.solve(environment: environment)
        assertScreen(result.upperScreen, inside: safe, avoiding: [camera])
        assertScreen(result.lowerScreen, inside: safe, avoiding: [camera])
        XCTAssertFalse(result.upperScreen.intersects(result.lowerScreen))
        for controls in result.controlRegions {
            XCTAssertTrue(safe.contains(controls))
            XCTAssertFalse(controls.intersects(camera))
            XCTAssertFalse(controls.intersects(result.upperScreen))
            XCTAssertFalse(controls.intersects(result.lowerScreen))
        }
    }

    func testDivisionAndSwapKeepNativeLowerDestinationDistinct() {
        let safe = rect(0, 0, 900, 700)
        let division = rect(440, 0, 20, 700)
        let environment = DisplayEnvironment(bounds: safe, safeBounds: safe,
            reservedRegions: [ReservedRegion(frame: division, kind: .division)])
        let standard = ScreenLayoutSolver.solve(environment: environment)
        let swapped = ScreenLayoutSolver.solve(environment: environment, swapScreens: true)
        assertScreen(standard.upperScreen, inside: safe, avoiding: [division])
        assertScreen(standard.lowerScreen, inside: safe, avoiding: [division])
        XCTAssertEqual(standard.effectiveMode, .split)
        XCTAssertTrue(standard.upperScreen.duoEquals(swapped.lowerScreen))
        XCTAssertTrue(standard.lowerScreen.duoEquals(swapped.upperScreen))
    }

    func testManualModesAndCompactFallback() {
        let safe = rect(0, 0, 320, 470)
        let environment = DisplayEnvironment(bounds: safe, safeBounds: safe)
        let stacked = ScreenLayoutSolver.solve(environment: environment, preference: .stacked)
        let side = ScreenLayoutSolver.solve(environment: environment, preference: .sideBySide)
        XCTAssertEqual(stacked.effectiveMode, .stacked)
        XCTAssertEqual(side.effectiveMode, .sideBySide)
        assertScreen(stacked.upperScreen, inside: safe, avoiding: [])
        assertScreen(stacked.lowerScreen, inside: safe, avoiding: [])
        assertScreen(side.upperScreen, inside: safe, avoiding: [])
        assertScreen(side.lowerScreen, inside: safe, avoiding: [])
    }

    func testTouchMappingRejectsOutsideAndUsesLowerScreenCoordinates() {
        let lower = rect(20, 30, 512, 384)
        let center = InputRouter.mapTouch(CGPoint(x: 276, y: 222), in: lower)
        XCTAssertEqual(center?.x, 128)
        XCTAssertEqual(center?.y, 96)
        let last = InputRouter.mapTouch(CGPoint(x: 531.999, y: 413.999), in: lower)
        XCTAssertEqual(last?.x, 255)
        XCTAssertEqual(last?.y, 191)
        XCTAssertNil(InputRouter.mapTouch(CGPoint(x: 532, y: 222), in: lower))
        XCTAssertNil(InputRouter.mapTouch(CGPoint(x: 276, y: 29), in: lower))
    }

    func testStylusIdentityAndResizeCancellation() {
        let router = InputRouter()
        let lower = rect(0, 200, 256, 192)
        XCTAssertFalse(router.beginStylus(id: 1, at: CGPoint(x: 10, y: 10), lowerScreen: lower))
        XCTAssertTrue(router.beginStylus(id: 1, at: CGPoint(x: 10, y: 210), lowerScreen: lower))
        XCTAssertFalse(router.beginStylus(id: 2, at: CGPoint(x: 20, y: 220), lowerScreen: lower))
        router.endStylus(id: 2)
        XCTAssertTrue(router.snapshot.touching)
        router.setLowerScreen(rect(0, 180, 256, 192))
        XCTAssertFalse(router.snapshot.touching)
        XCTAssertTrue(router.beginStylus(id: 2, at: CGPoint(x: 20, y: 220), lowerScreen: rect(0, 180, 256, 192)))
        router.cancelTransientInputs()
        XCTAssertFalse(router.snapshot.touching)
    }

    func testButtonSourcesDoNotReleaseEachOther() {
        let router = InputRouter()
        router.press(.a, source: "virtual.one")
        router.setButtons([.a, .b], source: "controller.one")
        router.release(.a, source: "virtual.one")
        XCTAssertNotEqual(router.snapshot.buttons & (1 << DSButton.a.rawValue), 0)
        router.disconnect(source: "controller.one")
        XCTAssertEqual(router.snapshot.buttons, 0)
        router.press(.l, source: "virtual.two")
        router.setButtons([.r], source: "controller.two")
        router.disconnect(source: "controller.two")
        XCTAssertNotEqual(router.snapshot.buttons & (1 << DSButton.l.rawValue), 0)
        router.cancelTransientInputs()
        XCTAssertEqual(router.snapshot.buttons, 0)
    }
}
