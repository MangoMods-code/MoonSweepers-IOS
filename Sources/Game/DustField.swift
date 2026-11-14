import UIKit
import SceneKit
import Metal

/// The layer of lunar dust over the whole map: a 2048 x 2048 grid (12.5 cm cells) drawn as the
/// alpha of a dark regolith mesh sitting just above the clean ground. Dust is tracked per
/// small hex tile and per region (the 12 station sectors).
final class DustField {
    static let res = 2048
    static let kgPerSquareMeter: Float = 0.5

    let res = DustField.res
    let cellSize: Float = WorldDims.size / Float(DustField.res)
    private(set) var mask: [UInt8]
    private let tile: [UInt16]
    private let fresh: [UInt8]
    private let tileRegion: [UInt8]
    private var tileDust: [Int32]
    private let tileInitial: [Int32]
    private(set) var sectorDust: [Int]
    private(set) var sectorInitial: [Int]
    private(set) var totalDust: Int
    private(set) var initialTotal: Int
    /// Tiles that were just finished (drained by the game each frame to pay bonuses).
    private var completed: [Int] = []
    let material = SCNMaterial()
    private var texture: MTLTexture?

    var cleanFraction: Double { 1.0 - Double(totalDust) / Double(max(initialTotal, 1)) }

    func sectorClean(_ i: Int) -> Double {
        1.0 - Double(sectorDust[i]) / Double(max(sectorInitial[i], 1))
    }

    /// 0...1 clean fraction of the small hex tile under a point.
    func tileClean(atX x: Float, z: Float) -> Double {
        let t = Tile.index(x, z)
        let initial = tileInitial[t]
        if initial <= 0 { return 1 }
        return 1.0 - Double(tileDust[t]) / Double(initial)
    }

    func drainCompleted() -> [Int] {
        if completed.isEmpty { return [] }
        let out = completed
        completed.removeAll()
        return out
    }

    private var kgPerValue: Float { cellSize * cellSize * DustField.kgPerSquareMeter / 255 }

    init(savedMask: [UInt8]?) {
        let n = DustField.res
        let cs = WorldDims.size / Float(n)
        var freshMask = [UInt8](repeating: 0, count: n * n)
        var tiles = [UInt16](repeating: 0, count: n * n)
        let padR: Float = 10.75
        for j in 0..<n {
            let z = WorldDims.minZ + (Float(j) + 0.5) * cs
            for i in 0..<n {
                let x = WorldDims.minX + (Float(i) + 0.5) * cs
                let k = j * n + i
                tiles[k] = UInt16(Tile.index(x, z))
                // No dust on station foundations.
                let c = Hex.centers[Hex.home]
                if Tile.inHex(x - c.x, z - c.y, radius: padR) { continue }
                let thick = 0.75 + 0.25 * Noise.value(Float(i) / 72, Float(j) / 72, seed: 11)
                freshMask[k] = UInt8(255 * thick)
            }
        }
        fresh = freshMask
        tile = tiles
        var regions = [UInt8](repeating: 0, count: Tile.slots)
        for t in 0..<Tile.slots {
            let c = Tile.center(t)
            regions[t] = UInt8(Hex.nearest(c.x, c.y))
        }
        tileRegion = regions

        var start: [UInt8] = freshMask
        if let saved = savedMask, saved.count == n * n { start = saved }
        mask = start
        var tInit = [Int32](repeating: 0, count: Tile.slots)
        var tNow = [Int32](repeating: 0, count: Tile.slots)
        for k in 0..<(n * n) {
            let t = Int(tiles[k])
            tInit[t] += Int32(freshMask[k])
            tNow[t] += Int32(start[k])
        }
        tileInitial = tInit
        tileDust = tNow
        var sInit = [Int](repeating: 0, count: Hex.count)
        var sNow = [Int](repeating: 0, count: Hex.count)
        for t in 0..<Tile.slots {
            sInit[Int(regions[t])] += Int(tInit[t])
            sNow[Int(regions[t])] += Int(tNow[t])
        }
        sectorInitial = sInit
        sectorDust = sNow
        initialTotal = sInit.reduce(0, +)
        totalDust = sNow.reduce(0, +)

        setupMaterial()
        upload(0, 0, n - 1, n - 1)
    }

    private func setupMaterial() {
        // Lunar dust: dark, matte, clumpy grey regolith.
        material.lightingModel = .lambert
        material.diffuse.contents = Tex.tinted(size: 512, tint: SIMD3<Float>(1.0, 0.98, 0.95)) { u, v in
            let a = Noise.fbmTile(u, v, basePeriod: 5, octaves: 5, seed: 40)
            let clump = Noise.fbmTile(u, v, basePeriod: 14, octaves: 3, seed: 47)
            let grain = Noise.hash(Int(u * 512), Int(v * 512), 41)
            return 0.27 + 0.13 * a + 0.07 * clump + 0.05 * grain
        }
        material.normal.contents = Tex.normal(size: 512, strength: 11) { u, v in
            let a = Noise.fbmTile(u, v, basePeriod: 8, octaves: 5, seed: 44)
            let clump = Noise.fbmTile(u, v, basePeriod: 20, octaves: 3, seed: 47)
            return a + 0.6 * clump
        }
        let tileXf = SCNMatrix4MakeScale(96, 96, 1)
        for p in [material.diffuse, material.normal] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 8
            p.contentsTransform = tileXf
        }
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false

