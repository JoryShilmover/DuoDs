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

    /// Geometries observed on the iPhone Duo simulator and the iPhone 15 Pro Max (2026-09-23), plus an
    /// estimated iPhone landscape canvas. Every pose must give two DS-style thumb clusters that are
    /// large enough, inside the safe area, and clear of both screens.
    func testObservedGeometriesGetDSStyleClusters() {
        let min = ScreenLayoutSolver.clusterMinimum
        for (name, size) in [("Duo inner portrait", CGSize(width: 669, height: 805)),
                             ("Duo outer display", CGSize(width: 382, height: 532)),
                             ("Duo outer landscape", CGSize(width: 594, height: 320)),
                             ("Duo inner landscape", CGSize(width: 867, height: 523)),
                             ("iPhone 15 Pro Max portrait", CGSize(width: 430, height: 747)),
                             ("iPhone landscape (estimate)", CGSize(width: 814, height: 350))] {
            let safe = rect(0, 0, size.width, size.height)
            let result = ScreenLayoutSolver.solve(environment: DisplayEnvironment(bounds: safe, safeBounds: safe))
            XCTAssertEqual(result.controlRegions.count, 2, name)
            XCTAssertFalse(result.controlsOverlapScreens, name)
            XCTAssertFalse(result.isCompact, name)
            let (left, right) = (result.controlRegions[0], result.controlRegions[1])
            XCTAssertLessThan(left.midX, right.midX, "\(name): D-pad cluster must be on the left")
            for cluster in result.controlRegions {
                XCTAssertGreaterThanOrEqual(cluster.width, min.width, name)
                XCTAssertGreaterThanOrEqual(cluster.height, min.height, name)
                XCTAssertTrue(safe.contains(cluster), name)
                XCTAssertFalse(cluster.intersects(result.upperScreen) || cluster.intersects(result.lowerScreen), name)
            }
            XCTAssertFalse(left.intersects(right), name)
        }
    }

    func testHalfFoldPutsControlsWithLowerScreenClearOfHinge() {
        let safe = rect(0, 0, 867, 523)
        let division = rect(456, -82, 40, 669)
        let result = ScreenLayoutSolver.solve(environment: DisplayEnvironment(bounds: safe, safeBounds: safe,
            reservedRegions: [ReservedRegion(frame: division, kind: .division)]))
        XCTAssertEqual(result.effectiveMode, .split)
        XCTAssertEqual(result.controlRegions.count, 2)
        for cluster in result.controlRegions {
            XCTAssertFalse(cluster.intersects(division))
            XCTAssertFalse(cluster.intersects(result.lowerScreen) || cluster.intersects(result.upperScreen))
        }
    }

    func testControlLayoutPlacesDSLiteElements() {
        let layout = ControlLayout(left: rect(0, 500, 200, 240), right: rect(230, 500, 200, 240))
        func frame(_ element: ControlLayout.Element) -> CGRect { layout.items.first { $0.element == element }!.frame }
        XCTAssertLessThan(frame(.dpad).midX, frame(.face).midX)
        XCTAssertLessThan(frame(.button(.l)).midY, frame(.dpad).midY)          // shoulder above D-pad
        XCTAssertLessThan(frame(.button(.r)).midY, frame(.face).midY)
        XCTAssertGreaterThan(frame(.button(.start)).midY, frame(.face).midY)   // Start/Select under face buttons
        XCTAssertGreaterThan(frame(.pause).midY, frame(.dpad).midY)
        XCTAssertGreaterThanOrEqual(frame(.dpad).width, 100)
        for (i, a) in layout.items.enumerated() {
            for b in layout.items[(i + 1)...] { XCTAssertFalse(a.hitFrame.intersects(b.hitFrame), "\(a.element) vs \(b.element)") }
        }
        let centers = Dictionary(uniqueKeysWithValues: layout.faceCenters.map { ($0.0, $0.1) })
        XCTAssertLessThan(centers[.x]!.y, centers[.b]!.y)                      // X top, B bottom
        XCTAssertLessThan(centers[.y]!.x, centers[.a]!.x)                      // Y left, A right
        XCTAssertEqual(layout.faceButton(at: centers[.a]!), .a)
        XCTAssertEqual(layout.faceButton(at: CGPoint(x: centers[.a]!.x - 4, y: centers[.a]!.y + 3)), .a)
        XCTAssertNil(layout.faceButton(at: CGPoint(x: 5, y: 5)))
    }

    func testDPadEightWayWithDeadZone() {
        let pad = rect(0, 0, 100, 100)
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 50, y: 50), in: pad), [])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 95, y: 50), in: pad), [.right])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 50, y: 5), in: pad), [.up])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 5, y: 50), in: pad), [.left])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 50, y: 95), in: pad), [.down])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 90, y: 10), in: pad), [.up, .right])
        XCTAssertEqual(ControlLayout.dpadButtons(at: CGPoint(x: 10, y: 90), in: pad), [.down, .left])
    }
}
