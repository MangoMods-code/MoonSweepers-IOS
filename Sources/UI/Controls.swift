import UIKit

/// Floating virtual joystick: appears where your thumb lands.
final class JoystickView: UIView {
    private(set) var value = CGPoint.zero  // x right, y up, length <= 1
    private let base = UIView()
    private let knob = UIView()
    private var activeTouch: UITouch?
    private var center0 = CGPoint.zero
    private let radius: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        base.frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        base.layer.cornerRadius = radius
        base.backgroundColor = UIColor(white: 1, alpha: 0.08)
        base.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        base.layer.borderWidth = 2
        base.isUserInteractionEnabled = false
        knob.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        knob.layer.cornerRadius = 27
        knob.backgroundColor = UIColor(white: 1, alpha: 0.45)
        knob.isUserInteractionEnabled = false
        addSubview(base)
        addSubview(knob)
        resetVisual()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if activeTouch == nil { resetVisual() }
    }

    private func resetVisual() {
        center0 = CGPoint(x: radius + 40, y: bounds.height - radius - 40)
        base.center = center0
        knob.center = center0
        base.alpha = 0.55
        knob.alpha = 0.55
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        center0 = t.location(in: self)
        base.center = center0
        knob.center = center0
        base.alpha = 1
        knob.alpha = 1
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let p = t.location(in: self)
        var dx = p.x - center0.x, dy = p.y - center0.y
        let len = sqrt(dx * dx + dy * dy)
        if len > radius { dx = dx / len * radius; dy = dy / len * radius }
        knob.center = CGPoint(x: center0.x + dx, y: center0.y + dy)
        value = CGPoint(x: dx / radius, y: -dy / radius)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        value = .zero
        resetVisual()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

/// Drag anywhere on it to look around.
final class LookPad: UIView {
    var onLook: ((CGFloat, CGFloat) -> Void)?
    private var activeTouch: UITouch?
    private var last = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        last = t.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let p = t.location(in: self)
        onLook?(p.x - last.x, p.y - last.y)
        last = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

/// Round hold-able button that also lets you drag to look while holding.
final class HoldButton: UIView {
    var isHeld = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onDragLook: ((CGFloat, CGFloat) -> Void)?
    private let label = UILabel()
    private var activeTouch: UITouch?
    private var last = CGPoint.zero
    var tint: UIColor = .white { didSet { applyStyle() } }

    init(title: String, size: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        isMultipleTouchEnabled = true
        layer.cornerRadius = size / 2
        layer.borderWidth = 2
        label.text = title
        label.font = .systemFont(ofSize: size > 80 ? 15 : 12, weight: .heavy)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.frame = bounds.insetBy(dx: 6, dy: 6)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
        applyStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    var title: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    private func applyStyle() {
        layer.borderColor = tint.withAlphaComponent(0.8).cgColor
        backgroundColor = tint.withAlphaComponent(isHeld ? 0.45 : 0.16)
        label.textColor = .white
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        last = t.location(in: self)
        isHeld = true
        applyStyle()
        onPress?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let p = t.location(in: self)
        onDragLook?(p.x - last.x, p.y - last.y)
        last = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        isHeld = false
        applyStyle()
        onRelease?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

/// Thin labelled progress bar.
final class MeterView: UIView {
    private let fill = UIView()
    private let text = UILabel()
    var fraction: CGFloat = 0 { didSet { setNeedsLayout() } }
    var color: UIColor = .white { didSet { fill.backgroundColor = color } }
    var caption: String = "" { didSet { text.text = caption } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.45)
        layer.cornerRadius = 5
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        clipsToBounds = true
        addSubview(fill)
        text.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        text.textColor = .white
        text.textAlignment = .center
        addSubview(text)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let f = max(0, min(1, fraction))
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * f, height: bounds.height)
        text.frame = bounds
    }
}
