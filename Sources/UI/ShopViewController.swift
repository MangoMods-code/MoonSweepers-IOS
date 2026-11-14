import UIKit

/// The Upgrade Terminal screen.
final class ShopViewController: UIViewController {
    struct Item {
        let title: String
        let current: String
        let next: String?
        let detail: String
        let cost: Int?
        let buy: () -> Void
    }

    var credits: () -> Double = { 0 }
    var items: () -> [Item] = { [] }
    var onClose: (() -> Void)?

    private let panel = UIView()
    private let creditsLabel = UILabel()
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0, alpha: 0.55)

        panel.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 0.96)
        panel.layer.cornerRadius = 18
        panel.layer.borderColor = UIColor(red: 0.3, green: 0.8, blue: 1, alpha: 0.7).cgColor
        panel.layer.borderWidth = 2
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let title = UILabel()
        title.text = "L.S.D. UPGRADE TERMINAL"
        title.font = .systemFont(ofSize: 20, weight: .black)
        title.textColor = UIColor(red: 0.5, green: 0.9, blue: 1, alpha: 1)
        title.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(title)

        creditsLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .bold)
        creditsLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        creditsLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(creditsLabel)

        let close = UIButton(type: .system)
        close.setTitle("CLOSE", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        close.tintColor = .white
        close.backgroundColor = UIColor(white: 1, alpha: 0.12)
        close.layer.cornerRadius = 10
        close.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(close)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.indicatorStyle = .white
        panel.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: g.centerXAnchor),
            panel.topAnchor.constraint(equalTo: g.topAnchor, constant: 14),
            panel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -14),
            panel.widthAnchor.constraint(equalTo: g.widthAnchor, multiplier: 0.86),

            title.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            creditsLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            creditsLabel.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -16),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        reload()
    }

    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in self?.onClose?() }
    }

    func reload() {
        creditsLabel.text = "◈ \(Int(credits())) credits"
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items() {
            stack.addArrangedSubview(row(for: item))
        }
    }

    private func row(for item: Item) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 1, alpha: 0.06)
        box.layer.cornerRadius = 12

        let name = UILabel()
        name.text = item.title.uppercased()
        name.font = .systemFont(ofSize: 12, weight: .heavy)
        name.textColor = UIColor(white: 1, alpha: 0.55)

        let cur = UILabel()
        cur.text = item.next.map { "\(item.current)  →  \($0)" } ?? "\(item.current)  (max)"
        cur.font = .systemFont(ofSize: 16, weight: .bold)
        cur.textColor = .white
        cur.adjustsFontSizeToFitWidth = true
        cur.minimumScaleFactor = 0.7

        let det = UILabel()
        det.text = item.detail
        det.font = .systemFont(ofSize: 12, weight: .medium)
        det.textColor = UIColor(white: 1, alpha: 0.7)
        det.numberOfLines = 2

        let texts = UIStackView(arrangedSubviews: [name, cur, det])
        texts.axis = .vertical
        texts.spacing = 2

        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        btn.layer.cornerRadius = 10
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        if let cost = item.cost {
            let afford = credits() >= Double(cost)
            btn.setTitle("BUY  ◈ \(cost)", for: .normal)
            btn.tintColor = afford ? .black : UIColor(white: 1, alpha: 0.5)
            btn.backgroundColor = afford ? UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1) : UIColor(white: 1, alpha: 0.1)
            btn.isEnabled = afford
            btn.addAction(UIAction { [weak self] _ in
                item.buy()
                self?.reload()
            }, for: .touchUpInside)
        } else {
            btn.setTitle("OWNED", for: .normal)
            btn.tintColor = UIColor(white: 1, alpha: 0.5)
            btn.backgroundColor = UIColor(white: 1, alpha: 0.06)
            btn.isEnabled = false
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
            h.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            h.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            h.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            h.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
        ])
        return box
    }
}
