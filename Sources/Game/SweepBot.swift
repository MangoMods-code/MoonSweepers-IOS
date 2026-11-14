import SceneKit
import simd

/// Automated cleaners. Robot Vacuums work a fixed radius around the home depot and drive
/// their dust back; J.O.O.N.A.S. roams every sector and fires capsules at the Capsule Catcher.
final class SweepBot {
    enum Kind { case vacuum, joonas }
    enum State { case seeking, cleaning, returning, unloading }

    let kind: Kind
    let node = SCNNode()
    private let dustPuff: SCNParticleSystem
    var position: SIMD3<Float>
    private var state: State = .seeking
    private(set) var load: Float = 0
    private var target: SIMD3<Float>?
    private var timer: Float = 0
    private var heading: Float = 0
    private let index: Int

    var capacity: Float { kind == .vacuum ? 12 : 60 }
    private var speed: Float { kind == .vacuum ? 1.8 : 4.2 }
    private var cleanRadius: Float { kind == .vacuum ? 0.7 : 1.9 }
    private var cleanRate: Float { kind == .vacuum ? 1.2 : 2.4 }

    /// Called with (kg, capsule start position) when a load leaves the bot.
    var onDeliver: ((Float, SIMD3<Float>) -> Void)?

    init(kind: Kind, index: Int, start: SIMD3<Float>) {
        self.kind = kind
        self.index = index
        self.position = start
        self.dustPuff = SweepBot.makeDustParticles()

        if kind == .vacuum, let robot = Kit.make("robot", fit: 1.15) {
            node.addChildNode(robot)
            node.addChildNode(Make.part(SCNCylinder(radius: 0.3, height: 0.05), Mat.toolBlue, 0, 0.04, -0.62))
        } else if kind == .vacuum {
            node.addChildNode(Make.part(SCNCylinder(radius: 0.5, height: 0.22), Mat.white, 0, 0.2, 0))
            node.addChildNode(Make.part(SCNTube(innerRadius: 0.5, outerRadius: 0.54, height: 0.1), Mat.orange, 0, 0.2, 0))
            node.addChildNode(Make.part(SCNCylinder(radius: 0.16, height: 0.06), Mat.cyanGlow, 0, 0.33, -0.15))
            node.addChildNode(Make.part(SCNCylinder(radius: 0.3, height: 0.05), Mat.toolBlue, 0, 0.06, -0.3))
        } else {
            node.addChildNode(Make.part(Make.box(1.5, 0.7, 2.1, chamfer: 0.15), Mat.white, 0, 0.85, 0))
            node.addChildNode(Make.part(Make.box(1.54, 0.2, 2.14, chamfer: 0.04), Mat.orange, 0, 0.7, 0))
            for sx in [-1, 1] {
                node.addChildNode(Make.part(Make.box(0.4, 0.5, 2.3, chamfer: 0.2), Mat.rubber, Float(sx) * 0.85, 0.28, 0))
            }
            node.addChildNode(Make.part(SCNCylinder(radius: 0.12, height: 0.5), Mat.steel, 0, 1.4, -0.5))
            let head = Make.part(Make.box(0.8, 0.45, 0.5, chamfer: 0.12), Mat.white, 0, 1.8, -0.55)
            node.addChildNode(head)
            for sx in [-1, 1] {
                node.addChildNode(Make.part(SCNCylinder(radius: 0.11, height: 0.04), Mat.cyanGlow, Float(sx) * 0.2, 1.82, -0.81))
                node.childNodes.last?.eulerAngles.x = .pi / 2
            }
            node.addChildNode(Make.part(SCNCylinder(radius: 0.02, height: 0.9), Mat.steel, 0.5, 1.6, 0.7))
            let tip = Make.part(SCNSphere(radius: 0.07), Mat.redGlow, 0.5, 2.08, 0.7)
            Make.blink(tip, period: 0.4)
            node.addChildNode(tip)
            let roller = Make.part(SCNCylinder(radius: 0.3, height: 3.6), Mat.toolBlue, 0, 0.3, -1.6)
            roller.eulerAngles.z = .pi / 2
            node.addChildNode(roller)
            node.addChildNode(Make.part(Make.box(3.7, 0.12, 0.7, chamfer: 0.03), Mat.orange, 0, 0.66, -1.55))
            // Capsule launcher on its back.
            let tube = Make.part(SCNCylinder(radius: 0.22, height: 1.1), Mat.dark, -0.35, 1.5, 0.6)
            tube.eulerAngles.x = -0.5
            node.addChildNode(tube)
        }
        let puff = SCNNode()
        puff.position = SCNVector3(0, 0.1, kind == .vacuum ? -0.4 : -1.7)
        puff.addParticleSystem(dustPuff)
        node.addChildNode(puff)
        node.simdPosition = start
    }

