import UIKit
import simd

/// The Moon Map: sector progress, stations, flags, waypoints and station teleport.
final class MapViewController: UIViewController {
    struct Snapshot {
        var sectorClean: [Double] = []
        var stationsFound: [Bool] = []
        var stationPos: [SIMD3<Float>] = []
        var flagPos: [SIMD3<Float>] = []
        var flagsClaimed: [Bool] = []
        var botPos: [SIMD3<Float>] = []
        var vehiclePos: SIMD3<Float>?
        var playerPos = SIMD3<Float>(0, 0, 0)
        var playerYaw: Float = 0
        var waypoint: SIMD2<Float>?
        var canTeleport = true
        var money: Double = 0
        var stationCost = 0
        var hasBuildTool = false
    }

    var snapshot = Snapshot()
    var onWaypoint: ((SIMD2<Float>?) -> Void)?
    var onTeleport: ((Int) -> Void)?
    var onBuild: ((Int) -> Void)?
    var onClose: (() -> Void)?

    private let canvas = MapCanvas()
    private let info = UILabel()
    private let teleportButton = UIButton(type: .system)
    private let buildButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private var selected: Int?

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 0.96)
        canvas.snapshot = snapshot
        canvas.backgroundColor = .clear
        canvas.contentMode = .redraw
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        canvas.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))

        let title = UILabel()
        title.text = "MOON MAP"
        title.font = .systemFont(ofSize: 20, weight: .black)
        title.textColor = UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1)

        info.numberOfLines = 0
        info.font = .systemFont(ofSize: 13, weight: .semibold)
        info.textColor = UIColor(white: 1, alpha: 0.85)
        info.text = "Tap the map to drop a waypoint.\nTap a station marker to teleport there, or to build one."

        func style(_ b: UIButton, _ text: String, _ color: UIColor) {
            b.setTitle(text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
            b.tintColor = .black
            b.backgroundColor = color
            b.layer.cornerRadius = 10
            b.heightAnchor.constraint(equalToConstant: 42).isActive = true
        }
        style(teleportButton, "TELEPORT", UIColor(red: 0.35, green: 0.92, blue: 1, alpha: 1))
        teleportButton.isHidden = true
        teleportButton.addAction(UIAction { [weak self] _ in
            guard let self = self, let s = self.selected else { return }
            self.dismiss(animated: true) { self.onTeleport?(s) }
        }, for: .touchUpInside)
        style(buildButton, "BUILD STATION", UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1))
        buildButton.isHidden = true
        buildButton.addAction(UIAction { [weak self] _ in
            guard let self = self, let s = self.selected else { return }
            self.dismiss(animated: true) { self.onBuild?(s) }
        }, for: .touchUpInside)
        style(clearButton, "CLEAR WAYPOINT", UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1))
        clearButton.isHidden = snapshot.waypoint == nil
        clearButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.snapshot.waypoint = nil
            self.canvas.snapshot = self.snapshot
            self.canvas.setNeedsDisplay()
            self.clearButton.isHidden = true
            self.onWaypoint?(nil)
        }, for: .touchUpInside)
        let close = UIButton(type: .system)
        style(close, "CLOSE", UIColor(white: 0.85, alpha: 1))
        close.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.onClose?() }
        }, for: .touchUpInside)

        let total = snapshot.sectorClean.isEmpty ? 0 : snapshot.sectorClean.reduce(0, +) / Double(snapshot.sectorClean.count)
        let stats = UILabel()
        stats.numberOfLines = 0
        stats.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        stats.textColor = .white
        let found = snapshot.stationsFound.filter { $0 }.count
        let flags = snapshot.flagsClaimed.filter { $0 }.count
        stats.text = String(format: "Moon cleaned  %.2f%%\nStations  %d / 12\nFlags  %d / %d", total * 100, found, flags, snapshot.flagsClaimed.count)

        let spacer = UIView()
        let side = UIStackView(arrangedSubviews: [title, stats, info, spacer, teleportButton, buildButton, clearButton, close])
        side.axis = .vertical
        side.spacing = 12
        side.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(side)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            side.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            side.topAnchor.constraint(equalTo: g.topAnchor, constant: 14),
            side.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -14),
            side.widthAnchor.constraint(equalToConstant: 210),
            canvas.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 8),
            canvas.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            canvas.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -8),
            canvas.trailingAnchor.constraint(equalTo: side.leadingAnchor, constant: -12),
        ])
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let p = g.location(in: canvas)
        // Station hit?
        for (i, sp) in snapshot.stationPos.enumerated() {
            let q = canvas.toView(sp.x, sp.z)
            if hypot(q.x - p.x, q.y - p.y) < 22 {
                selected = i
                let found = i < snapshot.stationsFound.count && snapshot.stationsFound[i]
                let pct = i < snapshot.sectorClean.count ? snapshot.sectorClean[i] * 100 : 0
                var text = String(format: "SECTOR %02d\n%@\n%.1f%% clean", i + 1, Hex.names[i], pct)
                teleportButton.isHidden = true
                buildButton.isHidden = true
                if found {
                    if snapshot.canTeleport {
                        teleportButton.isHidden = false
                    } else {
                        text += "\nLeave your vehicle to teleport."
                    }
                } else {
                    text += "\nNo station here yet. A station lets you sell, upgrade and teleport in this sector."
                    if !snapshot.hasBuildTool {
                        text += "\nNeeds the Building Tool (Supply Wall, $50)."
                    } else {
                        buildButton.isHidden = false
                        let afford = snapshot.money >= Double(snapshot.stationCost)
                        buildButton.setTitle("BUILD  $\(snapshot.stationCost)", for: .normal)
                        buildButton.isEnabled = afford
                        buildButton.alpha = afford ? 1 : 0.4
                    }
                }
                info.text = text
                canvas.selected = i
                canvas.setNeedsDisplay()
                return
            }
        }
        let w = canvas.toWorld(p)
        guard WorldDims.contains(w.x, w.y, margin: 6) else { return }
        selected = nil
        canvas.selected = nil
        teleportButton.isHidden = true
        buildButton.isHidden = true
        snapshot.waypoint = w
        canvas.snapshot = snapshot
        canvas.setNeedsDisplay()
        clearButton.isHidden = false
        info.text = "Waypoint set in \(Hex.names[Hex.nearest(w.x, w.y)])."
        onWaypoint?(w)
    }
}

