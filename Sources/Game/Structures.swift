import UIKit
import SceneKit
import simd

/// The home station, the eleven outposts, the flags and every buildable machine.
final class Structures {
    let root = SCNNode()

    let depotPos = SIMD3<Float>(7, 0, -4)
    let wallPos = SIMD3<Float>(-7, 0, -4)
    let matrixPos = SIMD3<Float>(0, 0, -9)
    let garagePos = SIMD3<Float>(-17, 0, -12)
    let vehicleSpawn = SIMD3<Float>(-17, 0, -3)
    let catcherPos = SIMD3<Float>(9, 0, -15)
    let botDock = SIMD3<Float>(4, 0, 2)

    /// Intake position for each sector's station (home = the depot).
    private(set) var stationPos: [SIMD3<Float>] = []
    private(set) var flagPos: [SIMD3<Float>] = []

    private var outpostBeacons: [SCNNode?] = []
    private var outpostRings: [SCNNode?] = []
    private var flagCloths: [SCNNode] = []
    private let garageNode = SCNNode()
    private let garageSign = SCNNode()
    private let packagerNode = SCNNode()
    private let chamberNode = SCNNode()
    private let pressNode = SCNNode()
    private let batteryNode = SCNNode()
    private let catcherNode = SCNNode()
    private let conveyorNode = SCNNode()
    private var launchTop: SIMD3<Float> { depotPos + SIMD3<Float>(1.9, 6.2, 0) }

    init(world: MoonWorld) {
        buildHome(world: world)
        buildOutposts(world: world)
        buildFlags(world: world)
    }

    private func add(_ node: SCNNode, at p: SIMD3<Float>, yaw: Float = 0) {
        node.simdPosition = p
        node.eulerAngles.y = yaw
        root.addChildNode(node)
    }

