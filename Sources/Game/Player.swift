import SceneKit
import simd

/// First-person body: no hands, just a camera with the tool floating in view.
final class Player {
    let node = SCNNode()
    let cameraNode = SCNNode()
    let lampNode = SCNNode()
    private let toolHolder = SCNNode()
    private let capsuleNode = SCNNode()
    private var toolIndex = -1

    var position = SIMD3<Float>(0, 0, 2)
    var velocity = SIMD3<Float>(0, 0, 0)
    var yaw: Float = 0
    var pitch: Float = -0.2
    var onGround = true
    var fuel: Float = 0
    var maxFuel: Float = 0
    var moveSpeed: Float = 3.4
    var jetThrusting = false
    var stepEvent = false
    private var bobPhase: Float = 0
    private var scrubPhase: Float = 0
    private var scrubAmount: Float = 0

    let gravity: Float = 1.62
    let eyeHeight: Float = 1.68
    let radius: Float = 0.4

    var lampOn = false { didSet { lampNode.isHidden = !lampOn } }

    init() {
        let cam = SCNCamera()
        cam.zNear = 0.1
        cam.zFar = 2500
        cam.fieldOfView = 74
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
        node.addChildNode(cameraNode)

        let spot = SCNLight()
        spot.type = .spot
        spot.intensity = 1800
        spot.spotInnerAngle = 24
        spot.spotOuterAngle = 52
        spot.attenuationStartDistance = 3
        spot.attenuationEndDistance = 32
        spot.color = UIColor(red: 1, green: 0.96, blue: 0.86, alpha: 1)
        lampNode.light = spot
        lampNode.position = SCNVector3(0.12, 0.12, 0)
        lampNode.isHidden = true
        cameraNode.addChildNode(lampNode)

        cameraNode.addChildNode(toolHolder)

        let cap = Structures.makeCapsule(scale: 1)
        cap.eulerAngles = SCNVector3(0.35, 0, 1.25)
        capsuleNode.addChildNode(cap)
        capsuleNode.position = SCNVector3(-0.34, -0.2, -0.62)
        capsuleNode.isHidden = true
        Make.noShadows(capsuleNode)
        cameraNode.addChildNode(capsuleNode)
    }

    func setLamp(level: Int) {
        lampNode.light?.intensity = CGFloat(1800 + 900 * level)
        lampNode.light?.spotOuterAngle = CGFloat(52 + 14 * level)
        lampNode.light?.attenuationEndDistance = CGFloat(32 + 14 * level)
    }

    func setTool(_ index: Int) {
        guard index != toolIndex else { return }
        toolIndex = index
        toolHolder.childNodes.forEach { $0.removeFromParentNode() }
        guard index >= 0 else { return }
        let model = ToolModels.make(index)
        if index >= 3 {
            model.position = SCNVector3(0.3, -0.12, 0.25)
            model.eulerAngles = SCNVector3(-0.62, 0.16, 0)
        } else {
            model.scale = SCNVector3(1.5, 1.5, 1.5)
            model.position = SCNVector3(0.21, -0.1, -0.36)
            model.eulerAngles = SCNVector3(-0.42, 0.3, 0.1)
        }
        toolHolder.addChildNode(model)
    }

    func setToolVisible(_ v: Bool) { toolHolder.isHidden = !v }
    func setCapsuleVisible(_ v: Bool) { capsuleNode.isHidden = !v }

    /// Back-and-forth scrubbing motion of the tool.
    func animateTool(dt: Float, scrubbing: Bool) {
        scrubAmount += ((scrubbing ? 1 : 0) - scrubAmount) * min(1, dt * 10)
        scrubPhase += dt * 15
        let fwd = sin(scrubPhase) * 0.06 * scrubAmount
        let side = sin(scrubPhase * 0.5) * 0.02 * scrubAmount
        let sway = sin(bobPhase) * 0.012
        toolHolder.simdPosition = SIMD3<Float>(side + sway, -0.05 * scrubAmount + abs(sway) * 0.5, -fwd - 0.06 * scrubAmount)
        toolHolder.simdEulerAngles = SIMD3<Float>(-0.22 * scrubAmount, 0, 0)
    }

