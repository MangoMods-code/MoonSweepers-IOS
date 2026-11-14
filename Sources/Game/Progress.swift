import Foundation

struct HandTool {
    let name: String
    let cost: Int
    let width: Float     // meters swept (across)
    let depth: Float     // meters front-to-back of the head
    let capacity: Float  // kg held in the tool's container
    let rate: Float      // how fast it lifts dust
    let reach: Float     // meters from the eye
}

struct VehicleTier {
    let name: String
    let cost: Int
    let width: Float
    let capacity: Float
    let speed: Float
    let length: Float
    let bodyWidth: Float
    let seat: Float
}

struct Perk {
    let name: String
    let detail: String
    let costs: [Int]
    var maxLevel: Int { costs.count }
}

enum Catalog {
    static let tools: [HandTool] = [
        HandTool(name: "Toothbrush", cost: 0, width: 0.12, depth: 0.06, capacity: 0.5, rate: 1.4, reach: 5.5),
        HandTool(name: "Nail Brush", cost: 5, width: 0.20, depth: 0.10, capacity: 1.0, rate: 1.5, reach: 5.5),
        HandTool(name: "Handbrush", cost: 10, width: 0.35, depth: 0.15, capacity: 1.5, rate: 1.6, reach: 5.5),
        HandTool(name: "Household Broom", cost: 25, width: 0.60, depth: 0.10, capacity: 3.0, rate: 1.8, reach: 6.0),
        HandTool(name: "Wide Broom", cost: 75, width: 1.00, depth: 0.10, capacity: 5.0, rate: 2.0, reach: 6.0),
        HandTool(name: "Extra Wide Broom", cost: 150, width: 1.50, depth: 0.11, capacity: 8.0, rate: 2.2, reach: 6.5),
    ]

    static let vehicles: [VehicleTier] = [
        VehicleTier(name: "Push Sweeper", cost: 500, width: 2.0, capacity: 30, speed: 4.5, length: 2.2, bodyWidth: 1.5, seat: 1.7),
        VehicleTier(name: "Sweeper Truck", cost: 2500, width: 3.7, capacity: 150, speed: 8.0, length: 4.4, bodyWidth: 2.6, seat: 2.5),
        VehicleTier(name: "Mega Suagrover", cost: 6000, width: 6.0, capacity: 500, speed: 9.5, length: 6.0, bodyWidth: 3.6, seat: 3.2),
    ]

    static let compactor = Perk(name: "Dust Compactor", detail: "+20% tool container per level.", costs: [20, 50, 120, 300, 700])
    static let wideHeads = Perk(name: "Wide Heads", detail: "+15% tool width per level.", costs: [30, 80, 200, 500, 1200])
    static let bristles = Perk(name: "Long Handles", detail: "+0.6 m cleaning reach per level.", costs: [25, 60, 150, 400, 900])
    static let jetTanks = Perk(name: "Jetpack Tanks", detail: "+2s of jetpack fuel per level.", costs: [120, 400, 1200])
    static let lampLens = Perk(name: "Helmet Lamp Lens", detail: "Brighter, wider helmet lamp.", costs: [40, 160])
    static let autoPacker = Perk(name: "Auto Packer", detail: "Packs a capsule automatically when your tool is full.", costs: [150])
    static let capsuleSize = Perk(name: "Capsule Size", detail: "Bigger capsules: 5 → 15 → 40 → 100 kg.", costs: [40, 150, 500])
    static let brokerage = Perk(name: "Dust Brokerage", detail: "+10% sale price per level.", costs: [100, 300, 800, 2000, 5000])

    static let capsuleSizes: [Float] = [5, 15, 40, 100]
    static let pricePerKg: Double = 2
    static let flagReward = 100
    static let sectorReward = 500
    static let hexReward = 5
    static let stationBaseCost = 600

