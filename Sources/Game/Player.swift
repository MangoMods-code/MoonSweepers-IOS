import SceneKit
import simd

/// First-person body: no visible hands, just a camera on low-gravity legs.
final class Player {
    let node = SCNNode()
    let cameraNode = SCNNode()
    let lampNode = SCNNode()

    var position = SIMD3<Float>(0, 0, 6)
    var velocity = SIMD3<Float>(0, 0, 0)
    var yaw: Float = 0
    var pitch: Float = -0.15
    var onGround = true
    var fuel: Float = 0
    var maxFuel: Float = 0
    var moveSpeed: Float = 3.2
    var jetThrusting = false
    private var bobPhase: Float = 0

    let gravity: Float = 1.62
    let eyeHeight: Float = 1.65
    let radius: Float = 0.4

    var lampOn = false {
        didSet { lampNode.isHidden = !lampOn }
    }

    init() {
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 2000
        cam.fieldOfView = 72
        cam.wantsHDR = false
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, eyeHeight, 0)
        node.addChildNode(cameraNode)

        let spot = SCNLight()
        spot.type = .spot
        spot.intensity = 1600
        spot.spotInnerAngle = 22
        spot.spotOuterAngle = 48
        spot.attenuationStartDistance = 2
        spot.attenuationEndDistance = 28
        spot.color = UIColor(red: 1, green: 0.96, blue: 0.86, alpha: 1)
        lampNode.light = spot
        lampNode.position = SCNVector3(0.15, 0.1, 0)
        lampNode.isHidden = true
        cameraNode.addChildNode(lampNode)
    }

    var forward: SIMD3<Float> { SIMD3<Float>(-sin(yaw), 0, -cos(yaw)) }
    var right: SIMD3<Float> { SIMD3<Float>(cos(yaw), 0, -sin(yaw)) }

    var eyePosition: SIMD3<Float> { position + SIMD3<Float>(0, eyeHeight, 0) }

    var lookDirection: SIMD3<Float> {
        let cp = cos(pitch)
        return SIMD3<Float>(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
    }

    func look(dx: Float, dy: Float) {
        yaw -= dx
        pitch = max(-1.45, min(1.35, pitch - dy))
    }

    func update(dt: Float, move: SIMD2<Float>, jumpPressed: Bool, jumpHeld: Bool, world: MoonWorld) {
        // move.x = strafe right, move.y = forward
        var wish = forward * move.y + right * move.x
        let len = simd_length(wish)
        if len > 1 { wish /= len }
        let target = wish * moveSpeed
        let k: Float = onGround ? min(1, 9 * dt) : min(1, 1.6 * dt)
        velocity.x += (target.x - velocity.x) * k
        velocity.z += (target.z - velocity.z) * k

        if onGround && jumpPressed {
            velocity.y = 3.0
            onGround = false
        }

        jetThrusting = false
        if !onGround && jumpHeld && fuel > 0 && maxFuel > 0 {
            velocity.y += 4.4 * dt
            velocity.y = min(velocity.y, 5)
            fuel = max(0, fuel - dt)
            jetThrusting = true
        }

        velocity.y -= gravity * dt
        position += velocity * dt
        world.resolveCollisions(&position, radius: radius)

        let ground = world.height(atX: position.x, z: position.z)
        if position.y <= ground {
            position.y = ground
            if velocity.y < 0 { velocity.y = 0 }
            onGround = true
        } else if onGround && velocity.y <= 0 && position.y - ground < 0.35 {
            // stick to the ground when walking downhill
            position.y = ground
            velocity.y = 0
        } else {
            onGround = false
        }

        if onGround {
            fuel = min(maxFuel, fuel + dt * 0.6)
        }

        // Gentle head bob while walking.
        let hs = simd_length(SIMD2<Float>(velocity.x, velocity.z))
        if onGround && hs > 0.3 {
            bobPhase += dt * hs * 2.2
        }
        let bob = onGround ? sin(bobPhase) * 0.035 * min(1, hs / 3) : 0

        node.simdPosition = position
        node.simdEulerAngles = SIMD3<Float>(0, yaw, 0)
        cameraNode.simdPosition = SIMD3<Float>(0, eyeHeight + bob, 0)
        cameraNode.simdEulerAngles = SIMD3<Float>(pitch, 0, 0)
    }

    /// Where the tool hits the ground, if within reach.
    func aimPoint(world: MoonWorld, reach: Float) -> SIMD3<Float>? {
        let o = eyePosition
        let d = lookDirection
        var t: Float = 0.3
        var prev = o + d * 0.2
        while t <= reach {
            let p = o + d * t
            let g = world.height(atX: p.x, z: p.z)
            if p.y <= g {
                // refine between prev and p
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
        return nil
    }
}