final class MapCanvas: UIView {
    var snapshot = MapViewController.Snapshot()
    var selected: Int?

    private var scale: CGFloat { min(bounds.width, bounds.height) / CGFloat(WorldDims.size) }
    private var origin: CGPoint {
        CGPoint(x: (bounds.width - CGFloat(WorldDims.size) * scale) / 2,
                y: (bounds.height - CGFloat(WorldDims.size) * scale) / 2)
    }

    func toView(_ x: Float, _ z: Float) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x - WorldDims.minX) * scale,
                y: origin.y + CGFloat(z - WorldDims.minZ) * scale)
    }

    func toWorld(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2<Float>(Float((p.x - origin.x) / scale) + WorldDims.minX,
                     Float((p.y - origin.y) / scale) + WorldDims.minZ)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let mapRect = CGRect(x: origin.x, y: origin.y,
                             width: CGFloat(WorldDims.size) * scale, height: CGFloat(WorldDims.size) * scale)
        ctx.saveGState()
        ctx.clip(to: mapRect)
        UIColor(white: 0.1, alpha: 1).setFill()
        ctx.fill(mapRect)

        for i in 0..<Hex.count {
            let clean = i < snapshot.sectorClean.count ? CGFloat(snapshot.sectorClean[i]) : 0
            let path = UIBezierPath()
            for (k, c) in Hex.corners(i).enumerated() {
                let p = toView(c.x, c.y)
                if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.close()
            // Dusty = pale grey, clean = deep blue-grey, finished = green.
            let fill: UIColor
            if clean >= 0.99 {
                fill = UIColor(red: 0.16, green: 0.5, blue: 0.3, alpha: 1)
            } else {
                fill = UIColor(red: 0.74 - 0.56 * clean, green: 0.72 - 0.5 * clean, blue: 0.68 - 0.36 * clean, alpha: 1)
            }
            fill.setFill()
            path.fill()
            (i == selected ? UIColor(red: 0.35, green: 0.92, blue: 1, alpha: 1) : UIColor(white: 0, alpha: 0.55)).setStroke()
            path.lineWidth = i == selected ? 3 : 1.5
            path.stroke()

            let c = Hex.centers[i]
            let cp = toView(c.x, c.y)
            let text = String(format: "%.0f%%", Double(clean) * 100) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .heavy),
                .foregroundColor: clean > 0.45 ? UIColor.white : UIColor.black,
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: cp.x - size.width / 2, y: cp.y + 9), withAttributes: attrs)
        }

        // Flags
        for (i, f) in snapshot.flagPos.enumerated() {
            let claimed = i < snapshot.flagsClaimed.count && snapshot.flagsClaimed[i]
            let p = toView(f.x, f.z)
            (claimed ? UIColor(red: 0.2, green: 0.55, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)).setFill()
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: p.x - 3, y: p.y + 4))
            tri.addLine(to: CGPoint(x: p.x - 3, y: p.y - 5))
            tri.addLine(to: CGPoint(x: p.x + 5, y: p.y - 2))
            tri.addLine(to: CGPoint(x: p.x - 3, y: p.y + 1))
            tri.close()
            tri.fill()
        }

        // Stations
        for (i, s) in snapshot.stationPos.enumerated() {
            let found = i < snapshot.stationsFound.count && snapshot.stationsFound[i]
            let p = toView(s.x, s.z)
            let r: CGFloat = i == Hex.home ? 8 : 6
            let hex = UIBezierPath()
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3 + .pi / 6
                let q = CGPoint(x: p.x + cos(a) * r, y: p.y + sin(a) * r)
                if k == 0 { hex.move(to: q) } else { hex.addLine(to: q) }
            }
            hex.close()
            (found ? UIColor(red: 0.3, green: 1, blue: 0.55, alpha: 1) : UIColor(white: 0.25, alpha: 0.55)).setFill()
            hex.fill()
            UIColor.black.setStroke()
            hex.lineWidth = 1.5
            hex.stroke()
        }

        // Robots and vehicle
        UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1).setFill()
        for b in snapshot.botPos {
            let p = toView(b.x, b.z)
            ctx.fillEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
        }
        if let v = snapshot.vehiclePos {
            let p = toView(v.x, v.z)
            UIColor.white.setFill()
            ctx.fill(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            UIColor(red: 0.96, green: 0.46, blue: 0.1, alpha: 1).setFill()
            ctx.fill(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
        }

        // Waypoint
        if let w = snapshot.waypoint {
            let p = toView(w.x, w.y)
            UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
            ring.lineWidth = 3
            ring.stroke()
            let dot = UIBezierPath(ovalIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1).setFill()
            dot.fill()
        }

        // Player arrow (north / -Z is up).
        let pp = toView(snapshot.playerPos.x, snapshot.playerPos.z)
        let yaw = CGFloat(snapshot.playerYaw)
        let fwd = CGPoint(x: -sin(yaw), y: -cos(yaw))
        let rightV = CGPoint(x: cos(yaw), y: -sin(yaw))
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: pp.x + fwd.x * 11, y: pp.y + fwd.y * 11))
        arrow.addLine(to: CGPoint(x: pp.x - fwd.x * 6 + rightV.x * 7, y: pp.y - fwd.y * 6 + rightV.y * 7))
        arrow.addLine(to: CGPoint(x: pp.x - fwd.x * 2, y: pp.y - fwd.y * 2))
        arrow.addLine(to: CGPoint(x: pp.x - fwd.x * 6 - rightV.x * 7, y: pp.y - fwd.y * 6 - rightV.y * 7))
        arrow.close()
        UIColor(red: 0.35, green: 0.92, blue: 1, alpha: 1).setFill()
        arrow.fill()
        UIColor.black.setStroke()
        arrow.lineWidth = 1.5
        arrow.stroke()

        ctx.restoreGState()
        UIColor(white: 1, alpha: 0.3).setStroke()
        ctx.stroke(mapRect, width: 1)
    }
}
