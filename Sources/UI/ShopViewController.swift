import UIKit

/// Shared screen for the Supply Wall, Upgrade Matrix and Garage.
final class ShopViewController: UIViewController {
    struct Item {
        let title: String
        let detail: String
        let cost: Int?          // nil = nothing to buy
        let status: String?     // shown instead of a price ("OWNED", "NEEDS …")
        let buy: () -> Void
    }
    struct Section {
        let header: String
        let items: [Item]
    }

    var heading = "SUPPLY WALL"
    var accent = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
    var money: () -> Double = { 0 }
    var sections: () -> [Section] = { [] }
    var onClose: (() -> Void)?

    private let panel = UIView()
    private let moneyLabel = UILabel()
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.55)

        panel.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 0.97)
        panel.layer.cornerRadius = 18
        panel.layer.borderColor = accent.withAlphaComponent(0.8).cgColor
        panel.layer.borderWidth = 2
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let title = UILabel()
        title.text = heading
        title.font = .systemFont(ofSize: 20, weight: .black)
        title.textColor = accent
        title.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(title)

        moneyLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .heavy)
        moneyLabel.textColor = UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
        moneyLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(moneyLabel)

        let close = UIButton(type: .system)
        close.setTitle("CLOSE", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        close.tintColor = .white
        close.backgroundColor = UIColor(white: 1, alpha: 0.12)
        close.layer.cornerRadius = 10
        close.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        close.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.onClose?() }
        }, for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(close)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.indicatorStyle = .white
        panel.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            panel.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            panel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
            panel.widthAnchor.constraint(equalTo: g.widthAnchor, multiplier: 0.88),

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            moneyLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            moneyLabel.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -16),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        reload()
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func dollars(_ v: Double) -> String {
        "$" + (formatter.string(from: NSNumber(value: v.rounded(.down))) ?? "0")
    }

    func reload() {
        moneyLabel.text = ShopViewController.dollars(money())
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for section in sections() {
            let h = UILabel()
            h.text = "  " + section.header.uppercased()
            h.font = .systemFont(ofSize: 12, weight: .heavy)
            h.textColor = accent
            stack.addArrangedSubview(h)
            for item in section.items {
                stack.addArrangedSubview(row(for: item))
            }
            stack.setCustomSpacing(16, after: stack.arrangedSubviews.last ?? h)
        }
    }

    private func row(for item: Item) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 1, alpha: 0.06)
        box.layer.cornerRadius = 12

        let name = UILabel()
        name.text = item.title
        name.font = .systemFont(ofSize: 16, weight: .bold)
        name.textColor = .white
        name.adjustsFontSizeToFitWidth = true
        name.minimumScaleFactor = 0.7

        let det = UILabel()
        det.text = item.detail
        det.font = .systemFont(ofSize: 12, weight: .medium)
        det.textColor = UIColor(white: 1, alpha: 0.7)
        det.numberOfLines = 2

        let texts = UIStackView(arrangedSubviews: [name, det])
        texts.axis = .vertical
        texts.spacing = 2

        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        btn.layer.cornerRadius = 10
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        if let status = item.status {
            btn.setTitle(status, for: .normal)
            btn.tintColor = UIColor(white: 1, alpha: 0.5)
            btn.backgroundColor = UIColor(white: 1, alpha: 0.06)
            btn.isEnabled = false
        } else if let cost = item.cost {
            let afford = money() >= Double(cost)
            btn.setTitle(cost == 0 ? "TAKE" : "BUY  $\(cost)", for: .normal)
            btn.tintColor = afford ? .black : UIColor(white: 1, alpha: 0.5)
            btn.backgroundColor = afford ? UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1) : UIColor(white: 1, alpha: 0.1)
            btn.isEnabled = afford
            btn.addAction(UIAction { [weak self] _ in
                item.buy()
                self?.reload()
            }, for: .touchUpInside)
        }
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)

        let h = UIStackView(arrangedSubviews: [texts, btn])
        h.axis = .horizontal
        h.alignment = .center
        h.spacing = 12
        h.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(h)
        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: box.topAnchor, constant: 9),
            h.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -9),
            h.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            h.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
        ])
        return box
    }
}
