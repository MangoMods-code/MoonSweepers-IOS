import UIKit
import SceneKit
import simd

/// Terrain, sky, sun/day-night cycle and the base buildings.
final class MoonWorld {
    let size: Float = 160
    let grid = 160
    private(set) var heights: [Float] = []
    var half: Float { size / 2 }

    struct Collider { let x: Float; let z: Float; let r: Float }
    private(set) var colliders: [Collider] = []

    private struct Crater { let x: Float; let z: Float; let r: Float; let depth: Float }
    private var craters: [Crater] = []

    let root = SCNNode()
    private(set) var siloPos = SIMD3<Float>(4.5, 0, -2)
    private(set) var terminalPos = SIMD3<Float>(-4.5, 0, -2)
    private let sunNode = SCNNode()
    private let sunDisc = SCNNode()
    private let ambientNode = SCNNode()
    private let earthshineNode = SCNNode()
    private var beacons: [SCNNode] = []

    /// 0..1, one full lunar "day" loop.
    var timeOfDay: Float = 0.12
    let dayLength: Float = 600 // seconds

    init(scene: SCNScene, dust: DustField) {
        makeCraters()
        buildHeights()

        let terrainGeo = makeGridGeometry(yOffset: 0)
        terrainGeo.materials = [makeRockMaterial()]
        let terrain = SCNNode(geometry: terrainGeo)
        root.addChildNode(terrain)

        let dustGeo = makeGridGeometry(yOffset: 0.035)
        dustGeo.materials = [dust.material]
        let dustNode = SCNNode(geometry: dustGeo)
        dustNode.renderingOrder = 10
        root.addChildNode(dustNode)

        scene.rootNode.addChildNode(root)
        scene.background.contents = MoonWorld.makeStarfield()

        setupLights(scene: scene)
        buildEarth(scene: scene)
        buildBase()
        updateSun(dt: 0)
    }

    // MARK: Terrain

    private func makeCraters() {
        var rng = SeededRNG(seed: 0xC0FFEE)
        var list: [Crater] = []
        while list.count < 34 {
            let x = Float.random(in: -74...74, using: &rng)
            let z = Float.random(in: -74...74, using: &rng)
            let r = Float.random(in: 3.5...17, using: &rng)
            if sqrt(x * x + z * z) < 24 + r { continue }
            list.append(Crater(x: x, z: z, r: r, depth: r * Float.random(in: 0.12...0.22, using: &rng)))
        }
        craters = list
    }

    private func rawHeight(_ x: Float, _ z: Float) -> Float {
        var h = (Noise.value(x / 38, z / 38, seed: 1) - 0.5) * 7
        h += (Noise.value(x / 11 + 100, z / 11, seed: 2) - 0.5) * 1.6
        h += (Noise.value(x / 3.5, z / 3.5 + 50, seed: 5) - 0.5) * 0.3
        for c in craters {
            let dx = x - c.x, dz = z - c.z
            let d = sqrt(dx * dx + dz * dz) / c.r
            if d < 1 {
                h += c.depth * (d * d - 1)
            }
            let rim = (d - 1) / 0.28
            h += c.depth * 0.35 * exp(-rim * rim)
        }
        // Keep the base area flat.
        let d0 = sqrt(x * x + z * z)
        let flat = smoothstep(13, 26, d0)
        return h * flat
    }

