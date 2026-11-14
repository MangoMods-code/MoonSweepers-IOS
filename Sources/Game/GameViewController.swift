import UIKit
import SceneKit
import simd

final class GameViewController: UIViewController {
    // Scene
    private let scnView = SCNView()
    private let scene = SCNScene()
    private var dust: DustField!
    private var world: MoonWorld!
    private var structures: Structures!
    private let player = Player()
    private var bots: [SweepBot] = []
    private var vehicle: Vehicle?
    private var driving = false
    private let aimRing = SCNNode()
    private let brushPuffNode = SCNNode()
    private var brushPuff: SCNParticleSystem!

    // State
    private var save = SaveData()
    private var paused = true
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var saveTimer: Float = 0
    private var slowTimer: Float = 0
    private var scrubHeld = false
    private var jumpHeld = false
    private var jumpQueued = false
    private var hapticTimer: Float = 0
    private var nightTipShown = false
    private var tipCooldown: Float = 0
    private var nightVisionOn = false
    private var lastMoneyShown = -1
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private func buzz(_ intensity: CGFloat) {
        if save.hapticsOn { haptic.impactOccurred(intensity: intensity) }
    }

    // HUD
    private let joystick = JoystickView()
    private let lookPad = LookPad()
    private let scrubButton = HoldButton(title: "SCRUB", size: 100)
    private let jumpButton = HoldButton(title: "JUMP", size: 70)
    private let packButton = HoldButton(title: "PACK", size: 64)
    private let useButton = HoldButton(title: "USE", size: 86)
    private let pauseButton = HoldButton(title: "II", size: 46)
    private let mapButton = HoldButton(title: "MAP", size: 46)
    private let gridButton = HoldButton(title: "GRID", size: 46)
    private let lampButton = HoldButton(title: "LAMP", size: 46)
    private let nvButton = HoldButton(title: "NV", size: 46)
    private let moneyLabel = UILabel()
    private let sectorLabel = UILabel()
    private let moonLabel = UILabel()
    private let toolPanel = UIView()
    private let toolName = UILabel()
    private let toolMeter = MeterView()
    private let capsuleMeter = MeterView()
    private let fuelMeter = MeterView()
    private let crosshair = UIView()
    private let toastLabel = UILabel()
    private let waypointLabel = UILabel()
    private let nvOverlay = UIView()
    private let titleOverlay = UIView()
    private var hudViews: [UIView] = []

    private enum UseAction: Equatable {
        case none, deposit(Int), sellTray(Int), unload(Int), wall, matrix, garage, drive, exitVehicle, flag(Int)
    }
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
        let n = DustField.res
        dust = DustField(savedMask: loaded != nil ? SaveManager.loadMask(expectedCount: n * n) : nil)
        world = MoonWorld(scene: scene, dust: dust)
        structures = Structures(world: world)
        scene.rootNode.addChildNode(structures.root)

        scene.rootNode.addChildNode(player.node)
        setupAimRing()
        brushPuff = SweepBot.makeDustParticles()
        brushPuffNode.addParticleSystem(brushPuff)
        scene.rootNode.addChildNode(brushPuffNode)

        scnView.scene = scene
        scnView.pointOfView = player.cameraNode
        scnView.backgroundColor = .black
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        scnView.isUserInteractionEnabled = false
        view.addSubview(scnView)