    static let bootsCost = 60
    static let jetpackCost = 200
    static let nightVisionCost = 350
    static let buildToolCost = 50
    static let packagerCost = 100
    static let batteryCost = 400
    static let chamberCost = 500
    static let pressCost = 1000
    static let catcherCost = 1500
    static let garageCost = 200
    static let vacuumCost = 750
    static let maxVacuums = 4
    static let joonasCost = 20000
    static let maxJoonas = 3
}

struct SaveData: Codable {
    var money: Double = 0
    var totalEarned: Double = 0
    var kgSold: Double = 0

    var toolsOwned: [Bool] = [false, false, false, false, false, false]
    var currentTool = -1
    var trayKg: Float = 0
    var toolLoad: Float = 0
    var capsuleLoad: Float = 0

    var compactor = 0
    var wideHeads = 0
    var bristles = 0
    var jetTanks = 0
    var lampLens = 0
    var autoPacker = 0
    var capsuleSize = 0
    var brokerage = 0

    var hasBoots = false
    var hasJetpack = false
    var hasNightVision = false
    var hasBuildTool = false
    var hasPackager = false
    var hasBattery = false
    var hasChamber = false
    var hasPress = false
    var hasCatcher = false
    var hasGarage = false

    var vehicleLevel = -1
    var vehicleLoad: Float = 0
    var vehicleX: Float = 0
    var vehicleZ: Float = 0
    var vehicleHeading: Float = 0
    var hasVehiclePos = false

    var vacuums = 0
    var joonas = 0

    var stationsFound: [Bool] = (0..<12).map { $0 == Hex.home }
    var flagsClaimed: [Bool] = [Bool](repeating: false, count: 36)
    var sectorsDone: [Bool] = [Bool](repeating: false, count: 12)

    var px: Float = 0
    var py: Float = 0
    var pz: Float = 2
    var yaw: Float = 0
    var pitch: Float = -0.2
    var timeOfDay: Float = 0.06
    var tutorialStep = 0

    var hasWaypoint = false
    var waypointX: Float = 0
    var waypointZ: Float = 0

    var soundOn = true
    var highGraphics = true
    var gridOn = false
    var hapticsOn = true
    var invertY = false
    var sensitivity: Float = 1

    // Derived stats
    var hasTool: Bool { currentTool >= 0 }
    var tool: HandTool { Catalog.tools[max(0, currentTool)] }
    var toolCapacity: Float { tool.capacity * (1 + 0.2 * Float(compactor)) }
    var toolRadius: Float { tool.width / 2 * (1 + 0.15 * Float(wideHeads)) }
    var toolHalfDepth: Float { tool.depth / 2 }
    var toolReach: Float { tool.reach + 0.6 * Float(bristles) }
    var capsuleCapacity: Float { Catalog.capsuleSizes[min(capsuleSize, Catalog.capsuleSizes.count - 1)] }
    var moveSpeed: Float { hasBoots ? 5.2 : 3.4 }
    var jetFuel: Float { hasJetpack ? 2.5 + 2 * Float(jetTanks) : 0 }

    func processing(night: Bool) -> Double {
        if night && !hasBattery { return 1 }
        if hasPress { return 7 }
        if hasChamber { return 3 }
        return 1
    }

    func value(ofKg kg: Float, night: Bool) -> Double {
        Double(kg) * Catalog.pricePerKg * processing(night: night) * (1 + 0.1 * Double(brokerage))
    }
}

enum SaveManager {
    private static let ioQueue = DispatchQueue(label: "moonsweepers.save", qos: .utility)
    private static let key = "moonsweepers.save.v4"

    private static var maskURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("dustbits-v4.bin")
    }

    static var hasSave: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func load() -> SaveData? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }

    static func loadBits() -> Data? {
        try? Data(contentsOf: maskURL)
    }

    static func save(_ s: SaveData, mask: [UInt8]) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
        // The dust mask is a few MB, so write it off the main thread.
        let url = maskURL
        ioQueue.async {
            try? DustField.pack(mask).write(to: url, options: .atomic)
        }
    }

    static func wipe() {
        UserDefaults.standard.removeObject(forKey: key)
        let url = maskURL
        ioQueue.sync { try? FileManager.default.removeItem(at: url) }
    }
}
