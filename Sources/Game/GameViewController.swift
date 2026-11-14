import UIKit
import SceneKit
import simd

final class GameViewController: UIViewController {
    // Scene
    private let scnView = SCNView()
    private let scene = SCNScene()
    private var dust: DustField!
    private var world: MoonWorld!
    private let player = Player()
    private var bots: [SweepBot] = []
    private let aimRing = SCNNode()
    private let brushPuffNode = SCNNode()
    private var brushPuff: SCNParticleSystem!

    // State
    private var save = SaveData()
    private var paused = true
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var saveTimer: Float = 0
    private var scrubHeld = false
    private var jumpHeld = false
    private var jumpQueued = false
    private var hapticTimer: Float = 0
    private var nightTipShown = false
    private var fullTipCooldown: Float = 0
    private var nightVisionOn = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // HUD
    private let joystick = JoystickView()
    private let lookPad = LookPad()
    private let scrubButton = HoldButton(title: "SCRUB", size: 104)
    private let jumpButton = HoldButton(title: "JUMP", size: 74)
    private let useButton = HoldButton(title: "USE", size: 84)
    private let lampButton = HoldButton(title: "LAMP", size: 54)
    private let nvButton = HoldButton(title: "NV", size: 54)
    private let menuButton = HoldButton(title: "☰", size: 54)
    private let creditsLabel = UILabel()
    private let toolLabel = UILabel()
    private let bagMeter = MeterView()
    private let fuelMeter = MeterView()
    private let cleanLabel = UILabel()
    private let timeLabel = UILabel()
    private let crosshair = UIView()
    private let toastLabel = UILabel()
    private let nvOverlay = UIView()
    private let titleOverlay = UIView()
    private var hudViews: [UIView] = []

    private enum UseAction { case none, silo, terminal }
    private var useAction: UseAction = .none

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // MARK: Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let loaded = SaveManager.load()
        let res = 512
        dust = DustField(res: res, worldSize: 160,
                         savedMask: loaded != nil ? SaveManager.loadMask(expectedCount: res * res) : nil)
        world = MoonWorld(scene: scene, dust: dust)

        scene.rootNode.addChildNode(player.node)
        setupAimRing()
        brushPuff = SweepBot.makeDustParticles()
        brushPuffNode.addParticleSystem(brushPuff)
        scene.rootNode.addChildNode(brushPuffNode)

        scnView.scene = scene
        scnView.pointOfView = player.cameraNode
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling2X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        scnView.isUserInteractionEnabled = false
        view.addSubview(scnView)

