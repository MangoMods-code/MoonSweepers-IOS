import UIKit
import SceneKit
import simd

/// The twelve dust stations (you start inside the first one), the flags, and everything
/// that only appears once you build it: machines, solar field, Capsule Catcher, Garage.
final class Structures {
    let root = SCNNode()

    // Home-station build plots (nothing stands on them until bought).
    let garagePos = SIMD3<Float>(-20, 0, 2)
    let vehicleSpawn = SIMD3<Float>(-20, 0, 12)
    let catcherPos = SIMD3<Float>(-13, 0, -13)
    let botDock = SIMD3<Float>(10, 0, 9)

    // Offsets inside every station, relative to its centre.
    static let spawnOffset = SIMD3<Float>(0, 0, 2.2)
    static let intakeOffset = SIMD3<Float>(4.7, 0, -1.3)
    static let wallOffset = SIMD3<Float>(-5.4, 0, -0.5)
    static let matrixOffset = SIMD3<Float>(0, 0, -1.9)
    static let launcherOffset = SIMD3<Float>(5.7, 8.6, -3.7)

    private(set) var stationPos: [SIMD3<Float>] = []
    private(set) var flagPos: [SIMD3<Float>] = []

    private var beacons: [SCNNode] = []
    private var stationNodes: [[SCNNode]] = []
    private var wallTools: [[SCNNode]] = []
    private weak var world: MoonWorld?
    private var flagCloths: [SCNNode] = []
    private let interiorLights = SCNNode()
    private var litStation = -1
    private let garageNode = SCNNode()
    private let packagerNode = SCNNode()
    private let chamberNode = SCNNode()
    private let pressNode = SCNNode()
    private let powerNode = SCNNode()
    private let batteryNode = SCNNode()
    private let catcherNode = SCNNode()
    private let dockNode = SCNNode()

    private let plateWhite: SCNMaterial = {
        let m = Mat.solid(UIColor(white: 0.9, alpha: 1), spec: 0.2)
        m.isDoubleSided = true
        return m
    }()
    private let plateOrange: SCNMaterial = {
        let m = Mat.solid(Kit.orange)
        m.isDoubleSided = true
        return m
    }()
    private let floorMat = Mat.solid(UIColor(white: 0.34, alpha: 1), spec: 0.3)

    init(world: MoonWorld) {
        self.world = world
        for i in 0..<Hex.count {
            let c = Hex.centers[i]
            let p = SIMD3<Float>(c.x, world.height(atX: c.x, z: c.y), c.y)
            stationPos.append(p)
            buildStation(i, at: p, world: world)
        }
        buildInteriorLights()
        buildHomePlots(world: world)
        buildFlags(world: world)
    }

    func intakePos(_ i: Int) -> SIMD3<Float> { stationPos[i] + Structures.intakeOffset }
    func wallUsePos(_ i: Int) -> SIMD3<Float> { stationPos[i] + Structures.wallOffset }
    func matrixUsePos(_ i: Int) -> SIMD3<Float> { stationPos[i] + Structures.matrixOffset }
    func spawnPos(_ i: Int) -> SIMD3<Float> { stationPos[i] + Structures.spawnOffset }

    private func add(_ node: SCNNode, at p: SIMD3<Float>, yaw: Float = 0) {
        node.simdPosition = p
        node.eulerAngles.y = yaw
        root.addChildNode(node)
    }

