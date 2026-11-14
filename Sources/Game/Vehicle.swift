import SceneKit
import simd

/// A drivable cleaning vehicle: Push Sweeper, Sweeper Truck or Mega Suagrover.
final class Vehicle {
    let node = SCNNode()
    let tier: VehicleTier
    let level: Int
    var position: SIMD3<Float>
    var heading: Float
    var speed: Float = 0
    private let brush = SCNNode()
    private let dustPuff: SCNParticleSystem

    init(level: Int, position: SIMD3<Float>, heading: Float) {
        self.level = level
        self.tier = Catalog.vehicles[level]
        self.position = position
        self.heading = heading
        self.dustPuff = SweepBot.makeDustParticles()

        let L = tier.length, W = tier.bodyWidth
        let wheelR: Float = level == 0 ? 0.28 : (level == 1 ? 0.5 : 0.7)
        let deckY = wheelR + 0.25
        let body = SCNNode()
        // Hopper at the back, cab toward the front (front is -Z).
        let hopperH: Float = level == 0 ? 0.7 : (level == 1 ? 1.5 : 2.0)
        body.addChildNode(Make.part(Make.box(CGFloat(W), CGFloat(hopperH), CGFloat(L * 0.55), chamfer: 0.08), Mat.white,
                                    0, deckY + hopperH / 2, L * 0.2))
        body.addChildNode(Make.part(Make.box(CGFloat(W + 0.04), 0.22, CGFloat(L * 0.56), chamfer: 0.02), Mat.orange,
                                    0, deckY + hopperH * 0.35, L * 0.2))
        body.addChildNode(Make.part(Make.box(CGFloat(W), 0.3, CGFloat(L), chamfer: 0.05), Mat.dark, 0, deckY - 0.1, 0))
        if level > 0 {
            let cabH: Float = level == 1 ? 1.3 : 1.7
            body.addChildNode(Make.part(Make.box(CGFloat(W * 0.8), CGFloat(cabH), CGFloat(L * 0.32), chamfer: 0.12), Mat.orange,
                                        0, deckY + cabH / 2, -L * 0.28))
            let glass = Mat.solid(UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), spec: 0.9)
            body.addChildNode(Make.part(Make.box(CGFloat(W * 0.7), CGFloat(cabH * 0.45), 0.05, chamfer: 0.02), glass,
                                        0, deckY + cabH * 0.68, -L * 0.445))
            for sx in [-1, 1] {
                let lamp = Make.part(SCNSphere(radius: 0.13), Mat.warmGlow, Float(sx) * W * 0.32, deckY + 0.3, -L * 0.46)
                body.addChildNode(lamp)
            }
        } else {
            // Walk-behind handlebar.
            body.addChildNode(Make.part(SCNCylinder(radius: 0.03, height: 1.1), Mat.steel, -0.4, deckY + 0.9, L * 0.48))
            body.addChildNode(Make.part(SCNCylinder(radius: 0.03, height: 1.1), Mat.steel, 0.4, deckY + 0.9, L * 0.48))
            let bar = Make.part(SCNCylinder(radius: 0.035, height: 0.9), Mat.rubber, 0, deckY + 1.45, L * 0.48)
            bar.eulerAngles.z = .pi / 2
            body.addChildNode(bar)
        }
        let beacon = Make.part(SCNSphere(radius: 0.1), Mat.glow(UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1)),
                               0, deckY + hopperH + 0.12, L * 0.2)
        Make.blink(beacon, period: 0.35)
        body.addChildNode(beacon)

        let axles = level == 2 ? 3 : 2
        for a in 0..<axles {
            let z = -L * 0.34 + Float(a) * (L * 0.68 / Float(axles - 1))
            for sx in [-1, 1] {
                let wheel = Make.part(SCNCylinder(radius: CGFloat(wheelR), height: CGFloat(wheelR * 0.7)), Mat.rubber,
                                      Float(sx) * (W / 2 + 0.02), wheelR, z)
                wheel.eulerAngles.z = .pi / 2
                body.addChildNode(wheel)
                let hub = Make.part(SCNCylinder(radius: CGFloat(wheelR * 0.45), height: CGFloat(wheelR * 0.72)), Mat.orange,
                                    Float(sx) * (W / 2 + 0.03), wheelR, z)
                hub.eulerAngles.z = .pi / 2
                body.addChildNode(hub)
            }
        }
        // Spinning roller brush across the full cleaning width.
        let roller = SCNCylinder(radius: 0.28, height: CGFloat(tier.width))
        roller.materials = [Mat.toolBlue]
        brush.geometry = roller
        let holder = SCNNode()
        holder.position = SCNVector3(0, 0.3, -L / 2 - 0.45)
        holder.eulerAngles.z = .pi / 2
        holder.addChildNode(brush)
        body.addChildNode(holder)
        body.addChildNode(Make.part(Make.box(CGFloat(tier.width + 0.1), 0.12, 0.7, chamfer: 0.03), Mat.orange, 0, 0.66, -L / 2 - 0.4))
        brush.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.4)))
        let puffNode = SCNNode()
        puffNode.position = SCNVector3(0, 0.15, -L / 2 - 0.6)
        puffNode.addParticleSystem(dustPuff)
        body.addChildNode(puffNode)
        dustPuff.emitterShape = SCNBox(width: CGFloat(tier.width), height: 0.2, length: 0.4, chamferRadius: 0)

        node.addChildNode(body)
        syncNode(pitch: 0, roll: 0)
    }

    var forward: SIMD3<Float> { SIMD3<Float>(-sin(heading), 0, -cos(heading)) }
    var brushCenter: SIMD3<Float> { position + forward * (tier.length / 2 + 0.5) }
    var seat: SIMD3<Float> {
        level == 0 ? position - forward * (tier.length * 0.8) : position + forward * (tier.length * 0.05)
    }

    func setSweeping(_ on: Bool) {
        dustPuff.birthRate = on ? CGFloat(60 * tier.width) : 0
    }

    /// Returns how much the heading changed, so the camera can turn with it.
    func update(dt: Float, throttle: Float, steer: Float, world: MoonWorld) -> Float {
        let target = throttle * (throttle >= 0 ? tier.speed : tier.speed * 0.5)
        speed += (target - speed) * min(1, 2.2 * dt)
        if abs(speed) < 0.02 && abs(throttle) < 0.05 { speed = 0 }
        let turn = -steer * 1.5 * dt * max(-1, min(1, speed / 2.5))
        heading += turn
        position += forward * (speed * dt)
        world.resolveCollisions(&position, radius: tier.bodyWidth / 2)
        position.y = world.height(atX: position.x, z: position.z)

        let f = forward
        let r = SIMD3<Float>(cos(heading), 0, -sin(heading))
        let hl = tier.length / 2, hw = tier.bodyWidth / 2
        let hF = world.height(atX: position.x + f.x * hl, z: position.z + f.z * hl)
        let hB = world.height(atX: position.x - f.x * hl, z: position.z - f.z * hl)
        let hR = world.height(atX: position.x + r.x * hw, z: position.z + r.z * hw)
        let hL = world.height(atX: position.x - r.x * hw, z: position.z - r.z * hw)
        position.y = (hF + hB + hR + hL) / 4
        syncNode(pitch: atan2(hF - hB, tier.length), roll: atan2(hR - hL, tier.bodyWidth))
        return turn
    }

    private func syncNode(pitch: Float, roll: Float) {
        node.simdPosition = position
        let q = simd_quatf(angle: heading, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        node.simdOrientation = q
    }
}
