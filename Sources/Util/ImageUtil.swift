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
