import UIKit
import SceneKit
import simd

/// Terrain, boulders, sky, sun and the hex sector grid.
final class MoonWorld {
    let grid = 256
    private(set) var heights: [Float] = []

    struct Collider { let x: Float; let z: Float; let r: Float; let group: Int }
    private(set) var colliders: [Collider] = []
    struct Wall { let a: SIMD2<Float>; let b: SIMD2<Float>; let half: Float; let group: Int }
    /// Collision groups (one per station) that are switched off because nothing is built there.
    var disabledGroups = Set<Int>()
    private(set) var walls: [Wall] = []

    private struct Crater { let x: Float; let z: Float; let r: Float; let depth: Float }
    private var craters: [Crater] = []

    let root = SCNNode()
    let gridNode = SCNNode()
    let waypointNode = SCNNode()
    private let sunNode = SCNNode()
    private let sunDisc = SCNNode()
    private let ambientNode = SCNNode()
    private let earthshineNode = SCNNode()
    private let fillNode = SCNNode()

    /// 0..1 through one lunar day.
    var timeOfDay: Float = 0.06
    let dayLength: Float = 720
    private(set) var daylight: Float = 1
    var isNight: Bool { daylight < 0.2 }
    var nightVision = false

    init(scene: SCNScene, dust: DustField) {
        makeCraters()
        buildHeights()

        let terrainGeo = makeGridGeometry(yOffset: 0)
        terrainGeo.materials = [makeGroundMaterial()]
        let terrain = SCNNode(geometry: terrainGeo)
        terrain.castsShadow = true
        root.addChildNode(terrain)

        let dustGeo = makeGridGeometry(yOffset: 0.04)
        dustGeo.materials = [dust.material]
        let dustNode = SCNNode(geometry: dustGeo)
        dustNode.renderingOrder = 10
        dustNode.castsShadow = false
        root.addChildNode(dustNode)

        scatterRocks()
        buildGridLines()
        buildWaypoint()

        scene.rootNode.addChildNode(root)
        scene.background.contents = MoonWorld.makeStarfield()
        setupLights(scene: scene)
        buildEarth(scene: scene)
        updateSun(dt: 0)
    }

    func addCollider(x: Float, z: Float, r: Float, group: Int = -1) {
        colliders.append(Collider(x: x, z: z, r: r, group: group))
    }

    func addWall(_ a: SIMD2<Float>, _ b: SIMD2<Float>, half: Float = 0.18, group: Int = -1) {
        walls.append(Wall(a: a, b: b, half: half, group: group))
    }

    // MARK: Terrain

    private func makeCraters() {
        var rng = SeededRNG(seed: 0xC0FFEE)
        var list: [Crater] = []
        var tries = 0
        while list.count < 70 && tries < 4000 {
            tries += 1
            let x = WorldDims.centerX + Float.random(in: -120...120, using: &rng)
            let z = WorldDims.centerZ + Float.random(in: -120...120, using: &rng)
            let big = Float.random(in: 0...1, using: &rng) < 0.25
            let r = big ? Float.random(in: 10...22, using: &rng) : Float.random(in: 2.5...9, using: &rng)
            var ok = true
            for (i, c) in Hex.centers.enumerated() {
                let d = simd_length(SIMD2<Float>(x, z) - c)
                let clear: Float = i == Hex.home ? 40 : 22
                if d < clear + r { ok = false; break }
            }
            if !ok { continue }
            list.append(Crater(x: x, z: z, r: r, depth: r * Float.random(in: 0.13...0.24, using: &rng)))
        }
        craters = list
    }

    private func rawHeight(_ x: Float, _ z: Float) -> Float {
        var h = (Noise.value(x / 46 + 7, z / 46 + 3, seed: 1) - 0.5) * 9
        h += (Noise.value(x / 15 + 100, z / 15, seed: 2) - 0.5) * 2.2
        h += (Noise.value(x / 4.5, z / 4.5 + 50, seed: 5) - 0.5) * 0.35
        for c in craters {
            let dx = x - c.x, dz = z - c.z
            let d2 = dx * dx + dz * dz
            let reach = c.r * 1.9
            if d2 > reach * reach { continue }
            let d = d2.squareRoot() / c.r
            if d < 1 { h += c.depth * (d * d - 1) }
            let rim = (d - 1) / 0.3
            h += c.depth * 0.4 * exp(-rim * rim)
        }
        // Ridge around the edge of the map.
        let edge = max(abs(x - WorldDims.centerX), abs(z - WorldDims.centerZ))
        h += smoothstep(WorldDims.half - 16, WorldDims.half, edge) * 12
        // Flat pads under stations.
        var flat: Float = 1
        for (i, c) in Hex.centers.enumerated() {
            let d = simd_length(SIMD2<Float>(x, z) - c)
            let f = i == Hex.home ? smoothstep(26, 42, d) : smoothstep(13, 21, d)
            flat = min(flat, f)
        }
        return h * flat
    }