        if let s = loaded { save = s }
        applySave()
        buildHUD()
        buildTitle()

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        haptic.prepare()
    }

    @objc private func appWillResign() {
        if !titleOverlay.isHidden { return }
        writeSave()
    }

    private func setupAimRing() {
        let tube = SCNTube(innerRadius: 0.9, outerRadius: 1.0, height: 0.02)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.35, green: 0.9, blue: 1, alpha: 0.85)
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        tube.materials = [m]
        aimRing.geometry = tube
        aimRing.renderingOrder = 50
        aimRing.isHidden = true
        scene.rootNode.addChildNode(aimRing)
    }

    private func applySave() {
        player.position = SIMD3<Float>(save.px, save.py, save.pz)
        if save.py == 0 {
            player.position.y = world.height(atX: save.px, z: save.pz)
        }
        player.yaw = save.yaw
        player.pitch = save.pitch
        world.timeOfDay = save.timeOfDay
        applyUpgrades()
        player.fuel = player.maxFuel
        player.update(dt: 0, move: .zero, jumpPressed: false, jumpHeld: false, world: world)
    }

    private func applyUpgrades() {
        player.moveSpeed = Upgrades.boots[save.bootLevel].value
        player.maxFuel = Upgrades.jetpacks[save.jetLevel].value
        while bots.count < save.bots {
            let i = bots.count
            let start = world.siloPos + SIMD3<Float>(-3, 0, Float(i) - 1)
            let bot = SweepBot(index: i, start: SIMD3<Float>(start.x, world.height(atX: start.x, z: start.z), start.z))
            bots.append(bot)
            scene.rootNode.addChildNode(bot.node)
        }
        while bots.count > save.bots {
            bots.removeLast().node.removeFromParentNode()
        }
        nvButton.isHidden = !save.hasNightVision
        if !save.hasNightVision { setNightVision(false) }
    }

    // MARK: HUD

    private func buildHUD() {
        joystick.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(lookPad)
        view.addSubview(joystick)

        lookPad.onLook = { [weak self] dx, dy in self?.applyLook(dx, dy) }

        nvOverlay.backgroundColor = UIColor(red: 0.1, green: 1, blue: 0.3, alpha: 0.18)
        nvOverlay.isUserInteractionEnabled = false
        nvOverlay.isHidden = true
        view.addSubview(nvOverlay)

        scrubButton.tint = UIColor(red: 0.35, green: 0.9, blue: 1, alpha: 1)
        scrubButton.onPress = { [weak self] in self?.scrubHeld = true }
        scrubButton.onRelease = { [weak self] in self?.scrubHeld = false }
        scrubButton.onDragLook = { [weak self] dx, dy in self?.applyLook(dx, dy) }

        jumpButton.tint = UIColor(white: 1, alpha: 1)
        jumpButton.onPress = { [weak self] in self?.jumpHeld = true; self?.jumpQueued = true }
        jumpButton.onRelease = { [weak self] in self?.jumpHeld = false }

        useButton.tint = UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1)
        useButton.onRelease = { [weak self] in self?.useTapped() }
        useButton.isHidden = true

        lampButton.tint = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        lampButton.onRelease = { [weak self] in
            guard let self = self else { return }
            self.player.lampOn.toggle()
            self.lampButton.tint = self.player.lampOn ? UIColor(red: 1, green: 0.95, blue: 0.3, alpha: 1)
                                                      : UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
            self.lampButton.title = self.player.lampOn ? "LAMP ●" : "LAMP"
        }
        nvButton.tint = UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1)
        nvButton.onRelease = { [weak self] in
            guard let self = self else { return }
            self.setNightVision(!self.nightVisionOn)
        }
        menuButton.onRelease = { [weak self] in self?.showMenu() }

        for b in [scrubButton, jumpButton, useButton, lampButton, nvButton, menuButton] {
            view.addSubview(b)
        }

        for l in [creditsLabel, toolLabel, cleanLabel, timeLabel] {
            l.textColor = .white
            l.shadowColor = UIColor(white: 0, alpha: 0.8)
            l.shadowOffset = CGSize(width: 0, height: 1)
            l.isUserInteractionEnabled = false
            view.addSubview(l)
        }
        creditsLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .heavy)
        creditsLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        toolLabel.font = .systemFont(ofSize: 12, weight: .bold)
        cleanLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .heavy)
        cleanLabel.textAlignment = .center
        timeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        timeLabel.textAlignment = .center

        bagMeter.color = UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.9)
        fuelMeter.color = UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 0.9)
        bagMeter.isUserInteractionEnabled = false
        fuelMeter.isUserInteractionEnabled = false
        view.addSubview(bagMeter)
        view.addSubview(fuelMeter)

        crosshair.backgroundColor = UIColor(white: 1, alpha: 0.85)
        crosshair.layer.cornerRadius = 3
        crosshair.isUserInteractionEnabled = false
        view.addSubview(crosshair)

        toastLabel.font = .systemFont(ofSize: 15, weight: .bold)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.backgroundColor = UIColor(white: 0, alpha: 0.55)
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.isUserInteractionEnabled = false
        view.addSubview(toastLabel)

        hudViews = [joystick, lookPad, scrubButton, jumpButton, lampButton, menuButton,
                    creditsLabel, toolLabel, cleanLabel, timeLabel, bagMeter, fuelMeter, crosshair]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let s = view.safeAreaInsets
        scnView.frame = b
        nvOverlay.frame = b
        titleOverlay.frame = b
        let left = max(s.left, 16), right = max(s.right, 16), bottom = max(s.bottom, 12)

        joystick.frame = CGRect(x: 0, y: b.height * 0.3, width: b.width * 0.42, height: b.height * 0.7)
        lookPad.frame = CGRect(x: b.width * 0.42, y: 0, width: b.width * 0.58, height: b.height)

        scrubButton.center = CGPoint(x: b.width - right - 60, y: b.height - bottom - 62)
        jumpButton.center = CGPoint(x: scrubButton.center.x - 112, y: b.height - bottom - 44)
        useButton.center = CGPoint(x: scrubButton.center.x - 6, y: scrubButton.center.y - 116)
        menuButton.center = CGPoint(x: b.width - right - 30, y: max(s.top, 10) + 32)
        lampButton.center = CGPoint(x: menuButton.center.x - 64, y: menuButton.center.y)
        nvButton.center = CGPoint(x: lampButton.center.x - 64, y: menuButton.center.y)

        let top = max(s.top, 10)
        creditsLabel.frame = CGRect(x: left, y: top + 4, width: 260, height: 24)
        toolLabel.frame = CGRect(x: left, y: top + 28, width: 260, height: 16)
        bagMeter.frame = CGRect(x: left, y: top + 48, width: 200, height: 18)
        fuelMeter.frame = CGRect(x: left, y: top + 70, width: 200, height: 14)
        cleanLabel.frame = CGRect(x: b.width / 2 - 160, y: top + 4, width: 320, height: 20)
        timeLabel.frame = CGRect(x: b.width / 2 - 160, y: top + 24, width: 320, height: 16)
        crosshair.frame = CGRect(x: b.midX - 3, y: b.midY - 3, width: 6, height: 6)
        toastLabel.frame = CGRect(x: b.width / 2 - 230, y: b.height * 0.22, width: 460, height: 54)
    }

    private func applyLook(_ dx: CGFloat, _ dy: CGFloat) {
        guard !paused else { return }
        let sens: Float = 0.0055
        player.look(dx: Float(dx) * sens, dy: Float(dy) * sens)
    }

    private func setNightVision(_ on: Bool) {
        nightVisionOn = on
        nvOverlay.isHidden = !on
        if let cam = player.cameraNode.camera {
            cam.wantsHDR = on
            cam.exposureOffset = on ? 2.2 : 0
            cam.minimumExposure = -1
            cam.maximumExposure = 3
            cam.wantsExposureAdaptation = false
        }
        nvButton.title = on ? "NV ●" : "NV"
    }

    private func toast(_ text: String, duration: TimeInterval = 2.6) {
        toastLabel.text = "  " + text + "  "
        toastLabel.layer.removeAllAnimations()
        toastLabel.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { self.toastLabel.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: duration, options: [.allowUserInteraction], animations: {
                self.toastLabel.alpha = 0
            })
        }
    }

    // MARK: Title / menu

    private func buildTitle() {
        titleOverlay.backgroundColor = UIColor(white: 0, alpha: 0.6)
        view.addSubview(titleOverlay)

        let title = UILabel()
        title.text = "MOON SWEEPERS"
        title.font = .systemFont(ofSize: 46, weight: .black)
        title.textColor = .white
        title.textAlignment = .center
        let sub = UILabel()
        sub.text = "iOS MOCKUP  ·  v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))"
        sub.font = .systemFont(ofSize: 14, weight: .bold)
        sub.textColor = UIColor(red: 0.5, green: 0.9, blue: 1, alpha: 1)
        sub.textAlignment = .center
        let blurb = UILabel()
        blurb.text = "The Lunar Surface Department needs the Moon cleaned.\nThe budget covered one toothbrush."
        blurb.numberOfLines = 2
        blurb.font = .systemFont(ofSize: 14, weight: .medium)
        blurb.textColor = UIColor(white: 1, alpha: 0.8)
        blurb.textAlignment = .center

        func makeButton(_ text: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 18, weight: .heavy)
            b.tintColor = primary ? .black : .white
            b.backgroundColor = primary ? UIColor(red: 0.35, green: 0.9, blue: 1, alpha: 1) : UIColor(white: 1, alpha: 0.15)
            b.layer.cornerRadius = 12
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            b.widthAnchor.constraint(equalToConstant: 220).isActive = true
            b.heightAnchor.constraint(equalToConstant: 50).isActive = true
            return b
        }
        var buttons: [UIView] = []
        if SaveManager.hasSave {
            buttons.append(makeButton("CONTINUE", primary: true) { [weak self] in self?.startGame(fresh: false) })
            buttons.append(makeButton("NEW GAME", primary: false) { [weak self] in self?.confirmNewGame() })
        } else {
            buttons.append(makeButton("START SHIFT", primary: true) { [weak self] in self?.startGame(fresh: true) })
        }
        let btnRow = UIStackView(arrangedSubviews: buttons)
        btnRow.axis = .horizontal
        btnRow.spacing = 16
        let stack = UIStackView(arrangedSubviews: [title, sub, blurb, btnRow])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.setCustomSpacing(26, after: blurb)
        stack.translatesAutoresizingMaskIntoConstraints = false
        titleOverlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: titleOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: titleOverlay.centerYAnchor),
        ])
        hudViews.forEach { $0.isHidden = true }
    }

    private func confirmNewGame() {
        let a = UIAlertController(title: "Start over?", message: "This wipes your credits, upgrades and cleaned ground.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Start over", style: .destructive) { [weak self] _ in self?.startGame(fresh: true) })
        present(a, animated: true)
    }

    private func startGame(fresh: Bool) {
        if fresh {
            SaveManager.wipe()
            save = SaveData()
            dust.reset()
            applySave()
        }
        UIView.animate(withDuration: 0.3, animations: { self.titleOverlay.alpha = 0 }) { _ in
            self.titleOverlay.isHidden = true
        }
        hudViews.forEach { $0.isHidden = false }
        nvButton.isHidden = !save.hasNightVision
        paused = false
        lastTime = 0
        switch save.tutorialStep {
        case 0: toast("Look at the ground and hold SCRUB to brush away dust.", duration: 4)
        default: toast("Back on shift. The Moon is \(cleanPercentText()) clean.")
        }
    }

    private func showMenu() {
        paused = true
        let a = UIAlertController(title: "Paused", message: "Moon cleaned: \(cleanPercentText())\nTotal earned: ◈ \(Int(save.totalEarned))", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Resume", style: .cancel) { [weak self] _ in self?.resume() })
        a.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.writeSave(); self?.resume(); self?.toast("Progress saved.")
        })
        a.addAction(UIAlertAction(title: "Start over", style: .destructive) { [weak self] _ in
            self?.startGame(fresh: true)
        })
        present(a, animated: true)
    }

    private func resume() {
        paused = false
        lastTime = 0
    }

    private func cleanPercentText() -> String {
        String(format: "%.3f%%", dust.cleanFraction * 100)
    }

    // MARK: Interactions

    private func useTapped() {
        switch useAction {
        case .silo: emptyBag(atSilo: true)
        case .terminal: openShop()
        case .none: break
        }
    }

    private func emptyBag(atSilo: Bool) {
        guard save.bagDust > 0.01 else {
            if atSilo { toast("Your bag is empty. Go brush some dust!") }
            return
        }
        let value = Double(save.bagDust * Upgrades.creditsPerUnit) * (atSilo ? 1.0 : 0.75)
        save.credits += value
        save.totalEarned += value
        save.bagDust = 0
        haptic.impactOccurred(intensity: 1)
        if atSilo {
            toast("Dust delivered: +◈ \(Int(value.rounded()))")
            if save.tutorialStep <= 2 {
                save.tutorialStep = 3
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.toast("Spend credits at the blue UPGRADE TERMINAL for better tools.", duration: 4)
                }
            }
        } else {
            toast("Teleported dust: +◈ \(Int(value.rounded()))", duration: 1.4)
        }
    }

    private func openShop() {
        paused = true
        scrubHeld = false
        let shop = ShopViewController()
        shop.modalPresentationStyle = .overFullScreen
        shop.modalTransitionStyle = .crossDissolve
        shop.credits = { [weak self] in self?.save.credits ?? 0 }
        shop.items = { [weak self] in self?.shopItems() ?? [] }
        shop.onClose = { [weak self] in
            self?.writeSave()
            self?.resume()
        }
        present(shop, animated: true)
        if save.tutorialStep == 3 { save.tutorialStep = 4 }
    }

    private func buy(_ cost: Int, _ apply: () -> Void) {
        guard save.credits >= Double(cost) else { return }
        save.credits -= Double(cost)
        apply()
        applyUpgrades()
        haptic.impactOccurred(intensity: 1)
    }

    private func shopItems() -> [ShopViewController.Item] {
        var items: [ShopViewController.Item] = []
        let tl = save.toolLevel
        let tool = Upgrades.tools[tl]
        let nextTool = tl + 1 < Upgrades.tools.count ? Upgrades.tools[tl + 1] : nil
        items.append(.init(title: "Cleaning tool",
                           current: tool.name,
                           next: nextTool?.name,
                           detail: nextTool.map { String(format: "Brush width %.1fm → %.1fm, faster scrubbing, longer reach.", tool.radius * 2, $0.radius * 2) }
                               ?? "The best tool the L.S.D. can buy.",
                           cost: nextTool?.cost,
                           buy: { [weak self] in self?.buy(nextTool?.cost ?? 0) { self?.save.toolLevel += 1 } }))

        let bl = save.bagLevel
        let bag = Upgrades.bags[bl]
        let nextBag = bl + 1 < Upgrades.bags.count ? Upgrades.bags[bl + 1] : nil
        items.append(.init(title: "Dust bag",
                           current: bag.name,
                           next: nextBag?.name,
                           detail: nextBag.map { "Holds \(Int(bag.value)) → \(Int($0.value)) dust." } ?? "Holds \(Int(bag.value)) dust.",
                           cost: nextBag?.cost,
                           buy: { [weak self] in self?.buy(nextBag?.cost ?? 0) { self?.save.bagLevel += 1 } }))

        let ol = save.bootLevel
        let boot = Upgrades.boots[ol]
        let nextBoot = ol + 1 < Upgrades.boots.count ? Upgrades.boots[ol + 1] : nil
        items.append(.init(title: "Boots",
                           current: boot.name,
                           next: nextBoot?.name,
                           detail: nextBoot.map { String(format: "Walk speed %.1f → %.1f m/s.", boot.value, $0.value) } ?? "Top speed.",
                           cost: nextBoot?.cost,
                           buy: { [weak self] in self?.buy(nextBoot?.cost ?? 0) { self?.save.bootLevel += 1 } }))

        let jl = save.jetLevel
        let jet = Upgrades.jetpacks[jl]
        let nextJet = jl + 1 < Upgrades.jetpacks.count ? Upgrades.jetpacks[jl + 1] : nil
        items.append(.init(title: "Jetpack",
                           current: jet.name,
                           next: nextJet?.name,
                           detail: nextJet.map { String(format: "Hold JUMP in the air to boost. Fuel %.1fs → %.1fs.", jet.value, $0.value) } ?? "Maximum fuel.",
                           cost: nextJet?.cost,
                           buy: { [weak self] in self?.buy(nextJet?.cost ?? 0) { self?.save.jetLevel += 1 } }))

        items.append(.init(title: "Night vision goggles",
                           current: save.hasNightVision ? "Installed" : "None",
                           next: save.hasNightVision ? nil : "NV Goggles",
                           detail: "See clearly during the lunar night. Toggle with the NV button.",
                           cost: save.hasNightVision ? nil : Upgrades.nightVisionCost,
                           buy: { [weak self] in self?.buy(Upgrades.nightVisionCost) { self?.save.hasNightVision = true } }))

        let nb = save.bots
        let botCost = nb < Upgrades.botCosts.count ? Upgrades.botCosts[nb] : nil
        items.append(.init(title: "D.U.S.T.Y. sweep-bots",
                           current: "\(nb) working",
                           next: botCost != nil ? "\(nb + 1) working" : nil,
                           detail: "A robot that sweeps on its own and unloads at the silo. Each new one works a wider area.",
                           cost: botCost,
                           buy: { [weak self] in self?.buy(botCost ?? 0) { self?.save.bots += 1 } }))

        items.append(.init(title: "Dust teleporter",
                           current: save.hasTeleporter ? "Installed" : "None",
                           next: save.hasTeleporter ? nil : "Bag Teleporter",
                           detail: "When your bag fills up, it beams the dust to the silo automatically (75% value).",
                           cost: save.hasTeleporter ? nil : Upgrades.teleporterCost,
                           buy: { [weak self] in self?.buy(Upgrades.teleporterCost) { self?.save.hasTeleporter = true } }))
        return items
    }

    private func writeSave() {
        save.px = player.position.x
        save.py = player.position.y
        save.pz = player.position.z
        save.yaw = player.yaw
        save.pitch = player.pitch
        save.timeOfDay = world.timeOfDay
        SaveManager.save(save, mask: dust.mask)
    }

    // MARK: Loop

    @objc private func step(_ link: CADisplayLink) {
        if lastTime == 0 { lastTime = link.timestamp; return }
        let dt = Float(min(0.05, link.timestamp - lastTime))
        lastTime = link.timestamp
        if paused { return }

        world.updateSun(dt: dt)

        let mv = joystick.value
        player.update(dt: dt, move: SIMD2<Float>(Float(mv.x), Float(mv.y)),
                      jumpPressed: jumpQueued, jumpHeld: jumpHeld, world: world)
        jumpQueued = false

        // Tool
        let tool = Upgrades.tools[save.toolLevel]
        let cap = Upgrades.bags[save.bagLevel].value
        var collecting = false
        if let aim = player.aimPoint(world: world, reach: tool.reach) {
            aimRing.isHidden = false
            aimRing.simdPosition = aim + SIMD3<Float>(0, 0.06, 0)
            aimRing.simdScale = SIMD3<Float>(tool.radius, 1, tool.radius)
            if scrubHeld {
                let left = cap - save.bagDust
                if left <= 0.01 {
                    if save.hasTeleporter {
                        emptyBag(atSilo: false)
                    } else if fullTipCooldown <= 0 {
                        toast("Bag full! Empty it at the orange DUST SILO.")
                        fullTipCooldown = 4
                        if save.tutorialStep == 1 { save.tutorialStep = 2 }
                    }
                } else {
                    let got = dust.clean(atX: aim.x, z: aim.z, radius: tool.radius, rate: tool.rate,
                                         dt: dt, capacityLeft: left)
                    if got > 0 {
                        collecting = true
                        save.bagDust += got
                        if save.tutorialStep == 0 {
                            save.tutorialStep = 1
                            toast("Nice! Dust goes in your bag. Fill it up.")
                        }
                    }
                }
            }
            brushPuffNode.simdPosition = aim + SIMD3<Float>(0, 0.05, 0)
        } else {
            aimRing.isHidden = true
        }
        brushPuff.birthRate = collecting ? CGFloat(30 + tool.radius * 60) : 0
        fullTipCooldown -= dt

        if collecting {
            hapticTimer -= dt
            if hapticTimer <= 0 {
                haptic.impactOccurred(intensity: 0.35)
                hapticTimer = 0.11
            }
        }

        // Bots
        for bot in bots {
            let earned = bot.update(dt: dt, world: world, dust: dust, silo: world.siloPos)
            if earned > 0 {
                save.credits += Double(earned)
                save.totalEarned += Double(earned)
            }
        }

        dust.tick(dt: dt)

        // Context button
        let pp = SIMD2<Float>(player.position.x, player.position.z)
        let dSilo = simd_length(pp - SIMD2<Float>(world.siloPos.x, world.siloPos.z))
        let dTerm = simd_length(pp - SIMD2<Float>(world.terminalPos.x, world.terminalPos.z))
        if dSilo < 4.2 {
            useAction = .silo
            useButton.title = "EMPTY BAG"
        } else if dTerm < 3.4 {
            useAction = .terminal
            useButton.title = "UPGRADES"
        } else {
            useAction = .none
        }
        useButton.isHidden = useAction == .none

        // Night hint
        if world.isNight && !nightTipShown && !player.lampOn {
            nightTipShown = true
            toast("Lunar night is falling — tap LAMP to turn on your helmet light.", duration: 3.5)
        }
        if !world.isNight { nightTipShown = false }

        // HUD text
        creditsLabel.text = "◈ \(Int(save.credits))"
        toolLabel.text = "\(tool.name.uppercased())  ·  \(Upgrades.bags[save.bagLevel].name)"
        bagMeter.fraction = CGFloat(save.bagDust / cap)
        bagMeter.caption = "DUST \(Int(save.bagDust))/\(Int(cap))"
        bagMeter.color = save.bagDust >= cap - 0.01 ? UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 0.9)
                                                    : UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.9)
        fuelMeter.isHidden = player.maxFuel <= 0
        if player.maxFuel > 0 {
            fuelMeter.fraction = CGFloat(player.fuel / player.maxFuel)
            fuelMeter.caption = "FUEL"
        }
        cleanLabel.text = "MOON CLEANED  \(cleanPercentText())"
        let botText = bots.isEmpty ? "" : "  ·  \(bots.count) BOT\(bots.count == 1 ? "" : "S") SWEEPING"
        timeLabel.text = (world.isNight ? "☾ LUNAR NIGHT" : "☀ LUNAR DAY") + botText

        saveTimer += dt
        if saveTimer > 20 {
            saveTimer = 0
            writeSave()
        }
    }
}
