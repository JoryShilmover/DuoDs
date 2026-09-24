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

@MainActor
private final class TouchSurface: UIView {
    var router: InputRouter?
    var onChange: (() -> Void)?
    var onPause: (() -> Void)?
    var onLid: (() -> Void)?
    private enum Contact { case stylus(UInt64), button(DSButton), pause, lid }
    private var contacts: [ObjectIdentifier: Contact] = [:]
    private var nextID: UInt64 = 1
    private var lowerScreen = CGRect(x: 0, y: 0, width: 0, height: 0)
    private var targets: [(CGRect, Contact)] = []
    private var labels: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func configure(solution: LayoutSolution) {
        lowerScreen = solution.lowerScreen
        labels.forEach { $0.removeFromSuperview() }
        labels.removeAll()
        targets.removeAll()
        let names: [(String, Contact)] = [
            ("↑", .button(.up)), ("←", .button(.left)), ("↓", .button(.down)), ("→", .button(.right)),
            ("X", .button(.x)), ("Y", .button(.y)), ("A", .button(.a)), ("B", .button(.b)),
            ("L", .button(.l)), ("R", .button(.r)), ("Sel", .button(.select)), ("Start", .button(.start)),
            ("Ⅱ", .pause), ("Lid", .lid)
        ]
        // Prefer the lowest usable band (thumb reach); e.g. outer landscape has equal bands above and below.
        guard let area = solution.controlRegions.filter({ $0.width >= 150 && $0.height >= 48 }).max(by: { $0.maxY < $1.maxY })
            ?? solution.controlRegions.first else { return }
        let columns = 7, rows = 2
        let width = min(area.width / CGFloat(columns), 52)
        let height = min(area.height / CGFloat(rows), 48)
        let x0 = area.midX - width * CGFloat(columns) / 2
        let y0 = area.midY - height * CGFloat(rows) / 2
        for (index, pair) in names.enumerated() {
            let rect = CGRect(x: x0 + CGFloat(index % columns) * width,
                              y: y0 + CGFloat(index / columns) * height,
                              width: width - 2, height: height - 2)
            guard rect.width > 0, rect.height > 0 else { continue }
            targets.append((rect, pair.1))
            let label = UILabel(frame: rect)
            label.text = pair.0
            label.textAlignment = .center
            label.textColor = .white
            label.font = .boldSystemFont(ofSize: min(14, rect.height * 0.4))
            label.backgroundColor = UIColor.darkGray.withAlphaComponent(0.9)
            label.layer.cornerRadius = min(12, rect.height / 2)
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            addSubview(label)
            labels.append(label)
        }
    }

    func cancelContacts() {
        for (id, contact) in contacts {
            switch contact {
            case .stylus(let stylus): router?.endStylus(id: stylus)
            case .button(let button): router?.release(button, source: "touch.\(id)")
            case .pause, .lid: break
            }
        }
        contacts.removeAll()
        onChange?()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let point = touch.location(in: self)
            if let target = targets.first(where: { $0.0.contains(point) })?.1 {
                contacts[key] = target
                if case .button(let button) = target { router?.press(button, source: "touch.\(key)") }
            } else if router?.beginStylus(id: nextID, at: point, lowerScreen: lowerScreen) == true {
                contacts[key] = .stylus(nextID)
                nextID &+= 1
            }
        }
        onChange?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if case .stylus(let id) = contacts[ObjectIdentifier(touch)] {
                router?.moveStylus(id: id, to: touch.location(in: self))
            }
        }
        onChange?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches, cancelled: true) }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let contact = contacts.removeValue(forKey: key) else { continue }
            switch contact {
            case .stylus(let id): router?.endStylus(id: id)
            case .button(let button): router?.release(button, source: "touch.\(key)")
            case .pause: if !cancelled { onPause?() }
            case .lid: if !cancelled { onLid?() }
            }
        }
        onChange?()
    }
}
#endif