    private func buildHeights() {
        let n = grid + 1
        let step = size / Float(grid)
        heights = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                heights[j * n + i] = rawHeight(-half + Float(i) * step, -half + Float(j) * step)
            }
        }
    }

    /// Ground height matching the rendered triangles.
    func height(atX x: Float, z: Float) -> Float {
        let n = grid + 1
        let step = size / Float(grid)
        let fx = max(0, min(Float(grid) - 0.001, (x + half) / step))
        let fz = max(0, min(Float(grid) - 0.001, (z + half) / step))
        let i = Int(fx), j = Int(fz)
        let tx = fx - Float(i), tz = fz - Float(j)
        let h00 = heights[j * n + i]
        let h10 = heights[j * n + i + 1]
        let h01 = heights[(j + 1) * n + i]
        let h11 = heights[(j + 1) * n + i + 1]
        // Triangles are (00, 01, 10) and (10, 01, 11).
        if tx + tz <= 1 {
            return h00 + (h10 - h00) * tx + (h01 - h00) * tz
        } else {
            return h11 + (h01 - h11) * (1 - tx) + (h10 - h11) * (1 - tz)
        }
    }

    private func makeGridGeometry(yOffset: Float) -> SCNGeometry {
        let n = grid + 1
        let step = size / Float(grid)
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        verts.reserveCapacity(n * n)
        norms.reserveCapacity(n * n)
        uvs.reserveCapacity(n * n)
        func h(_ i: Int, _ j: Int) -> Float {
            heights[max(0, min(n - 1, j)) * n + max(0, min(n - 1, i))]
        }
        for j in 0..<n {
            for i in 0..<n {
                let x = -half + Float(i) * step
                let z = -half + Float(j) * step
                verts.append(SCNVector3(x, h(i, j) + yOffset, z))
                let nx = h(i - 1, j) - h(i + 1, j)
                let nz = h(i, j - 1) - h(i, j + 1)
                let v = simd_normalize(SIMD3<Float>(nx, 2 * step, nz))
                norms.append(SCNVector3(v.x, v.y, v.z))
                uvs.append(CGPoint(x: CGFloat(i) / CGFloat(grid), y: CGFloat(j) / CGFloat(grid)))
            }
        }
        var idx: [UInt32] = []
        idx.reserveCapacity(grid * grid * 6)
        for j in 0..<grid {
            for i in 0..<grid {
                let a = UInt32(j * n + i)
                let b = UInt32((j + 1) * n + i)
                let c = UInt32(j * n + i + 1)
                let d = UInt32((j + 1) * n + i + 1)
                idx.append(contentsOf: [a, b, c, c, b, d])
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts),
                                        SCNGeometrySource(normals: norms),
                                        SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return geo
    }

    private func makeRockMaterial() -> SCNMaterial {
        let w = 256
        var px = [UInt8](repeating: 255, count: w * w * 4)
        for j in 0..<w {
            for i in 0..<w {
                let fx = Float(i), fz = Float(j)
                // Tileable-ish: sample noise on a torus-friendly period
                let n1 = Noise.value(fx / 16, fz / 16, seed: 21)
                let n2 = Noise.hash(i, j, 22)
                let v = 0.32 + 0.16 * n1 + 0.08 * n2
                let k = (j * w + i) * 4
                px[k] = UInt8(255 * v * 0.92)
                px[k + 1] = UInt8(255 * v * 0.95)
                px[k + 2] = UInt8(min(255, 255 * v * 1.08))
            }
        }
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = ImageUtil.cgImage(width: w, height: w, rgba: px)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(60, 60, 1)
        m.isDoubleSided = true
        return m
    }

    // MARK: Sky

    static func makeStarfield() -> UIImage {
        let w = 2048, h = 1024
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for k in stride(from: 3, to: px.count, by: 4) { px[k] = 255 }
        var rng = SeededRNG(seed: 42)
        for _ in 0..<5200 {
            let x = Int.random(in: 0..<w, using: &rng)
            let y = Int.random(in: 0..<h, using: &rng)
            let b = UInt8.random(in: 90...255, using: &rng)
            let tint = Int.random(in: 0...2, using: &rng)
            let k = (y * w + x) * 4
            px[k] = tint == 2 ? b : UInt8(Int(b) * 9 / 10)
            px[k + 1] = b
            px[k + 2] = tint == 0 ? b : UInt8(Int(b) * 9 / 10)
            if b > 235 && x + 1 < w {
                let k2 = k + 4
                px[k2] = b / 2; px[k2 + 1] = b / 2; px[k2 + 2] = b / 2
            }
        }
        // faint milky band
        for x in 0..<w {
            let cy = Float(h) * 0.42 + sin(Float(x) / Float(w) * .pi * 2) * 120
            for dy in -60...60 {
                let y = Int(cy) + dy
                if y < 0 || y >= h { continue }
                let fade = 1 - Float(abs(dy)) / 60
                let n = Noise.value(Float(x) / 30, Float(y) / 30, seed: 9)
                let add = UInt8(18 * fade * n)
                let k = (y * w + x) * 4
                px[k] = px[k] &+ add; px[k + 1] = px[k + 1] &+ add; px[k + 2] = px[k + 2] &+ add &+ add / 3
            }
        }
        return ImageUtil.image(width: w, height: h, rgba: px)
    }

    private func buildEarth(scene: SCNScene) {
        let size = CGSize(width: 512, height: 256)
        let tex = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.08, green: 0.25, blue: 0.62, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            var rng = SeededRNG(seed: 77)
            UIColor(red: 0.22, green: 0.48, blue: 0.22, alpha: 1).setFill()
            for _ in 0..<22 {
                let x = CGFloat.random(in: 0...512, using: &rng)
                let y = CGFloat.random(in: 40...216, using: &rng)
                let r = CGFloat.random(in: 12...46, using: &rng)
                ctx.cgContext.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
            }
            UIColor(white: 1, alpha: 0.75).setFill()
            for _ in 0..<40 {
                let x = CGFloat.random(in: 0...512, using: &rng)
                let y = CGFloat.random(in: 0...256, using: &rng)
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: CGFloat.random(in: 30...90, using: &rng), height: 7))
            }
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 512, height: 16))
            ctx.cgContext.fill(CGRect(x: 0, y: 240, width: 512, height: 16))
        }
        let sphere = SCNSphere(radius: 38)
        sphere.segmentCount = 48
        let m = SCNMaterial()
        m.diffuse.contents = tex
        m.emission.contents = tex
        m.emission.intensity = 0.45
        m.lightingModel = .lambert
        sphere.materials = [m]
        let earth = SCNNode(geometry: sphere)
        earth.position = SCNVector3(-320, 210, -620)
        earth.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 400)))
        scene.rootNode.addChildNode(earth)
    }

    private func setupLights(scene: SCNScene) {
        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(white: 1.0, alpha: 1)
        sun.intensity = 1300
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(white: 0.55, alpha: 1)
        amb.intensity = 120
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)

        // Soft bluish fill from Earth so nights aren't pitch black.
        let es = SCNLight()
        es.type = .directional
        es.color = UIColor(red: 0.45, green: 0.6, blue: 1.0, alpha: 1)
        es.intensity = 70
        earthshineNode.light = es
        earthshineNode.position = SCNVector3(-320, 210, -620)
        earthshineNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(earthshineNode)

        let disc = SCNSphere(radius: 22)
        let dm = SCNMaterial()
        dm.lightingModel = .constant
        dm.diffuse.contents = UIColor(red: 1, green: 0.98, blue: 0.9, alpha: 1)
        disc.materials = [dm]
        sunDisc.geometry = disc
        scene.rootNode.addChildNode(sunDisc)
    }

    /// 0 = full night, 1 = full day.
    private(set) var daylight: Float = 1

    var isNight: Bool { daylight < 0.25 }

    func updateSun(dt: Float) {
        timeOfDay = (timeOfDay + dt / dayLength).truncatingRemainder(dividingBy: 1)
        let ang = timeOfDay * 2 * .pi
        let elev = sin(ang) * 0.95 + 0.3
        let dir = simd_normalize(SIMD3<Float>(cos(ang), elev, 0.35))
        sunNode.simdPosition = dir * 100
        sunNode.look(at: SCNVector3(0, 0, 0))
        sunDisc.simdPosition = dir * 900
        sunDisc.isHidden = dir.y < -0.05
        daylight = smoothstep(-0.05, 0.25, dir.y)
        sunNode.light?.intensity = CGFloat(1300 * daylight)
        ambientNode.light?.intensity = CGFloat(35 + 110 * daylight)
    }

    // MARK: Base buildings

    private func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        m.lightingModel = .blinn
        m.specular.contents = UIColor(white: 0.3, alpha: 1)
        return m
    }

    private func glow(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        return m
    }

    private func buildBase() {
        // Pad under the base.
        let pad = SCNCylinder(radius: 11, height: 0.12)
        pad.materials = [color(0.33, 0.34, 0.37)]
        let padNode = SCNNode(geometry: pad)
        padNode.position = SCNVector3(0, 0.05, -2)
        root.addChildNode(padNode)

        // Dust Silo
        siloPos.y = height(atX: siloPos.x, z: siloPos.z)
        let silo = SCNNode()
        silo.simdPosition = siloPos
        let body = SCNNode(geometry: SCNCylinder(radius: 1.5, height: 4.2))
        body.geometry?.materials = [color(0.85, 0.47, 0.12)]
        body.position = SCNVector3(0, 2.1, 0)
        silo.addChildNode(body)
        for y in [1.0, 2.4, 3.8] {
            let band = SCNNode(geometry: SCNTube(innerRadius: 1.5, outerRadius: 1.56, height: 0.25))
            band.geometry?.materials = [color(0.15, 0.15, 0.18)]
            band.position = SCNVector3(0, Float(y), 0)
            silo.addChildNode(band)
        }
        let cone = SCNNode(geometry: SCNCone(topRadius: 0.4, bottomRadius: 1.55, height: 1.2))
        cone.geometry?.materials = [color(0.75, 0.75, 0.78)]
        cone.position = SCNVector3(0, 4.8, 0)
        silo.addChildNode(cone)
        let hopper = SCNNode(geometry: SCNBox(width: 1.4, height: 0.9, length: 1.0, chamferRadius: 0.08))
        hopper.geometry?.materials = [color(0.25, 0.25, 0.28)]
        hopper.position = SCNVector3(-1.6, 0.9, 0)
        silo.addChildNode(hopper)
        let hopperMouth = SCNNode(geometry: SCNBox(width: 1.1, height: 0.05, length: 0.7, chamferRadius: 0))
        hopperMouth.geometry?.materials = [glow(UIColor(red: 0.2, green: 1, blue: 0.6, alpha: 1))]
        hopperMouth.position = SCNVector3(-1.6, 1.36, 0)
        silo.addChildNode(hopperMouth)
        silo.addChildNode(label("DUST SILO", y: 5.8, color: .white))
        let beacon = SCNNode(geometry: SCNSphere(radius: 0.18))
        beacon.geometry?.materials = [glow(UIColor(red: 1, green: 0.4, blue: 0.1, alpha: 1))]
        beacon.position = SCNVector3(0, 5.5, 0)
        silo.addChildNode(beacon)
        beacons.append(beacon)
        root.addChildNode(silo)
        colliders.append(Collider(x: siloPos.x, z: siloPos.z, r: 1.8))

        // Upgrade Terminal
        terminalPos.y = height(atX: terminalPos.x, z: terminalPos.z)
        let term = SCNNode()
        term.simdPosition = terminalPos
        let stand = SCNNode(geometry: SCNBox(width: 1.3, height: 1.5, length: 0.6, chamferRadius: 0.06))
        stand.geometry?.materials = [color(0.22, 0.24, 0.3)]
        stand.position = SCNVector3(0, 0.75, 0)
        term.addChildNode(stand)
        let screen = SCNNode(geometry: SCNBox(width: 1.1, height: 0.7, length: 0.05, chamferRadius: 0.02))
        screen.geometry?.materials = [glow(UIColor(red: 0.15, green: 0.75, blue: 1, alpha: 1))]
        screen.position = SCNVector3(0, 1.85, 0.12)
        screen.eulerAngles.x = -0.25
        term.addChildNode(screen)
        let screenBack = SCNNode(geometry: SCNBox(width: 1.25, height: 0.85, length: 0.08, chamferRadius: 0.03))
        screenBack.geometry?.materials = [color(0.22, 0.24, 0.3)]
        screenBack.position = SCNVector3(0, 1.85, 0.06)
        screenBack.eulerAngles.x = -0.25
        term.addChildNode(screenBack)
        term.addChildNode(label("UPGRADES", y: 2.6, color: UIColor(red: 0.5, green: 0.9, blue: 1, alpha: 1)))
        // Face the spawn point.
        term.eulerAngles.y = 0.35
        root.addChildNode(term)
        colliders.append(Collider(x: terminalPos.x, z: terminalPos.z, r: 0.9))

        // Lander (decoration)
        let lander = SCNNode()
        lander.position = SCNVector3(0, 0.1, -10)
        let cab = SCNNode(geometry: SCNBox(width: 3, height: 2, length: 3, chamferRadius: 0.3))
        cab.geometry?.materials = [color(0.82, 0.78, 0.55)]
        cab.position = SCNVector3(0, 2.4, 0)
        lander.addChildNode(cab)
        let top = SCNNode(geometry: SCNCylinder(radius: 1.1, height: 1.2))
        top.geometry?.materials = [color(0.85, 0.85, 0.88)]
        top.position = SCNVector3(0, 4, 0)
        lander.addChildNode(top)
        let window = SCNNode(geometry: SCNBox(width: 1.2, height: 0.5, length: 0.05, chamferRadius: 0.05))
        window.geometry?.materials = [glow(UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1))]
        window.position = SCNVector3(0, 4.1, 1.12)
        lander.addChildNode(window)
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 2.4))
            leg.geometry?.materials = [color(0.6, 0.6, 0.62)]
            leg.position = SCNVector3(Float(sx) * 1.9, 1.0, Float(sz) * 1.9)
            leg.eulerAngles = SCNVector3(Float(sz) * 0.35, 0, Float(-sx) * 0.35)
            lander.addChildNode(leg)
            let foot = SCNNode(geometry: SCNCylinder(radius: 0.35, height: 0.08))
            foot.geometry?.materials = [color(0.6, 0.6, 0.62)]
            foot.position = SCNVector3(Float(sx) * 2.3, 0, Float(sz) * 2.3)
            lander.addChildNode(foot)
        }
        lander.addChildNode(label("L.S.D. LANDER 01", y: 5.3, color: .white))
        root.addChildNode(lander)
        colliders.append(Collider(x: 0, z: -10, r: 2.3))

        // Flag
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.03, height: 2.6))
        pole.geometry?.materials = [color(0.85, 0.85, 0.85)]
        pole.position = SCNVector3(-7.5, 1.3, -8)
        root.addChildNode(pole)
        let flag = SCNNode(geometry: SCNBox(width: 1.1, height: 0.65, length: 0.01, chamferRadius: 0))
        flag.geometry?.materials = [color(0.15, 0.55, 0.95)]
        flag.position = SCNVector3(-6.92, 2.25, -8)
        root.addChildNode(flag)

        for b in beacons {
            b.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.15, duration: 0.6),
                                                  .fadeOpacity(to: 1, duration: 0.6)])))
        }
    }

    private func label(_ text: String, y: Float, color: UIColor) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0.02)
        t.font = UIFont.systemFont(ofSize: 0.4, weight: .heavy)
        t.flatness = 0.05
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        t.materials = [m]
        let node = SCNNode(geometry: t)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        node.position = SCNVector3(0, y, 0)
        let bill = SCNBillboardConstraint()
        bill.freeAxes = .Y
        node.constraints = [bill]
        return node
    }

    /// Pushes a point out of building colliders.
    func resolveCollisions(_ p: inout SIMD3<Float>, radius: Float) {
        for c in colliders {
            let dx = p.x - c.x, dz = p.z - c.z
            let d = sqrt(dx * dx + dz * dz)
            let minD = c.r + radius
            if d < minD && d > 0.0001 {
                p.x = c.x + dx / d * minD
                p.z = c.z + dz / d * minD
            }
        }
        let lim = half - 2
        p.x = max(-lim, min(lim, p.x))
        p.z = max(-lim, min(lim, p.z))
    }
}
