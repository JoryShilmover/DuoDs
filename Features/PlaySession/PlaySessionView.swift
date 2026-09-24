#if canImport(UIKit)
import UIKit
import SwiftUI
import MetalKit
import CoreImage

/// Presentation-only view. Its owner supplies copied frames and forwards input snapshots to the runtime.
@MainActor
public final class PlaySessionCanvas: UIView {
    public var onInput: ((DSInput) -> Void)?
    public var onPause: (() -> Void)?
    public var onLidToggle: (() -> Void)?
    /// Diagnostics only: reports each new geometry solution (e.g. fold/unfold, resize).
    public var onGeometry: ((DisplayEnvironment, LayoutSolution) -> Void)?
    public var inputEpoch = 0 { didSet { if inputEpoch != oldValue { cancelInput() } } }
    public var layoutPreference: ScreenLayoutPreference = .automatic { didSet { lastEnvironment = nil; refreshGeometry() } }
    public var swapScreens = false { didSet { lastEnvironment = nil; refreshGeometry() } }

    private let router = InputRouter()
    private let topView = DSScreenView(screenIndex: 0)
    private let bottomView = DSScreenView(screenIndex: 1)
    private let inputSurface = TouchSurface()
    private var hingeInteraction: UIInteraction?
    private var controllerAdapter: ControllerInputAdapter?
    private var lastEnvironment: DisplayEnvironment?
    private var lastSolution: LayoutSolution?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        addSubview(topView)
        addSubview(bottomView)
        addSubview(inputSurface)
        inputSurface.onChange = { [weak self] in self?.onInput?(self?.router.snapshot ?? DSInput()) }
        inputSurface.router = router
        inputSurface.onPause = { [weak self] in self?.onPause?() }
        inputSurface.onLid = { [weak self] in self?.onLidToggle?() }
        hingeInteraction = DisplayEnvironmentAdapter.observeHinge(on: self) { [weak self] in
            self?.refreshGeometry()
        }
        controllerAdapter = ControllerInputAdapter(onButtons: { [weak self] buttons, source in
            self?.setControllerButtons(buttons, source: source)
        }, onDisconnect: { [weak self] source in
            self?.disconnectController(source: source)
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        refreshGeometry()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        refreshGeometry()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshGeometry()
    }

    public func update(frame: DSFrame?) {
        topView.update(frame: frame)
        bottomView.update(frame: frame)
    }

    public func setControllerButtons(_ buttons: Set<DSButton>, source: String) {
        router.setButtons(buttons, source: "controller.\(source)")
        onInput?(router.snapshot)
    }

    public func disconnectController(source: String) {
        router.disconnect(source: "controller.\(source)")
        onInput?(router.snapshot)
    }

    public func cancelInput() {
        inputSurface.cancelContacts()
        router.cancelTransientInputs()
        onInput?(router.snapshot)
    }

    private func refreshGeometry() {
        let environment = DisplayEnvironmentAdapter.capture(in: self)
        guard environment != lastEnvironment || lastSolution == nil else { return }
        let solution = ScreenLayoutSolver.solve(environment: environment,
                                                preference: layoutPreference,
                                                swapScreens: swapScreens)
        if lastSolution.map({ !solution.lowerScreen.duoEquals($0.lowerScreen) || !solution.upperScreen.duoEquals($0.upperScreen) }) ?? true {
            inputSurface.cancelContacts()
            router.setLowerScreen(solution.lowerScreen)
            onInput?(router.snapshot)
        }
        topView.frame = solution.upperScreen
        bottomView.frame = solution.lowerScreen
        inputSurface.frame = bounds
        inputSurface.configure(solution: solution)
        let changed = solution != lastSolution
        lastEnvironment = environment
        lastSolution = solution
        if changed { onGeometry?(environment, solution) }
    }
}

public struct PlaySessionView: UIViewRepresentable {
    public var frame: DSFrame?
    public var preference: ScreenLayoutPreference
    public var swapScreens: Bool
    public var onInput: (DSInput) -> Void
    public var onPause: () -> Void
    public var onLidToggle: () -> Void
    public var onGeometry: (DisplayEnvironment, LayoutSolution) -> Void
    /// Changes when the owner releases all input (pause, interruption); held touches/buttons are cancelled.
    public var inputEpoch: Int

