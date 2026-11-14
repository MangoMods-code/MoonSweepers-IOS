import SceneKit
import simd

/// D.U.S.T.Y. — a small helper robot that sweeps near the base and
/// brings its load back to the silo by itself.
final class SweepBot {
    enum State { case seeking, cleaning, returning, unloading }

    let node = SCNNode()
    private let brush = SCNNode()
    private let beacon = SCNNode()
    private let dustPuff: SCNParticleSystem
    var position: SIMD3<Float>
    var state: State = .seeking
    var load: Float = 0
    let capacity: Float = 45
    let speed: Float = 2.2
    let cleanRadius: Float = 0.9
    let cleanRate: Float = 0.7
    private var target: SIMD3<Float>?
    private var unloadTimer: Float = 0
    private var heading: Float = 0
    let workRadius: Float
    let index: Int

    init(index: Int, start: SIMD3<Float>) {
        self.index = index
        self.position = start
        self.workRadius = 22 + Float(index) * 9
        self.dustPuff = SweepBot.makeDustParticles()

        func mat(_ c: UIColor, glow: Bool = false) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = c
            m.lightingModel = glow ? .constant : .blinn
            return m
        }
        let body = SCNNode(geometry: SCNBox(width: 0.8, height: 0.45, length: 1.0, chamferRadius: 0.12))
        body.geometry?.materials = [mat(UIColor(red: 0.95, green: 0.82, blue: 0.2, alpha: 1))]
        body.position = SCNVector3(0, 0.42, 0)
        node.addChildNode(body)
        let dome = SCNNode(geometry: SCNSphere(radius: 0.26))
        dome.geometry?.materials = [mat(UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1), glow: true)]
        dome.position = SCNVector3(0, 0.66, -0.15)
        node.addChildNode(dome)
        for (x, z) in [(-0.42, -0.32), (0.42, -0.32), (-0.42, 0.32), (0.42, 0.32)] {
            let wheel = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.1))
            wheel.geometry?.materials = [mat(UIColor(white: 0.15, alpha: 1))]
            wheel.eulerAngles.z = .pi / 2
            wheel.position = SCNVector3(Float(x), 0.17, Float(z))
            node.addChildNode(wheel)
        }
        brush.geometry = SCNCylinder(radius: 0.32, height: 0.08)
        brush.geometry?.materials = [mat(UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1))]
        brush.position = SCNVector3(0, 0.06, -0.55)
        node.addChildNode(brush)
        brush.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.5)))
        beacon.geometry = SCNSphere(radius: 0.06)
        beacon.geometry?.materials = [mat(UIColor(red: 1, green: 0.3, blue: 0.2, alpha: 1), glow: true)]
        beacon.position = SCNVector3(0, 0.95, 0.25)
        node.addChildNode(beacon)
        beacon.runAction(.repeatForever(.sequence([.fadeOut(duration: 0.4), .fadeIn(duration: 0.4)])))

        dustPuff.birthRate = 0
        brush.addParticleSystem(dustPuff)

        node.simdPosition = start
    }

    static func makeDustParticles() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.particleLifeSpan = 1.1
        p.particleLifeSpanVariation = 0.4
        p.particleSize = 0.045
        p.particleSizeVariation = 0.03
        p.particleColor = UIColor(red: 0.82, green: 0.8, blue: 0.75, alpha: 1)
        p.particleColorVariation = SCNVector4(0, 0, 0.1, 0.2)
        p.emitterShape = SCNSphere(radius: 0.15)
        p.birthLocation = .volume
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 70
        p.particleVelocity = 0.9
        p.particleVelocityVariation = 0.5
        p.acceleration = SCNVector3(0, -1.62, 0)
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.particleColorVariation = SCNVector4(0, 0, 0.1, 0.1)
        return p
    }

    /// Returns credits earned this frame (non-zero when unloading at the silo).
    func update(dt: Float, world: MoonWorld, dust: DustField, silo: SIMD3<Float>) -> Float {
        var earned: Float = 0
        dustPuff.birthRate = 0
        let unloadSpot = silo + SIMD3<Float>(-2.9, 0, Float(index % 3) - 1)

        switch state {
        case .seeking:
            if target == nil { target = findDusty(world: world, dust: dust, around: silo, radius: workRadius) }
            if let t = target {
                if moveToward(t, dt: dt, world: world) { state = .cleaning }
            } else {
                state = load > 0 ? .returning : .seeking
            }
        case .cleaning:
            let got = dust.clean(atX: position.x - sin(heading) * 0.55,
                                 z: position.z - cos(heading) * 0.55,
                                 radius: cleanRadius, rate: cleanRate, dt: dt,
                                 capacityLeft: capacity - load)
            load += got
            dustPuff.birthRate = got > 0 ? 40 : 0
            if load >= capacity - 0.01 {
                state = .returning
                target = nil
            } else if got < 0.0005 {
                // local patch is clean — creep forward or pick a new patch nearby
                let ahead = position + SIMD3<Float>(-sin(heading), 0, -cos(heading)) * 0.9
                if dust.averageDust(atX: ahead.x, z: ahead.z, radius: 0.6) > 0.05 {
                    target = ahead
                } else {
                    target = findDusty(world: world, dust: dust, around: position, radius: 6)
                        ?? findDusty(world: world, dust: dust, around: silo, radius: workRadius)
                }
                state = target == nil ? .returning : .seeking
            }
        case .returning:
            if moveToward(unloadSpot, dt: dt, world: world) {
                state = .unloading
                unloadTimer = 1.2
            }
        case .unloading:
            unloadTimer -= dt
            if unloadTimer <= 0 {
                earned = load * Upgrades.creditsPerUnit
                load = 0
                target = nil
                state = .seeking
            }
        }
        node.simdPosition = position
        node.simdEulerAngles = SIMD3<Float>(0, heading, 0)
        return earned
    }

    private func moveToward(_ t: SIMD3<Float>, dt: Float, world: MoonWorld) -> Bool {
        var d = SIMD2<Float>(t.x - position.x, t.z - position.z)
        let dist = simd_length(d)
        if dist < 0.3 { return true }
        d /= dist
        let desired = atan2(-d.x, -d.y)
        var diff = desired - heading
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        heading += max(-4 * dt, min(4 * dt, diff))
        let step = min(dist, speed * dt)
        position.x += d.x * step
        position.z += d.y * step
        world.resolveCollisions(&position, radius: 0.5)
        position.y = world.height(atX: position.x, z: position.z)
        return false
    }

    private func findDusty(world: MoonWorld, dust: DustField, around c: SIMD3<Float>, radius: Float) -> SIMD3<Float>? {
        var best: SIMD3<Float>?
        var bestScore: Float = 0.05
        for _ in 0..<36 {
            let a = Float.random(in: 0..<(2 * .pi))
            let r = sqrt(Float.random(in: 0...1)) * radius
            let x = c.x + cos(a) * r, z = c.z + sin(a) * r
            if abs(x) > world.half - 3 || abs(z) > world.half - 3 { continue }
            let amt = dust.averageDust(atX: x, z: z, radius: 0.7)
            let dist = simd_length(SIMD2<Float>(x - position.x, z - position.z))
            let score = amt - dist * 0.004
            if amt > 0.05 && score > bestScore {
                bestScore = score
                best = SIMD3<Float>(x, 0, z)
            }
        }
        return best
    }
}
