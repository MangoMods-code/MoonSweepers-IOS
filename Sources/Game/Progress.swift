import Foundation

struct ToolTier {
    let name: String
    let radius: Float   // meters
    let rate: Float     // fraction of full dust removed per second
    let reach: Float    // meters from the eye
    let cost: Int
}

struct SimpleTier {
    let name: String
    let value: Float
    let cost: Int
}

enum Upgrades {
    static let tools: [ToolTier] = [
        ToolTier(name: "Toothbrush",     radius: 0.35, rate: 0.6, reach: 2.6, cost: 0),
        ToolTier(name: "Scrub Brush",    radius: 0.70, rate: 0.8, reach: 2.8, cost: 60),
        ToolTier(name: "Push Broom",     radius: 1.20, rate: 1.0, reach: 3.3, cost: 350),
        ToolTier(name: "Dust Vacuum",    radius: 1.90, rate: 1.3, reach: 4.5, cost: 1500),
        ToolTier(name: "Sweeper Cannon", radius: 3.00, rate: 1.6, reach: 6.5, cost: 6000),
    ]
    static let bags: [SimpleTier] = [
        SimpleTier(name: "Pocket Pouch", value: 15, cost: 0),
        SimpleTier(name: "Dust Sack",    value: 40, cost: 40),
        SimpleTier(name: "Canvas Bag",   value: 110, cost: 220),
        SimpleTier(name: "Dust Tank",    value: 320, cost: 1000),
        SimpleTier(name: "Mega Hopper",  value: 1000, cost: 4500),
    ]
    static let boots: [SimpleTier] = [
        SimpleTier(name: "Standard Boots",   value: 3.2, cost: 0),
        SimpleTier(name: "Grip Boots",       value: 4.3, cost: 90),
        SimpleTier(name: "Gravity Boots",    value: 5.6, cost: 500),
        SimpleTier(name: "Mag-Sprint Boots", value: 7.2, cost: 2200),
    ]
    static let jetpacks: [SimpleTier] = [
        SimpleTier(name: "No Jetpack",   value: 0, cost: 0),
        SimpleTier(name: "Jetpack Mk1",  value: 1.5, cost: 150),
        SimpleTier(name: "Jetpack Mk2",  value: 3.5, cost: 800),
        SimpleTier(name: "Jetpack Mk3",  value: 7.0, cost: 2800),
    ]
    static let botCosts: [Int] = [500, 1600, 4200, 9000]
    static let nightVisionCost = 250
    static let teleporterCost = 8000

    /// Dust units per square meter of fully dusty ground.
    static let unitsPerSquareMeter: Float = 10
    static let creditsPerUnit: Float = 1
}

struct SaveData: Codable {
    var credits: Double = 0
    var totalEarned: Double = 0
    var toolLevel = 0
    var bagLevel = 0
    var bootLevel = 0
    var jetLevel = 0
    var hasNightVision = false
    var hasTeleporter = false
    var bots = 0
    var bagDust: Float = 0
    var px: Float = 0
    var py: Float = 0
    var pz: Float = 6
    var yaw: Float = 0
    var pitch: Float = -0.15
    var timeOfDay: Float = 0.12
    var tutorialStep = 0
}

enum SaveManager {
    private static let key = "moonsweepers.save.v1"

    private static var maskURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("dustmask-v1.bin")
    }

    static var hasSave: Bool { UserDefaults.standard.data(forKey: key) != nil }

    static func load() -> SaveData? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: data)
    }

    static func loadMask(expectedCount: Int) -> [UInt8]? {
        guard let data = try? Data(contentsOf: maskURL), data.count == expectedCount else { return nil }
        return [UInt8](data)
    }

    static func save(_ s: SaveData, mask: [UInt8]) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
        try? Data(mask).write(to: maskURL, options: .atomic)
    }

    static func wipe() {
        UserDefaults.standard.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: maskURL)
    }
}