        if let device = MTLCreateSystemDefaultDevice() {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: res, height: res, mipmapped: false)
            d.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: d)
        }
        if let t = texture {
            material.transparent.contents = t
            material.transparent.wrapS = .clamp
            material.transparent.wrapT = .clamp
            material.transparent.mipFilter = .none
            // The same texture's colour channels darken a rim along every dust edge.
            material.multiply.contents = t
            material.multiply.wrapS = .clamp
            material.multiply.wrapT = .clamp
            material.multiply.mipFilter = .none
        }
    }

    func reset() {
        mask = fresh
        tileDust = tileInitial
        sectorDust = sectorInitial
        totalDust = initialTotal
        completed.removeAll()
        upload(0, 0, res - 1, res - 1)
    }

    /// Uploads a region of the mask. Alpha is all-or-nothing (a crisp edge) and the colour
    /// channels draw a dark border line on every dust cell that touches clean ground.
    private func upload(_ a0: Int, _ b0: Int, _ a1: Int, _ b1: Int) {
        guard let t = texture, a0 <= a1, b0 <= b1 else { return }
        let i0 = max(0, a0 - 2), j0 = max(0, b0 - 2)
        let i1 = min(res - 1, a1 + 2), j1 = min(res - 1, b1 + 2)
        let w = i1 - i0 + 1, h = j1 - j0 + 1
        let n = res
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        mask.withUnsafeBufferPointer { m in
            for j in 0..<h {
                let y = j0 + j
                for i in 0..<w {
                    let x = i0 + i
                    let k = (j * w + i) * 4
                    if m[y * n + x] == 0 {
                        buf[k + 3] = 0
                        continue
                    }
                    // Distance (in cells, up to 2) to the nearest clean cell.
                    var near = 3
                    for dy in -2...2 {
                        let yy = y + dy
                        if yy < 0 || yy >= n { continue }
                        for dx in -2...2 {
                            let xx = x + dx
                            if xx < 0 || xx >= n { continue }
                            if m[yy * n + xx] == 0 {
                                near = min(near, max(abs(dx), abs(dy)))
                            }
                        }
                    }
                    let shade: UInt8 = near == 1 ? 26 : (near == 2 ? 120 : 255)
                    buf[k] = shade
                    buf[k + 1] = shade
                    buf[k + 2] = shade
                }
            }
        }
        buf.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(i0, j0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
            }
        }
    }

    /// Removes all dust inside a flat-top hexagon (under a newly built station).
    func clearHex(x: Float, z: Float, radius: Float) {
        let (ia, ja) = cell(x - radius, z - radius)
        let (ib, jb) = cell(x + radius, z + radius)
        let i0 = max(0, ia), i1 = min(res - 1, ib)
        let j0 = max(0, ja), j1 = min(res - 1, jb)
        guard i0 <= i1, j0 <= j1 else { return }
        var changed = false
        for j in j0...j1 {
            let cz = WorldDims.minZ + (Float(j) + 0.5) * cellSize - z
            for i in i0...i1 {
                let cx = WorldDims.minX + (Float(i) + 0.5) * cellSize - x
                let idx = j * res + i
                if mask[idx] > 0 && Tile.inHex(cx, cz, radius: radius) {
                    remove(idx, Int(mask[idx]))
                    mask[idx] = 0
                    changed = true
                }
            }
        }
        if changed { upload(i0, j0, i1, j1) }
    }

    private func cell(_ x: Float, _ z: Float) -> (Int, Int) {
        (Int(((x - WorldDims.minX) / cellSize).rounded(.down)), Int(((z - WorldDims.minZ) / cellSize).rounded(.down)))
    }

    func dust(atX x: Float, z: Float) -> Float {
        let (i, j) = cell(x, z)
        guard i >= 0, j >= 0, i < res, j < res else { return 0 }
        return Float(mask[j * res + i]) / 255
    }

    func averageDust(atX x: Float, z: Float, radius: Float) -> Float {
        var sum: Float = 0
        var n: Float = 0
        for a in -2...2 {
            for b in -2...2 {
                sum += dust(atX: x + Float(a) / 2 * radius, z: z + Float(b) / 2 * radius)
                n += 1
            }
        }
        return sum / n
    }

    private func remove(_ idx: Int, _ amount: Int) {
        let t = Int(tile[idx])
        tileDust[t] -= Int32(amount)
        sectorDust[Int(tileRegion[t])] -= amount
        totalDust -= amount
    }

    /// Removes all dust in a circle without collecting it (used under newly built structures).
    func clearArea(x: Float, z: Float, radius: Float) {
        let (ia, ja) = cell(x - radius, z - radius)
        let (ib, jb) = cell(x + radius, z + radius)
        let i0 = max(0, ia), i1 = min(res - 1, ib)
        let j0 = max(0, ja), j1 = min(res - 1, jb)
        guard i0 <= i1, j0 <= j1 else { return }
        var changed = false
        for j in j0...j1 {
            let cz = WorldDims.minZ + (Float(j) + 0.5) * cellSize - z
            for i in i0...i1 {
                let cx = WorldDims.minX + (Float(i) + 0.5) * cellSize - x
                let idx = j * res + i
                if cx * cx + cz * cz <= radius * radius && mask[idx] > 0 {
                    remove(idx, Int(mask[idx]))
                    mask[idx] = 0
                    changed = true
                }
            }
        }
        if changed { upload(i0, j0, i1, j1) }
    }

    /// A tile that is 99.5% done seals: the last specks vanish and it counts as complete.
    private func sealIfDone(_ t: Int) -> Float {
        let initial = tileInitial[t]
        guard initial > 0 else { return 0 }
        if Double(tileDust[t]) > Double(initial) * 0.005 { return 0 }
        let c = Tile.center(t)
        let (ia, ja) = cell(c.x - Tile.radius - 0.2, c.y - Tile.radius - 0.2)
        let (ib, jb) = cell(c.x + Tile.radius + 0.2, c.y + Tile.radius + 0.2)
        let i0 = max(0, ia), i1 = min(res - 1, ib)
        let j0 = max(0, ja), j1 = min(res - 1, jb)
        var extra = 0
        if i0 <= i1 && j0 <= j1 {
            for j in j0...j1 {
                for i in i0...i1 {
                    let idx = j * res + i
                    if Int(tile[idx]) == t && mask[idx] > 0 {
                        extra += Int(mask[idx])
                        remove(idx, Int(mask[idx]))
                        mask[idx] = 0
                    }
                }
            }
            if extra > 0 { upload(i0, j0, i1, j1) }
        }
        completed.append(t)
        return Float(extra) * kgPerValue
    }

    /// Removes dust in a circle; returns kg collected, never more than `capacityLeft`.
    @discardableResult
    func clean(atX x: Float, z: Float, radius: Float, rate: Float, dt: Float, capacityLeft: Float) -> Float {
        guard capacityLeft > 0.0001 else { return 0 }
        let cs = cellSize
        let r = radius + cs * 0.5
        let (ia, ja) = cell(x - r, z - r)
        let (ib, jb) = cell(x + r, z + r)
        let i0 = max(0, ia), i1 = min(res - 1, ib)
        let j0 = max(0, ja), j1 = min(res - 1, jb)
        guard i0 <= i1, j0 <= j1 else { return 0 }
        let maxRemove = rate * dt * 255
        let perValue = kgPerValue
        let r2 = r * r

        var potential: Float = 0
        for j in j0...j1 {
            let cz = WorldDims.minZ + (Float(j) + 0.5) * cs - z
            for i in i0...i1 {
                let cx = WorldDims.minX + (Float(i) + 0.5) * cs - x
                let d2 = cx * cx + cz * cz
                if d2 > r2 { continue }
                let t = d2 / r2
                let fall = max(0.4, 1 - t * t)
                potential += min(Float(mask[j * res + i]), maxRemove * fall)
            }
        }
        if potential <= 0 { return 0 }
        let scale = min(1, capacityLeft / (potential * perValue))

        var removed = 0
        var carry: Float = 0
        var touched: [Int] = []
        for j in j0...j1 {
            let cz = WorldDims.minZ + (Float(j) + 0.5) * cs - z
            for i in i0...i1 {
                let cx = WorldDims.minX + (Float(i) + 0.5) * cs - x
                let d2 = cx * cx + cz * cz
                if d2 > r2 { continue }
                let idx = j * res + i
                let cur = mask[idx]
                if cur == 0 { continue }
                let t = d2 / r2
                let fall = max(0.4, 1 - t * t)
                let want = min(Float(cur), maxRemove * fall) * scale + carry
                var take = Int(want)
                carry = want - Float(take)
                if cur <= 48 && scale >= 1 { take = Int(cur) }
                take = min(take, Int(cur))
                if take > 0 {
                    mask[idx] = cur - UInt8(take)
                    remove(idx, take)
                    removed += take
                    let tl = Int(tile[idx])
                    if touched.last != tl && !touched.contains(tl) { touched.append(tl) }
                }
            }
        }
        var kg = Float(removed) * perValue
        if removed > 0 {
            upload(i0, j0, i1, j1)
            for t in touched { kg += sealIfDone(t) }
        }
        return kg
    }
}
