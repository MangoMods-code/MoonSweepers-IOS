import UIKit

enum ImageUtil {
    /// Builds a CGImage from straight (non-premultiplied) RGBA bytes.
    static func cgImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    static func image(width: Int, height: Int, rgba: [UInt8]) -> UIImage {
        if let cg = cgImage(width: width, height: height, rgba: rgba) {
            return UIImage(cgImage: cg)
        }
        return UIImage()
    }
}

/// Small deterministic RNG so the moon is the same every launch.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

enum Noise {
    static func hash(_ x: Int, _ z: Int, _ seed: Int = 0) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ z &* 668_265_263 &+ seed &* 2_147_483_647)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return Float(h & 0xFFFF) / 65535.0
    }

    static func value(_ x: Float, _ z: Float, seed: Int = 0) -> Float {
        let xf = x.rounded(.down), zf = z.rounded(.down)
        let xi = Int(xf), zi = Int(zf)
        let tx = x - xf, tz = z - zf
        let sx = tx * tx * (3 - 2 * tx)
        let sz = tz * tz * (3 - 2 * tz)
        let a = hash(xi, zi, seed), b = hash(xi + 1, zi, seed)
        let c = hash(xi, zi + 1, seed), d = hash(xi + 1, zi + 1, seed)
        let top = a + (b - a) * sx
        let bot = c + (d - c) * sx
        return top + (bot - top) * sz
    }
}

func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

extension Noise {
    /// Value noise that repeats every `period` lattice cells (for tiling textures).
    static func tile(_ x: Float, _ z: Float, period: Int, seed: Int) -> Float {
        let xf = x.rounded(.down), zf = z.rounded(.down)
        let xi = Int(xf), zi = Int(zf)
        let tx = x - xf, tz = z - zf
        let sx = tx * tx * (3 - 2 * tx)
        let sz = tz * tz * (3 - 2 * tz)
        func w(_ v: Int) -> Int { let m = v % period; return m < 0 ? m + period : m }
        let a = hash(w(xi), w(zi), seed), b = hash(w(xi + 1), w(zi), seed)
        let c = hash(w(xi), w(zi + 1), seed), d = hash(w(xi + 1), w(zi + 1), seed)
        let top = a + (b - a) * sx
        let bot = c + (d - c) * sx
        return top + (bot - top) * sz
    }

    /// Tiling fractal noise, u/v in 0...1, result 0...1.
    static func fbmTile(_ u: Float, _ v: Float, basePeriod: Int, octaves: Int, seed: Int) -> Float {
        var sum: Float = 0
        var amp: Float = 0.5
        var norm: Float = 0
        var p = basePeriod
        for o in 0..<octaves {
            sum += amp * tile(u * Float(p), v * Float(p), period: p, seed: seed + o * 17)
            norm += amp
            amp *= 0.5
            p *= 2
        }
        return sum / norm
    }
}

enum Tex {
    /// Greyscale-tinted texture from a 0...1 function of (u, v).
    static func tinted(size n: Int, tint: SIMD3<Float>, _ f: (Float, Float) -> Float) -> CGImage? {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for j in 0..<n {
            for i in 0..<n {
                let v = max(0, min(1, f(Float(i) / Float(n), Float(j) / Float(n))))
                let k = (j * n + i) * 4
                px[k] = UInt8(max(0, min(255, 255 * v * tint.x)))
                px[k + 1] = UInt8(max(0, min(255, 255 * v * tint.y)))
                px[k + 2] = UInt8(max(0, min(255, 255 * v * tint.z)))
            }
        }
        return ImageUtil.cgImage(width: n, height: n, rgba: px)
    }

    /// Tangent-space normal map from a tiling height function.
    static func normal(size n: Int, strength: Float, _ f: (Float, Float) -> Float) -> CGImage? {
        var h = [Float](repeating: 0, count: n * n)
        for j in 0..<n {
            for i in 0..<n {
                h[j * n + i] = f(Float(i) / Float(n), Float(j) / Float(n))
            }
        }
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for j in 0..<n {
            let jm = (j + n - 1) % n, jp = (j + 1) % n
            for i in 0..<n {
                let im = (i + n - 1) % n, ip = (i + 1) % n
                let dx = (h[j * n + ip] - h[j * n + im]) * strength
                let dz = (h[jp * n + i] - h[jm * n + i]) * strength
                let len = (dx * dx + dz * dz + 1).squareRoot()
                let k = (j * n + i) * 4
                px[k] = UInt8(max(0, min(255, (-dx / len * 0.5 + 0.5) * 255)))
                px[k + 1] = UInt8(max(0, min(255, (-dz / len * 0.5 + 0.5) * 255)))
                px[k + 2] = UInt8(max(0, min(255, (1 / len * 0.5 + 0.5) * 255)))
            }
        }
        return ImageUtil.cgImage(width: n, height: n, rgba: px)
    }
}
