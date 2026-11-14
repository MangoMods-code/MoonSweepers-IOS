import UIKit
import SceneKit
import Metal

/// The layer of lunar dust over the whole map: a 4096 x 4096 grid (6.25 cm cells).
/// Each cell holds 255 (dust), 0 (clean) or an in-between coverage value on a brushed edge,
/// so the edge can be drawn as a smooth, sharp contour by the shader. Dust is tracked per
/// small hex tile and per region (the 12 sectors).
final class DustField {
    static let res = 4096
    static let kgPerSquareMeter: Float = 0.45

    let res = DustField.res
    let cellSize: Float = WorldDims.size / Float(DustField.res)
    private(set) var mask: [UInt8]
    private let tileRegion: [UInt8]
    private var tileDust: [Int32]
    private var tileInitial: [Int32]
    private(set) var sectorDust: [Int]
    private(set) var sectorInitial: [Int]
    private(set) var totalDust: Int
    private(set) var initialTotal: Int
    private var completed: [Int] = []
    let material = SCNMaterial()
    private var texture: MTLTexture?
    private static let padRadius: Float = 10.75

    var cleanFraction: Double { 1.0 - Double(totalDust) / Double(max(initialTotal, 1)) }

    func sectorClean(_ i: Int) -> Double {
        1.0 - Double(sectorDust[i]) / Double(max(sectorInitial[i], 1))
    }

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

    /// One bit per cell (1 = dust), for saving.
    static func pack(_ mask: [UInt8]) -> Data {
        var out = [UInt8](repeating: 0, count: (mask.count + 7) / 8)
        mask.withUnsafeBufferPointer { m in
            for k in 0..<m.count where m[k] >= 128 {
                out[k >> 3] |= UInt8(1 << (k & 7))
            }
        }
        return Data(out)
    }

    init(savedBits: Data?) {
        let n = DustField.res
        var regions = [UInt8](repeating: 0, count: Tile.slots)
        for t in 0..<Tile.slots {
            let c = Tile.center(t)
            regions[t] = UInt8(Hex.nearest(c.x, c.y))
        }
        tileRegion = regions
        mask = [UInt8](repeating: 0, count: n * n)
        tileDust = [Int32](repeating: 0, count: Tile.slots)
        tileInitial = [Int32](repeating: 0, count: Tile.slots)
        sectorDust = [Int](repeating: 0, count: Hex.count)
        sectorInitial = [Int](repeating: 0, count: Hex.count)
        totalDust = 0
        initialTotal = 0
        var bits: [UInt8]? = nil
        if let d = savedBits, d.count == (n * n + 7) / 8 { bits = [UInt8](d) }
        fill(bits: bits)
        setupMaterial()
        uploadAll()
    }

    /// Lays down fresh dust (none on the home foundation), optionally restoring saved cells.
    private func fill(bits: [UInt8]?) {
        let n = res
        let cs = cellSize
        let home = Hex.centers[Hex.home]
        var tInit = [Int32](repeating: 0, count: Tile.slots)
        var tNow = [Int32](repeating: 0, count: Tile.slots)
        mask.withUnsafeMutableBufferPointer { m in
            for j in 0..<n {
                let z = WorldDims.minZ + (Float(j) + 0.5) * cs
                let nearPadZ = abs(z - home.y) <= DustField.padRadius
                for i in 0..<n {
                    let x = WorldDims.minX + (Float(i) + 0.5) * cs
                    let k = j * n + i
                    if nearPadZ && abs(x - home.x) <= DustField.padRadius
                        && Tile.inHex(x - home.x, z - home.y, radius: DustField.padRadius) {
                        m[k] = 0
                        continue
                    }
                    let t = Tile.index(x, z)
                    tInit[t] += 255
                    var v: UInt8 = 255
                    if let b = bits, b[k >> 3] & UInt8(1 << (k & 7)) == 0 { v = 0 }
                    m[k] = v
                    tNow[t] += Int32(v)
                }
            }
        }
        tileInitial = tInit
        tileDust = tNow
        var sInit = [Int](repeating: 0, count: Hex.count)
        var sNow = [Int](repeating: 0, count: Hex.count)
        for t in 0..<Tile.slots {
            sInit[Int(tileRegion[t])] += Int(tInit[t])
            sNow[Int(tileRegion[t])] += Int(tNow[t])
        }
        sectorInitial = sInit
        sectorDust = sNow
        initialTotal = sInit.reduce(0, +)
        totalDust = sNow.reduce(0, +)
        completed.removeAll()
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
        material.multiply.contents = Tex.tinted(size: 256, tint: SIMD3<Float>(1, 1, 1)) { u, v in
            let a = Noise.value(u * 7, v * 7, seed: 61)
            let b = Noise.value(u * 23, v * 23, seed: 62)
            return 0.8 + 0.14 * a + 0.08 * b
        }
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false

        if let device = MTLCreateSystemDefaultDevice() {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .a8Unorm, width: res, height: res, mipmapped: false)
            d.usage = [.shaderRead]
            texture = device.makeTexture(descriptor: d)
        }
        if let t = texture {
            material.transparent.contents = t
            material.transparent.wrapS = .clamp
            material.transparent.wrapT = .clamp
            material.transparent.mipFilter = .none
        }