    public init(frame: DSFrame?, preference: ScreenLayoutPreference = .automatic,
                swapScreens: Bool = false, onInput: @escaping (DSInput) -> Void,
                onPause: @escaping () -> Void = {}, onLidToggle: @escaping () -> Void = {},
                onGeometry: @escaping (DisplayEnvironment, LayoutSolution) -> Void = { _, _ in },
                inputEpoch: Int = 0) {
        self.frame = frame
        self.preference = preference
        self.swapScreens = swapScreens
        self.onInput = onInput
        self.onPause = onPause
        self.onLidToggle = onLidToggle
        self.onGeometry = onGeometry
        self.inputEpoch = inputEpoch
    }

    public func makeUIView(context: Context) -> PlaySessionCanvas { PlaySessionCanvas(frame: .zero) }

    public func updateUIView(_ view: PlaySessionCanvas, context: Context) {
        view.onInput = onInput
        view.onPause = onPause
        view.onLidToggle = onLidToggle
        view.onGeometry = onGeometry
        view.inputEpoch = inputEpoch
        view.layoutPreference = preference
        view.swapScreens = swapScreens
        view.update(frame: frame)
    }
}

@MainActor
private final class DSScreenView: MTKView, MTKViewDelegate {
    private let screenIndex: Int
    private var image: CIImage?
    private var ciContext: CIContext?