    private func buildHeights() {
        let n = grid + 1
        let step = WorldDims.size / Float(grid)
        heights = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                heights[j * n + i] = rawHeight(WorldDims.minX + Float(i) * step, WorldDims.minZ + Float(j) * step)
            }
        }
    }

    /// Ground height matching the rendered triangles.
    func height(atX x: Float, z: Float) -> Float {
        let n = grid + 1
        let step = WorldDims.size / Float(grid)
        let fx = max(0, min(Float(grid) - 0.001, (x - WorldDims.minX) / step))
        let fz = max(0, min(Float(grid) - 0.001, (z - WorldDims.minZ) / step))
        let i = Int(fx), j = Int(fz)
        let tx = fx - Float(i), tz = fz - Float(j)
        let h00 = heights[j * n + i]
        let h10 = heights[j * n + i + 1]
        let h01 = heights[(j + 1) * n + i]
        let h11 = heights[(j + 1) * n + i + 1]
        if tx + tz <= 1 {
            return h00 + (h10 - h00) * tx + (h01 - h00) * tz
        }
        return h11 + (h01 - h11) * (1 - tx) + (h10 - h11) * (1 - tz)
    }

    private func makeGridGeometry(yOffset: Float) -> SCNGeometry {
        let n = grid + 1
        let step = WorldDims.size / Float(grid)
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
                let x = WorldDims.minX + Float(i) * step
                let z = WorldDims.minZ + Float(j) * step
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
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts),
                                     SCNGeometrySource(normals: norms),
                                     SCNGeometrySource(textureCoordinates: uvs)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// The clean ground you uncover: pale, smooth "clean silver" with a soft sheen.
    private func makeGroundMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = Tex.tinted(size: 512, tint: SIMD3<Float>(0.97, 0.99, 1.03)) { u, v in
            let a = Noise.fbmTile(u, v, basePeriod: 4, octaves: 4, seed: 21)
            let fine = Noise.hash(Int(u * 512), Int(v * 512), 22)
            return 0.70 + 0.12 * a + 0.03 * fine
        }
        m.normal.contents = Tex.normal(size: 512, strength: 3) { u, v in
            Noise.fbmTile(u, v, basePeriod: 6, octaves: 4, seed: 25)
        }
        let tile = SCNMatrix4MakeScale(64, 64, 1)
        for p in [m.diffuse, m.normal] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
            p.contentsTransform = tile
        }
        m.normal.intensity = 0.6
        m.specular.contents = UIColor(white: 0.22, alpha: 1)
        m.shininess = 0.4
        m.multiply.contents = Tex.tinted(size: 256, tint: SIMD3<Float>(1, 1, 1)) { u, v in
            0.86 + 0.14 * Noise.value(u * 9, v * 9, seed: 71)
        }
        m.isDoubleSided = true
        return m
    }

    // MARK: Boulders

    private func scatterRocks() {
        var rng = SeededRNG(seed: 0xB0B0)
        let tones: [CGFloat] = [0.26, 0.31, 0.36, 0.42]
        var shapes: [SCNGeometry] = []
        for s in 0..<10 {
            let g = Make.rockGeometry(seed: 200 + s, subdivisions: s < 4 ? 2 : 1)
            let m = SCNMaterial()
            m.lightingModel = .lambert
            let t = tones[s % tones.count]
            m.diffuse.contents = UIColor(red: t * 0.95, green: t * 0.97, blue: t * 1.03, alpha: 1)
            g.materials = [m]
            shapes.append(g)
        }
        let kitRocks = ["rocks", "rocksSmall", "rocksTall", "meteorHalf", "meteorFullRound"]
        let kitTones = [UIColor(white: 0.25, alpha: 1), UIColor(white: 0.31, alpha: 1),
                        UIColor(red: 0.34, green: 0.35, blue: 0.38, alpha: 1)]
        var groups: [SCNNode] = (0..<Hex.count).map { _ in SCNNode() }
        var placed = 0
        var tries = 0
        while placed < 420 && tries < 6000 {
            tries += 1
            let x = WorldDims.centerX + Float.random(in: -122...122, using: &rng)
            let z = WorldDims.centerZ + Float.random(in: -122...122, using: &rng)
            let roll = Float.random(in: 0...1, using: &rng)
            let scale: Float = roll < 0.75 ? Float.random(in: 0.15...0.55, using: &rng)
                : (roll < 0.95 ? Float.random(in: 0.7...1.5, using: &rng) : Float.random(in: 1.8...3.2, using: &rng))
            var ok = true
            for (i, c) in Hex.centers.enumerated() {
                let d = simd_length(SIMD2<Float>(x, z) - c)
                if d < (i == Hex.home ? 30 : 14) + scale { ok = false; break }
            }
            if !ok { continue }
            let big = scale >= 0.7
            let y = height(atX: x, z: z)
            let shapeIndex = big ? Int.random(in: 0..<4, using: &rng) : Int.random(in: 4..<10, using: &rng)
            let kitIndex = Int.random(in: 0..<kitRocks.count, using: &rng)
            let toneIndex = Int.random(in: 0..<kitTones.count, using: &rng)
            var node = SCNNode(geometry: shapes[shapeIndex])
            node.position = SCNVector3(x, y + scale * 0.12, z)
            node.scale = SCNVector3(scale, scale, scale)
            // Bigger rocks use the Space Kit models, repainted moon-grey.
            if scale >= 0.4, let kit = Kit.make(kitRocks[kitIndex], fit: scale * 2.3,
                                                tint: kitTones[toneIndex], tintKey: "moon\(toneIndex)") {
                node = kit
                node.position = SCNVector3(x, y - scale * (kitIndex == 4 ? 0.5 : 0.08), z)
            }
            let tiltX = Float.random(in: -0.2...0.2, using: &rng)
            let spin = Float.random(in: 0...6.28, using: &rng)
            let tiltZ = Float.random(in: -0.2...0.2, using: &rng)
            node.eulerAngles = node.geometry == nil ? SCNVector3(0, spin, 0) : SCNVector3(tiltX, spin, tiltZ)
            groups[Hex.nearest(x, z)].addChildNode(node)
            if scale >= 0.9 { addCollider(x: x, z: z, r: scale * 0.8) }
            placed += 1
        }
        for g in groups {
            let flat = g.flattenedClone()
            flat.castsShadow = true
            root.addChildNode(flat)
        }
    }

    // MARK: Hex grid overlay + waypoint

    private func buildGridLines() {
        var verts: [SCNVector3] = []
        var idx: [UInt32] = []
        let halfW: Float = 0.035
        let R = Tile.radius
        for t in 0..<Tile.slots {
            let c = Tile.center(t)
            if !WorldDims.contains(c.x, c.y, margin: 3) { continue }
            // Three of the six edges; neighbours supply the rest.
            for k in 0..<3 {
                let a0 = Float(k) * Float.pi / 3, a1 = Float(k + 1) * Float.pi / 3
                let a = SIMD2<Float>(c.x + R * cos(a0), c.y + R * sin(a0))
                let b = SIMD2<Float>(c.x + R * cos(a1), c.y + R * sin(a1))
                let dir = simd_normalize(b - a)
                let side = SIMD2<Float>(-dir.y, dir.x) * halfW
                let pts = [a, (a + b) * 0.5, b]
                for s in 0..<2 {
                    let p = pts[s], q = pts[s + 1]
                    let py = height(atX: p.x, z: p.y) + 0.14
                    let qy = height(atX: q.x, z: q.y) + 0.14
                    let base = UInt32(verts.count)
                    verts.append(SCNVector3(p.x - side.x, py, p.y - side.y))
                    verts.append(SCNVector3(p.x + side.x, py, p.y + side.y))
                    verts.append(SCNVector3(q.x - side.x, qy, q.y - side.y))
                    verts.append(SCNVector3(q.x + side.x, qy, q.y + side.y))
                    idx.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
                }
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = Mat.glow(UIColor(red: 0.3, green: 0.9, blue: 1, alpha: 0.75))
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        geo.materials = [m]
        gridNode.geometry = geo
        gridNode.castsShadow = false
        gridNode.renderingOrder = 20
        gridNode.isHidden = true
        root.addChildNode(gridNode)
    }

    private func buildWaypoint() {
        let beam = SCNCylinder(radius: 0.25, height: 80)
        let m = Mat.glow(UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.45))
        m.writesToDepthBuffer = false
        m.blendMode = .add
        beam.materials = [m]
        let n = SCNNode(geometry: beam)
        n.position = SCNVector3(0, 40, 0)
        n.castsShadow = false
        waypointNode.addChildNode(n)
        waypointNode.renderingOrder = 30
        waypointNode.isHidden = true
        root.addChildNode(waypointNode)
    }

    func setWaypoint(x: Float, z: Float, visible: Bool) {
        waypointNode.isHidden = !visible
        waypointNode.position = SCNVector3(x, height(atX: x, z: z), z)
    }

    // MARK: Sky

    static func makeStarfield() -> UIImage {
        let w = 2048, h = 1024
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for k in stride(from: 3, to: px.count, by: 4) { px[k] = 255 }
        var rng = SeededRNG(seed: 42)
        for _ in 0..<6500 {
            let x = Int.random(in: 0..<w, using: &rng)
            let y = Int.random(in: 0..<h, using: &rng)
            let b = UInt8.random(in: 70...255, using: &rng)
            let tint = Int.random(in: 0...2, using: &rng)
            let k = (y * w + x) * 4
            px[k] = tint == 2 ? b : UInt8(Int(b) * 9 / 10)
            px[k + 1] = UInt8(Int(b) * 19 / 20)
            px[k + 2] = tint == 0 ? b : UInt8(Int(b) * 9 / 10)
            if b > 225 && x + 1 < w && y + 1 < h {
                for k2 in [k + 4, k + w * 4] {
                    px[k2] = b / 2; px[k2 + 1] = b / 2; px[k2 + 2] = b / 2
                }
            }
        }
        for x in 0..<w {
            let cy = Float(h) * 0.42 + sin(Float(x) / Float(w) * .pi * 2) * 130
            for dy in -70...70 {
                let y = Int(cy) + dy
                if y < 0 || y >= h { continue }
                let fade = 1 - Float(abs(dy)) / 70
                let n = Noise.value(Float(x) / 34, Float(y) / 34, seed: 9)
                let add = Int(20 * fade * fade * n)
                let k = (y * w + x) * 4
                px[k] = UInt8(min(255, Int(px[k]) + add))
                px[k + 1] = UInt8(min(255, Int(px[k + 1]) + add))
                px[k + 2] = UInt8(min(255, Int(px[k + 2]) + add + add / 3))
            }
        }
        return ImageUtil.image(width: w, height: h, rgba: px)
    }

    private func buildEarth(scene: SCNScene) {
        let w = 512, h = 256
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for j in 0..<h {
            let lat = abs(Float(j) / Float(h) - 0.5) * 2
            for i in 0..<w {
                let u = Float(i) / Float(w), v = Float(j) / Float(h)
                let land = Noise.fbmTile(u, v, basePeriod: 5, octaves: 5, seed: 80)
                let cloud = Noise.fbmTile(u, v, basePeriod: 8, octaves: 4, seed: 85)
                var c = SIMD3<Float>(0.05, 0.22, 0.55)
                if land > 0.55 {
                    let g = min(1, (land - 0.55) * 6)
                    c = SIMD3<Float>(0.18 + 0.25 * g, 0.42 - 0.08 * g, 0.16)
                }
                if lat > 0.86 { c = SIMD3<Float>(0.95, 0.96, 1) }
                let cl = smoothstep(0.55, 0.75, cloud)
                c = c + (SIMD3<Float>(1, 1, 1) - c) * cl * 0.85
                let k = (j * w + i) * 4
                px[k] = UInt8(255 * c.x); px[k + 1] = UInt8(255 * c.y); px[k + 2] = UInt8(255 * c.z)
            }
        }
        let tex = ImageUtil.cgImage(width: w, height: h, rgba: px)
        let sphere = SCNSphere(radius: 46)
        sphere.segmentCount = 64
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = tex
        m.emission.contents = tex
        m.emission.intensity = 0.12
        sphere.materials = [m]
        let earth = SCNNode(geometry: sphere)
        earth.position = SCNVector3(-300, 260, -640)
        earth.castsShadow = false
        earth.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 500)))
        scene.rootNode.addChildNode(earth)

        let halo = SCNSphere(radius: 49)
        halo.segmentCount = 48
        let hm = Mat.glow(UIColor(red: 0.3, green: 0.55, blue: 1, alpha: 0.22))
        hm.cullMode = .front
        hm.blendMode = .add
        hm.writesToDepthBuffer = false
        halo.materials = [hm]
        let haloNode = SCNNode(geometry: halo)
        haloNode.position = earth.position
        haloNode.castsShadow = false
        scene.rootNode.addChildNode(haloNode)
    }

    private func setupLights(scene: SCNScene) {
        let sun = SCNLight()
        sun.type = .directional
        sun.color = UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 1)
        sun.intensity = 1500
        sun.castsShadow = true
        sun.shadowColor = UIColor(white: 0, alpha: 0.9)
        sun.shadowRadius = 2.5
        sun.shadowSampleCount = 8
        sun.shadowBias = 2
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 120
        sun.shadowCascadeCount = 3
        sun.shadowCascadeSplittingFactor = 0.3
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(red: 0.62, green: 0.68, blue: 0.8, alpha: 1)
        amb.intensity = 150
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)

        let es = SCNLight()
        es.type = .directional
        es.color = UIColor(red: 0.45, green: 0.6, blue: 1.0, alpha: 1)
        es.intensity = 90
        earthshineNode.light = es
        earthshineNode.position = SCNVector3(-300, 260, -640)
        earthshineNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(earthshineNode)

        // Soft fill from the side opposite the sun, so shadowed walls keep their shape.
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(red: 0.74, green: 0.79, blue: 0.9, alpha: 1)
        fill.intensity = 0
        fill.castsShadow = false
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        let disc = SCNSphere(radius: 20)
        disc.materials = [Mat.glow(UIColor(red: 1, green: 0.99, blue: 0.93, alpha: 1))]
        sunDisc.geometry = disc
        sunDisc.castsShadow = false
        scene.rootNode.addChildNode(sunDisc)
    }

    func setShadowQuality(high: Bool) {
        guard let sun = sunNode.light else { return }
        sun.shadowMapSize = high ? CGSize(width: 2048, height: 2048) : CGSize(width: 1024, height: 1024)
        sun.shadowSampleCount = high ? 8 : 2
        sun.shadowCascadeCount = high ? 3 : 2
        sun.maximumShadowDistance = high ? 120 : 70
    }

    func updateSun(dt: Float) {
        timeOfDay = (timeOfDay + dt / dayLength).truncatingRemainder(dividingBy: 1)
        let ang = timeOfDay * 2 * .pi
        let elev = sin(ang) * 0.75 + 0.22
        let dir = simd_normalize(SIMD3<Float>(cos(ang), elev, 0.4))
        sunNode.simdPosition = SIMD3<Float>(WorldDims.centerX, 0, WorldDims.centerZ) + dir * 150
        sunNode.look(at: SCNVector3(WorldDims.centerX, 0, WorldDims.centerZ))
        let centre = SIMD3<Float>(WorldDims.centerX, 0, WorldDims.centerZ)
        fillNode.simdPosition = centre + simd_normalize(SIMD3<Float>(-dir.x, 0.35, -dir.z)) * 150
        fillNode.look(at: SCNVector3(centre.x, centre.y, centre.z))
        fillNode.light?.intensity = nightVision ? 0 : CGFloat(60 + 300 * daylight)
        sunDisc.simdPosition = dir * 900
        sunDisc.isHidden = dir.y < -0.03
        daylight = smoothstep(-0.04, 0.14, dir.y)
        sunNode.light?.intensity = CGFloat(1500 * daylight)
        sunNode.light?.castsShadow = daylight > 0.02 && !nightVision
        if nightVision {
            ambientNode.light?.intensity = 950
            ambientNode.light?.color = UIColor(red: 0.75, green: 1, blue: 0.8, alpha: 1)
        } else {
            ambientNode.light?.intensity = CGFloat(24 + 96 * daylight)
            ambientNode.light?.color = UIColor(red: 0.62, green: 0.68, blue: 0.8, alpha: 1)
        }
    }

    /// Pushes a point out of obstacles and keeps it on the map.
    func resolveCollisions(_ p: inout SIMD3<Float>, radius: Float) {
        for c in colliders {
            if c.group >= 0 && disabledGroups.contains(c.group) { continue }
            let dx = p.x - c.x, dz = p.z - c.z
            let minD = c.r + radius
            let d2 = dx * dx + dz * dz
            if d2 < minD * minD && d2 > 0.000001 {
                let d = d2.squareRoot()
                p.x = c.x + dx / d * minD
                p.z = c.z + dz / d * minD
            }
        }
        for w in walls {
            if w.group >= 0 && disabledGroups.contains(w.group) { continue }
            let pt = SIMD2<Float>(p.x, p.z)
            let ab = w.b - w.a
            let t = max(0, min(1, simd_dot(pt - w.a, ab) / simd_dot(ab, ab)))
            let c = w.a + ab * t
            let d = pt - c
            let minD = w.half + radius
            let d2 = simd_dot(d, d)
            if d2 < minD * minD && d2 > 0.000001 {
                let len = d2.squareRoot()
                p.x = c.x + d.x / len * minD
                p.z = c.y + d.y / len * minD
            }
        }
        let lim = WorldDims.half - 6
        p.x = max(WorldDims.centerX - lim, min(WorldDims.centerX + lim, p.x))
        p.z = max(WorldDims.centerZ - lim, min(WorldDims.centerZ + lim, p.z))
    }
}