    static func makeDustParticles() -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = 0
        p.particleLifeSpan = 1.3
        p.particleLifeSpanVariation = 0.5
        p.particleSize = 0.05
        p.particleSizeVariation = 0.035
        p.particleColor = UIColor(red: 0.84, green: 0.82, blue: 0.77, alpha: 0.9)
        p.emitterShape = SCNSphere(radius: 0.15)
        p.birthLocation = .volume
        p.birthDirection = .random
        p.emittingDirection = SCNVector3(0, 1, 0)
        p.spreadingAngle = 80
        p.particleVelocity = 0.8
        p.particleVelocityVariation = 0.6
        p.acceleration = SCNVector3(0, -1.62, 0)
        p.blendMode = .alpha
        p.isLightingEnabled = false
        p.isLocal = false
        return p
    }

    func update(dt: Float, world: MoonWorld, dust: DustField, home: SIMD3<Float>, dock: SIMD3<Float>) {
        dustPuff.birthRate = 0
        switch state {
        case .seeking:
            if target == nil { target = pickTarget(world: world, dust: dust, home: home) }
            if let t = target {
                if moveToward(t, dt: dt, world: world) { state = .cleaning }
            } else if load > 0.01 {
                state = .returning
            }
        case .cleaning:
            let fx = position.x - sin(heading) * (kind == .vacuum ? 0.4 : 1.6)
            let fz = position.z - cos(heading) * (kind == .vacuum ? 0.4 : 1.6)
            let got = dust.clean(atX: fx, z: fz, radius: cleanRadius, capacityLeft: capacity - load)
            load += got
            dustPuff.birthRate = got > 0 ? (kind == .vacuum ? 30 : 140) : 0
            if load >= capacity - 0.01 {
                state = .returning
                target = nil
            } else if got < 0.00005 {
                let ahead = position + SIMD3<Float>(-sin(heading), 0, -cos(heading)) * (cleanRadius * 1.2)
                if WorldDims.contains(ahead.x, ahead.z, margin: 8)
                    && dust.averageDust(atX: ahead.x, z: ahead.z, radius: cleanRadius) > 0.04 {
                    target = ahead
                } else {
                    target = sample(world: world, dust: dust, around: position, radius: 9, tries: 24)
                        ?? pickTarget(world: world, dust: dust, home: home)
                }
                state = target == nil ? .returning : .seeking
            }
        case .returning:
            if kind == .joonas {
                state = .unloading
                timer = 0.8
            } else {
                let spot = dock + SIMD3<Float>(Float(index) * 1.3, 0, 0)
                if moveToward(spot, dt: dt, world: world) {
                    state = .unloading
                    timer = 1.0
                }
            }
        case .unloading:
            timer -= dt
            if timer <= 0 {
                if load > 0.01 { onDeliver?(load, position + SIMD3<Float>(0, 1.8, 0)) }
                load = 0
                target = nil
                state = .seeking
            }
        }
        node.simdPosition = position
        node.simdEulerAngles = SIMD3<Float>(0, heading, 0)
    }

    private func moveToward(_ t: SIMD3<Float>, dt: Float, world: MoonWorld) -> Bool {
        var d = SIMD2<Float>(t.x - position.x, t.z - position.z)
        let dist = simd_length(d)
        if dist < 0.35 { return true }
        d /= dist
        let desired = atan2(-d.x, -d.y)
        var diff = desired - heading
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        heading += max(-4 * dt, min(4 * dt, diff))
        let step = min(dist, speed * dt)
        let before = position
        position.x += d.x * step
        position.z += d.y * step
        world.resolveCollisions(&position, radius: kind == .vacuum ? 0.5 : 1.0)
        position.y = world.height(atX: position.x, z: position.z)
        // Blocked by an obstacle: give up on this target.
        let moved = simd_length(SIMD2<Float>(position.x - before.x, position.z - before.z))
        if moved < step * 0.2 {
            timer += dt
            if timer > 1.5 { timer = 0; return true }
        }
        return false
    }

    private func pickTarget(world: MoonWorld, dust: DustField, home: SIMD3<Float>) -> SIMD3<Float>? {
        if kind == .vacuum {
            return sample(world: world, dust: dust, around: home, radius: 24 + Float(index) * 5, tries: 40)
        }
        // J.O.O.N.A.S.: nearest sector that still has dust.
        var best = -1
        var bestD = Float.greatestFiniteMagnitude
        for s in 0..<Hex.count where dust.sectorClean(s) < 0.995 {
            let c = Hex.centers[s]
            let d = simd_length(SIMD2<Float>(position.x, position.z) - c) + Float((s * 7 + index * 5) % 11)
            if d < bestD { bestD = d; best = s }
        }
        guard best >= 0 else { return nil }
        let c = Hex.centers[best]
        return sample(world: world, dust: dust, around: SIMD3<Float>(c.x, 0, c.y), radius: 44, tries: 80)
    }

    private func sample(world: MoonWorld, dust: DustField, around c: SIMD3<Float>, radius: Float, tries: Int) -> SIMD3<Float>? {
        var best: SIMD3<Float>?
        var bestScore: Float = -1000
        for _ in 0..<tries {
            let a = Float.random(in: 0..<(2 * .pi))
            let r = Float.random(in: 0...1).squareRoot() * radius
            let x = c.x + cos(a) * r, z = c.z + sin(a) * r
            if !WorldDims.contains(x, z, margin: 9) { continue }
            let amt = dust.averageDust(atX: x, z: z, radius: cleanRadius)
            if amt < 0.06 { continue }
            let dist = simd_length(SIMD2<Float>(x - position.x, z - position.z))
            let score = amt - dist * 0.01
            if score > bestScore {
                bestScore = score
                best = SIMD3<Float>(x, 0, z)
            }
        }
        return best
    }
}
