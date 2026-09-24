import Foundation

extension CGRect {
    func duoEquals(_ other: CGRect) -> Bool {
        minX == other.minX && minY == other.minY && width == other.width && height == other.height
    }
}

public struct ReservedRegion: Equatable {
    public enum Kind: Equatable { case division, occlusion }
    public let frame: CGRect
    public let kind: Kind
    public init(frame: CGRect, kind: Kind) { self.frame = frame; self.kind = kind }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.frame.duoEquals(rhs.frame)
    }
}

/// All rectangles use the coordinate system of the PlaySession canvas.
public struct DisplayEnvironment: Equatable {
    public let bounds: CGRect
    public let safeBounds: CGRect
    public let reservedRegions: [ReservedRegion]
    public init(bounds: CGRect, safeBounds: CGRect, reservedRegions: [ReservedRegion] = []) {
        self.bounds = bounds
        self.safeBounds = safeBounds
        self.reservedRegions = reservedRegions
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bounds.duoEquals(rhs.bounds) && lhs.safeBounds.duoEquals(rhs.safeBounds)
            && lhs.reservedRegions == rhs.reservedRegions
    }
}

public enum ScreenLayoutPreference: Equatable { case automatic, stacked, sideBySide }
public enum ScreenLayoutMode: Equatable { case stacked, sideBySide, split }

public struct LayoutSolution: Equatable {
    public let upperScreen: CGRect
    public let lowerScreen: CGRect
    public let effectiveMode: ScreenLayoutMode
    public let controlRegions: [CGRect]
    public let isCompact: Bool
    public init(upperScreen: CGRect, lowerScreen: CGRect, effectiveMode: ScreenLayoutMode,
                controlRegions: [CGRect], isCompact: Bool) {
        self.upperScreen = upperScreen
        self.lowerScreen = lowerScreen
        self.effectiveMode = effectiveMode
        self.controlRegions = controlRegions
        self.isCompact = isCompact
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.upperScreen.duoEquals(rhs.upperScreen) && lhs.lowerScreen.duoEquals(rhs.lowerScreen)
            && lhs.effectiveMode == rhs.effectiveMode && lhs.isCompact == rhs.isCompact
            && lhs.controlRegions.count == rhs.controlRegions.count
            && zip(lhs.controlRegions, rhs.controlRegions).allSatisfy { $0.duoEquals($1) }
    }
}

public enum ScreenLayoutSolver {
    private static let aspect: CGFloat = 4.0 / 3.0
    private static let gutter: CGFloat = 8
    /// Keeping a control band outranks larger screens, as long as both screens stay legible;
    /// otherwise controls end up in unusable slivers (seen in Duo portrait and outer display).
    private static func score(minWidth: CGFloat, reservesControls: Bool) -> CGFloat {
        minWidth + (reservesControls && minWidth >= 170 ? 10_000 : 0)
    }

