import SceneKit
import UIKit

final class Game: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camNode = SCNNode()
    let player = SCNNode()
    let model = SCNNode()
    var armL = SCNNode(), armR = SCNNode(), legL = SCNNode(), legR = SCNNode()
    var coins: [SCNNode] = []
    @Published var score = 0
    @Published var total = 0
    @Published var won = false
    var move = CGVector.zero
    var wantJump = false
    var yaw: Float = 0, pitch: Float = 0.4
    var phase: Float = 0, face: Float = 0, last: TimeInterval = 0
    let start = SCNVector3(0, 1.2, 0)
    let haptic = UIImpactFeedbackGenerator(style: .light)

    override init() { super.init(); build() }

    // MARK: - Мир
    func build() {
        let sky = UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)
        scene.physicsWorld.gravity = SCNVector3(0, -20, 0)
        scene.background.contents = sky
        scene.fogColor = sky; scene.fogStartDistance = 40; scene.fogEndDistance = 110

        let sun = SCNNode(); sun.light = SCNLight()
        sun.light!.type = .directional; sun.light!.intensity = 1100
        sun.light!.castsShadow = true; sun.light!.shadowMode = .deferred
        sun.light!.shadowColor = UIColor(white: 0, alpha: 0.45); sun.light!.shadowSampleCount = 8
        sun.eulerAngles = SCNVector3(-1.0, 0.6, 0)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 450
        scene.rootNode.addChildNode(sun); scene.rootNode.addChildNode(amb)

        let ground = SCNBox(width: 120, height: 1, length: 120, chamferRadius: 0)
        let gm = SCNMaterial(); gm.diffuse.contents = checker()
        gm.diffuse.wrapS = .repeat; gm.diffuse.wrapT = .repeat
        gm.diffuse.contentsTransform = SCNMatrix4MakeScale(30, 30, 1); gm.diffuse.mipFilter = .linear
        ground.materials = [gm]
        _ = solid(ground, SCNVector3(0, -0.5, 0))

        // Спиральная лестница из платформ + монеты на каждой
        for i in 0..<9 {
            let h = 0.6 * Float(i + 1), a = Float(i) * 0.75
            let box = SCNBox(width: 4, height: CGFloat(h), length: 4, chamferRadius: 0.1)
            box.firstMaterial?.diffuse.contents = UIColor(hue: CGFloat(i) / 9, saturation: 0.55, brightness: 0.95, alpha: 1)
            _ = solid(box, SCNVector3(cos(a) * 9, h / 2, sin(a) * 9))
            addCoin(SCNVector3(cos(a) * 9, h + 1.0, sin(a) * 9))
        }
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi
            addCoin(SCNVector3(cos(a) * 5, 1.0, sin(a) * 5))
        }
        total = coins.count

        buildCharacter()
        player.position = start
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: SCNCapsule(capRadius: 0.35, height: 1.9), options: nil))
        body.mass = 1; body.friction = 0; body.restitution = 0
        body.angularVelocityFactor = SCNVector3Zero; body.allowsResting = false
        body.categoryBitMask = 4; body.collisionBitMask = 1
        player.physicsBody = body
        model.position.y = -0.95
        player.addChildNode(model)
        scene.rootNode.addChildNode(player)

        camNode.camera = SCNCamera(); camNode.camera?.fieldOfView = 65; camNode.camera?.zFar = 300
        camNode.position = SCNVector3(0, 5, 7)
        scene.rootNode.addChildNode(camNode)
    }

    func solid(_ g: SCNGeometry, _ p: SCNVector3) -> SCNNode {
        let n = SCNNode(geometry: g); n.position = p
        n.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        n.physicsBody?.categoryBitMask = 1
        scene.rootNode.addChildNode(n); return n
    }

    func addCoin(_ p: SCNVector3) {
        let cyl = SCNCylinder(radius: 0.35, height: 0.08)
        let m = SCNMaterial(); m.diffuse.contents = UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)
        m.lightingModel = .physicallyBased; m.metalness.contents = 0.9; m.roughness.contents = 0.3
        m.emission.contents = UIColor(red: 0.4, green: 0.25, blue: 0, alpha: 1)
        cyl.materials = [m]
        let disc = SCNNode(geometry: cyl); disc.eulerAngles.x = .pi / 2
        let coin = SCNNode(); coin.position = p; coin.addChildNode(disc)
        coin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 2)))
        scene.rootNode.addChildNode(coin); coins.append(coin)
    }

    func checker() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { c in
            UIColor(red: 0.55, green: 0.80, blue: 0.50, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor(red: 0.47, green: 0.72, blue: 0.43, alpha: 1).setFill()
            c.fill(CGRect(x: 0, y: 0, width: 32, height: 32)); c.fill(CGRect(x: 32, y: 32, width: 32, height: 32))
        }
    }

    // MARK: - Персонаж
    func buildCharacter() {
        // Если положить figure.usdz в Sources/ — используется она
        if let url = Bundle.main.url(forResource: "figure", withExtension: "usdz"),
           let s = try? SCNScene(url: url, options: nil) {
            let n = s.rootNode.clone()
            let (mn, mx) = n.boundingBox
            let k = 1.9 / max(mx.y - mn.y, 0.001)
            n.scale = SCNVector3(k, k, k); n.position = SCNVector3(0, -k * mn.y, 0)
            model.addChildNode(n); return
        }
        func mat(_ c: UIColor) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = c; m.lightingModel = .physicallyBased
            m.roughness.contents = 0.45; m.metalness.contents = 0.15; return m
        }
        func part(_ g: SCNGeometry, _ c: UIColor, _ p: SCNVector3, in parent: SCNNode) {
            g.materials = [mat(c)]
            let n = SCNNode(geometry: g); n.position = p; parent.addChildNode(n)
        }
        let orange = UIColor(red: 1, green: 0.5, blue: 0.15, alpha: 1)
        let light = UIColor(white: 0.92, alpha: 1), dark = UIColor(white: 0.1, alpha: 1)
        part(SCNBox(width: 0.6, height: 0.7, length: 0.35, chamferRadius: 0.12), orange, SCNVector3(0, 1.05, 0), in: model)
        part(SCNSphere(radius: 0.3), light, SCNVector3(0, 1.65, 0), in: model)
        part(SCNSphere(radius: 0.065), dark, SCNVector3(-0.12, 1.68, -0.26), in: model)
        part(SCNSphere(radius: 0.065), dark, SCNVector3(0.12, 1.68, -0.26), in: model)
        part(SCNCylinder(radius: 0.02, height: 0.25), dark, SCNVector3(0, 2.05, 0), in: model)
        part(SCNSphere(radius: 0.06), UIColor.red, SCNVector3(0, 2.2, 0), in: model)
        for (node, x, y, color) in [(armL, Float(-0.42), Float(1.3), light), (armR, 0.42, 1.3, light),
                                    (legL, -0.17, 0.7, dark), (legR, 0.17, 0.7, dark)] {
            node.position = SCNVector3(x, y, 0); model.addChildNode(node)
            part(SCNCapsule(capRadius: 0.12, height: 0.7), color, SCNVector3(0, -0.3, 0), in: node)
        }
    }

    // MARK: - Управление
    func look(dx: CGFloat, dy: CGFloat) {
        yaw -= Float(dx) * 0.008
        pitch = min(1.2, max(0.05, pitch + Float(dy) * 0.006))
    }

    func reset() {
        for c in coins where c.parent == nil { scene.rootNode.addChildNode(c) }
        score = 0; won = false; respawn()
    }

    func respawn() {
        player.physicsBody?.velocity = SCNVector3Zero
        player.position = start; player.physicsBody?.resetTransform()
    }

    // MARK: - Игровой цикл
    func renderer(_ r: SCNSceneRenderer, updateAtTime t: TimeInterval) {
        let dt = Float(min(t - last, 0.05)); last = t
        guard let body = player.physicsBody else { return }
        let p = player.presentation.position

        let hits = scene.physicsWorld.rayTestWithSegment(from: p, to: SCNVector3(p.x, p.y - 1.1, p.z),
                                                         options: [.collisionBitMask: 1])
        let ground = !hits.isEmpty

        let mx = Float(move.dx), mz = Float(move.dy)
        let mag = min(1, hypot(mx, mz))
        var dx = cos(yaw) * mx + sin(yaw) * mz
        var dz = -sin(yaw) * mx + cos(yaw) * mz
        let len = hypot(dx, dz)
        if len > 0.001 { dx /= len; dz /= len }
        let speed = 7 * mag
        var vy = body.velocity.y
        if wantJump && ground { vy = 9; haptic.impactOccurred() }
        wantJump = false
        body.velocity = SCNVector3(dx * speed, vy, dz * speed)

        if mag > 0.1 {
            var d = atan2(dx, dz) + .pi - face
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            face += d * min(1, dt * 12)
            model.eulerAngles.y = face
        }

        phase += dt * (6 + speed * 1.2)
        if ground {
            let s = sin(phase) * 0.9 * mag
            legL.eulerAngles.x = s; legR.eulerAngles.x = -s
            armL.eulerAngles.x = -s; armR.eulerAngles.x = s
            model.position.y = -0.95 + abs(sin(phase)) * 0.06 * mag
        } else {
            armL.eulerAngles.x = -2.6; armR.eulerAngles.x = -2.6
            legL.eulerAngles.x = 0.5; legR.eulerAngles.x = -0.3
        }

        for c in coins where c.parent != nil {
            let q = c.position
            if hypot(hypot(q.x - p.x, q.y - p.y), q.z - p.z) < 1.1 {
                c.removeFromParentNode()
                DispatchQueue.main.async {
                    self.score += 1; self.haptic.impactOccurred()
                    if self.score >= self.total { self.won = true }
                }
            }
        }

        if p.y < -15 { respawn() }

        let focus = SCNVector3(p.x, p.y + 0.8, p.z), dist: Float = 7
        let want = SCNVector3(focus.x + sin(yaw) * cos(pitch) * dist,
                              max(focus.y + sin(pitch) * dist, 0.6),
                              focus.z + cos(yaw) * cos(pitch) * dist)
        let c = camNode.position, k = min(1, dt * 10)
        camNode.position = SCNVector3(c.x + (want.x - c.x) * k, c.y + (want.y - c.y) * k, c.z + (want.z - c.z) * k)
        camNode.look(at: focus)
    }
}