    init(screenIndex: Int) {
        self.screenIndex = screenIndex
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isOpaque = true
        backgroundColor = .black
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self
        if let device { ciContext = CIContext(mtlDevice: device) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func update(frame: DSFrame?) {
        guard let frame, frame.pixels.count == 256 * 384 * 4,
              let provider = CGDataProvider(data: frame.pixels as CFData),
              let full = CGImage(width: 256, height: 384, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                    .union(.byteOrder32Little), provider: provider,
                                 decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let cropped = full.cropping(to: CGRect(x: 0, y: screenIndex * 192, width: 256, height: 192)) else {
            image = nil
            setNeedsDisplay()
            return
        }
        image = CIImage(cgImage: cropped)
        setNeedsDisplay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { setNeedsDisplay() }

    func draw(in view: MTKView) {
        guard let image, let drawable = currentDrawable, let queue = device?.makeCommandQueue(),
              let buffer = queue.makeCommandBuffer(), let ciContext else { return }
        let scale = CGAffineTransform(scaleX: drawableSize.width / 256, y: drawableSize.height / 192)
        let output = image.transformed(by: scale)
        ciContext.render(output, to: drawable.texture, commandBuffer: buffer,
                         bounds: CGRect(origin: .zero, size: drawableSize),
                         colorSpace: CGColorSpaceCreateDeviceRGB())
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Draws the DS Lite–style controls and routes touches: controls first, then stylus on the lower screen.
@MainActor
private final class TouchSurface: UIView {
    var router: InputRouter?
    var onChange: (() -> Void)?
    var onPause: (() -> Void)?
    var onLid: (() -> Void)?
    private enum Contact { case stylus(UInt64), dpad(Set<DSButton>), face(DSButton?), button(DSButton), pause, lid }
    private var contacts: [ObjectIdentifier: Contact] = [:]
    private var nextID: UInt64 = 1
    private var lowerScreen = CGRect(x: 0, y: 0, width: 0, height: 0)
    private var layout: ControlLayout?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func configure(solution: LayoutSolution) {
        lowerScreen = solution.lowerScreen
        layout = solution.controlRegions.count == 2
            ? ControlLayout(left: solution.controlRegions[0], right: solution.controlRegions[1]) : nil
        setNeedsDisplay()
    }

    func cancelContacts() {
        for (key, contact) in contacts { release(contact, key: key) }
        contacts.removeAll()
        setNeedsDisplay()
        onChange?()
    }

    private func source(_ key: ObjectIdentifier) -> String { "touch.\(key.hashValue)" }

    private func release(_ contact: Contact, key: ObjectIdentifier) {
        switch contact {
        case .stylus(let id): router?.endStylus(id: id)
        case .dpad, .face, .button: router?.setButtons([], source: source(key))
        case .pause, .lid: break
        }
    }

    private func buttons(of contact: Contact) -> Set<DSButton> {
        switch contact {
        case .dpad(let set): return set
        case .face(let button): return button.map { [$0] } ?? []
        case .button(let button): return [button]
        default: return []
        }
    }

    /// Applies a contact's new state, with a haptic tick when it presses something new.
    private func apply(_ contact: Contact, key: ObjectIdentifier) {
        let before = contacts[key].map(buttons(of:)) ?? []
        contacts[key] = contact
        let now = buttons(of: contact)
        if case .stylus = contact {} else if case .pause = contact {} else if case .lid = contact {} else {
            router?.setButtons(now, source: source(key))
        }
        if !now.subtracting(before).isEmpty { haptics.impactOccurred() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            if let layout, let item = layout.item(at: point) {
                switch item.element {
                case .dpad: apply(.dpad(ControlLayout.dpadButtons(at: point, in: item.frame)), key: key)
                case .face: apply(.face(layout.faceButton(at: point)), key: key)
                case .button(let button): apply(.button(button), key: key)
                case .pause: contacts[key] = .pause; haptics.impactOccurred()
                case .lid: contacts[key] = .lid; haptics.impactOccurred()
                }
            } else if router?.beginStylus(id: nextID, at: point, lowerScreen: lowerScreen) == true {
                contacts[key] = .stylus(nextID)
                nextID &+= 1
            }
        }
        setNeedsDisplay()
        onChange?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            switch contacts[key] {
            case .stylus(let id): router?.moveStylus(id: id, to: point)
            case .dpad:
                // Keep tracking outside the pad so a sliding thumb never drops the direction.
                if let frame = layout?.items.first(where: { $0.element == .dpad })?.frame {
                    apply(.dpad(ControlLayout.dpadButtons(at: point, in: frame)), key: key)
                }
            case .face: apply(.face(layout?.faceButton(at: point)), key: key)
            default: break
            }
        }
        setNeedsDisplay()
        onChange?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let contact = contacts.removeValue(forKey: key) else { continue }
            release(contact, key: key)
            if case .pause = contact, !cancelled { onPause?() }
            if case .lid = contact, !cancelled { onLid?() }
        }
        setNeedsDisplay()
        onChange?()
    }

    // MARK: Drawing

    private static let fill = UIColor(white: 1, alpha: 0.14)
    private static let pressedFill = UIColor(white: 1, alpha: 0.45)
    private static let stroke = UIColor(white: 1, alpha: 0.35)
    private static let text = UIColor(white: 1, alpha: 0.85)

    override func draw(_ rect: CGRect) {
        guard let layout else { return }
        let held = contacts.values.reduce(into: Set<DSButton>()) { $0.formUnion(buttons(of: $1)) }
        let heldPause = contacts.values.contains { if case .pause = $0 { return true }; return false }
        let heldLid = contacts.values.contains { if case .lid = $0 { return true }; return false }
        for item in layout.items {
            switch item.element {
            case .dpad: drawDPad(item.frame, held: held)
            case .face: drawFace(layout, held: held)
            case .button(let button): drawPill(item.frame, title: item.title, pressed: held.contains(button))
            case .pause: drawPill(item.frame, title: item.title, pressed: heldPause)
            case .lid: drawPill(item.frame, title: item.title, pressed: heldLid)
            }
        }
    }

    private func paint(_ path: UIBezierPath, pressed: Bool) {
        (pressed ? Self.pressedFill : Self.fill).setFill()
        path.fill()
        Self.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func label(_ title: String, in frame: CGRect, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: .semibold),
                                                         .foregroundColor: Self.text]
        let text = title as NSString
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: frame.midX - bounds.width / 2, y: frame.midY - bounds.height / 2), withAttributes: attributes)
    }

    private func drawPill(_ frame: CGRect, title: String, pressed: Bool) {
        paint(UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2), pressed: pressed)
        label(title, in: frame, size: min(14, frame.height * 0.45))
    }