        // The smoothly filtered coverage is turned into a hard, anti-aliased edge with a
        // dark outline hugging it, instead of a soft fade.
        material.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        float dustA = _output.color.a;
        float dustW = clamp(fwidth(dustA) * 0.75, 0.015, 0.2);
        float dustEdge = smoothstep(0.5 - dustW, 0.5 + dustW, dustA);
        float3 dustRGB = _output.color.rgb / max(dustA, 0.001);
        float dustRim = 1.0 - smoothstep(0.56, 0.99, dustA);
        dustRGB = dustRGB * (1.0 - 0.85 * dustRim);
        _output.color = float4(dustRGB * dustEdge, dustEdge);
        """]
    }

    func reset() {
        fill(bits: nil)
        uploadAll()
    }

    private func uploadAll() { upload(0, 0, res - 1, res - 1) }

    /// The texture is the mask itself, so a region uploads straight from the array.
    private func upload(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) {
        guard let t = texture, i0 <= i1, j0 <= j1 else { return }
        let w = i1 - i0 + 1, h = j1 - j0 + 1
        let n = res
        mask.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            t.replace(region: MTLRegionMake2D(i0, j0, w, h), mipmapLevel: 0,
                      withBytes: base + (j0 * n + i0), bytesPerRow: n)
        }
    }

    private func cell(_ x: Float, _ z: Float) -> (Int, Int) {
        (Int(((x - WorldDims.minX) / cellSize).rounded(.down)), Int(((z - WorldDims.minZ) / cellSize).rounded(.down)))
    }

    private func box(_ x: Float, _ z: Float, _ r: Float) -> (Int, Int, Int, Int)? {
        let (ia, ja) = cell(x - r, z - r)
        let (ib, jb) = cell(x + r, z + r)
        let i0 = max(0, ia), i1 = min(res - 1, ib)
        let j0 = max(0, ja), j1 = min(res - 1, jb)
        if i0 > i1 || j0 > j1 { return nil }
        return (i0, j0, i1, j1)
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

    private func remove(tile t: Int, _ amount: Int) {
        tileDust[t] -= Int32(amount)
        sectorDust[Int(tileRegion[t])] -= amount
        totalDust -= amount
    }

    /// Clears every cell for which `inside(dx, dz)` is true, without collecting the dust.
    private func clear(x: Float, z: Float, radius: Float, inside: (Float, Float) -> Bool) {
        guard let (i0, j0, i1, j1) = box(x, z, radius) else { return }
        var changed = false
        for j in j0...j1 {
            let wz = WorldDims.minZ + (Float(j) + 0.5) * cellSize
            for i in i0...i1 {
                let idx = j * res + i
                let cur = mask[idx]
                if cur == 0 { continue }
                let wx = WorldDims.minX + (Float(i) + 0.5) * cellSize
                if inside(wx - x, wz - z) {
                    remove(tile: Tile.index(wx, wz), Int(cur))
                    mask[idx] = 0
                    changed = true
                }
            }
        }
        if changed { upload(i0, j0, i1, j1) }
    }

    func clearArea(x: Float, z: Float, radius: Float) {
        clear(x: x, z: z, radius: radius) { dx, dz in dx * dx + dz * dz <= radius * radius }
    }

    func clearHex(x: Float, z: Float, radius: Float) {
        clear(x: x, z: z, radius: radius) { dx, dz in Tile.inHex(dx, dz, radius: radius) }
    }

    /// A tile that is 99.5% done seals: the last specks vanish and it counts as complete.
    private func sealIfDone(_ t: Int) -> Float {
        let initial = tileInitial[t]
        guard initial > 0 else { return 0 }
        if Double(tileDust[t]) > Double(initial) * 0.005 { return 0 }
        let c = Tile.center(t)
        var extra = 0
        if let (i0, j0, i1, j1) = box(c.x, c.y, Tile.radius + 0.2) {
            for j in j0...j1 {
                let wz = WorldDims.minZ + (Float(j) + 0.5) * cellSize
                for i in i0...i1 {
                    let idx = j * res + i
                    let cur = mask[idx]
                    if cur == 0 { continue }
                    let wx = WorldDims.minX + (Float(i) + 0.5) * cellSize
                    if Tile.index(wx, wz) == t {
                        extra += Int(cur)
                        remove(tile: t, Int(cur))
                        mask[idx] = 0
                    }
                }
            }
            if extra > 0 { upload(i0, j0, i1, j1) }
        }
        completed.append(t)
        return Float(extra) * kgPerValue
    }

    /// Instantly wipes the dust inside a circle. Returns kg collected, never more than
    /// `capacityLeft` (cleaning simply stops when the container is full).
    @discardableResult
    func clean(atX x: Float, z: Float, radius: Float, capacityLeft: Float) -> Float {
        guard capacityLeft > 0.00001 else { return 0 }
        let cs = cellSize
        guard let (i0, j0, i1, j1) = box(x, z, radius + cs) else { return 0 }
        let perValue = kgPerValue
        var budget = Int(capacityLeft / perValue)
        if budget <= 0 { return 0 }
        var removed = 0
        var touched: [Int] = []
        let outer = radius + cs * 0.5
        let outer2 = outer * outer
        outerLoop: for j in j0...j1 {
            let wz = WorldDims.minZ + (Float(j) + 0.5) * cs
            let dz = wz - z
            for i in i0...i1 {
                let idx = j * res + i
                let cur = mask[idx]
                if cur == 0 { continue }
                let wx = WorldDims.minX + (Float(i) + 0.5) * cs
                let dx = wx - x
                let d2 = dx * dx + dz * dz
                if d2 >= outer2 { continue }
                // Coverage: 0 well inside the brush, rising to 1 at its rim (sub-cell accurate).
                let cov = (d2.squareRoot() - radius) / cs + 0.5
                let target: UInt8 = cov < 0.5 ? 0 : UInt8(min(255, cov * 255))
                if cur <= target { continue }
                let delta = Int(cur - target)
                if delta > budget { break outerLoop }
                budget -= delta
                mask[idx] = target
                let t = Tile.index(wx, wz)
                remove(tile: t, delta)
                removed += delta
                if touched.last != t && !touched.contains(t) { touched.append(t) }
            }
        }
        var kg = Float(removed) * perValue
        if removed > 0 {
            upload(i0, j0, i1, j1)
            for t in touched { kg += sealIfDone(t) }
        }
        return kg
    }

    /// Cleans along a stroke so fast sweeps leave a continuous line instead of dots.
    func cleanStroke(from a: SIMD2<Float>, to b: SIMD2<Float>, radius: Float, capacityLeft: Float) -> Float {
        let len = simd_length(b - a)
        let stepLen = max(radius * 0.7, cellSize)
        let steps = max(1, min(80, Int((len / stepLen).rounded(.up))))
        var got: Float = 0
        for s in 1...steps {
            let p = a + (b - a) * (Float(s) / Float(steps))
            let left = capacityLeft - got
            if left <= 0.00001 { break }
            got += clean(atX: p.x, z: p.y, radius: radius, capacityLeft: left)
        }
        return got
    }
}