    var forward: SIMD3<Float> { SIMD3<Float>(-sin(yaw), 0, -cos(yaw)) }
    var right: SIMD3<Float> { SIMD3<Float>(cos(yaw), 0, -sin(yaw)) }
    var eyePosition: SIMD3<Float> { position + SIMD3<Float>(0, eyeHeight, 0) }
    var lookDirection: SIMD3<Float> {
        let cp = cos(pitch)
        return SIMD3<Float>(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
    }

    var isMoving: Bool { simd_length(SIMD2<Float>(velocity.x, velocity.z)) > 0.4 }

    func look(dx: Float, dy: Float) {
        yaw -= dx
        pitch = max(-1.45, min(1.35, pitch - dy))
    }

    func update(dt: Float, move: SIMD2<Float>, jumpPressed: Bool, jumpHeld: Bool, world: MoonWorld) {
        stepEvent = false
        var wish = forward * move.y + right * move.x
        let len = simd_length(wish)
        if len > 1 { wish /= len }
        let target = wish * moveSpeed
        let k: Float = onGround ? min(1, 9 * dt) : min(1, 1.4 * dt)
        velocity.x += (target.x - velocity.x) * k
        velocity.z += (target.z - velocity.z) * k

        if onGround && jumpPressed {
            velocity.y = 2.9
            onGround = false
        }

        jetThrusting = false
        if !onGround && jumpHeld && fuel > 0 && maxFuel > 0 {
            velocity.y = min(5, velocity.y + 4.6 * dt)
            let push = forward * (3.2 * dt)
            velocity.x += push.x
            velocity.z += push.z
            fuel = max(0, fuel - dt)
            jetThrusting = true
        }

        velocity.y -= gravity * dt
        position += velocity * dt
        world.resolveCollisions(&position, radius: radius)

        let ground = world.height(atX: position.x, z: position.z)
        if position.y <= ground {
            if !onGround && velocity.y < -1.2 { stepEvent = true }
            position.y = ground
            if velocity.y < 0 { velocity.y = 0 }
            onGround = true
        } else if onGround && velocity.y <= 0 && position.y - ground < 0.4 {
            position.y = ground
            velocity.y = 0
        } else {
            onGround = false
        }
        if onGround { fuel = min(maxFuel, fuel + dt * 0.8) }

        let hs = simd_length(SIMD2<Float>(velocity.x, velocity.z))
        if onGround && hs > 0.4 {
            let before = Int(bobPhase / .pi)
            bobPhase += dt * hs * 2.1
            if Int(bobPhase / .pi) != before { stepEvent = true }
        }
        let bob = onGround ? sin(bobPhase * 2) * 0.03 * min(1, hs / 3) : 0
        apply(eye: eyeHeight + bob)
    }

    /// Used while driving: the vehicle owns the position.
    func ride(at p: SIMD3<Float>, seatHeight: Float) {
        position = p
        velocity = .zero
        onGround = true
        apply(eye: seatHeight)
    }

    private func apply(eye: Float) {
        node.simdPosition = position
        node.simdEulerAngles = SIMD3<Float>(0, yaw, 0)
        cameraNode.simdPosition = SIMD3<Float>(0, eye, 0)
        cameraNode.simdEulerAngles = SIMD3<Float>(pitch, 0, 0)
    }

    /// Where the tool touches the ground, if within reach.
    func aimPoint(world: MoonWorld, reach: Float) -> SIMD3<Float>? {
        let o = eyePosition
        let d = lookDirection
        var t: Float = 0.3
        var prev = o + d * 0.2
        while t <= reach {
            let p = o + d * t
            if p.y <= world.height(atX: p.x, z: p.z) {
                var a = prev, b = p
                for _ in 0..<6 {
                    let m = (a + b) * 0.5
                    if m.y <= world.height(atX: m.x, z: m.z) { b = m } else { a = m }
                }
                return SIMD3<Float>(b.x, world.height(atX: b.x, z: b.z), b.z)
            }
            prev = p
            t += 0.08
        }
        // Looking out toward the horizon: clean at full reach instead of nothing.
        if d.y < 0.35 {
            let flat = SIMD2<Float>(d.x, d.z)
            let len = simd_length(flat)
            if len > 0.001 {
                let q = SIMD2<Float>(o.x, o.z) + flat / len * reach
                return SIMD3<Float>(q.x, world.height(atX: q.x, z: q.y), q.y)
            }
        }
        return nil
    }
}