    private func drawDPad(_ frame: CGRect, held: Set<DSButton>) {
        let arm = frame.width * 0.34
        let horizontal = CGRect(x: frame.minX, y: frame.midY - arm / 2, width: frame.width, height: arm)
        let vertical = CGRect(x: frame.midX - arm / 2, y: frame.minY, width: arm, height: frame.height)
        // One plus-shaped outline so the arms don't show overlapping edges in the middle.
        let cross = UIBezierPath()
        for point in [CGPoint(x: vertical.minX, y: frame.minY), CGPoint(x: vertical.maxX, y: frame.minY),
                      CGPoint(x: vertical.maxX, y: horizontal.minY), CGPoint(x: frame.maxX, y: horizontal.minY),
                      CGPoint(x: frame.maxX, y: horizontal.maxY), CGPoint(x: vertical.maxX, y: horizontal.maxY),
                      CGPoint(x: vertical.maxX, y: frame.maxY), CGPoint(x: vertical.minX, y: frame.maxY),
                      CGPoint(x: vertical.minX, y: horizontal.maxY), CGPoint(x: frame.minX, y: horizontal.maxY),
                      CGPoint(x: frame.minX, y: horizontal.minY), CGPoint(x: vertical.minX, y: horizontal.minY)] {
            if cross.isEmpty { cross.move(to: point) } else { cross.addLine(to: point) }
        }
        cross.close()
        cross.lineJoinStyle = .round
        paint(cross, pressed: false)
        let half = (frame.width - arm) / 2
        let arms: [(DSButton, CGRect)] = [
            (.up, CGRect(x: vertical.minX, y: frame.minY, width: arm, height: half)),
            (.down, CGRect(x: vertical.minX, y: frame.maxY - half, width: arm, height: half)),
            (.left, CGRect(x: frame.minX, y: horizontal.minY, width: half, height: arm)),
            (.right, CGRect(x: frame.maxX - half, y: horizontal.minY, width: half, height: arm))]
        for (button, rect) in arms {
            if held.contains(button) {
                Self.pressedFill.setFill()
                UIBezierPath(rect: rect).fill()
            }
            // Small direction marks, like the lines on the DS Lite's pad.
            let mark = UIBezierPath()
            let c = CGPoint(x: rect.midX, y: rect.midY), m = arm * 0.16
            switch button {
            case .up: mark.move(to: CGPoint(x: c.x, y: c.y - m)); mark.addLine(to: CGPoint(x: c.x, y: c.y + m))
            case .down: mark.move(to: CGPoint(x: c.x, y: c.y - m)); mark.addLine(to: CGPoint(x: c.x, y: c.y + m))
            default: mark.move(to: CGPoint(x: c.x - m, y: c.y)); mark.addLine(to: CGPoint(x: c.x + m, y: c.y))
            }
            Self.text.setStroke()
            mark.lineWidth = 2
            mark.lineCapStyle = .round
            mark.stroke()
        }
    }

    private func drawFace(_ layout: ControlLayout, held: Set<DSButton>) {
        let d = layout.faceButtonDiameter
        for (button, center) in layout.faceCenters {
            let frame = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            paint(UIBezierPath(ovalIn: frame), pressed: held.contains(button))
            let title: String
            switch button { case .a: title = "A"; case .b: title = "B"; case .x: title = "X"; default: title = "Y" }
            label(title, in: frame, size: d * 0.4)
        }
    }
}
#endif
