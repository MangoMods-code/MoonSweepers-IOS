import UIKit
import SceneKit

/// The layer of moon dust covering the whole map. Stored as a grid of
/// 0...255 values and shown as an alpha texture on a mesh above the ground.
final class DustField {
    let res: Int
    let worldSize: Float
    private(set) var mask: [UInt8]
    private var pixels: [UInt8]
    let material: SCNMaterial
    private(set) var totalDust: Int = 0
    private(set) var initialTotal: Int = 1
    private var dirty = true
    private var timeSinceUpload: Float = 0

    var cellSize: Float { worldSize / Float(res) }
    var cellArea: Float { cellSize * cellSize }

    /// 0...1 fraction of the moon that's clean.
    var cleanFraction: Double {
        1.0 - Double(totalDust) / Double(max(initialTotal, 1))
    }

    init(res: Int, worldSize: Float, savedMask: [UInt8]?) {
        self.res = res
        self.worldSize = worldSize
        let count = res * res
        var pixels = [UInt8](repeating: 0, count: count * 4)

        // Base dust colour with grain, plus the starting amount of dust per cell.
        var fresh = [UInt8](repeating: 0, count: count)
        for j in 0..<res {
            for i in 0..<res {
                let idx = j * res + i
                let fx = Float(i), fz = Float(j)
                let grain = Noise.hash(i, j, 7)
                let blotch = Noise.value(fx / 24, fz / 24, seed: 3)
                let tone = 0.72 + 0.16 * blotch + 0.10 * grain
                pixels[idx * 4 + 0] = UInt8(min(255, 205 * tone + 20))
                pixels[idx * 4 + 1] = UInt8(min(255, 198 * tone + 18))
                pixels[idx * 4 + 2] = UInt8(min(255, 186 * tone + 14))
                let thick = 0.75 + 0.25 * Noise.value(fx / 9, fz / 9, seed: 11)
                fresh[idx] = UInt8(255 * thick)
            }
        }
        let startMask: [UInt8]
        if let saved = savedMask, saved.count == count {
            startMask = saved
        } else {
            startMask = fresh
        }
        self.pixels = pixels
        self.mask = startMask
        self.initialTotal = fresh.reduce(0) { $0 + Int($1) }
        self.totalDust = startMask.reduce(0) { $0 + Int($1) }

        material = SCNMaterial()
        material.lightingModel = .lambert
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        upload()
    }

    func reset() {
        var fresh = [UInt8](repeating: 0, count: res * res)
        for j in 0..<res {
            for i in 0..<res {
                let thick = 0.75 + 0.25 * Noise.value(Float(i) / 9, Float(j) / 9, seed: 11)
                fresh[j * res + i] = UInt8(255 * thick)
            }
        }
        mask = fresh
        totalDust = mask.reduce(0) { $0 + Int($1) }
        dirty = true
        upload()
    }

    private func cellIndex(x: Float, z: Float) -> (Int, Int) {
        let half = worldSize / 2
        let i = Int(((x + half) / cellSize).rounded(.down))
        let j = Int(((z + half) / cellSize).rounded(.down))
        return (i, j)
    }

    /// 0...1 amount of dust at a world position.
    func dust(atX x: Float, z: Float) -> Float {
        let (i, j) = cellIndex(x: x, z: z)
        guard i >= 0, j >= 0, i < res, j < res else { return 0 }
        return Float(mask[j * res + i]) / 255
    }

    /// Average dust in a small area.
    func averageDust(atX x: Float, z: Float, radius: Float) -> Float {
        var sum: Float = 0, n: Float = 0
        let steps = 3
        for a in -steps...steps {
            for b in -steps...steps {
                let ox = Float(a) / Float(steps) * radius
                let oz = Float(b) / Float(steps) * radius
                sum += dust(atX: x + ox, z: z + oz); n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }

    /// Removes dust in a circle. Returns dust units collected, never more than `capacityLeft`.
    @discardableResult
    func clean(atX x: Float, z: Float, radius: Float, rate: Float, dt: Float, capacityLeft: Float) -> Float {
        guard capacityLeft > 0.0001 else { return 0 }
        let half = worldSize / 2
        let cs = cellSize
        let r = radius + cs * 0.5
        let i0 = max(0, Int(((x - r + half) / cs).rounded(.down)))
        let i1 = min(res - 1, Int(((x + r + half) / cs).rounded(.down)))
        let j0 = max(0, Int(((z - r + half) / cs).rounded(.down)))
        let j1 = min(res - 1, Int(((z + r + half) / cs).rounded(.down)))
        guard i0 <= i1, j0 <= j1 else { return 0 }

        let maxRemove = rate * dt * 255
        let unitsPerValue = cellArea * Upgrades.unitsPerSquareMeter / 255

        // First pass: how much could we take?
        var potential: Float = 0
        for j in j0...j1 {
            let cz = -half + (Float(j) + 0.5) * cs
            for i in i0...i1 {
                let cx = -half + (Float(i) + 0.5) * cs
                let d = sqrt((cx - x) * (cx - x) + (cz - z) * (cz - z))
                if d > r { continue }
                let t = d / r
                let fall = max(0.15, 1 - t * t * t * t)
                potential += min(Float(mask[j * res + i]), maxRemove * fall)
            }
        }
        if potential <= 0 { return 0 }
        let scale = min(1, capacityLeft / (potential * unitsPerValue))

        var removedTotal = 0
        var carry: Float = 0
        for j in j0...j1 {
            let cz = -half + (Float(j) + 0.5) * cs
            for i in i0...i1 {
                let cx = -half + (Float(i) + 0.5) * cs
                let d = sqrt((cx - x) * (cx - x) + (cz - z) * (cz - z))
                if d > r { continue }
                let idx = j * res + i
                let cur = mask[idx]
                if cur == 0 { continue }
                let t = d / r
                let fall = max(0.15, 1 - t * t * t * t)
                let want = min(Float(cur), maxRemove * fall) * scale + carry
                var take = Int(want)
                carry = want - Float(take)
                // Make sure even slow tools finish off nearly clean cells.
                if take == 0 && cur <= 6 && scale >= 1 { take = Int(cur) }
                take = min(take, Int(cur))
                if take > 0 {
                    mask[idx] = cur - UInt8(take)
                    removedTotal += take
                }
            }
        }
        if removedTotal > 0 {
            totalDust -= removedTotal
            dirty = true
        }
        return Float(removedTotal) * unitsPerValue
    }

    /// Re-uploads the dust texture at most ~12 times per second.
    func tick(dt: Float) {
        timeSinceUpload += dt
        if dirty && timeSinceUpload > 0.08 {
            upload()
        }
    }

    private func upload() {
        timeSinceUpload = 0
        dirty = false
        let count = res * res
        pixels.withUnsafeMutableBufferPointer { p in
            mask.withUnsafeBufferPointer { m in
                for idx in 0..<count {
                    let v = Int(m[idx])
                    // Thin dust still shows a little, fully clean is fully see-through.
                    p[idx * 4 + 3] = v == 0 ? 0 : UInt8(min(255, 30 + v * 225 / 255))
                }
            }
        }
        material.diffuse.contents = ImageUtil.cgImage(width: res, height: res, rgba: pixels)
    }
}
