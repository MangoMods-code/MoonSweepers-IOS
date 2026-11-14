import UIKit
import SceneKit
import simd

enum WorldDims {
    static let size: Float = 256
    static let half: Float = 128
    static let centerX: Float = 27
    static let centerZ: Float = 15.6
    static var minX: Float { centerX - half }
    static var minZ: Float { centerZ - half }

    static func contains(_ x: Float, _ z: Float, margin: Float) -> Bool {
        let dx = abs(x - centerX), dz = abs(z - centerZ)
        return dx < half - margin && dz < half - margin
    }
}

/// The Moon is split into 12 hexagonal sectors (flat-top hexes, 4 columns x 3 rows).
enum Hex {
    static let radius: Float = 36
    static let home = 4
    static let count = 12

    static let centers: [SIMD2<Float>] = {
        var out: [SIMD2<Float>] = []
        let r = radius
        let rowH = Float(3).squareRoot() * r
        for c in 0..<4 {
            for row in 0..<3 {
                let x = 1.5 * r * Float(c - 1)
                var z = rowH * Float(row - 1)
                if c % 2 == 0 { z += rowH / 2 }
                out.append(SIMD2<Float>(x, z))
            }
        }
        return out
    }()

    static let names: [String] = [
        "Lint Plains", "Mare Crumbs", "Cobweb Ridge",
        "Dustbowl Alpha", "Tranquility Depot", "Crater Row",
        "Bunny Hollow", "The Smudge", "Grit Basin",
        "Static Flats", "Sneeze Valley", "Far Side Annex",
    ]

    static func nearest(_ x: Float, _ z: Float) -> Int {
        var best = 0
        var bestD = Float.greatestFiniteMagnitude
        for (i, c) in centers.enumerated() {
            let dx = x - c.x, dz = z - c.y
            let d = dx * dx + dz * dz
            if d < bestD { bestD = d; best = i }
        }
        return best
    }

    static func corners(_ i: Int) -> [SIMD2<Float>] {
        let c = centers[i]
        var out: [SIMD2<Float>] = []
        for k in 0..<6 {
            let a = Float(k) * Float.pi / 3
            out.append(SIMD2<Float>(c.x + radius * cos(a), c.y + radius * sin(a)))
        }
        return out
    }
}

/// Shared materials and small builders for the station art.
enum Mat {
    static func solid(_ c: UIColor, spec: CGFloat = 0.25) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = c
        m.specular.contents = UIColor(white: spec, alpha: 1)
        m.shininess = 0.35
        return m
    }

    static func glow(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        return m
    }

    static let white = solid(UIColor(white: 0.93, alpha: 1), spec: 0.35)
    static let offWhite = solid(UIColor(white: 0.78, alpha: 1))
    static let orange = solid(UIColor(red: 0.96, green: 0.46, blue: 0.10, alpha: 1), spec: 0.3)
    static let dark = solid(UIColor(white: 0.16, alpha: 1), spec: 0.2)
    static let steel = solid(UIColor(white: 0.55, alpha: 1), spec: 0.6)
    static let solar = solid(UIColor(red: 0.07, green: 0.20, blue: 0.62, alpha: 1), spec: 0.9)
    static let rubber = solid(UIColor(white: 0.08, alpha: 1), spec: 0.05)
    static let bristle = solid(UIColor(white: 0.97, alpha: 1), spec: 0.05)
    static let toolBlue = solid(UIColor(red: 0.20, green: 0.62, blue: 0.98, alpha: 1), spec: 0.5)
    static let warmGlow = glow(UIColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 1))
    static let cyanGlow = glow(UIColor(red: 0.35, green: 0.92, blue: 1.0, alpha: 1))
    static let redGlow = glow(UIColor(red: 1.0, green: 0.25, blue: 0.15, alpha: 1))
    static let greenGlow = glow(UIColor(red: 0.3, green: 1.0, blue: 0.55, alpha: 1))
}

enum Make {
    static func part(_ g: SCNGeometry, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        return n
    }