    public static func solve(environment: DisplayEnvironment,
                             preference: ScreenLayoutPreference = .automatic,
                             swapScreens: Bool = false) -> LayoutSolution {
        let safe = environment.safeBounds.standardized.intersection(environment.bounds.standardized)
        guard safe.width > 0, safe.height > 0 else {
            return LayoutSolution(upperScreen: CGRect(x: 0, y: 0, width: 0, height: 0),
                                  lowerScreen: CGRect(x: 0, y: 0, width: 0, height: 0),
                                  effectiveMode: .stacked, controlRegions: [], isCompact: true)
        }
        let barriers = environment.reservedRegions.map { $0.frame.standardized.intersection(safe) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
        let free = maximalFreeRects(in: safe, avoiding: barriers)
        // A small gap is kept for controls whenever usable height permits it.
        let controlHeight: CGFloat = safe.height >= 500 ? 96 : (safe.height >= 320 ? 56 : 0)
        var candidates: [Candidate] = []
        for cell in free {
            for mode in [ScreenLayoutMode.stacked, .sideBySide] {
                if preference == .stacked && mode != .stacked { continue }
                if preference == .sideBySide && mode != .sideBySide { continue }
                if let candidate = fitPair(in: cell, mode: mode, controlHeight: controlHeight) {
                    candidates.append(candidate)
                }
                // Compact fallback keeps both screens visible when a control reserve is impossible.
                if let candidate = fitPair(in: cell, mode: mode, controlHeight: 0) {
                    candidates.append(candidate)
                }
            }
        }
        // A division or occlusion may split the usable display into two separate cells.
        if preference == .automatic {
            for i in free.indices {
                for j in free.indices where j > i {
                    if let candidate = fitSplit(free[i], free[j], safe: safe, controlHeight: controlHeight) {
                        candidates.append(candidate)
                    }
                }
            }
        }
        let selected = candidates.max { $0.score < $1.score }
            ?? Candidate(first: CGRect(x: 0, y: 0, width: 0, height: 0),
                         second: CGRect(x: 0, y: 0, width: 0, height: 0), mode: .stacked, score: 0)
        let top = swapScreens ? selected.second : selected.first
        let bottom = swapScreens ? selected.first : selected.second
        var controls: [CGRect] = []
        for rect in free {
            controls.append(contentsOf: subtract(rect, excluding: [selected.first, selected.second]))
        }
        controls = controls.filter { $0.width >= 40 && $0.height >= 36 }
        controls.sort { lhs, rhs in (lhs.width * lhs.height) > (rhs.width * rhs.height) }
        return LayoutSolution(upperScreen: top, lowerScreen: bottom,
                              effectiveMode: selected.mode, controlRegions: controls,
                              isCompact: min(top.width, bottom.width) < 170)
    }

    private struct Candidate {
        let first: CGRect
        let second: CGRect
        let mode: ScreenLayoutMode
        let score: CGFloat
    }

    private static func fit(_ area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return CGRect(x: 0, y: 0, width: 0, height: 0) }
        let width = min(area.width, area.height * aspect)
        let height = width / aspect
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2,
                      width: width, height: height)
    }

    private static func fitPair(in cell: CGRect, mode: ScreenLayoutMode, controlHeight: CGFloat) -> Candidate? {
        guard cell.height > controlHeight else { return nil }
        let usable = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.height - controlHeight)
        let slots: (CGRect, CGRect)
        switch mode {
        case .stacked:
            guard usable.height > gutter else { return nil }
            let height = (usable.height - gutter) / 2
            slots = (CGRect(x: usable.minX, y: usable.minY, width: usable.width, height: height),
                     CGRect(x: usable.minX, y: usable.minY + height + gutter, width: usable.width, height: height))
        case .sideBySide:
            guard usable.width > gutter else { return nil }
            let width = (usable.width - gutter) / 2
            slots = (CGRect(x: usable.minX, y: usable.minY, width: width, height: usable.height),
                     CGRect(x: usable.minX + width + gutter, y: usable.minY, width: width, height: usable.height))
        case .split: return nil
        }
        let first = fit(slots.0), second = fit(slots.1)
        guard first.width > 0, second.width > 0 else { return nil }
        return Candidate(first: first, second: second, mode: mode,
                         score: score(minWidth: min(first.width, second.width), reservesControls: controlHeight > 0))
    }

    private static func fitSplit(_ a: CGRect, _ b: CGRect, safe: CGRect, controlHeight: CGFloat) -> Candidate? {
        let horizontal = abs(a.midX - b.midX) > abs(a.midY - b.midY)
        let (firstCell, secondCell) = horizontal
            ? (a.midX < b.midX ? a : b, a.midX < b.midX ? b : a)
            : (a.midY < b.midY ? a : b, a.midY < b.midY ? b : a)
        // The lower or trailing pane hosts controls where possible.
        let secondUsable = CGRect(x: secondCell.minX, y: secondCell.minY,
                                  width: secondCell.width, height: max(0, secondCell.height - controlHeight))
        let first = fit(firstCell), second = fit(secondUsable)
        guard first.width > 0, second.width > 0, !first.intersects(second) else { return nil }
        let separated = horizontal ? first.maxX <= second.minX : first.maxY <= second.minY
        guard separated else { return nil }
        let minWidth = min(first.width, second.width)
        // A split should win automatically only if each screen remains legible.
        guard minWidth >= min(170, safe.width * 0.38) else { return nil }
        return Candidate(first: first, second: second, mode: .split,
                         score: score(minWidth: minWidth, reservesControls: controlHeight > 0) + 1) // split wins ties
    }

    private static func maximalFreeRects(in safe: CGRect, avoiding barriers: [CGRect]) -> [CGRect] {
        let xs = Array(Set(([safe.minX, safe.maxX] + barriers.flatMap { [$0.minX, $0.maxX] }))).sorted()
        let ys = Array(Set(([safe.minY, safe.maxY] + barriers.flatMap { [$0.minY, $0.maxY] }))).sorted()
        var result: [CGRect] = []
        for left in 0..<(xs.count - 1) {
            for right in (left + 1)..<xs.count {
                for top in 0..<(ys.count - 1) {
                    for bottom in (top + 1)..<ys.count {
                        let rect = CGRect(x: xs[left], y: ys[top], width: xs[right] - xs[left], height: ys[bottom] - ys[top])
                        guard rect.width > 0, rect.height > 0,
                              !barriers.contains(where: { $0.intersects(rect) }) else { continue }
                        result.append(rect)
                    }
                }
            }
        }
        return result.filter { rect in
            !result.contains { other in !other.duoEquals(rect) && other.contains(rect) }
        }
    }

    private static func subtract(_ rect: CGRect, excluding exclusions: [CGRect]) -> [CGRect] {
        exclusions.reduce([rect]) { pieces, exclusion in
            pieces.flatMap { piece -> [CGRect] in
                let intersection = piece.intersection(exclusion)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return [piece] }
                return [CGRect(x: piece.minX, y: piece.minY, width: piece.width, height: intersection.minY - piece.minY),
                        CGRect(x: piece.minX, y: intersection.maxY, width: piece.width, height: piece.maxY - intersection.maxY),
                        CGRect(x: piece.minX, y: intersection.minY, width: intersection.minX - piece.minX, height: intersection.height),
                        CGRect(x: intersection.maxX, y: intersection.minY, width: piece.maxX - intersection.maxX, height: intersection.height)]
                    .filter { $0.width > 0 && $0.height > 0 }
            }
        }
    }
}
