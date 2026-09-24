import Foundation
import CoreGraphics

/// DS Lite–style on-screen controls placed inside the two thumb clusters chosen by ScreenLayoutSolver.
/// Left cluster: L shoulder (top, outer edge), D-pad, Mic/Lid/Pause pills.
/// Right cluster: R shoulder (top, outer edge), X/Y/A/B diamond, Start/Select pills.
/// Pills go in an inner column when the cluster is wide, otherwise in a row underneath.
public struct ControlLayout: Equatable {
    public enum Element: Equatable { case button(DSButton), dpad, face, pause, lid, mic }
    public enum Shape: Equatable { case pill, dpad, diamond }
    public struct Item: Equatable {
        public let element: Element
        public let title: String
        public let shape: Shape
        /// Drawn bounds.
        public let frame: CGRect
        /// Touch bounds; slightly larger than the drawn control, never overlapping another item's.
        public let hitFrame: CGRect
    }

    public let items: [Item]
    /// Face-button centres inside the diamond, in DS positions (X top, Y left, A right, B bottom).
    public let faceCenters: [(DSButton, CGPoint)]
    public let faceButtonDiameter: CGFloat

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.items == rhs.items }

    static let shoulderHeight: CGFloat = 34
    static let pillHeight: CGFloat = 30
    static let spacing: CGFloat = 8
    static let touchSlop: CGFloat = 10

    /// `scale` (0.6–1) shrinks the D-pad and face diamond within their space; `leftHanded` swaps the
    /// D-pad and face-button sides (shoulders stay L-left, R-right).
    public init(left: CGRect, right: CGRect, scale: CGFloat = 1, leftHanded: Bool = false) {
        var items: [Item] = []
        func pad(_ r: CGRect) -> CGRect { r.insetBy(dx: 6, dy: 4) }
        let l = pad(left), r = pad(right)

        // Shoulders sit at the outer top corners, where the DS's L/R buttons are.
        let shoulderWidth = min(110, l.width)
        items.append(Item(element: .button(.l), title: "L", shape: .pill,
                          frame: CGRect(x: l.minX, y: l.minY, width: shoulderWidth, height: Self.shoulderHeight),
                          hitFrame: CGRect(x: l.minX, y: l.minY, width: shoulderWidth, height: Self.shoulderHeight)))
        let rShoulderWidth = min(110, r.width)
        items.append(Item(element: .button(.r), title: "R", shape: .pill,
                          frame: CGRect(x: r.maxX - rShoulderWidth, y: r.minY, width: rShoulderWidth, height: Self.shoulderHeight),
                          hitFrame: CGRect(x: r.maxX - rShoulderWidth, y: r.minY, width: rShoulderWidth, height: Self.shoulderHeight)))

        // Wide clusters stack the small pills in a column on the inner side (toward the screens, like
        // Start/Select on the DS Lite) so the D-pad and diamond can use the full height; narrow clusters
        // put them in a row underneath.
        let pillWidth: CGFloat = 64
        let columnPills = l.width >= pillWidth + Self.spacing + 96 && r.width >= pillWidth + Self.spacing + 96
        func main(_ c: CGRect, innerOnRight: Bool) -> CGRect {
            let top = c.minY + Self.shoulderHeight + Self.spacing
            let bottom = columnPills ? c.maxY : c.maxY - Self.pillHeight - Self.spacing
            let available = columnPills ? c.width - pillWidth - Self.spacing : c.width
            let side = max(0, min(available, bottom - top, 170)) * min(1, max(0.6, scale))
            let x = !columnPills ? c.midX - side / 2
                : innerOnRight ? c.minX + (available - side) / 2 : c.maxX - available + (available - side) / 2
            return CGRect(x: x, y: top + (bottom - top - side) / 2, width: side, height: side)
        }
        // The inner side of each cluster faces the screens: right for the left cluster, left for the right one.
        let (padCluster, faceCluster) = leftHanded ? (r, l) : (l, r)
        let padInnerRight = !leftHanded, faceInnerRight = leftHanded
        let dpad = main(padCluster, innerOnRight: padInnerRight), face = main(faceCluster, innerOnRight: faceInnerRight)
        func hit(_ square: CGRect, in cluster: CGRect, innerOnRight: Bool) -> CGRect {
            // Generous slop, clipped to this control's part of the cluster so neighbours never overlap.
            var band = CGRect(x: cluster.minX, y: cluster.minY + Self.shoulderHeight + 1,
                              width: cluster.width, height: cluster.height - Self.shoulderHeight - 1)
            if columnPills {
                band.size.width -= pillWidth + 1
                if !innerOnRight { band.origin.x += pillWidth + 1 }
            } else {
                band.size.height -= Self.pillHeight + 1
            }
            return square.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop).intersection(band)
        }
        items.append(Item(element: .dpad, title: "", shape: .dpad, frame: dpad, hitFrame: hit(dpad, in: padCluster, innerOnRight: padInnerRight)))
        items.append(Item(element: .face, title: "", shape: .diamond, frame: face, hitFrame: hit(face, in: faceCluster, innerOnRight: faceInnerRight)))

        func pills(_ c: CGRect, _ entries: [(Element, String)], innerOnRight: Bool) {
            for (index, entry) in entries.enumerated() {
                let frame: CGRect
                if columnPills {
                    let x = innerOnRight ? c.maxX - pillWidth : c.minX
                    frame = CGRect(x: x, y: c.maxY - CGFloat(entries.count - index) * (Self.pillHeight + Self.spacing) + Self.spacing,
                                   width: pillWidth, height: Self.pillHeight)
                } else {
                    let count = CGFloat(entries.count)
                    let width = min(pillWidth, (c.width - Self.spacing * (count - 1)) / count)
                    let total = width * count + Self.spacing * (count - 1)
                    frame = CGRect(x: c.midX - total / 2 + CGFloat(index) * (width + Self.spacing),
                                   y: c.maxY - Self.pillHeight, width: width, height: Self.pillHeight)
                }
                items.append(Item(element: entry.0, title: entry.1, shape: .pill, frame: frame, hitFrame: frame))
            }
        }
        pills(padCluster, [(.mic, "Mic"), (.lid, "Lid"), (.pause, "Pause")], innerOnRight: padInnerRight)
        pills(faceCluster, [(.button(.start), "Start"), (.button(.select), "Select")], innerOnRight: faceInnerRight)

        self.items = items
        let d = face.width * 0.36
        faceButtonDiameter = d
        faceCenters = [(.x, CGPoint(x: face.midX, y: face.minY + d / 2)),
                       (.y, CGPoint(x: face.minX + d / 2, y: face.midY)),
                       (.a, CGPoint(x: face.maxX - d / 2, y: face.midY)),
                       (.b, CGPoint(x: face.midX, y: face.maxY - d / 2))]
    }

    public func item(at point: CGPoint) -> Item? { items.first { $0.hitFrame.contains(point) } }

    /// Nearest face button to a touch inside the diamond area, so thumbs can roll between buttons.
    public func faceButton(at point: CGPoint) -> DSButton? {
        guard let area = items.first(where: { $0.element == .face })?.hitFrame, area.contains(point) else { return nil }
        return faceCenters.min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }?.0
    }

    /// Eight-way D-pad: sectors of 45° around the centre, with a small dead zone.
    public static func dpadButtons(at point: CGPoint, in rect: CGRect) -> Set<DSButton> {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        let radius = min(rect.width, rect.height) / 2
        guard radius > 0, hypot(dx, dy) >= radius * 0.18 else { return [] }
        let sector = (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8 // 0 = right, clockwise (y down)
        switch sector {
        case 0: return [.right]
        case 1: return [.right, .down]
        case 2: return [.down]
        case 3: return [.down, .left]
        case 4: return [.left]
        case 5: return [.left, .up]
        case 6: return [.up]
        default: return [.up, .right]
        }
    }
}