    static func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, chamfer: CGFloat = 0.03) -> SCNBox {
        SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
    }

    static func hexPrism(radius: CGFloat, height: CGFloat) -> SCNCylinder {
        let c = SCNCylinder(radius: radius, height: height)
        c.radialSegmentCount = 6
        return c
    }

    static func label(_ text: String, size: CGFloat = 0.42, color: UIColor = .white) -> SCNNode {
        let t = SCNText(string: text, extrusionDepth: 0.02)
        t.font = UIFont.systemFont(ofSize: size, weight: .heavy)
        t.flatness = 0.1
        t.materials = [Mat.glow(color)]
        let node = SCNNode(geometry: t)
        let (minB, maxB) = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation((maxB.x + minB.x) / 2, 0, 0)
        let bill = SCNBillboardConstraint()
        bill.freeAxes = .Y
        node.constraints = [bill]
        node.castsShadow = false
        return node
    }

    static func noShadows(_ node: SCNNode) {
        node.castsShadow = false
        node.enumerateChildNodes { n, _ in n.castsShadow = false }
    }

    static func blink(_ node: SCNNode, period: Double = 0.6) {
        node.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.1, duration: period),
                                                 .fadeOpacity(to: 1, duration: period)])))
    }

    /// Chunky flat-shaded boulder.
    static func rockGeometry(seed: Int, subdivisions: Int) -> SCNGeometry {
        let t: Float = (1 + Float(5).squareRoot()) / 2
        let raw: [[Float]] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ]
        var verts: [SIMD3<Float>] = raw.map { simd_normalize(SIMD3<Float>($0[0], $0[1], $0[2])) }
        var faces: [[Int]] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
        ]
        for _ in 0..<subdivisions {
            var cache: [Int: Int] = [:]
            func mid(_ a: Int, _ b: Int) -> Int {
                let key = min(a, b) * 100_000 + max(a, b)
                if let v = cache[key] { return v }
                verts.append(simd_normalize((verts[a] + verts[b]) * 0.5))
                cache[key] = verts.count - 1
                return verts.count - 1
            }
            var next: [[Int]] = []
            for f in faces {
                let ab = mid(f[0], f[1]), bc = mid(f[1], f[2]), ca = mid(f[2], f[0])
                next.append([f[0], ab, ca])
                next.append([f[1], bc, ab])
                next.append([f[2], ca, bc])
                next.append([ab, bc, ca])
            }
            faces = next
        }
        // Lumpy displacement.
        let squash: Float = 0.55 + 0.3 * Noise.hash(seed, 3, 91)
        let shaped: [SIMD3<Float>] = verts.map { v in
            let n1 = Noise.value(v.x * 1.7 + v.y * 2.3 + 10, v.z * 1.7 - v.y * 1.1 + 10, seed: seed)
            let n2 = Noise.value(v.x * 4.1 - v.y * 3.0 + 30, v.z * 4.1 + v.y * 2.2 + 30, seed: seed + 5)
            let r: Float = 0.72 + 0.42 * n1 + 0.14 * n2
            return SIMD3<Float>(v.x * r, v.y * r * squash, v.z * r)
        }
        var pos: [SCNVector3] = []
        var nrm: [SCNVector3] = []
        var idx: [UInt16] = []
        for f in faces {
            let a = shaped[f[0]], b = shaped[f[1]], c = shaped[f[2]]
            var n = simd_cross(b - a, c - a)
            let len = simd_length(n)
            n = len > 0 ? n / len : SIMD3<Float>(0, 1, 0)
            for p in [a, b, c] {
                idx.append(UInt16(pos.count))
                pos.append(SCNVector3(p.x, p.y, p.z))
                nrm.append(SCNVector3(n.x, n.y, n.z))
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}

/// The hand tools, modelled from primitives. Origin is the grip; the head points along -Z.
enum ToolModels {
    static func make(_ index: Int) -> SCNNode {
        let root = SCNNode()
        func add(_ g: SCNGeometry, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float) {
            root.addChildNode(Make.part(g, m, x, y, z))
        }
        func handle(length: CGFloat, radius: CGFloat, material: SCNMaterial) {
            let c = SCNCylinder(radius: radius, height: length)
            c.materials = [material]
            let n = SCNNode(geometry: c)
            n.eulerAngles.x = .pi / 2
            n.position = SCNVector3(0, 0, -Float(length) / 2)
            root.addChildNode(n)
        }
        switch index {
        case 0: // Toothbrush
            add(Make.box(0.014, 0.009, 0.17, chamfer: 0.004), Mat.toolBlue, 0, 0, -0.085)
            add(Make.box(0.016, 0.008, 0.04, chamfer: 0.003), Mat.white, 0, 0, -0.185)
            add(Make.box(0.013, 0.014, 0.034, chamfer: 0.001), Mat.bristle, 0, -0.011, -0.185)
        case 1: // Nail brush
            add(Make.box(0.05, 0.022, 0.10, chamfer: 0.008), Mat.orange, 0, 0, -0.06)
            add(Make.box(0.046, 0.02, 0.094, chamfer: 0.001), Mat.bristle, 0, -0.02, -0.06)
        case 2: // Handbrush
            handle(length: 0.13, radius: 0.012, material: Mat.orange)
            add(Make.box(0.065, 0.022, 0.15, chamfer: 0.008), Mat.orange, 0, 0, -0.2)
            add(Make.box(0.06, 0.035, 0.14, chamfer: 0.001), Mat.bristle, 0, -0.028, -0.2)
        default: // Brooms
            let widths: [CGFloat] = [0.34, 0.56, 0.84]
            let w = widths[max(0, min(2, index - 3))]
            handle(length: 1.15, radius: 0.013, material: Mat.white)
            add(Make.box(w, 0.035, 0.06, chamfer: 0.01), Mat.orange, 0, 0, -1.16)
            add(Make.box(w - 0.01, 0.10, 0.05, chamfer: 0.001), Mat.bristle, 0, -0.065, -1.16)
        }
        Make.noShadows(root)
        return root
    }
}
