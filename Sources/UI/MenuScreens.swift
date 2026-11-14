import UIKit

/// Dark panel with a title, an optional stats line and a column of buttons (the pause screen).
final class MenuViewController: UIViewController {
    struct Button {
        let title: String
        let style: Style
        let action: () -> Void
        enum Style { case primary, normal, danger }
    }

    var heading = "PAUSED"
    var stats: String?
    var buttons: [Button] = []

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.6)

        let panel = UIView()
        panel.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.97)
        panel.layer.cornerRadius = 18
        panel.layer.borderWidth = 2
        panel.layer.borderColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 0.8).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let title = UILabel()
        title.text = heading
        title.font = .systemFont(ofSize: 26, weight: .black)
        title.textColor = .white
        title.textAlignment = .center

        let left = UIStackView(arrangedSubviews: [title])
        left.axis = .vertical
        left.spacing = 10
        left.alignment = .center
        if let stats = stats {
            let s = UILabel()
            s.text = stats
            s.numberOfLines = 0
            s.textAlignment = .center
            s.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
            s.textColor = UIColor(white: 1, alpha: 0.8)
            left.addArrangedSubview(s)
        }

        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 8
        for b in buttons {
            let btn = UIButton(type: .system)
            btn.setTitle(b.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .heavy)
            btn.layer.cornerRadius = 10
            switch b.style {
            case .primary:
                btn.backgroundColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
                btn.tintColor = .black
            case .normal:
                btn.backgroundColor = UIColor(white: 1, alpha: 0.13)
                btn.tintColor = .white
            case .danger:
                btn.backgroundColor = UIColor(red: 0.6, green: 0.12, blue: 0.1, alpha: 0.6)
                btn.tintColor = UIColor(red: 1, green: 0.6, blue: 0.55, alpha: 1)
            }
            btn.heightAnchor.constraint(equalToConstant: 42).isActive = true
            btn.widthAnchor.constraint(equalToConstant: 230).isActive = true
            let action = b.action
            btn.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true) { action() }
            }, for: .touchUpInside)
            col.addArrangedSubview(btn)
        }

        let row = UIStackView(arrangedSubviews: [left, col])
        row.axis = .horizontal
        row.spacing = 36
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(row)

        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            row.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            row.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -22),
            row.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 32),
            row.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -32),
            left.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
    }
}

/// The settings screen. Reads and writes through closures so it never owns the save.
final class SettingsViewController: UIViewController {
    struct Values {
        var soundOn = true
        var hapticsOn = true
        var highGraphics = true
        var invertY = false
        var sensitivity: Float = 1
        var gridOn = false
    }