        if let s = loaded { save = s }
        buildHUD()
        applySave()
        buildTitle()

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        haptic.prepare()
        Sfx.shared.start()
        Sfx.shared.enabled = save.soundOn
    }

    @objc private func appWillResign() {
        if titleOverlay.isHidden { writeSave() }
    }

    @objc private func appDidBecomeActive() {
        Sfx.shared.resumeIfNeeded()
        lastTime = 0
    }

    private func setupAimRing() {
        let tube = SCNTube(innerRadius: 0.93, outerRadius: 1.0, height: 0.015)
        tube.radialSegmentCount = 40
        let m = Mat.glow(UIColor(white: 1, alpha: 0.7))
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        tube.materials = [m]
        aimRing.geometry = tube
        aimRing.renderingOrder = 50
        aimRing.castsShadow = false
        aimRing.isHidden = true
        scene.rootNode.addChildNode(aimRing)
    }

    private func applySave() {
        player.position = SIMD3<Float>(save.px, save.py, save.pz)
        player.position.y = max(save.py, world.height(atX: save.px, z: save.pz))
        player.yaw = save.yaw
        player.pitch = save.pitch
        player.velocity = .zero
        world.timeOfDay = save.timeOfDay
        driving = false
        bots.forEach { $0.node.removeFromParentNode() }
        bots.removeAll()
        vehicle?.node.removeFromParentNode()
        vehicle = nil
        applyUpgrades()
        player.fuel = player.maxFuel
        player.setToolVisible(true)
        player.update(dt: 0, move: .zero, jumpPressed: false, jumpHeld: false, world: world)
        world.gridNode.isHidden = !save.gridOn
        world.setWaypoint(x: save.waypointX, z: save.waypointZ, visible: save.hasWaypoint)
        applyGraphics()
        setNightVision(false)
        lastMoneyShown = -1
    }

    private func applyUpgrades() {
        player.moveSpeed = save.moveSpeed
        player.maxFuel = save.jetFuel
        player.setTool(save.currentTool)
        player.setLamp(level: save.lampLens)
        structures.refresh(save, dust: dust)
        nvButton.isHidden = !save.hasNightVision || !titleOverlay.isHidden
        if !save.hasNightVision && nightVisionOn { setNightVision(false) }

        // Robots
        let vacuums = bots.filter { $0.kind == .vacuum }.count
        let joonas = bots.filter { $0.kind == .joonas }.count
        if vacuums < save.vacuums {
            for i in vacuums..<save.vacuums { addBot(.vacuum, index: i) }
        }
        if joonas < save.joonas {
            for i in joonas..<save.joonas { addBot(.joonas, index: i) }
        }

        // Vehicle
        if save.vehicleLevel >= 0 && (vehicle == nil || vehicle?.level != save.vehicleLevel) {
            if driving { exitVehicle() }
            vehicle?.node.removeFromParentNode()
            var p = structures.vehicleSpawn
            var h: Float = .pi
            if vehicle == nil && save.hasVehiclePos {
                p = SIMD3<Float>(save.vehicleX, 0, save.vehicleZ)
                h = save.vehicleHeading
            }
            p.y = world.height(atX: p.x, z: p.z)
            let v = Vehicle(level: save.vehicleLevel, position: p, heading: h)
            scene.rootNode.addChildNode(v.node)
            vehicle = v
            save.vehicleLoad = min(save.vehicleLoad, v.tier.capacity)
        }
    }

    private func addBot(_ kind: SweepBot.Kind, index: Int) {
        var p = structures.botDock + (kind == .joonas ? SIMD3<Float>(Float(index) * 4, 0, 7) : SIMD3<Float>(Float(index) * 1.3, 0, 0))
        p.y = world.height(atX: p.x, z: p.z)
        let bot = SweepBot(kind: kind, index: index, start: p)
        bot.onDeliver = { [weak self] kg, from in
            guard let self = self else { return }
            if kind == .joonas {
                self.flyCapsule(from: from, to: self.structures.catcherPos + SIMD3<Float>(0, 3.2, 0)) {
                    self.sell(kg: kg, station: Hex.home, announce: false)
                }
            } else {
                self.sell(kg: kg, station: Hex.home, announce: false)
            }
        }
        bots.append(bot)
        scene.rootNode.addChildNode(bot.node)
    }

    /// A capsule lobbed in a high arc (J.O.O.N.A.S. → Capsule Catcher).
    private func flyCapsule(from a: SIMD3<Float>, to b: SIMD3<Float>, done: @escaping () -> Void) {
        let c = Make.part(SCNCapsule(capRadius: 0.22, height: 0.8), Mat.glow(UIColor(red: 1, green: 0.6, blue: 0.15, alpha: 1)), 0, 0, 0)
        c.simdPosition = a
        c.castsShadow = false
        scene.rootNode.addChildNode(c)
        let dist = simd_length(b - a)
        let duration = TimeInterval(max(1.5, min(5, dist / 28)))
        let peak = max(12, dist * 0.35)
        let fly = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = Float(elapsed / CGFloat(duration))
            var p = a + (b - a) * t
            p.y += peak * 4 * t * (1 - t)
            node.simdPosition = p
        }
        c.runAction(.sequence([fly, .removeFromParentNode()])) {
            DispatchQueue.main.async { done() }
        }
    }

    private func applyGraphics() {
        let high = save.highGraphics
        scnView.antialiasingMode = high ? .multisampling2X : .none
        world.setShadowQuality(high: high)
        guard let cam = player.cameraNode.camera else { return }
        cam.wantsHDR = high
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.15
        cam.bloomIntensity = high ? 0.55 : 0
        cam.bloomThreshold = 0.82
        cam.bloomBlurRadius = 9
        cam.vignettingIntensity = high ? 0.55 : 0
        cam.vignettingPower = 1.1
        cam.contrast = high ? 0.12 : 0
        cam.saturation = 1.08
        cam.screenSpaceAmbientOcclusionIntensity = high ? 0.5 : 0
        cam.screenSpaceAmbientOcclusionRadius = 0.9
    }

    // MARK: HUD

    private func buildHUD() {
        view.addSubview(lookPad)
        view.addSubview(joystick)
        lookPad.onLook = { [weak self] dx, dy in self?.applyLook(dx, dy) }

        nvOverlay.backgroundColor = UIColor(red: 0.1, green: 1, blue: 0.3, alpha: 0.13)
        nvOverlay.isUserInteractionEnabled = false
        nvOverlay.isHidden = true
        view.addSubview(nvOverlay)

        scrubButton.tint = UIColor(red: 0.35, green: 0.9, blue: 1, alpha: 1)
        scrubButton.onPress = { [weak self] in self?.scrubHeld = true }
        scrubButton.onRelease = { [weak self] in self?.scrubHeld = false }
        scrubButton.onDragLook = { [weak self] dx, dy in self?.applyLook(dx, dy) }

        jumpButton.onPress = { [weak self] in self?.jumpHeld = true; self?.jumpQueued = true }
        jumpButton.onRelease = { [weak self] in self?.jumpHeld = false }

        packButton.tint = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
        packButton.onRelease = { [weak self] in self?.pack(manual: true) }
        packButton.isHidden = true

        useButton.tint = UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
        useButton.onRelease = { [weak self] in self?.useTapped() }
        useButton.isHidden = true

        lampButton.tint = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        lampButton.onRelease = { [weak self] in
            guard let self = self else { return }
            self.player.lampOn.toggle()
            self.lampButton.title = self.player.lampOn ? "LAMP●" : "LAMP"
            Sfx.shared.play("click")
        }
        nvButton.tint = UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1)
        nvButton.onRelease = { [weak self] in
            guard let self = self else { return }
            self.setNightVision(!self.nightVisionOn)
            Sfx.shared.play("click")
        }
        gridButton.tint = UIColor(red: 0.35, green: 0.9, blue: 1, alpha: 1)
        gridButton.onRelease = { [weak self] in
            guard let self = self else { return }
            self.save.gridOn.toggle()
            self.world.gridNode.isHidden = !self.save.gridOn
            self.gridButton.title = self.save.gridOn ? "GRID●" : "GRID"
            Sfx.shared.play("click")
        }
        mapButton.onRelease = { [weak self] in self?.openMap() }
        pauseButton.onRelease = { [weak self] in self?.showMenu() }

        for b in [scrubButton, jumpButton, packButton, useButton, pauseButton, mapButton, gridButton, lampButton, nvButton] {
            view.addSubview(b)
        }

        for l in [moneyLabel, sectorLabel, moonLabel] {
            l.textColor = .white
            l.shadowColor = UIColor(white: 0, alpha: 0.85)
            l.shadowOffset = CGSize(width: 0, height: 1)
            l.isUserInteractionEnabled = false
            view.addSubview(l)
        }
        moneyLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .black)
        moneyLabel.textColor = UIColor(red: 0.45, green: 1, blue: 0.55, alpha: 1)
        sectorLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .heavy)
        moonLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        moonLabel.textColor = UIColor(white: 1, alpha: 0.8)

        toolPanel.backgroundColor = UIColor(white: 0, alpha: 0.45)
        toolPanel.layer.cornerRadius = 12
        toolPanel.layer.borderWidth = 1
        toolPanel.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        toolName.font = .systemFont(ofSize: 13, weight: .heavy)
        toolName.textColor = .white
        toolName.textAlignment = .center
        toolName.adjustsFontSizeToFitWidth = true
        toolName.minimumScaleFactor = 0.7
        toolMeter.color = UIColor(red: 0.85, green: 0.78, blue: 0.62, alpha: 0.9)
        capsuleMeter.color = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.9)
        toolPanel.addSubview(toolName)
        toolPanel.addSubview(toolMeter)
        toolPanel.addSubview(capsuleMeter)
        toolPanel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cycleTool)))
        view.addSubview(toolPanel)

        fuelMeter.color = UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 0.9)
        fuelMeter.caption = "JETPACK"
        fuelMeter.isUserInteractionEnabled = false
        view.addSubview(fuelMeter)

        crosshair.backgroundColor = UIColor(white: 1, alpha: 0.85)
        crosshair.layer.cornerRadius = 2.5
        crosshair.isUserInteractionEnabled = false
        view.addSubview(crosshair)

        waypointLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .heavy)
        waypointLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0.25, alpha: 1)
        waypointLabel.shadowColor = .black
        waypointLabel.shadowOffset = CGSize(width: 0, height: 1)
        waypointLabel.textAlignment = .center
        waypointLabel.isUserInteractionEnabled = false
        waypointLabel.isHidden = true
        view.addSubview(waypointLabel)

        toastLabel.font = .systemFont(ofSize: 15, weight: .bold)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.backgroundColor = UIColor(white: 0, alpha: 0.62)
        toastLabel.layer.cornerRadius = 10
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0
        toastLabel.isUserInteractionEnabled = false
        view.addSubview(toastLabel)

        hudViews = [joystick, lookPad, scrubButton, jumpButton, pauseButton, mapButton, gridButton, lampButton,
                    moneyLabel, sectorLabel, moonLabel, toolPanel, crosshair]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let s = view.safeAreaInsets
        scnView.frame = b
        nvOverlay.frame = b
        titleOverlay.frame = b
        let left = max(s.left, 16), right = max(s.right, 16), bottom = max(s.bottom, 12), top = max(s.top, 10)

        joystick.frame = CGRect(x: 0, y: b.height * 0.3, width: b.width * 0.42, height: b.height * 0.7)
        lookPad.frame = CGRect(x: b.width * 0.42, y: 0, width: b.width * 0.58, height: b.height)

        scrubButton.center = CGPoint(x: b.width - right - 58, y: b.height - bottom - 60)
        jumpButton.center = CGPoint(x: scrubButton.center.x - 106, y: b.height - bottom - 44)
        packButton.center = CGPoint(x: scrubButton.center.x - 98, y: scrubButton.center.y - 84)
        useButton.center = CGPoint(x: scrubButton.center.x, y: scrubButton.center.y - 112)

        var x = b.width - right - 23
        for btn in [pauseButton, mapButton, gridButton, lampButton, nvButton] {
            btn.center = CGPoint(x: x, y: top + 25)
            x -= 52
        }

        moneyLabel.frame = CGRect(x: left, y: top, width: 300, height: 28)
        sectorLabel.frame = CGRect(x: left, y: top + 30, width: 360, height: 16)
        moonLabel.frame = CGRect(x: left, y: top + 47, width: 360, height: 16)
        fuelMeter.frame = CGRect(x: left, y: top + 68, width: 150, height: 14)

        let pw: CGFloat = 250
        toolPanel.frame = CGRect(x: b.midX - pw / 2, y: b.height - bottom - 66, width: pw, height: 66)
        toolName.frame = CGRect(x: 8, y: 5, width: pw - 16, height: 16)
        toolMeter.frame = CGRect(x: 10, y: 24, width: pw - 20, height: 16)
        capsuleMeter.frame = CGRect(x: 10, y: 44, width: pw - 20, height: 16)

        crosshair.frame = CGRect(x: b.midX - 2.5, y: b.midY - 2.5, width: 5, height: 5)
        toastLabel.frame = CGRect(x: b.midX - 240, y: b.height * 0.2, width: 480, height: 54)
    }

    private func applyLook(_ dx: CGFloat, _ dy: CGFloat) {
        guard !paused else { return }
        let k = 0.0052 * save.sensitivity
        player.look(dx: Float(dx) * k, dy: Float(dy) * k * (save.invertY ? -1 : 1))
    }

    private func setNightVision(_ on: Bool) {
        nightVisionOn = on
        nvOverlay.isHidden = !on
        world.nightVision = on
        nvButton.title = on ? "NV●" : "NV"
    }

    private func toast(_ text: String, duration: TimeInterval = 2.6) {
        toastLabel.text = text
        toastLabel.layer.removeAllAnimations()
        toastLabel.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { self.toastLabel.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: duration, options: [.allowUserInteraction], animations: {
                self.toastLabel.alpha = 0
            })
        }
    }

    private func bumpMoney() {
        moneyLabel.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        UIView.animate(withDuration: 0.35) { self.moneyLabel.transform = .identity }
    }

    // MARK: Title / menus

    private func buildTitle() {
        titleOverlay.subviews.forEach { $0.removeFromSuperview() }
        titleOverlay.backgroundColor = UIColor(white: 0, alpha: 0.5)
        titleOverlay.alpha = 1
        titleOverlay.isHidden = false
        if titleOverlay.superview == nil { view.addSubview(titleOverlay) }

        let title = UILabel()
        title.text = "MOON SWEEPERS"
        title.font = .systemFont(ofSize: 50, weight: .black)
        title.textColor = .white
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sub = UILabel()
        sub.text = "iOS MOCKUP  ·  v\(ver) (\(build))"
        sub.font = .systemFont(ofSize: 13, weight: .bold)
        sub.textColor = UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1)
        let blurb = UILabel()
        blurb.text = "The Moon is covered in dust. The Lunar Surface Department sent you to clean it.\nThe budget only covered a toothbrush."
        blurb.numberOfLines = 2
        blurb.font = .systemFont(ofSize: 14, weight: .medium)
        blurb.textColor = UIColor(white: 1, alpha: 0.85)
        blurb.textAlignment = .center

        func makeButton(_ text: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 18, weight: .heavy)
            b.tintColor = primary ? .black : .white
            b.backgroundColor = primary ? UIColor(red: 0.96, green: 0.52, blue: 0.14, alpha: 1) : UIColor(white: 1, alpha: 0.16)
            b.layer.cornerRadius = 12
            b.addAction(UIAction { _ in action() }, for: .touchUpInside)
            b.widthAnchor.constraint(equalToConstant: 190).isActive = true
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
        buttons.append(makeButton("SETTINGS", primary: false) { [weak self] in self?.openSettings(thenResume: false) })
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 16
        let stack = UIStackView(arrangedSubviews: [title, sub, blurb, row])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(26, after: blurb)
        stack.translatesAutoresizingMaskIntoConstraints = false
        titleOverlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: titleOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: titleOverlay.centerYAnchor),
        ])
        paused = true
        hudViews.forEach { $0.isHidden = true }
        let extras: [UIView] = [nvButton, packButton, useButton, fuelMeter, waypointLabel]
        extras.forEach { $0.isHidden = true }
    }

    private func confirmNewGame() {
        let a = UIAlertController(title: "Start over?", message: "This wipes your money, upgrades and every cleaned patch of Moon.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            if self?.titleOverlay.isHidden == true { self?.resume() }
        })
        a.addAction(UIAlertAction(title: "Start over", style: .destructive) { [weak self] _ in self?.startGame(fresh: true) })
        present(a, animated: true)
    }

    private func startGame(fresh: Bool) {
        if fresh {
            let sound = save.soundOn, gfx = save.highGraphics
            SaveManager.wipe()
            save = SaveData()
            save.soundOn = sound
            save.highGraphics = gfx
            dust.reset()
            applySave()
            gridButton.title = "GRID"
        } else {
            gridButton.title = save.gridOn ? "GRID●" : "GRID"
        }
        UIView.animate(withDuration: 0.3, animations: { self.titleOverlay.alpha = 0 }) { _ in
            self.titleOverlay.isHidden = true
        }
        hudViews.forEach { $0.isHidden = false }
        nvButton.isHidden = !save.hasNightVision
        paused = false
        lastTime = 0
        if save.tutorialStep == 0 {
            toast("Welcome to N Station. Take the free Toothbrush from the SUPPLY WALL on your left.", duration: 5)
        } else {
            toast(String(format: "Back on shift. The Moon is %.2f%% clean.", dust.cleanFraction * 100))
        }
    }

    private func showMenu() {
        guard !paused else { return }
        paused = true
        scrubHeld = false
        Sfx.shared.play("click")
        let menu = MenuViewController()
        menu.modalPresentationStyle = .overFullScreen
        menu.modalTransitionStyle = .crossDissolve
        menu.stats = String(format: "Moon cleaned  %.3f%%\nDust shipped  %.0f kg\nTotal earned  %@\nStations  %d / 12\nFlags  %d / %d",
                            dust.cleanFraction * 100, save.kgSold, ShopViewController.dollars(save.totalEarned),
                            save.stationsFound.filter { $0 }.count,
                            save.flagsClaimed.filter { $0 }.count, save.flagsClaimed.count)
        menu.buttons = [
            .init(title: "RESUME", style: .primary) { [weak self] in self?.resume() },
            .init(title: "SETTINGS", style: .normal) { [weak self] in self?.openSettings(thenResume: true) },
            .init(title: "MOON MAP", style: .normal) { [weak self] in self?.paused = false; self?.openMap() },
            .init(title: "SAVE GAME", style: .normal) { [weak self] in
                self?.writeSave(); self?.resume(); self?.toast("Progress saved.")
            },
            .init(title: "MAIN MENU", style: .normal) { [weak self] in
                self?.writeSave(); self?.buildTitle()
            },
            .init(title: "START OVER", style: .danger) { [weak self] in self?.confirmNewGame() },
        ]
        present(menu, animated: true)
    }

    private func openSettings(thenResume: Bool) {
        let vc = SettingsViewController()
        vc.modalPresentationStyle = .overFullScreen
        vc.modalTransitionStyle = .crossDissolve
        vc.values = SettingsViewController.Values(soundOn: save.soundOn, hapticsOn: save.hapticsOn,
                                                  highGraphics: save.highGraphics, invertY: save.invertY,
                                                  sensitivity: save.sensitivity, gridOn: save.gridOn)
        vc.onChange = { [weak self] v in
            guard let self = self else { return }
            let gfxChanged = v.highGraphics != self.save.highGraphics
            self.save.soundOn = v.soundOn
            self.save.hapticsOn = v.hapticsOn
            self.save.highGraphics = v.highGraphics
            self.save.invertY = v.invertY
            self.save.sensitivity = v.sensitivity
            self.save.gridOn = v.gridOn
            Sfx.shared.enabled = v.soundOn
            self.world.gridNode.isHidden = !v.gridOn
            self.gridButton.title = v.gridOn ? "GRID●" : "GRID"
            if gfxChanged { self.applyGraphics() }
        }
        vc.onClose = { [weak self] in
            guard let self = self else { return }
            if thenResume {
                self.writeSave()
                self.resume()
            }
        }
        present(vc, animated: true)
    }

    private func resume() {
        paused = false
        lastTime = 0
    }

    // MARK: Cleaning loop

    @objc private func cycleTool() {
        guard !paused, !driving, save.hasTool else { return }
        var i = save.currentTool
        for _ in 0..<Catalog.tools.count {
            i = (i + 1) % Catalog.tools.count
            if save.toolsOwned[i] { break }
        }
        guard i != save.currentTool else { return }
        save.currentTool = i
        player.setTool(i)
        Sfx.shared.play("click")
    }

    private func pack(manual: Bool) {
        guard save.toolLoad > 0.001 else { return }
        let room = save.capsuleCapacity - save.capsuleLoad
        if room <= 0.001 {
            if manual || tipCooldown <= 0 {
                toast("Capsule full — carry it back to a station.")
                tipCooldown = 4
            }
            return
        }
        let moved = min(room, save.toolLoad)
        save.toolLoad -= moved
        save.capsuleLoad += moved
        Sfx.shared.play("pack")
        buzz(0.8)
        if save.tutorialStep == 2 {
            save.tutorialStep = 3
            toast("Capsule packed. Carry it to the orange DEPOSIT intake inside the station.", duration: 4)
        }
    }

    private func sell(kg: Float, station: Int, announce: Bool) {
        guard kg > 0.0005 else { return }
        let night = world.isNight
        let value = save.value(ofKg: kg, night: night)
        save.money += value
        save.totalEarned += value
        save.kgSold += Double(kg)
        structures.launchShipment(from: station)
        Sfx.shared.play("cash", volume: announce ? 1 : 0.35)
        if announce {
            Sfx.shared.play("launch", volume: 0.7)
            buzz(1)
            var text = String(format: "Shipment launched: %.1f kg  →  +%@", kg, ShopViewController.dollars(value.rounded(.up)))
            if night && !save.hasBattery && (save.hasChamber || save.hasPress) {
                text += "\nMachines are unpowered at night (raw dust price)."
            }
            toast(text)
        }
        bumpMoney()
    }

    private func useTapped() {
        guard !paused else { return }
        switch useAction {
        case .deposit:
            let kg = save.capsuleLoad + save.toolLoad
            guard kg > 0.0005 else { return }
            save.capsuleLoad = 0
            save.toolLoad = 0
            save.trayKg += kg
            Sfx.shared.play("pack")
            buzz(0.8)
            toast(String(format: "%.2f kg in the tray. Tap SELL to launch the shipment.", save.trayKg))
        case .sellTray(let s):
            let kg = save.trayKg
            guard kg > 0.0005 else { return }
            save.trayKg = 0
            sell(kg: kg, station: s, announce: true)
            if save.tutorialStep <= 3 {
                save.tutorialStep = 4
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
                    self?.toast("Spend it at the SUPPLY WALL — the Nail Brush is only $5.", duration: 4)
                }
            }
        case .unload(let s):
            let kg = save.vehicleLoad
            save.vehicleLoad = 0
            sell(kg: kg, station: s, announce: true)
        case .wall: openShop(.wall)
        case .matrix: openShop(.matrix)
        case .garage: openShop(.garage)
        case .drive: enterVehicle()
        case .exitVehicle: exitVehicle()
        case .flag(let i):
            guard i < save.flagsClaimed.count, !save.flagsClaimed[i] else { return }
            save.flagsClaimed[i] = true
            save.money += Double(Catalog.flagReward)
            save.totalEarned += Double(Catalog.flagReward)
            structures.refresh(save, dust: dust)
            Sfx.shared.play("claim")
            buzz(1)
            let n = save.flagsClaimed.filter { $0 }.count
            toast("Flag claimed for the L.S.D.  +$\(Catalog.flagReward)   (\(n)/\(save.flagsClaimed.count))")
            bumpMoney()
        case .none: break
        }
    }

    private func enterVehicle() {
        guard let v = vehicle else { return }
        driving = true
        scrubHeld = false
        player.yaw = v.heading
        player.pitch = -0.28
        player.setToolVisible(false)
        Sfx.shared.play("click")
        toast("Driving the \(v.tier.name). It sweeps as it moves — steer with the stick.")
    }

    private func exitVehicle() {
        guard let v = vehicle else { driving = false; return }
        driving = false
        v.speed = 0
        v.setSweeping(false)
        let r = SIMD3<Float>(cos(v.heading), 0, -sin(v.heading))
        var p = v.position + r * (v.tier.bodyWidth / 2 + 1.0)
        world.resolveCollisions(&p, radius: 0.4)
        p.y = world.height(atX: p.x, z: p.z)
        player.position = p
        player.velocity = .zero
        player.setToolVisible(true)
        Sfx.shared.play("click")
    }

    // MARK: Shops

    private enum ShopKind { case wall, matrix, garage }

    private func purchase(_ cost: Int, _ apply: (inout SaveData) -> Void) {
        guard save.money >= Double(cost) else {
            Sfx.shared.play("deny")
            return
        }
        save.money -= Double(cost)
        apply(&save)
        applyUpgrades()
        if save.tutorialStep == 0 && save.hasTool {
            save.tutorialStep = 1
        }
        Sfx.shared.play(cost == 0 ? "click" : "cash", volume: 0.7)
        buzz(1)
    }

    private func gear(_ title: String, _ detail: String, cost: Int, owned: Bool, locked: String? = nil,
                      _ apply: @escaping (inout SaveData) -> Void) -> ShopViewController.Item {
        ShopViewController.Item(title: title, detail: detail, cost: owned ? nil : cost,
                                status: owned ? "OWNED" : locked,
                                buy: { [weak self] in self?.purchase(cost, apply) })
    }

    private func perk(_ p: Perk, _ kp: WritableKeyPath<SaveData, Int>) -> ShopViewController.Item {
        let lvl = save[keyPath: kp]
        let maxed = lvl >= p.maxLevel
        let cost = maxed ? 0 : p.costs[lvl]
        return ShopViewController.Item(title: "\(p.name)   Lv \(lvl)/\(p.maxLevel)", detail: p.detail,
                                       cost: maxed ? nil : cost, status: maxed ? "MAX" : nil,
                                       buy: { [weak self] in self?.purchase(cost) { $0[keyPath: kp] += 1 } })
    }

    private func wallSections() -> [ShopViewController.Section] {
        var tools: [ShopViewController.Item] = []
        for (i, t) in Catalog.tools.enumerated() {
            let owned = save.toolsOwned[i]
            let detail = String(format: "Sweeps %.0f cm · holds %.1f kg", t.width * 100, t.capacity)
            if owned {
                let equipped = save.currentTool == i
                tools.append(ShopViewController.Item(title: t.name, detail: detail, cost: equipped ? nil : 0,
                                                     status: equipped ? "EQUIPPED" : nil,
                                                     buy: { [weak self] in self?.purchase(0) { $0.currentTool = i } }))
            } else {
                tools.append(ShopViewController.Item(title: t.name, detail: detail, cost: t.cost, status: nil,
                                                     buy: { [weak self] in
                    self?.purchase(t.cost) { $0.toolsOwned[i] = true; $0.currentTool = i }
                }))
            }
        }
        let suit = [
            gear("Gravity Boots", "Walk much faster across the surface.", cost: Catalog.bootsCost, owned: save.hasBoots) { $0.hasBoots = true },
            gear("Forward Jetpack", "Hold JUMP in the air to boost up and forward.", cost: Catalog.jetpackCost, owned: save.hasJetpack) { $0.hasJetpack = true },
            gear("Night Vision Goggles", "Nights look like day, without shadows. Toggle with NV.", cost: Catalog.nightVisionCost, owned: save.hasNightVision) { $0.hasNightVision = true },
        ]
        var build = [
            gear("Building Tool", "Unlocks machines, robots, the Garage, and new stations (built from the Moon Map).", cost: Catalog.buildToolCost, owned: save.hasBuildTool) { $0.hasBuildTool = true },
        ]
        if save.hasBuildTool {
            build.append(gear("Packager", "Conveyor line into the Depot. Needed for machines and Robot Vacuums.",
                              cost: Catalog.packagerCost, owned: save.hasPackager) { $0.hasPackager = true })
            build.append(gear("Pressure Chamber", "Turns dust into Moon Sand: 3× the value.", cost: Catalog.chamberCost,
                              owned: save.hasChamber, locked: save.hasPackager ? nil : "NEEDS PACKAGER") { $0.hasChamber = true })
            build.append(gear("Stone Press", "Presses Moon Sand into Moonstone: 7× the value.", cost: Catalog.pressCost,
                              owned: save.hasPress, locked: save.hasChamber ? nil : "NEEDS CHAMBER") { $0.hasPress = true })
            build.append(gear("Battery Bank", "Solar power drops to zero at night. Batteries keep machines running.",
                              cost: Catalog.batteryCost, owned: save.hasBattery) { $0.hasBattery = true })
            build.append(gear("Robot Vacuum  (\(save.vacuums)/\(Catalog.maxVacuums))", "Cleans a fixed radius around the station and drives its dust home.",
                              cost: Catalog.vacuumCost, owned: save.vacuums >= Catalog.maxVacuums,
                              locked: save.hasPackager ? nil : "NEEDS PACKAGER") { $0.vacuums += 1 })
            build.append(gear("Garage", "Builds a garage beside N Station where you buy and park cleaning vehicles.",
                              cost: Catalog.garageCost, owned: save.hasGarage) { $0.hasGarage = true })
            build.append(gear("Capsule Catcher", "Catches capsules fired by J.O.O.N.A.S.", cost: Catalog.catcherCost,
                              owned: save.hasCatcher) { $0.hasCatcher = true })
            build.append(gear("J.O.O.N.A.S.  (\(save.joonas)/\(Catalog.maxJoonas))", "Roams every dirty sector on its own and fires capsules home.",
                              cost: Catalog.joonasCost, owned: save.joonas >= Catalog.maxJoonas,
                              locked: save.hasCatcher ? nil : "NEEDS CATCHER") { $0.joonas += 1 })
        }
        return [ShopViewController.Section(header: "Cleaning tools", items: tools),
                ShopViewController.Section(header: "Suit gear", items: suit),
                ShopViewController.Section(header: "Build", items: build)]
    }

    private func matrixSections() -> [ShopViewController.Section] {
        [ShopViewController.Section(header: "Containers", items: [perk(Catalog.compactor, \.compactor)]),
         ShopViewController.Section(header: "Cleaning", items: [perk(Catalog.wideHeads, \.wideHeads), perk(Catalog.bristles, \.bristles)]),
         ShopViewController.Section(header: "Suit", items: [perk(Catalog.jetTanks, \.jetTanks), perk(Catalog.lampLens, \.lampLens)]),
         ShopViewController.Section(header: "Logistics", items: [perk(Catalog.autoPacker, \.autoPacker), perk(Catalog.capsuleSize, \.capsuleSize)]),
         ShopViewController.Section(header: "Economy", items: [perk(Catalog.brokerage, \.brokerage)])]
    }

    private func garageSections() -> [ShopViewController.Section] {
        var items: [ShopViewController.Item] = []
        for (i, v) in Catalog.vehicles.enumerated() {
            let detail = String(format: "Sweeps a %.1f m strip · %.0f kg hopper · %.0f m/s", v.width, v.capacity, v.speed)
            items.append(gear(v.name, detail, cost: v.cost, owned: save.vehicleLevel >= i) {
                $0.vehicleLevel = i
                $0.hasVehiclePos = false
            })
        }
        return [ShopViewController.Section(header: "Vehicles", items: items)]
    }

    private func openShop(_ kind: ShopKind) {
        paused = true
        scrubHeld = false
        Sfx.shared.play("click")
        let shop = ShopViewController()
        shop.modalPresentationStyle = .overFullScreen
        shop.modalTransitionStyle = .crossDissolve
        shop.money = { [weak self] in self?.save.money ?? 0 }
        switch kind {
        case .wall:
            shop.heading = "SUPPLY WALL"
            shop.sections = { [weak self] in self?.wallSections() ?? [] }
        case .matrix:
            shop.heading = "UPGRADE MATRIX"
            shop.accent = UIColor(red: 0.4, green: 0.92, blue: 1, alpha: 1)
            shop.sections = { [weak self] in self?.matrixSections() ?? [] }
        case .garage:
            shop.heading = "GARAGE"
            shop.sections = { [weak self] in self?.garageSections() ?? [] }
        }
        shop.onClose = { [weak self] in
            guard let self = self else { return }
            self.writeSave()
            self.resume()
            if self.save.tutorialStep == 1 {
                self.toast("Head out the door and hold SCRUB on the dusty ground.", duration: 4)
            }
        }
        present(shop, animated: true)
    }

    private func openMap() {
        guard !paused else { return }
        paused = true
        scrubHeld = false
        Sfx.shared.play("click")
        let map = MapViewController()
        map.modalPresentationStyle = .overFullScreen
        map.modalTransitionStyle = .crossDissolve
        var snap = MapViewController.Snapshot()
        snap.sectorClean = (0..<Hex.count).map { dust.sectorClean($0) }
        snap.stationsFound = save.stationsFound
        snap.stationPos = structures.stationPos
        snap.flagPos = structures.flagPos
        snap.flagsClaimed = save.flagsClaimed
        snap.botPos = bots.map { $0.position }
        snap.vehiclePos = vehicle?.position
        snap.playerPos = player.position
        snap.playerYaw = player.yaw
        snap.waypoint = save.hasWaypoint ? SIMD2<Float>(save.waypointX, save.waypointZ) : nil
        snap.canTeleport = !driving
        snap.money = save.money
        snap.hasBuildTool = save.hasBuildTool
        snap.stationCost = Catalog.stationBaseCost * save.stationsFound.filter { $0 }.count
        map.snapshot = snap
        map.onWaypoint = { [weak self] w in
            guard let self = self else { return }
            self.save.hasWaypoint = w != nil
            if let w = w {
                self.save.waypointX = w.x
                self.save.waypointZ = w.y
            }
            self.world.setWaypoint(x: self.save.waypointX, z: self.save.waypointZ, visible: self.save.hasWaypoint)
        }
        map.onTeleport = { [weak self] i in
            guard let self = self else { return }
            var p = self.structures.spawnPos(i)
            p.y = self.world.height(atX: p.x, z: p.z)
            self.player.position = p
            self.player.velocity = .zero
            Sfx.shared.play("launch", volume: 0.6)
            self.resume()
            self.toast("Teleported to Station \(String(format: "%02d", i + 1)) · \(Hex.names[i])")
        }
        map.onBuild = { [weak self] i in
            guard let self = self else { return }
            let cost = Catalog.stationBaseCost * self.save.stationsFound.filter { $0 }.count
            self.resume()
            guard self.save.hasBuildTool, self.save.money >= Double(cost), !self.save.stationsFound[i] else {
                Sfx.shared.play("deny")
                return
            }
            self.save.money -= Double(cost)
            self.save.stationsFound[i] = true
            self.structures.refresh(self.save, dust: self.dust)
            self.writeSave()
            Sfx.shared.play("claim")
            self.buzz(1)
            self.toast("Station \(String(format: "%02d", i + 1)) built in \(Hex.names[i]). Selling, upgrades and teleport are online there.", duration: 4)
        }
        map.onClose = { [weak self] in self?.resume() }
        present(map, animated: true)
    }

    private func writeSave() {
        save.px = player.position.x
        save.py = player.position.y
        save.pz = player.position.z
        save.yaw = player.yaw
        save.pitch = player.pitch
        save.timeOfDay = world.timeOfDay
        if let v = vehicle {
            save.vehicleX = v.position.x
            save.vehicleZ = v.position.z
            save.vehicleHeading = v.heading
            save.hasVehiclePos = true
        }
        SaveManager.save(save, mask: dust.mask)
    }

    // MARK: Frame loop

    @objc private func step(_ link: CADisplayLink) {
        if lastTime == 0 { lastTime = link.timestamp; return }
        let dt = Float(min(0.05, link.timestamp - lastTime))
        lastTime = link.timestamp
        if paused {
            for name in ["scrub", "jet", "engine"] { Sfx.shared.setLoop(name, volume: 0) }
            return
        }

        world.updateSun(dt: dt)
        tipCooldown -= dt
        let mv = joystick.value
        var collecting = false

        if driving, let v = vehicle {
            let turn = v.update(dt: dt, throttle: Float(mv.y), steer: Float(mv.x), world: world)
            player.yaw += turn
            player.ride(at: v.seat, seatHeight: v.tier.seat)
            let left = v.tier.capacity - save.vehicleLoad
            var got: Float = 0
            if abs(v.speed) > 0.3 {
                if left > 0.01 {
                    let c = v.brushCenter
                    got = dust.clean(atX: c.x, z: c.z, radius: v.tier.width / 2, rate: 3.5, dt: dt, capacityLeft: left)
                    save.vehicleLoad += got
                } else if tipCooldown <= 0 {
                    toast("Hopper full — drive to a DEPOT and tap UNLOAD.")
                    tipCooldown = 5
                }
            }
            v.setSweeping(got > 0)
            collecting = got > 0
            aimRing.isHidden = true
            brushPuff.birthRate = 0
            player.animateTool(dt: dt, scrubbing: false)
        } else {
            player.update(dt: dt, move: SIMD2<Float>(Float(mv.x), Float(mv.y)),
                          jumpPressed: jumpQueued, jumpHeld: jumpHeld, world: world)
            if player.stepEvent { Sfx.shared.play("step", volume: 0.5) }

            let radius = save.toolRadius
            let cap = save.toolCapacity
            if let aim = player.aimPoint(world: world, reach: save.tool.reach) {
                aimRing.isHidden = false
                aimRing.simdPosition = aim + SIMD3<Float>(0, 0.07, 0)
                let ringR = radius + 0.1
                aimRing.simdScale = SIMD3<Float>(ringR, 1, ringR)
                brushPuffNode.simdPosition = aim + SIMD3<Float>(0, 0.06, 0)
                if scrubHeld && !save.hasTool {
                    if tipCooldown <= 0 {
                        toast("You have no tool yet — take the free Toothbrush from the SUPPLY WALL.")
                        tipCooldown = 4
                    }
                } else if scrubHeld {
                    if cap - save.toolLoad <= 0.001 {
                        if save.autoPacker > 0 {
                            pack(manual: false)
                        } else if tipCooldown <= 0 {
                            toast("Tool full — tap PACK to seal the dust in a capsule.")
                            tipCooldown = 4
                        }
                    }
                    let left = cap - save.toolLoad
                    if left > 0.001 {
                        let got = dust.clean(atX: aim.x, z: aim.z, radius: radius, rate: save.toolRate, dt: dt, capacityLeft: left)
                        if got > 0 {
                            collecting = true
                            save.toolLoad += got
                            if save.tutorialStep <= 1 {
                                save.tutorialStep = 2
                                toast("Dust fills your tool. When it's full, tap PACK.", duration: 4)
                            }
                        }
                    }
                }
            } else {
                aimRing.isHidden = true
            }
            brushPuff.birthRate = collecting ? CGFloat(40 + radius * 160) : 0
            aimRing.isHidden = aimRing.isHidden || !save.hasTool
            player.animateTool(dt: dt, scrubbing: scrubHeld && save.hasTool)
        }
        jumpQueued = false

        if collecting {
            hapticTimer -= dt
            if hapticTimer <= 0 {
                buzz(0.35)
                hapticTimer = 0.12
            }
        }

        for bot in bots {
            bot.update(dt: dt, world: world, dust: dust, home: structures.stationPos[Hex.home], dock: structures.botDock)
        }

        let sealed = dust.drainCompleted()
        if !sealed.isEmpty {
            let bonus = Double(sealed.count * Catalog.hexReward)
            save.money += bonus
            save.totalEarned += bonus
            if collecting {
                Sfx.shared.play("claim", volume: 0.45)
                toast("Hex clean!  L.S.D. bonus +$\(Int(bonus))", duration: 1.6)
                bumpMoney()
            }
        }

        updateContext()
        slowTimer += dt
        if slowTimer > 0.5 {
            slowTimer = 0
            slowChecks()
        }
        updateHUD()
        updateWaypointMarker()

        // Sound
        Sfx.shared.setLoop("scrub", volume: collecting && !driving ? 0.55 : 0)
        Sfx.shared.setLoop("jet", volume: player.jetThrusting && !driving ? 0.5 : 0)
        if driving, let v = vehicle {
            Sfx.shared.setLoop("engine", volume: 0.18 + 0.4 * abs(v.speed) / v.tier.speed)
        } else {
            Sfx.shared.setLoop("engine", volume: 0)
        }
        Sfx.shared.setLoop("amb", volume: 0.3)

        saveTimer += dt
        if saveTimer > 30 {
            saveTimer = 0
            writeSave()
        }
    }

    private func updateContext() {
        let pp = SIMD2<Float>(player.position.x, player.position.z)
        func near(_ p: SIMD3<Float>, _ r: Float) -> Bool {
            simd_length(pp - SIMD2<Float>(p.x, p.z)) < r
        }
        var action: UseAction = .none
        var title = "USE"
        if driving, let v = vehicle {
            action = .exitVehicle
            title = "EXIT"
            if save.vehicleLoad > 0.01 {
                let vp = SIMD2<Float>(v.position.x, v.position.z)
                let i = Hex.nearest(vp.x, vp.y)
                let s = structures.stationPos[i]
                if save.stationsFound[i] && simd_length(vp - SIMD2<Float>(s.x, s.z)) < 14 + v.tier.length / 2 {
                    action = .unload(i)
                    title = "UNLOAD"
                }
            }
        } else {
            for (i, f) in structures.flagPos.enumerated() where !save.flagsClaimed[i] {
                if near(f, 2.8) { action = .flag(i); title = "CLAIM FLAG"; break }
            }
            let st = Hex.nearest(pp.x, pp.y)
            if action == .none && save.stationsFound[st] && near(structures.stationPos[st], 9) {
                if near(structures.intakePos(st), 2.4) {
                    if save.capsuleLoad + save.toolLoad > 0.0005 {
                        action = .deposit(st)
                        title = "DEPOSIT"
                    } else if save.trayKg > 0.0005 {
                        action = .sellTray(st)
                        title = String(format: "SELL %.1f KG", save.trayKg)
                    }
                } else if near(structures.wallUsePos(st), 2.4) {
                    action = .wall
                    title = "SUPPLY WALL"
                } else if near(structures.matrixUsePos(st), 2.3) {
                    action = .matrix
                    title = "UPGRADES"
                }
            }
            if action == .none {
                if save.hasGarage && near(structures.garagePos, 4.2) {
                    action = .garage
                    title = "GARAGE"
                } else if let v = vehicle, near(v.position, v.tier.length / 2 + 2.6) {
                    action = .drive
                    title = "DRIVE"
                }
            }
        }
        useAction = action
        if useButton.title != title { useButton.title = title }
        useButton.isHidden = action == .none
        packButton.isHidden = driving || save.toolLoad <= 0.001
        scrubButton.isHidden = driving
        jumpButton.isHidden = driving
        crosshair.isHidden = driving
    }

    /// Twice a second: discoveries, sector completion, night hints.
    private func slowChecks() {
        let pp = SIMD2<Float>(player.position.x, player.position.z)
        let nearest = Hex.nearest(pp.x, pp.y)
        structures.lightStation(save.stationsFound[nearest] ? nearest : Hex.home)
        for i in 0..<Hex.count where !save.sectorsDone[i] && dust.sectorClean(i) >= 0.99 {
            save.sectorsDone[i] = true
            save.money += Double(Catalog.sectorReward)
            save.totalEarned += Double(Catalog.sectorReward)
            Sfx.shared.play("claim")
            bumpMoney()
            toast("SECTOR CLEAN: \(Hex.names[i])!  L.S.D. bonus +$\(Catalog.sectorReward)", duration: 4)
        }
        if world.isNight && !nightTipShown && !player.lampOn && !nightVisionOn {
            nightTipShown = true
            toast("Lunar night is falling — tap LAMP for your helmet light.", duration: 3.5)
        }
        if !world.isNight { nightTipShown = false }
    }

    private func updateHUD() {
        let m = Int(save.money)
        if m != lastMoneyShown {
            lastMoneyShown = m
            moneyLabel.text = ShopViewController.dollars(save.money)
        }
        let sec = Hex.nearest(player.position.x, player.position.z)
        sectorLabel.text = String(format: "HEX %.0f%%  ·  SECTOR %02d · %@ · %.1f%%",
                                  dust.tileClean(atX: player.position.x, z: player.position.z) * 100,
                                  sec + 1, Hex.names[sec].uppercased(), dust.sectorClean(sec) * 100)
        let mult = save.processing(night: world.isNight)
        let product = mult >= 7 ? "MOONSTONE ×7" : (mult >= 3 ? "MOON SAND ×3" : "RAW DUST")
        moonLabel.text = String(format: "MOON %.3f%% CLEAN · %@ · %@", dust.cleanFraction * 100,
                                world.isNight ? "NIGHT" : "DAY", product)

        if driving, let v = vehicle {
            toolName.text = v.tier.name.uppercased()
            toolMeter.fraction = CGFloat(save.vehicleLoad / v.tier.capacity)
            toolMeter.caption = String(format: "HOPPER %.0f / %.0f kg", save.vehicleLoad, v.tier.capacity)
            toolMeter.isHidden = false
            capsuleMeter.isHidden = true
        } else {
            let cap = save.toolCapacity
            let owned = save.toolsOwned.filter { $0 }.count
            toolName.text = save.hasTool ? save.tool.name.uppercased() + (owned > 1 ? "   ⇄" : "") : "NO TOOL"
            toolMeter.isHidden = !save.hasTool
            toolMeter.fraction = CGFloat(save.toolLoad / cap)
            toolMeter.caption = String(format: "TOOL %.2f / %.1f kg", save.toolLoad, cap)
            capsuleMeter.isHidden = false
            capsuleMeter.fraction = CGFloat(save.capsuleLoad / save.capsuleCapacity)
            capsuleMeter.caption = String(format: "CAPSULE %.1f / %.0f kg", save.capsuleLoad, save.capsuleCapacity)
        }
        player.setCapsuleVisible(!driving && save.capsuleLoad > 0.001)

        fuelMeter.isHidden = player.maxFuel <= 0 || driving
        if player.maxFuel > 0 { fuelMeter.fraction = CGFloat(player.fuel / player.maxFuel) }
    }

    private func updateWaypointMarker() {
        guard save.hasWaypoint else {
            waypointLabel.isHidden = true
            return
        }
        let target = SIMD3<Float>(save.waypointX, world.height(atX: save.waypointX, z: save.waypointZ) + 2, save.waypointZ)
        let d = target - player.eyePosition
        let dist = simd_length(SIMD2<Float>(d.x, d.z))
        if dist < 4 {
            save.hasWaypoint = false
            world.setWaypoint(x: 0, z: 0, visible: false)
            waypointLabel.isHidden = true
            toast("Waypoint reached.")
            return
        }
        waypointLabel.isHidden = false
        waypointLabel.text = String(format: "◆ %.0f m", dist)
        let b = view.bounds
        let ahead = simd_dot(d, player.forward)
        let side = simd_dot(d, player.right)
        let angle = atan2(side, ahead)
        var x: CGFloat
        var y: CGFloat = max(view.safeAreaInsets.top, 10) + 96
        if abs(angle) < 0.6 {
            let p = scnView.projectPoint(SCNVector3(target.x, target.y, target.z))
            x = CGFloat(p.x)
            y = max(y, min(b.height * 0.6, CGFloat(p.y) - 24))
        } else {
            x = angle > 0 ? b.width - 70 : 70
            y = b.height * 0.42
        }
        x = max(70, min(b.width - 70, x))
        waypointLabel.frame = CGRect(x: x - 60, y: y, width: 120, height: 18)
    }
}
