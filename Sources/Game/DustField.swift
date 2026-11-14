import UIKit
import SceneKit
import Metal

/// The layer of lunar dust over the whole map: a 1024 x 1024 grid (25 cm cells)
/// drawn as the alpha of a regolith-textured mesh sitting just above the ground.
final class DustField {
    static let res = 1024
    static let kgPerSquareMeter: Float = 0.5

    let res = DustField.res
    let cellSize: Float = WorldDims.size / Float(DustField.res)
    private(set) var mask: [UInt8]
    private let sector: [UInt8]
    private let fresh: [UInt8]
    private(set) var sectorDust: [Int]
    private(set) var sectorInitial: [Int]
    private(set) var totalDust: Int
    private(set) var initialTotal: Int
    let material = SCNMaterial()
    private var texture: MTLTexture?

    var cleanFraction: Double { 1.0 - Double(totalDust) / Double(max(initialTotal, 1)) }

    func sectorClean(_ i: Int) -> Double {
        1.0 - Double(sectorDust[i]) / Double(max(sectorInitial[i], 1))
    }

    private var kgPerValue: Float { cellSize * cellSize * DustField.kgPerSquareMeter / 255 }

    /// kg of dust still lying in a sector.
    func sectorKg(_ i: Int) -> Float { Float(sectorDust[i]) * kgPerValue }

    init(savedMask: [UInt8]?) {
        let n = DustField.res
        let cs = WorldDims.size / Float(n)
        var freshMask = [UInt8](repeating: 0, count: n * n)
        var sec = [UInt8](repeating: 0, count: n * n)
        for j in 0..<n {
            let z = WorldDims.minZ + (Float(j) + 0.5) * cs
            for i in 0..<n {
                let x = WorldDims.minX + (Float(i) + 0.5) * cs
                let thick = 0.75 + 0.25 * Noise.value(Float(i) / 36, Float(j) / 36, seed: 11)
                freshMask[j * n + i] = UInt8(255 * thick)
                sec[j * n + i] = UInt8(Hex.nearest(x, z))
            }
        }
        fresh = freshMask
        sector = sec
        let start: [UInt8] = (savedMask != nil && savedMask!.count == n * n) ? savedMask! : freshMask
        mask = start
        var initial = [Int](repeating: 0, count: Hex.count)
        var current = [Int](repeating: 0, count: Hex.count)
        for k in 0..<(n * n) {
            let s = Int(sec[k])
            initial[s] += Int(freshMask[k])
            current[s] += Int(start[k])
        }
        sectorInitial = initial
        sectorDust = current
        initialTotal = initial.reduce(0, +)
        totalDust = current.reduce(0, +)

        setupMaterial()
        upload(0, 0, n - 1, n - 1)
    }

    private func setupMaterial() {
        material.lightingModel = .lambert
        material.diffuse.contents = Tex.tinted(size: 512, tint: SIMD3<Float>(1.0, 0.975, 0.93)) { u, v in
            let a = Noise.fbmTile(u, v, basePeriod: 6, octaves: 5, seed: 40)
            let grain = Noise.hash(Int(u * 512), Int(v * 512), 41)
            return 0.66 + 0.2 * a + 0.07 * grain
        }
        material.normal.contents = Tex.normal(size: 512, strength: 5) { u, v in
            Noise.fbmTile(u, v, basePeriod: 10, octaves: 5, seed: 44)
        }
        let tile = SCNMatrix4MakeScale(110, 110, 1)
        for p in [material.diffuse, material.normal] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 4
            p.contentsTransform = tile
        }
        material.normal.intensity = 0.8
        material.multiply.contents = Tex.tinted(size: 256, tint: SIMD3<Float>(1, 1, 1)) { u, v in
            let a = Noise.value(u * 7, v * 7, seed: 61)
            let b = Noise.value(u * 19, v * 19, seed: 62)
            return 0.78 + 0.17 * a + 0.08 * b
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
        }
    }

    func reset() {
        mask = fresh
        sectorDust = sectorInitial
        totalDust = initialTotal
        upload(0, 0, res - 1, res - 1)
    }

    private func upload(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) {
        guard let t = texture, i0 <= i1, j0 <= j1 else { return }
        let w = i1 - i0 + 1, h = j1 - j0 + 1
        var buf = [UInt8](repeating: 255, count: w * h * 4)
        for j in 0..<h {
            let row = (j0 + j) * res + i0
            for i in 0..<w {
                let v = Int(mask[row + i])
                buf[(j * w + i) * 4 + 3] = v == 0 ? 0 : UInt8(min(255, 45 + v * 210 / 255))
            }
        }
        buf.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                t.replace(region: MTLRegionMake2D(i0, j0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
            }
        }
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
                let fall = max(0.25, 1 - t * t)
                potential += min(Float(mask[j * res + i]), maxRemove * fall)
            }
        }
        if potential <= 0 { return 0 }
        let scale = min(1, capacityLeft / (potential * perValue))

        var removed = 0
        var carry: Float = 0
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
                let fall = max(0.25, 1 - t * t)
                let want = min(Float(cur), maxRemove * fall) * scale + carry
                var take = Int(want)
                carry = want - Float(take)
                if cur <= 8 && scale >= 1 { take = Int(cur) }
                take = min(take, Int(cur))
                if take > 0 {
                    mask[idx] = cur - UInt8(take)
                    sectorDust[Int(sector[idx])] -= take
                    removed += take
                }
            }
        }
        if removed > 0 {
            totalDust -= removed
            upload(i0, j0, i1, j1)
        }
        return Float(removed) * perValue
    }
}