    var values = Values()
    var onChange: ((Values) -> Void)?
    var onClose: (() -> Void)?
    private let sensLabel = UILabel()

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.6)

        let panel = UIView()
        panel.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.97)
        panel.layer.cornerRadius = 18
        panel.layer.borderWidth = 2
        panel.layer.borderColor = UIColor(red: 0.4, green: 0.92, blue: 1, alpha: 0.8).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let title = UILabel()
        title.text = "SETTINGS"
        title.font = .systemFont(ofSize: 22, weight: .black)
        title.textColor = UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1)

        let done = UIButton(type: .system)
        done.setTitle("DONE", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        done.tintColor = .black
        done.backgroundColor = UIColor(red: 0.4, green: 0.92, blue: 1, alpha: 1)
        done.layer.cornerRadius = 10
        done.widthAnchor.constraint(equalToConstant: 90).isActive = true
        done.heightAnchor.constraint(equalToConstant: 36).isActive = true
        done.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.onClose?() }
        }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), done])
        header.axis = .horizontal
        header.alignment = .center

        func sectionLabel(_ text: String) -> UILabel {
            let l = UILabel()
            l.text = text
            l.font = .systemFont(ofSize: 12, weight: .heavy)
            l.textColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
            return l
        }
        func row(_ name: String, _ detail: String, _ control: UIView) -> UIView {
            let n = UILabel()
            n.text = name
            n.font = .systemFont(ofSize: 16, weight: .bold)
            n.textColor = .white
            let d = UILabel()
            d.text = detail
            d.font = .systemFont(ofSize: 12, weight: .medium)
            d.textColor = UIColor(white: 1, alpha: 0.6)
            let texts = UIStackView(arrangedSubviews: [n, d])
            texts.axis = .vertical
            texts.spacing = 1
            control.setContentHuggingPriority(.required, for: .horizontal)
            let h = UIStackView(arrangedSubviews: [texts, control])
            h.axis = .horizontal
            h.alignment = .center
            h.spacing = 14
            h.isLayoutMarginsRelativeArrangement = true
            h.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            let box = UIView()
            box.backgroundColor = UIColor(white: 1, alpha: 0.06)
            box.layer.cornerRadius = 12
            h.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(h)
            NSLayoutConstraint.activate([
                h.topAnchor.constraint(equalTo: box.topAnchor),
                h.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                h.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                h.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            ])
            return box
        }
        func toggle(_ on: Bool, _ set: @escaping (inout Values, Bool) -> Void) -> UISwitch {
            let s = UISwitch()
            s.isOn = on
            s.onTintColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
            s.addAction(UIAction { [weak self, weak s] _ in
                guard let self = self, let s = s else { return }
                set(&self.values, s.isOn)
                self.onChange?(self.values)
            }, for: .valueChanged)
            return s
        }

        let quality = UISegmentedControl(items: ["Performance", "High"])
        quality.selectedSegmentIndex = values.highGraphics ? 1 : 0
        quality.selectedSegmentTintColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
        quality.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        quality.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        quality.addAction(UIAction { [weak self, weak quality] _ in
            guard let self = self, let q = quality else { return }
            self.values.highGraphics = q.selectedSegmentIndex == 1
            self.onChange?(self.values)
        }, for: .valueChanged)

        let slider = UISlider()
        slider.minimumValue = 0.4
        slider.maximumValue = 2.2
        slider.value = values.sensitivity
        slider.minimumTrackTintColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        slider.addAction(UIAction { [weak self, weak slider] _ in
            guard let self = self, let sl = slider else { return }
            self.values.sensitivity = sl.value
            self.sensLabel.text = String(format: "%.1f×", sl.value)
            self.onChange?(self.values)
        }, for: .valueChanged)
        sensLabel.text = String(format: "%.1f×", values.sensitivity)
        sensLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        sensLabel.textColor = .white
        sensLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let sens = UIStackView(arrangedSubviews: [slider, sensLabel])
        sens.axis = .horizontal
        sens.spacing = 8
        sens.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            sectionLabel("  AUDIO"),
            row("Sound", "Effects and suit ambience.", toggle(values.soundOn) { $0.soundOn = $1 }),
            row("Vibration", "Haptic feedback while scrubbing.", toggle(values.hapticsOn) { $0.hapticsOn = $1 }),
            sectionLabel("  GRAPHICS"),
            row("Quality", "High adds shadows, bloom and ambient occlusion.", quality),
            row("Hex grid", "Outline the hex tiles on the ground.", toggle(values.gridOn) { $0.gridOn = $1 }),
            sectionLabel("  CONTROLS"),
            row("Look sensitivity", "How fast the camera turns.", sens),
            row("Invert look", "Drag up to look down.", toggle(values.invertY) { $0.invertY = $1 }),
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(16, after: stack.arrangedSubviews[2])
        stack.setCustomSpacing(16, after: stack.arrangedSubviews[5])

        let scroll = UIScrollView()
        scroll.indicatorStyle = .white
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        panel.addSubview(header)
        panel.addSubview(scroll)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            panel.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            panel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
            panel.widthAnchor.constraint(equalTo: g.widthAnchor, multiplier: 0.74),
            header.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }
}
