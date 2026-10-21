import SwiftUI
import SceneKit

enum AstraResources {
    static var bundle: Bundle? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let root = Bundle.main.resourceURL else { return nil }
            return Bundle(url: root.appendingPathComponent("Astra_Astra.bundle"))
        }
        return Bundle.module
    }
}

/// 独立球体渲染器。纹理来源和改动声明随资源包交付。
enum Planet: String {
    case earth, moon, mercury, jupiter, sun
    var texture: String { rawValue + (self == .mercury ? ".png" : ".jpg") }
    var period: Double { switch self { case .earth: 90; case .moon: 120; case .mercury: 80; case .jupiter: 100; case .sun: 140 } }
}
struct PlanetView: NSViewRepresentable {
    let planet: Planet
    var animate = true
    var onClick: (() -> Void)? = nil
    var actionLabel: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context: Context) -> PlanetSceneView {
        let view = PlanetSceneView(frame: .zero)
        view.configure(planet)
        view.onClick = onClick; view.actionLabel = actionLabel
        view.isPlaying = animate && !reduceMotion
        return view
    }
    func updateNSView(_ view: PlanetSceneView, context: Context) {
        if view.planet != planet { view.configure(planet) }
        view.onClick = onClick; view.actionLabel = actionLabel
        view.setAccessibilityRole(onClick == nil ? .image : .button)
        if let actionLabel { view.setAccessibilityLabel(actionLabel) }
        view.scene?.isPaused = !animate || reduceMotion
        view.isPlaying = animate && !reduceMotion
    }
    static func dismantleNSView(_ view: PlanetSceneView, coordinator: ()) {
        view.isPlaying = false; view.scene?.isPaused = true
    }
}
final class PlanetSceneView: SCNView {
    var planet: Planet?
    var onClick: (() -> Void)?
    var actionLabel: String?
    private var didDrag = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { guard let onClick else { return false }; onClick(); return true }
    private var globe: SCNNode?
    private var lastPoint: NSPoint?
    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .clear; preferredFramesPerSecond = 30
        antialiasingMode = .multisampling4X; autoenablesDefaultLighting = false
        allowsCameraControl = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ kind: Planet) {
        planet = kind
        let world = SCNScene(); world.background.contents = NSColor.clear
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1.0
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.position = SCNVector3(0, 0, 5); world.rootNode.addChildNode(camera); pointOfView = camera
        let ball = SCNSphere(radius: 1); ball.segmentCount = 128
        let material = SCNMaterial()
        if let url = AstraResources.bundle?.url(forResource: kind.rawValue, withExtension: kind == .mercury ? "png" : "jpg") {
            material.diffuse.contents = NSImage(contentsOf: url)
        }
        material.lightingModel = kind == .sun ? .constant : .lambert
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .clamp
        material.isDoubleSided = false
        ball.firstMaterial = material
        let tilt = SCNNode(); tilt.eulerAngles.z = kind == .earth ? -0.12 : 0.035
        let node = SCNNode(geometry: ball)
        node.eulerAngles.y = kind == .earth ? 0.3 : 0.7
        tilt.addChildNode(node); world.rootNode.addChildNode(tilt)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; ambient.light?.color = NSColor.white
        world.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.intensity = 650; sun.eulerAngles = SCNVector3(-0.35, -0.5, 0)
        world.rootNode.addChildNode(sun)
        node.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: kind.period)), forKey: "自转")
        globe = node; scene = world; isPlaying = true
        setAccessibilityElement(true)
        setAccessibilityLabel([Planet.earth: "地球动画", .moon: "月球动画", .mercury: "水星动画", .jupiter: "木星动画", .sun: "太阳动画"][kind])
    }
    override func mouseDown(with event: NSEvent) { didDrag = false; lastPoint = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        let point = convert(event.locationInWindow, from: nil)
        if let lastPoint {
            globe?.eulerAngles.y += (point.x - lastPoint.x) * 0.012
            globe?.parent?.eulerAngles.x = min(0.7, max(-0.7, (globe?.parent?.eulerAngles.x ?? 0) - (point.y - lastPoint.y) * 0.006))
        }
        lastPoint = point
    }
    override func mouseUp(with event: NSEvent) { lastPoint = nil; if !didDrag { onClick?() } }
}

/// 与参考窗口相同的主视觉锚点：1200×768 下球心 (600,338)，直径244。
struct PlanetHero<Content: View>: View {
    let planet: Planet
    var moon = false
    var satelliteAction: (() -> Void)? = nil
    var earthAction: (() -> Void)? = nil
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false
    var body: some View {
        GeometryReader { proxy in
            let h = proxy.size.height
            ZStack {
                PlanetView(planet: planet).frame(width: 244, height: 244)
                    .position(x: proxy.size.width / 2, y: h * 0.365)
                if moon {
                    PlanetView(planet: .moon, onClick: satelliteAction, actionLabel: "AI 工具清理与维护")
                        .frame(width: 44, height: 44).help("AI 工具清理与维护")
                        .offset(y: floating && !reduceMotion ? -7 : 0)
                        .position(x: proxy.size.width * 0.783, y: h * 0.121)
                        .onAppear { withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) { floating = true } }
                }
                if moon, let satelliteAction {
                    Button(action: satelliteAction) {
                        VStack(spacing: 5) {
                            Text("AI 工具清理与维护").font(.system(size: 12, weight: .medium))
                            Text("点击月球或此处进入 →").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }.padding(10).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .position(x: proxy.size.width * 0.783, y: h * 0.121 + 55)
                }
                if let earthAction {
                    PlanetView(planet: .earth, onClick: earthAction, actionLabel: "返回日常清理")
                        .frame(width: 44, height: 44).help("返回日常清理")
                        .position(x: proxy.size.width * 0.23, y: h * 0.66)
                }
                if let earthAction {
                    Button("点击地球返回日常清理", action: earthAction)
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.white.opacity(0.65))
                        .position(x: proxy.size.width * 0.23, y: h * 0.66 + 36)
                }
                content.position(x: proxy.size.width / 2, y: h * 0.75)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