    private func hexPad(radius: Float) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(Make.part(Make.hexPlate(radius: radius + 0.3, height: 0.06), plateOrange, 0, 0, 0))
        n.addChildNode(Make.part(Make.hexPlate(radius: radius, height: 0.09), plateWhite, 0, 0, 0))
        Make.noShadows(n)
        return n
    }

    // MARK: Station building

    /// One walk-in dust station. Local axes: door on +Z, service table at the back (-Z),
    /// supply wall on the left (-X), deposit intake and launcher on the right (+X).
    private func buildStation(_ i: Int, at p: SIMD3<Float>, world: MoonWorld) {
        let shell = SCNNode()
        let signs = SCNNode()
        let signsLit = SCNNode()
        let H: Float = 4.2
        func put(_ g: SCNGeometry, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float) {
            shell.addChildNode(Make.part(g, m, x, y, z))
        }
        func wall(_ w: CGFloat, _ l: CGFloat, _ x: Float, _ z: Float) {
            put(Make.box(w, CGFloat(H), l, chamfer: 0.02), Mat.white, x, H / 2 + 0.09, z)
        }
        shell.addChildNode(hexPad(radius: 10.5))
        put(Make.box(13.7, 0.05, 9.7, chamfer: 0), floorMat, 0, 0.11, 0)
        wall(14.3, 0.3, 0, -5)
        wall(0.3, 10, -7, 0)
        wall(0.3, 10, 7, 0)
        wall(5.4, 0.3, -4.3, 5)
        wall(5.4, 0.3, 4.3, 5)
        put(Make.box(3.2, 1.3, 0.3, chamfer: 0.02), Mat.white, 0, 3.64, 5)
        // Orange trim.
        put(Make.box(14.5, 0.35, 0.36, chamfer: 0.02), Mat.orange, 0, 3.2, 5)
        put(Make.box(14.5, 0.35, 0.36, chamfer: 0.02), Mat.orange, 0, 3.2, -5)
        put(Make.box(0.36, 0.35, 10.2, chamfer: 0.02), Mat.orange, -7, 3.2, 0)
        put(Make.box(0.36, 0.35, 10.2, chamfer: 0.02), Mat.orange, 7, 3.2, 0)
        put(Make.box(0.25, 3.0, 0.4, chamfer: 0.02), Mat.orange, -1.72, 1.6, 5)
        put(Make.box(0.25, 3.0, 0.4, chamfer: 0.02), Mat.orange, 1.72, 1.6, 5)
        // Roof, launcher and mast.
        put(Make.box(14.8, 0.3, 10.8, chamfer: 0.05), Mat.offWhite, 0, H + 0.24, 0)
        put(Make.archRoof(width: 15.2, length: 11.2, rise: 2.5), plateOrange, 0, H + 0.38, 0)
        put(Make.archRoof(width: 15.36, length: 1.3, rise: 2.58), plateWhite, 0, H + 0.38, 3.4)
        put(Make.archRoof(width: 15.36, length: 0.5, rise: 2.58), plateWhite, 0, H + 0.38, -4.2)
        put(SCNCylinder(radius: 0.5, height: 4), Mat.white, 5.7, H + 2.3, -3.7)
        for y in [0.9, 2.2, 3.5] {
            put(SCNTube(innerRadius: 0.5, outerRadius: 0.56, height: 0.3), Mat.orange, 5.7, H + 0.3 + Float(y), -3.7)
        }
        put(SCNCone(topRadius: 0.65, bottomRadius: 0.5, height: 0.4), Mat.dark, 5.7, H + 4.5, -3.7)
        put(SCNCylinder(radius: 0.05, height: 4), Mat.steel, -5.5, H + 2.3, -3.5)
        // Windows (thicker than the wall so they glow on both sides).
        for z in [-2.4, 2.0] {
            put(Make.box(0.34, 0.8, 2.2, chamfer: 0.02), Mat.warmGlow, 7, 2.4, Float(z))
        }
        // Ceiling light panels.
        put(Make.box(2.4, 0.05, 0.6, chamfer: 0), Mat.warmGlow, -3.5, H + 0.06, 0)
        put(Make.box(2.4, 0.05, 0.6, chamfer: 0), Mat.warmGlow, 3.5, H + 0.06, 0)
        // Belt intakes on the outside wall (orange frames with rubber flaps).
        for z in [-2.6, 1.6] {
            put(Make.box(0.14, 1.0, 1.5, chamfer: 0.02), Mat.orange, 7.18, 0.62, Float(z))
            put(Make.box(0.16, 0.74, 1.2, chamfer: 0), Mat.rubber, 7.2, 0.52, Float(z))
        }

        // Service table with the UPGRADES display behind it.
        put(Make.box(4.2, 1.0, 0.9, chamfer: 0.04), Mat.white, 0, 0.6, -3.1)
        put(Make.box(4.3, 0.08, 1.0, chamfer: 0.02), Mat.orange, 0, 1.13, -3.1)
        put(Make.hexPrism(radius: 0.7, height: 0.5), Mat.dark, 0, 0.35, -4.15)
        put(SCNCylinder(radius: 0.5, height: 0.03), Mat.cyanGlow, 0, 0.62, -4.15)
        put(Make.box(4.4, 1.2, 0.06, chamfer: 0.02), Mat.dark, 0, 3.25, -4.82)
        let up = Make.sign("UPGRADES", size: 0.62, color: UIColor(red: 0.4, green: 0.95, blue: 1, alpha: 1))
        up.position = SCNVector3(0, 3.25, -4.76)
        signs.addChildNode(up)

        // Supply wall: rack of brushes on the left wall.
        put(Make.box(0.12, 2.7, 5.4, chamfer: 0.02), Mat.offWhite, -6.78, 1.75, -0.5)
        put(Make.box(0.2, 0.3, 5.6, chamfer: 0.02), Mat.orange, -6.76, 3.2, -0.5)
        put(Make.box(0.5, 0.08, 5.4, chamfer: 0.01), Mat.dark, -6.6, 0.9, -0.5)
        // Pegs for each tool; the tools themselves are added below so they can appear as you buy them.
        var toolNodes: [SCNNode] = []
        for t in 0..<Catalog.tools.count {
            let z = 1.6 - Float(t) * 0.84
            let y: Float = t >= 3 ? 2.95 : 2.3
            put(Make.box(0.14, 0.05, 0.05, chamfer: 0), Mat.dark, -6.68, y + 0.03, z)
            let holder = SCNNode()
            holder.position = SCNVector3(-6.6, y, z)
            holder.eulerAngles.y = .pi / 2
            let tilt = SCNNode()
            tilt.eulerAngles.x = -.pi / 2
            let m = ToolModels.make(t)
            let k: Float = t >= 3 ? 1.25 : 2.8
            m.scale = SCNVector3(k, k, k)
            tilt.addChildNode(m)
            holder.addChildNode(tilt)
            holder.isHidden = true
            signs.addChildNode(holder)
            toolNodes.append(holder)
        }
        wallTools.append(toolNodes)
        let sw = Make.sign("SUPPLY WALL", size: 0.34, color: .white)
        sw.position = SCNVector3(-6.62, 3.2, -0.5)
        sw.eulerAngles.y = .pi / 2
        signs.addChildNode(sw)

        // Deposit intake: orange circular intake with a tray and a screen.
        put(SCNCylinder(radius: 0.95, height: 0.95), Mat.orange, 5.6, 0.57, -1.3)
        put(SCNCylinder(radius: 0.75, height: 0.04), Mat.dark, 5.6, 1.06, -1.3)
        put(SCNTube(innerRadius: 0.75, outerRadius: 0.95, height: 0.1), Mat.white, 5.6, 1.08, -1.3)
        put(Make.box(0.9, 0.12, 1.1, chamfer: 0.02), Mat.steel, 4.6, 0.85, -1.3)
        put(Make.box(0.08, 0.6, 0.9, chamfer: 0.02), Mat.dark, 6.7, 2.0, -1.3)
        put(Make.box(0.03, 0.46, 0.76, chamfer: 0), Mat.greenGlow, 6.64, 2.0, -1.3)
        put(Make.box(0.9, 0.9, 2.2, chamfer: 0.05), Mat.white, 5.7, 0.55, -3.0)
        put(SCNCylinder(radius: 0.5, height: 3.2), Mat.white, 5.7, 2.6, -3.7)
        let dep = Make.sign("DEPOSIT", size: 0.3, color: UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1))
        dep.position = SCNVector3(6.8, 2.7, -1.3)
        dep.eulerAngles.y = -.pi / 2
        signs.addChildNode(dep)

        // Name over the door, outside and in.
        let name = i == Hex.home ? "N STATION" : String(format: "STATION %02d", i + 1)
        let outside = Make.sign(name, size: 0.7, color: .white)
        outside.position = SCNVector3(0, 3.75, 5.2)
        signs.addChildNode(outside)
        let inside = Make.sign(name, size: 0.4, color: UIColor(white: 1, alpha: 0.9))
        inside.position = SCNVector3(0, 3.7, 4.8)
        inside.eulerAngles.y = .pi
        signs.addChildNode(inside)

        // Space Kit dressing: dish outside, consoles and barrels inside.
        if let dish = Kit.make("satelliteDishLarge", fit: 2.8) {
            dish.position = SCNVector3(-8.5, 0.09, 3.2)
            dish.eulerAngles.y = 2.3
            signsLit.addChildNode(dish)
            world.addCollider(x: p.x - 8.5, z: p.z + 3.2, r: 1.2, group: i)
        }
        if let c1 = Kit.make("consoleScreen", fit: 1.5) {
            c1.position = SCNVector3(-4.2, 0.13, -4.3)
            signsLit.addChildNode(c1)
        }
        if let c2 = Kit.make("console", fit: 1.5) {
            c2.position = SCNVector3(3.4, 0.13, -4.3)
            signsLit.addChildNode(c2)
        }
        for (bx, bz) in [(-6.1, 4.1), (-5.2, 4.3), (-6.2, 3.3)] {
            if let b = Kit.make("barrel", fit: 0.75) {
                b.position = SCNVector3(Float(bx), 0.13, Float(bz))
                signsLit.addChildNode(b)
            }
        }
        world.addCollider(x: p.x - 5.8, z: p.z + 3.9, r: 0.9, group: i)

        let flat = shell.flattenedClone()
        add(flat, at: p)
        add(signsLit, at: p)
        Make.noShadows(signs)
        add(signs, at: p)

        // Animated bits stay separate.
        let extras = SCNNode()
        let wire = Mat.glow(UIColor(red: 0.4, green: 0.95, blue: 1, alpha: 0.9))
        wire.fillMode = .lines
        wire.isDoubleSided = true
        let globeGeo = SCNSphere(radius: 0.62)
        globeGeo.segmentCount = 16
        let globe = Make.part(globeGeo, wire, 0, 1.75, -4.15)
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 14)))
        extras.addChildNode(globe)
        let core = Mat.glow(UIColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 0.2))
        core.writesToDepthBuffer = false
        core.blendMode = .add
        extras.addChildNode(Make.part(SCNSphere(radius: 0.6), core, 0, 1.75, -4.15))
        let beacon = Make.part(SCNSphere(radius: 0.2), Mat.redGlow, -5.5, H + 4.45, -3.5)
        Make.blink(beacon, period: 0.8)
        extras.addChildNode(beacon)
        beacons.append(beacon)
        Make.noShadows(extras)
        add(extras, at: p)
        stationNodes.append([flat, signs, signsLit, extras])

        // Collision.
        let o = SIMD2<Float>(p.x, p.z)
        func seg(_ ax: Float, _ az: Float, _ bx: Float, _ bz: Float, _ half: Float = 0.18) {
            world.addWall(o + SIMD2<Float>(ax, az), o + SIMD2<Float>(bx, bz), half: half, group: i)
        }
        seg(-7, -5, 7, -5)
        seg(-7, -5, -7, 5)
        seg(7, -5, 7, 5)
        seg(-7, 5, -1.75, 5)
        seg(1.75, 5, 7, 5)
        seg(-2.1, -3.1, 2.1, -3.1, 0.45)
        seg(-6.6, -3.2, -6.6, 2.2, 0.3)
        seg(5.7, -4.2, 5.7, -2.2, 0.5)
        world.addCollider(x: p.x + 5.6, z: p.z - 1.3, r: 0.95, group: i)
    }

    private func buildInteriorLights() {
        for x in [-3.5, 3.5] {
            let l = SCNLight()
            l.type = .omni
            l.color = UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
            l.intensity = 520
            l.attenuationStartDistance = 3
            l.attenuationEndDistance = 16
            let n = SCNNode()
            n.light = l
            n.position = SCNVector3(Float(x), 3.6, 0)
            interiorLights.addChildNode(n)
        }
        let holo = SCNLight()
        holo.type = .omni
        holo.color = UIColor(red: 0.3, green: 0.85, blue: 1, alpha: 1)
        holo.intensity = 220
        holo.attenuationStartDistance = 0.5
        holo.attenuationEndDistance = 6
        let hn = SCNNode()
        hn.light = holo
        hn.position = SCNVector3(0, 2.2, -3.9)
        interiorLights.addChildNode(hn)
        root.addChildNode(interiorLights)
        lightStation(Hex.home)
    }

    /// The interior lights follow the player to whichever station is nearest.
    func lightStation(_ i: Int) {
        guard i != litStation, i >= 0, i < stationPos.count else { return }
        litStation = i
        interiorLights.simdPosition = stationPos[i]
    }

    // MARK: Things you build at the home station

    private func buildHomePlots(world: MoonWorld) {
        // Packager, then a belt into the station's wall intake.
        packagerNode.addChildNode(Make.part(Make.box(1.6, 1.4, 1.6, chamfer: 0.08), Mat.orange, 12, 0.7, 4.2))
        packagerNode.addChildNode(Make.part(SCNCone(topRadius: 0.8, bottomRadius: 0.4, height: 0.6), Mat.dark, 12, 1.7, 4.2))
        packagerNode.addChildNode(Make.part(Make.box(0.6, 0.3, 0.04, chamfer: 0), Mat.cyanGlow, 12, 0.9, 5.01))
        let pl = Make.label("PACKAGER", size: 0.3)
        pl.position = SCNVector3(12, 2.3, 4.2)
        packagerNode.addChildNode(pl)
        let belt = SCNNode()
        belt.addChildNode(Make.part(Make.box(13.6, 0.1, 0.7, chamfer: 0.01), Mat.rubber, 14.1, 0.55, 1.6))
        belt.addChildNode(Make.part(Make.box(13.6, 0.16, 0.06, chamfer: 0), Mat.orange, 14.1, 0.6, 1.95))
        belt.addChildNode(Make.part(Make.box(13.6, 0.16, 0.06, chamfer: 0), Mat.orange, 14.1, 0.6, 1.25))
        for k in 0..<7 {
            belt.addChildNode(Make.part(SCNCylinder(radius: 0.05, height: 0.55), Mat.steel, 8.0 + Float(k) * 2.1, 0.27, 1.6))
        }
        belt.addChildNode(Make.part(Make.box(0.7, 0.1, 2.0, chamfer: 0.01), Mat.rubber, 12, 0.55, 2.9))
        for k in 0..<5 {
            let c = Structures.makeCapsule(scale: 2.2)
            c.position = SCNVector3(20.5, 0.78, 1.6)
            c.eulerAngles.z = .pi / 2
            let travel = SCNAction.sequence([.moveBy(x: -13.2, y: 0, z: 0, duration: 8),
                                             .moveBy(x: 13.2, y: 0, z: 0, duration: 0)])
            c.runAction(.sequence([.wait(duration: Double(k) * 1.6), .repeatForever(travel)]))
            belt.addChildNode(c)
        }
        Make.noShadows(belt)
        packagerNode.addChildNode(belt)
        root.addChildNode(packagerNode)

        if let tank = Kit.make("barrelLarge", fit: 3.0) {
            chamberNode.addChildNode(tank)
        } else {
            let ch = Make.part(SCNCapsule(capRadius: 0.9, height: 3.2), Mat.white, 0, 1.3, 0)
            ch.eulerAngles.z = .pi / 2
            chamberNode.addChildNode(ch)
            chamberNode.addChildNode(Make.part(Make.box(2.2, 0.5, 1.4, chamfer: 0.05), Mat.dark, 0, 0.25, 0))
        }
        if let pad = Kit.make("metalTile", fit: 3.6) {
            pad.position = SCNVector3(0, -0.2, 0)
            chamberNode.addChildNode(pad)
        }
        let cl = Make.label("PRESSURE CHAMBER", size: 0.3)
        cl.position = SCNVector3(0, 2.7, 0)
        chamberNode.addChildNode(cl)
        add(chamberNode, at: SIMD3<Float>(16.5, 0, 3.6))

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
        if let pad = Kit.make("metalTile", fit: 3.2) {
            pad.position = SCNVector3(0, -0.2, 0)
            pressNode.addChildNode(pad)
        }
        let sl = Make.label("STONE PRESS", size: 0.3)
        sl.position = SCNVector3(0, 4.3, 0)
        pressNode.addChildNode(sl)
        add(pressNode, at: SIMD3<Float>(20.5, 0, 3.8))

        // Solar field (appears with the first powered machine) and battery bank.
        for row in 0..<2 {
            for col in 0..<3 {
                let panel = SCNNode()
                panel.addChildNode(Make.part(SCNCylinder(radius: 0.08, height: 1.6), Mat.steel, 0, 0.8, 0))
                let p = SCNNode()
                p.addChildNode(Make.part(Make.box(3.0, 0.06, 1.7, chamfer: 0.01), Mat.solar, 0, 0, 0))
                p.addChildNode(Make.part(Make.box(3.1, 0.04, 1.8, chamfer: 0.01), Mat.white, 0, -0.04, 0))
                p.position = SCNVector3(0, 1.7, 0)
                p.eulerAngles.x = -0.5
                panel.addChildNode(p)
                panel.position = SCNVector3(14 + Float(col) * 3.6, 0, -4 - Float(row) * 3.2)
                powerNode.addChildNode(panel)
            }
        }
        root.addChildNode(powerNode)
        batteryNode.addChildNode(Make.part(Make.box(1.8, 1.2, 1.0, chamfer: 0.06), Mat.white, 0, 0.6, 0))
        batteryNode.addChildNode(Make.part(Make.box(1.5, 0.12, 0.04, chamfer: 0), Mat.greenGlow, 0, 0.9, 0.51))
        batteryNode.addChildNode(Make.part(Make.box(1.82, 0.2, 1.02, chamfer: 0.02), Mat.orange, 0, 0.2, 0))
        add(batteryNode, at: SIMD3<Float>(12, 0, -1.5))

        // Robot vacuum dock.
        dockNode.addChildNode(Make.part(Make.box(5.6, 0.12, 1.6, chamfer: 0.03), Mat.dark, 2, 0.1, 0))
        dockNode.addChildNode(Make.part(Make.box(5.6, 0.5, 0.2, chamfer: 0.03), Mat.orange, 2, 0.3, -0.8))
        Make.noShadows(dockNode)
        add(dockNode, at: botDock)

        // Capsule Catcher.
        catcherNode.addChildNode(Make.part(SCNCone(topRadius: 2.6, bottomRadius: 0.5, height: 1.7), plateOrange, 0, 3.0, 0))
        catcherNode.addChildNode(Make.part(SCNTube(innerRadius: 2.55, outerRadius: 2.7, height: 0.14), Mat.white, 0, 3.85, 0))
        if let tower = Kit.make("metalStructure", fit: 2.4) {
            catcherNode.addChildNode(tower)
        } else {
            for k in 0..<3 {
                let a = Float(k) * 2.094
                catcherNode.addChildNode(Make.part(SCNCylinder(radius: 0.07, height: 2.6), Mat.steel, cos(a) * 1.0, 1.2, sin(a) * 1.0))
            }
            catcherNode.addChildNode(Make.part(Make.hexPrism(radius: 0.8, height: 0.8), Mat.white, 0, 0.4, 0))
        }
        let kl = Make.label("CAPSULE CATCHER", size: 0.3)
        kl.position = SCNVector3(0, 4.4, 0)
        catcherNode.addChildNode(kl)
        add(catcherNode, at: catcherPos)

        // Garage (opens toward +Z).
        garageNode.addChildNode(hexPad(radius: 7))
        if let hangar = Kit.make("buildingOpen", fit: 9.4) {
            hangar.position = SCNVector3(0, 0.09, 0)
            garageNode.addChildNode(hangar)
        } else {
            garageNode.addChildNode(Make.part(Make.box(8, 4.2, 0.3), Mat.white, 0, 2.2, -4))
            garageNode.addChildNode(Make.part(Make.box(0.3, 4.2, 8), Mat.white, -4, 2.2, 0))
            garageNode.addChildNode(Make.part(Make.box(0.3, 4.2, 8), Mat.white, 4, 2.2, 0))
            garageNode.addChildNode(Make.part(Make.box(8.6, 0.3, 8.6), Mat.offWhite, 0, 4.45, 0))
            garageNode.addChildNode(Make.part(Make.box(8.3, 0.6, 0.2), Mat.orange, 0, 4.0, 4.1))
        }
        garageNode.addChildNode(Make.part(Make.box(1.0, 1.3, 0.5), Mat.dark, 3.2, 0.75, -3.4))
        garageNode.addChildNode(Make.part(Make.box(0.8, 0.5, 0.04, chamfer: 0), Mat.cyanGlow, 3.2, 1.1, -3.13))
        let gs = Make.sign("GARAGE", size: 0.6, color: .white)
        gs.position = SCNVector3(0, 5.4, 4.9)
        garageNode.addChildNode(gs)
        if let term = Kit.make("consoleScreen", fit: 1.4) {
            term.position = SCNVector3(3.2, 0.09, -3.3)
            garageNode.addChildNode(term)
        }
        add(garageNode, at: garagePos)
    }

    /// A dust capsule: a see-through canister packed with grey dust between two metal caps.
    static func makeCapsule(scale: Float) -> SCNNode {
        let n = SCNNode()
        let dustMat = Mat.solid(UIColor(white: 0.33, alpha: 1), spec: 0.05)
        n.addChildNode(Make.part(SCNCylinder(radius: 0.058, height: 0.2), dustMat, 0, 0, 0))
        let glass = Mat.solid(UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 0.28), spec: 1)
        glass.writesToDepthBuffer = false
        glass.isDoubleSided = true
        n.addChildNode(Make.part(SCNCylinder(radius: 0.068, height: 0.22), glass, 0, 0, 0))
        for sy in [-1, 1] {
            n.addChildNode(Make.part(SCNCylinder(radius: 0.074, height: 0.045), Mat.steel, 0, Float(sy) * 0.125, 0))
            n.addChildNode(Make.part(SCNTube(innerRadius: 0.07, outerRadius: 0.078, height: 0.014), Mat.orange, 0, Float(sy) * 0.095, 0))
        }
        n.scale = SCNVector3(scale, scale, scale)
        Make.noShadows(n)
        return n
    }

    // MARK: Flags

    private func buildFlags(world: MoonWorld) {
        var rng = SeededRNG(seed: 0xF1A6)
        for s in 0..<Hex.count {
            let c = Hex.centers[s]
            var made = 0
            var tries = 0
            while made < 3 && tries < 300 {
                tries += 1
                let a = Float.random(in: 0..<6.283, using: &rng)
                let d = Float.random(in: (s == Hex.home ? 28 : 17)...32, using: &rng)
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
            while made < 3 {
                let x = c.x + 18, z = c.y + Float(made) * 3
                flagPos.append(SIMD3<Float>(x, world.height(atX: x, z: z), z))
                flagCloths.append(SCNNode())
                made += 1
            }
        }
    }

    // MARK: State

    /// Shows what has been built and clears the dust under it.
    func refresh(_ s: SaveData, dust: DustField) {
        garageNode.isHidden = !s.hasGarage
        packagerNode.isHidden = !s.hasPackager
        chamberNode.isHidden = !s.hasChamber
        pressNode.isHidden = !s.hasPress
        batteryNode.isHidden = !s.hasBattery
        powerNode.isHidden = !(s.hasChamber || s.hasBattery)
        catcherNode.isHidden = !s.hasCatcher
        dockNode.isHidden = s.vacuums == 0
        if s.hasGarage { dust.clearArea(x: garagePos.x, z: garagePos.z, radius: 7.2) }
        if s.hasPackager {
            dust.clearArea(x: 12, z: 4.2, radius: 1.6)
            var x: Float = 7.6
            while x < 21 {
                dust.clearArea(x: x, z: 1.6, radius: 0.7)
                x += 0.7
            }
        }
        if s.hasChamber { dust.clearArea(x: 16.5, z: 3.6, radius: 2.0) }
        if s.hasPress { dust.clearArea(x: 20.5, z: 3.8, radius: 1.7) }
        if s.hasBattery { dust.clearArea(x: 12, z: -1.5, radius: 1.3) }
        if s.hasCatcher { dust.clearArea(x: catcherPos.x, z: catcherPos.z, radius: 1.4) }
        if s.vacuums > 0 { dust.clearArea(x: botDock.x + 2, z: botDock.z, radius: 3.0) }

        // Stations exist only once they are built (you start with just N Station).
        var off = Set<Int>()
        for i in 0..<stationNodes.count {
            let built = i < s.stationsFound.count && s.stationsFound[i]
            stationNodes[i].forEach { $0.isHidden = !built }
            beacons[i].geometry?.materials = [Mat.greenGlow]
            if built {
                if i != Hex.home { dust.clearHex(x: stationPos[i].x, z: stationPos[i].z, radius: 10.75) }
            } else {
                off.insert(i)
            }
            // The supply wall shows the tools you own.
            for (t, node) in wallTools[i].enumerated() {
                node.isHidden = !(t < s.toolsOwned.count && s.toolsOwned[t])
            }
        }
        world?.disabledGroups = off
        let claimed = Mat.solid(UIColor(red: 0.15, green: 0.5, blue: 0.95, alpha: 1))
        for (i, cloth) in flagCloths.enumerated() {
            let done = i < s.flagsClaimed.count && s.flagsClaimed[i]
            cloth.geometry?.materials = [done ? claimed : Mat.orange]
        }
    }

    /// A shipment capsule rockets out of a station's launcher.
    func launchShipment(from station: Int) {
        let c = Make.part(SCNCapsule(capRadius: 0.22, height: 0.8), Mat.glow(UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1)), 0, 0, 0)
        c.simdPosition = stationPos[station] + Structures.launcherOffset
        c.castsShadow = false
        root.addChildNode(c)
        let up = SCNAction.moveBy(x: 0, y: 160, z: 0, duration: 1.8)
        up.timingMode = .easeIn
        c.runAction(.sequence([up, .removeFromParentNode()]))
    }
}
