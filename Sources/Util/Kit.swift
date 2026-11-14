import UIKit
import SceneKit

/// Loads the bundled Kenney Space Kit models (CC0) and hands out normalised copies:
/// centred on X/Z, sitting on y = 0, scaled so the footprint's longest side is `fit` metres.
/// Every caller treats a nil result as "model missing" and falls back to built-in shapes.
enum Kit {
    private static var sources: [String: SCNNode] = [:]
    private static var units: [String: SCNNode] = [:]
    private static var missing = Set<String>()

    static let orange = UIColor(red: 0.886, green: 0.40, blue: 0.27, alpha: 1)

    private static func restyle(_ m: SCNMaterial) {
        m.lightingModel = .blinn
        m.specular.contents = UIColor(white: 0.22, alpha: 1)
        m.shininess = 0.3
        m.isDoubleSided = true
        let name = (m.name ?? "").lowercased()
        if name.contains("glass") {
            m.diffuse.contents = UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1)
            m.specular.contents = UIColor(white: 0.9, alpha: 1)
        } else if name.contains("portal") {
            m.lightingModel = .constant
            m.diffuse.contents = UIColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 1)
        } else if name.contains("rock") {
            m.diffuse.contents = UIColor(white: 0.33, alpha: 1)
        } else if name == "metal" {
            m.diffuse.contents = orange
        }
    }

    private static func source(_ name: String) -> SCNNode? {
        if let s = sources[name] { return s }
        if missing.contains(name) { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "obj", subdirectory: "Models"),
              let scene = try? SCNScene(url: url, options: nil) else {
            missing.insert(name)
            return nil
        }
        let holder = SCNNode()
        for child in Array(scene.rootNode.childNodes) {
            child.removeFromParentNode()
            holder.addChildNode(child)
        }
        var found = false
        holder.enumerateHierarchy { n, _ in
            if let g = n.geometry {
                found = true
                g.materials.forEach { restyle($0) }
            }
        }
        if !found {
            missing.insert(name)
            return nil
        }
        sources[name] = holder
        return holder
    }

    /// A prototype with a 1 m footprint; `tint` (if given) repaints every surface.
    private static func unit(_ name: String, tint: UIColor?, key: String) -> SCNNode? {
        let cacheKey = name + "|" + key
        if let u = units[cacheKey] { return u }
        guard let src = source(name) else { return nil }
        let inner = src.clone()
        if let tint = tint {
            let paint = SCNMaterial()
            paint.lightingModel = .lambert
            paint.diffuse.contents = tint
            paint.isDoubleSided = true
            inner.enumerateHierarchy { n, _ in
                if let g = n.geometry, let copy = g.copy() as? SCNGeometry {
                    copy.materials = Array(repeating: paint, count: max(1, g.materials.count))
                    n.geometry = copy
                }
            }
        }
        let (mn, mx) = inner.boundingBox
        let span = max(mx.x - mn.x, mx.z - mn.z, 0.001)
        let k = 1 / span
        inner.scale = SCNVector3(k, k, k)
        inner.position = SCNVector3(-(mn.x + mx.x) / 2 * k, -mn.y * k, -(mn.z + mx.z) / 2 * k)
        let out = SCNNode()
        out.addChildNode(inner)
        units[cacheKey] = out
        return out
    }

    static func make(_ name: String, fit: Float, tint: UIColor? = nil, tintKey: String = "") -> SCNNode? {
        guard let u = unit(name, tint: tint, key: tint == nil ? "" : tintKey) else { return nil }
        let node = u.clone()
        node.scale = SCNVector3(fit, fit, fit)
        return node
    }
}