    private func hexPad(radius: CGFloat) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(Make.part(Make.hexPrism(radius: radius, height: 0.08), Mat.offWhite, 0, 0.03, 0))
        let rim = SCNTube(innerRadius: radius - 0.25, outerRadius: radius, height: 0.1)
        rim.radialSegmentCount = 6
        n.addChildNode(Make.part(rim, Mat.orange, 0, 0.035, 0))
        Make.noShadows(n)
        return n
    }

    // MARK: Home station

    private func buildHome(world: MoonWorld) {
        // Hexagonal foundations.
        for (x, z, r) in [(0.0, -6.0, 9.0), (-15.6, -12.0, 7.0), (15.6, -12.0, 7.0), (0.0, -21.0, 7.0)] {
            add(hexPad(radius: CGFloat(r)), at: SIMD3<Float>(Float(x), 0, Float(z)), yaw: .pi / 6)
        }

        // Depot: intake funnel + launch rail.
        let depot = SCNNode()
        depot.addChildNode(Make.part(Make.hexPrism(radius: 1.5, height: 1.3), Mat.white, 0, 0.65, 0))
        depot.addChildNode(Make.part(SCNTube(innerRadius: 1.5, outerRadius: 1.56, height: 0.22), Mat.orange, 0, 0.4, 0))
        let funnel = SCNCone(topRadius: 1.25, bottomRadius: 0.5, height: 0.8)
        depot.addChildNode(Make.part(funnel, Mat.orange, 0, 1.7, 0))
        depot.addChildNode(Make.part(SCNCylinder(radius: 1.1, height: 0.04), Mat.greenGlow, 0, 2.0, 0))
        depot.addChildNode(Make.part(SCNCylinder(radius: 0.42, height: 6), Mat.white, 1.9, 3, 0))
        for y in [1.2, 3.0, 4.8] {
            depot.addChildNode(Make.part(SCNTube(innerRadius: 0.42, outerRadius: 0.47, height: 0.3), Mat.orange, 1.9, Float(y), 0))
        }
        depot.addChildNode(Make.part(SCNCone(topRadius: 0.55, bottomRadius: 0.42, height: 0.4), Mat.dark, 1.9, 6.2, 0))
        let lbl = Make.label("DEPOT")
        lbl.position = SCNVector3(0, 3.0, 0)
        depot.addChildNode(lbl)
        add(depot, at: depotPos)
        world.addCollider(x: depotPos.x, z: depotPos.z, r: 1.7)
        world.addCollider(x: depotPos.x + 1.9, z: depotPos.z, r: 0.6)

        // Supply Wall with the tools hung on it.
        let wall = SCNNode()
        wall.addChildNode(Make.part(Make.box(5.2, 2.9, 0.35), Mat.white, 0, 1.45, 0))
        wall.addChildNode(Make.part(Make.box(5.4, 0.3, 0.45), Mat.orange, 0, 3.0, 0))
        wall.addChildNode(Make.part(Make.box(5.2, 0.12, 0.7), Mat.dark, 0, 0.9, 0.3))
        wall.addChildNode(Make.part(Make.box(4.8, 0.05, 0.02, chamfer: 0), Mat.cyanGlow, 0, 2.75, 0.19))
        for i in 0..<Catalog.tools.count {
            let t = ToolModels.make(i)
            t.position = SCNVector3(-2.1 + Float(i) * 0.84, i >= 3 ? 2.5 : 2.0, 0.24)
            t.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            t.scale = i >= 3 ? SCNVector3(1.2, 1.2, 1.2) : SCNVector3(2.4, 2.4, 2.4)
            wall.addChildNode(t)
        }
        let wl = Make.label("SUPPLY WALL")
        wl.position = SCNVector3(0, 3.4, 0)
        wall.addChildNode(wl)
        add(wall, at: wallPos, yaw: 0.5)
        world.addCollider(x: wallPos.x - 1.4, z: wallPos.z + 0.7, r: 1.0)
        world.addCollider(x: wallPos.x, z: wallPos.z, r: 1.0)
        world.addCollider(x: wallPos.x + 1.4, z: wallPos.z - 0.7, r: 1.0)

        // Upgrade Matrix: console with a hologram globe.
        let matrix = SCNNode()
        matrix.addChildNode(Make.part(Make.hexPrism(radius: 1.1, height: 0.7), Mat.dark, 0, 0.35, 0))
        let ring = SCNTube(innerRadius: 0.95, outerRadius: 1.15, height: 0.1)
        ring.radialSegmentCount = 6
        matrix.addChildNode(Make.part(ring, Mat.orange, 0, 0.72, 0))
        matrix.addChildNode(Make.part(SCNCylinder(radius: 0.7, height: 0.03), Mat.cyanGlow, 0, 0.74, 0))
        let wire = Mat.glow(UIColor(red: 0.4, green: 0.95, blue: 1, alpha: 0.9))
        wire.fillMode = .lines
        wire.isDoubleSided = true
        let globeGeo = SCNSphere(radius: 0.75)
        globeGeo.segmentCount = 18
        let globe = Make.part(globeGeo, wire, 0, 1.9, 0)
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)))
        matrix.addChildNode(globe)
        let core = Mat.glow(UIColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 0.22))
        core.writesToDepthBuffer = false
        core.blendMode = .add
        matrix.addChildNode(Make.part(SCNSphere(radius: 0.72), core, 0, 1.9, 0))
        let beamMat = Mat.glow(UIColor(red: 0.3, green: 0.9, blue: 1, alpha: 0.12))
        beamMat.writesToDepthBuffer = false
        beamMat.blendMode = .add
        beamMat.isDoubleSided = true
        matrix.addChildNode(Make.part(SCNCone(topRadius: 0.75, bottomRadius: 0.2, height: 1.1), beamMat, 0, 1.3, 0))
        let holoLight = SCNLight()
        holoLight.type = .omni
        holoLight.color = UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1)
        holoLight.intensity = 260
        holoLight.attenuationStartDistance = 1
        holoLight.attenuationEndDistance = 9
        let hl = SCNNode()
        hl.light = holoLight
        hl.position = SCNVector3(0, 2.2, 0)
        matrix.addChildNode(hl)
        let ml = Make.label("UPGRADE MATRIX", color: UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1))
        ml.position = SCNVector3(0, 3.0, 0)
        matrix.addChildNode(ml)
        Make.noShadows(matrix)
        add(matrix, at: matrixPos)
        world.addCollider(x: matrixPos.x, z: matrixPos.z, r: 1.3)

        // Habitat dome.
        let hab = SCNNode()
        hab.addChildNode(Make.part(SCNCylinder(radius: 4, height: 3.2), Mat.white, 0, 1.6, 0))
        let dome = Make.part(SCNSphere(radius: 4), Mat.white, 0, 3.2, 0)
        dome.scale = SCNVector3(1, 0.5, 1)
        hab.addChildNode(dome)
        hab.addChildNode(Make.part(SCNTube(innerRadius: 4, outerRadius: 4.06, height: 0.5), Mat.orange, 0, 2.6, 0))
        hab.addChildNode(Make.part(Make.box(2.2, 2.5, 1.6, chamfer: 0.1), Mat.offWhite, 0, 1.25, 4.3))
        hab.addChildNode(Make.part(Make.box(1.3, 1.9, 0.06, chamfer: 0.02), Mat.warmGlow, 0, 1.05, 5.11))
        for a in [-0.9, 0.9, 2.2, -2.2] {
            let w = Make.part(Make.box(0.9, 0.6, 0.1, chamfer: 0.05), Mat.warmGlow, sin(Float(a)) * 4.0, 2.0, cos(Float(a)) * 4.0)
            w.eulerAngles.y = Float(a)
            hab.addChildNode(w)
        }
        hab.addChildNode(Make.part(SCNCylinder(radius: 0.05, height: 3), Mat.steel, 1.5, 6.3, 0))
        let tip = Make.part(SCNSphere(radius: 0.12), Mat.redGlow, 1.5, 7.9, 0)
        Make.blink(tip)
        hab.addChildNode(tip)
        let hlab = Make.label("L.S.D. STATION 01", size: 0.5)
        hlab.position = SCNVector3(0, 5.6, 0)
        hab.addChildNode(hlab)
        let doorLight = SCNLight()
        doorLight.type = .omni
        doorLight.color = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        doorLight.intensity = 420
        doorLight.attenuationStartDistance = 2
        doorLight.attenuationEndDistance = 22
        let dl = SCNNode()
        dl.light = doorLight
        dl.position = SCNVector3(0, 3.2, 7.5)
        hab.addChildNode(dl)
        add(hab, at: SIMD3<Float>(0, 0, -21))
        world.addCollider(x: 0, z: -21, r: 4.3)
        world.addCollider(x: 0, z: -16.6, r: 1.4)

        // Storage tanks.
        for (i, x) in [-9.0, -5.4].enumerated() {
            let tank = SCNNode()
            tank.addChildNode(Make.part(SCNCylinder(radius: 1.5, height: 3.4), Mat.white, 0, 2.2, 0))
            tank.addChildNode(Make.part(SCNSphere(radius: 1.5), Mat.white, 0, 3.9, 0))
            tank.addChildNode(Make.part(SCNTube(innerRadius: 1.5, outerRadius: 1.55, height: 0.35), Mat.orange, 0, 1.4, 0))
            tank.addChildNode(Make.part(SCNCylinder(radius: 1.2, height: 0.5), Mat.dark, 0, 0.25, 0))
            add(tank, at: SIMD3<Float>(Float(x), 0, -24 + Float(i) * 1.2))
            world.addCollider(x: Float(x), z: -24 + Float(i) * 1.2, r: 1.7)
        }

        // Solar field.
        for row in 0..<2 {
            for col in 0..<3 {
                let panel = SCNNode()
                panel.addChildNode(Make.part(SCNCylinder(radius: 0.08, height: 1.6), Mat.steel, 0, 0.8, 0))
                let p = SCNNode()
                p.addChildNode(Make.part(Make.box(3.0, 0.06, 1.7, chamfer: 0.01), Mat.solar, 0, 0, 0))
                p.addChildNode(Make.part(Make.box(3.1, 0.04, 1.8, chamfer: 0.01), Mat.white, 0, -0.04, 0))
                for k in -1...1 {
                    p.addChildNode(Make.part(Make.box(0.03, 0.07, 1.7, chamfer: 0), Mat.white, Float(k) * 0.75, 0.005, 0))
                }
                p.position = SCNVector3(0, 1.7, 0)
                p.eulerAngles.x = -0.5
                panel.addChildNode(p)
                add(panel, at: SIMD3<Float>(13.5 + Float(col) * 3.6, 0, -10.5 - Float(row) * 3.2), yaw: 0.2)
            }
        }
        batteryNode.addChildNode(Make.part(Make.box(1.8, 1.2, 1.0, chamfer: 0.06), Mat.white, 0, 0.6, 0))
        batteryNode.addChildNode(Make.part(Make.box(1.5, 0.12, 0.04, chamfer: 0), Mat.greenGlow, 0, 0.9, 0.51))
        batteryNode.addChildNode(Make.part(Make.box(1.82, 0.2, 1.02, chamfer: 0.02), Mat.orange, 0, 0.2, 0))
        add(batteryNode, at: SIMD3<Float>(12, 0, -8))

        // Processing line east of the depot.
        packagerNode.addChildNode(Make.part(Make.box(1.6, 1.4, 1.6, chamfer: 0.08), Mat.orange, 0, 0.7, 0))
        packagerNode.addChildNode(Make.part(SCNCone(topRadius: 0.8, bottomRadius: 0.4, height: 0.6), Mat.dark, 0, 1.7, 0))
        packagerNode.addChildNode(Make.part(Make.box(0.6, 0.3, 0.04, chamfer: 0), Mat.cyanGlow, 0, 0.9, 0.81))
        let pl = Make.label("PACKAGER", size: 0.3)
        pl.position = SCNVector3(0, 2.3, 0)
        packagerNode.addChildNode(pl)
        add(packagerNode, at: SIMD3<Float>(11.5, 0, 0.5))

        let cap = SCNCapsule(capRadius: 0.9, height: 3.2)
        let ch = Make.part(cap, Mat.white, 0, 1.3, 0)
        ch.eulerAngles.z = .pi / 2
        chamberNode.addChildNode(ch)
        chamberNode.addChildNode(Make.part(Make.box(2.2, 0.5, 1.4, chamfer: 0.05), Mat.dark, 0, 0.25, 0))
        chamberNode.addChildNode(Make.part(SCNTube(innerRadius: 0.9, outerRadius: 0.96, height: 0.3), Mat.orange, 0, 1.3, 0))
        chamberNode.childNodes.last?.eulerAngles.z = .pi / 2
        chamberNode.addChildNode(Make.part(SCNCylinder(radius: 0.2, height: 0.05), Mat.warmGlow, 0, 1.6, 0.9))
        chamberNode.childNodes.last?.eulerAngles.x = .pi / 2
        let cl = Make.label("PRESSURE CHAMBER", size: 0.3)
        cl.position = SCNVector3(0, 2.7, 0)
        chamberNode.addChildNode(cl)
        add(chamberNode, at: SIMD3<Float>(15.5, 0, 0.5))

        pressNode.addChildNode(Make.part(Make.box(2.0, 0.6, 2.0, chamfer: 0.05), Mat.dark, 0, 0.3, 0))
        for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            pressNode.addChildNode(Make.part(SCNCylinder(radius: 0.12, height: 3), Mat.steel, Float(sx) * 0.8, 2.0, Float(sz) * 0.8))
        }
        pressNode.addChildNode(Make.part(Make.box(2.0, 0.5, 2.0, chamfer: 0.05), Mat.orange, 0, 3.6, 0))
        let piston = Make.part(Make.box(1.3, 0.7, 1.3, chamfer: 0.05), Mat.white, 0, 2.6, 0)
        piston.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: -1.5, z: 0, duration: 0.35),
                                                   .wait(duration: 0.2),
                                                   .moveBy(x: 0, y: 1.5, z: 0, duration: 0.9),
                                                   .wait(duration: 0.4)])))
        pressNode.addChildNode(piston)
        let sl = Make.label("STONE PRESS", size: 0.3)
        sl.position = SCNVector3(0, 4.3, 0)
        pressNode.addChildNode(sl)
        add(pressNode, at: SIMD3<Float>(19.5, 0, 0.5))

        // Conveyor from the machines back to the depot, with capsules riding it.
        let belt = Make.part(Make.box(12.5, 0.1, 0.7, chamfer: 0.01), Mat.rubber, 13.5, 0.55, -1.6)
        conveyorNode.addChildNode(belt)
        conveyorNode.addChildNode(Make.part(Make.box(12.5, 0.16, 0.06, chamfer: 0), Mat.orange, 13.5, 0.6, -1.25))
        conveyorNode.addChildNode(Make.part(Make.box(12.5, 0.16, 0.06, chamfer: 0), Mat.orange, 13.5, 0.6, -1.95))
        for k in 0..<6 {
            conveyorNode.addChildNode(Make.part(SCNCylinder(radius: 0.05, height: 0.55), Mat.steel, 7.8 + Float(k) * 2.3, 0.27, -1.6))
        }
        for k in 0..<5 {
            let c = Make.part(SCNCapsule(capRadius: 0.16, height: 0.55), Mat.orange, 19.5, 0.76, -1.6)
            c.eulerAngles.z = .pi / 2
            let travel = SCNAction.sequence([.moveBy(x: -11.5, y: 0, z: 0, duration: 7),
                                             .moveBy(x: 11.5, y: 0, z: 0, duration: 0)])
            c.runAction(.sequence([.wait(duration: Double(k) * 1.4), .repeatForever(travel)]))
            conveyorNode.addChildNode(c)
        }
        Make.noShadows(conveyorNode)
        root.addChildNode(conveyorNode)

        // Capsule Catcher.
        let net = SCNCone(topRadius: 2.6, bottomRadius: 0.5, height: 1.7)
        let netMat = Mat.solid(UIColor(red: 0.96, green: 0.46, blue: 0.10, alpha: 1))
        netMat.isDoubleSided = true
        catcherNode.addChildNode(Make.part(net, netMat, 0, 3.0, 0))
        catcherNode.addChildNode(Make.part(SCNTube(innerRadius: 2.55, outerRadius: 2.7, height: 0.14), Mat.white, 0, 3.85, 0))
        for k in 0..<3 {
            let a = Float(k) * 2.094
            let leg = Make.part(SCNCylinder(radius: 0.07, height: 2.6), Mat.steel, cos(a) * 1.0, 1.2, sin(a) * 1.0)
            catcherNode.addChildNode(leg)
        }
        catcherNode.addChildNode(Make.part(Make.hexPrism(radius: 0.8, height: 0.8), Mat.white, 0, 0.4, 0))
        let kl = Make.label("CAPSULE CATCHER", size: 0.3)
        kl.position = SCNVector3(0, 4.4, 0)
        catcherNode.addChildNode(kl)
        add(catcherNode, at: catcherPos)

        // Garage plot.
        garageSign.addChildNode(Make.part(SCNCylinder(radius: 0.06, height: 1.4), Mat.steel, 0, 0.7, 0))
        garageSign.addChildNode(Make.part(Make.box(1.0, 0.6, 0.08), Mat.orange, 0, 1.5, 0))
        garageSign.addChildNode(Make.part(Make.box(0.8, 0.4, 0.02, chamfer: 0), Mat.cyanGlow, 0, 1.5, 0.05))
        let gl = Make.label("GARAGE")
        gl.position = SCNVector3(0, 2.1, 0)
        garageSign.addChildNode(gl)
        add(garageSign, at: garagePos + SIMD3<Float>(4.6, 0, 5))

        garageNode.addChildNode(Make.part(Make.box(8, 4.2, 0.3), Mat.white, 0, 2.1, -4))
        garageNode.addChildNode(Make.part(Make.box(0.3, 4.2, 8), Mat.white, -4, 2.1, 0))
        garageNode.addChildNode(Make.part(Make.box(0.3, 4.2, 8), Mat.white, 4, 2.1, 0))
        garageNode.addChildNode(Make.part(Make.box(8.6, 0.3, 8.6), Mat.offWhite, 0, 4.35, 0))
        garageNode.addChildNode(Make.part(Make.box(8.3, 0.6, 0.2), Mat.orange, 0, 3.9, 4.1))
        garageNode.addChildNode(Make.part(Make.box(7.4, 0.08, 0.05, chamfer: 0), Mat.warmGlow, 0, 3.55, 4.0))
        add(garageNode, at: garagePos)
        world.addCollider(x: garagePos.x - 4, z: garagePos.z - 2, r: 0.9)
        world.addCollider(x: garagePos.x + 4, z: garagePos.z - 2, r: 0.9)

        // Lamp posts.
        for (x, z) in [(-3.5, 3.0), (3.5, 3.0), (11.0, -6.5), (-11.0, -6.5)] {
            let post = SCNNode()
            post.addChildNode(Make.part(SCNCylinder(radius: 0.05, height: 3), Mat.steel, 0, 1.5, 0))
            post.addChildNode(Make.part(SCNSphere(radius: 0.16), Mat.warmGlow, 0, 3.05, 0))
            Make.noShadows(post)
            add(post, at: SIMD3<Float>(Float(x), 0, Float(z)))
        }
    }

    // MARK: Outposts and flags

    private func buildOutposts(world: MoonWorld) {
        for i in 0..<Hex.count {
            if i == Hex.home {
                stationPos.append(depotPos)
                outpostBeacons.append(nil)
                outpostRings.append(nil)
                continue
            }
            let c = Hex.centers[i]
            let y = world.height(atX: c.x, z: c.y)
            let p = SIMD3<Float>(c.x, y, c.y)
            stationPos.append(p)
            let n = SCNNode()
            n.addChildNode(hexPad(radius: 3.4))
            n.addChildNode(Make.part(Make.hexPrism(radius: 0.9, height: 1.0), Mat.white, 0, 0.5, 0))
            n.addChildNode(Make.part(SCNCone(topRadius: 0.85, bottomRadius: 0.4, height: 0.5), Mat.orange, 0, 1.25, 0))
            n.addChildNode(Make.part(SCNCylinder(radius: 0.07, height: 7), Mat.steel, 1.6, 3.5, -1.2))
            let beacon = Make.part(SCNSphere(radius: 0.22), Mat.redGlow, 1.6, 7.1, -1.2)
            Make.blink(beacon, period: 0.8)
            n.addChildNode(beacon)
            let ringGeo = SCNTube(innerRadius: 1.25, outerRadius: 1.45, height: 0.04)
            let ring = Make.part(ringGeo, Mat.cyanGlow, -1.3, 0.1, 1.4)
            ring.isHidden = true
            n.addChildNode(ring)
            let l = Make.label(String(format: "STATION %02d · %@", i + 1, Hex.names[i].uppercased()), size: 0.34)
            l.position = SCNVector3(0, 2.4, 0)
            n.addChildNode(l)
            add(n, at: p)
            world.addCollider(x: p.x, z: p.z, r: 1.1)
            outpostBeacons.append(beacon)
            outpostRings.append(ring)
        }
    }

    private func buildFlags(world: MoonWorld) {
        var rng = SeededRNG(seed: 0xF1A6)
        for s in 0..<Hex.count {
            let c = Hex.centers[s]
            var made = 0
            var tries = 0
            while made < 3 && tries < 200 {
                tries += 1
                let a = Float.random(in: 0..<6.283, using: &rng)
                let d = Float.random(in: (s == Hex.home ? 26 : 13)...31, using: &rng)
                let x = c.x + cos(a) * d, z = c.y + sin(a) * d
                if !WorldDims.contains(x, z, margin: 10) { continue }
                let p = SIMD3<Float>(x, world.height(atX: x, z: z), z)
                flagPos.append(p)
                let n = SCNNode()
                n.addChildNode(Make.part(SCNCylinder(radius: 0.035, height: 2.6), Mat.steel, 0, 1.3, 0))
                let cloth = Make.part(Make.box(1.0, 0.6, 0.02, chamfer: 0), Mat.orange, 0.52, 2.25, 0)
                n.addChildNode(cloth)
                flagCloths.append(cloth)
                add(n, at: p, yaw: a)
                made += 1
            }
            while made < 3 { // fallback so there are always 36
                flagPos.append(SIMD3<Float>(c.x + 14, world.height(atX: c.x + 14, z: c.y + Float(made) * 3), c.y + Float(made) * 3))
                let cloth = SCNNode()
                flagCloths.append(cloth)
                made += 1
            }
        }
    }

    // MARK: State

    func refresh(_ s: SaveData) {
        garageNode.isHidden = !s.hasGarage
        packagerNode.isHidden = !s.hasPackager
        chamberNode.isHidden = !s.hasChamber
        pressNode.isHidden = !s.hasPress
        batteryNode.isHidden = !s.hasBattery
        catcherNode.isHidden = !s.hasCatcher
        conveyorNode.isHidden = !s.hasPackager
        for i in 0..<Hex.count {
            let found = i < s.stationsFound.count && s.stationsFound[i]
            outpostBeacons[i]?.geometry?.materials = [found ? Mat.greenGlow : Mat.redGlow]
            outpostRings[i]?.isHidden = !found
        }
        let claimed = Mat.solid(UIColor(red: 0.15, green: 0.5, blue: 0.95, alpha: 1))
        for (i, cloth) in flagCloths.enumerated() {
            let done = i < s.flagsClaimed.count && s.flagsClaimed[i]
            cloth.geometry?.materials = [done ? claimed : Mat.orange]
        }
    }

    /// A shipment capsule rockets off from the depot rail (or straight up from an outpost).
    func launchShipment(from station: Int) {
        let start: SIMD3<Float> = station == Hex.home ? launchTop : stationPos[station] + SIMD3<Float>(0, 1.6, 0)
        let c = Make.part(SCNCapsule(capRadius: 0.2, height: 0.75), Mat.glow(UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1)), 0, 0, 0)
        c.simdPosition = start
        c.castsShadow = false
        root.addChildNode(c)
        let up = SCNAction.moveBy(x: 0, y: 160, z: 0, duration: 1.8)
        up.timingMode = .easeIn
        c.runAction(.sequence([up, .removeFromParentNode()]))
    }
}
