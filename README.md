# Moon Sweepers — iOS mockup

First-person (no hands) iOS mockup of Moon Sweepers, written in Swift + SceneKit. Terrain, textures, sky and sound are generated in code. Rocks, the garage, consoles, dishes and other props use Kenney's **Space Kit** (CC0, www.kenney.nl — licence in `Assets/Models`). No assets from the PC game are included.

## What's in it
- **You start inside N Station** with nothing: take the free Toothbrush from the Supply Wall, walk out the door and start sweeping. Nothing else stands on the Moon until you build it.
- **Stations:** 12 identical walk-in stations (one per sector). Each has the Supply Wall, the Upgrade Matrix hologram behind the service table, and the orange deposit intake with its launcher. Discovering one unlocks selling, upgrades and teleport there.
- **Dust:** dark regolith over pale clean ground, swept in crisp lines. The Moon is tiled in small hexes; finishing one pays a bonus, finishing a whole sector pays a bigger one. No dust under foundations.
- **Core loop:** sweep → PACK a capsule → carry it inside → DEPOSIT into the tray → SELL to launch the shipment.
- **Supply Wall:** Toothbrush → Nail Brush ($5) → Handbrush ($10) → Household Broom ($25) → Wide Broom ($75) → Extra Wide Broom ($150), suit gear, Building Tool ($50) and everything it builds (Packager, Pressure Chamber, Stone Press, Battery Bank, Robot Vacuums, Garage, Capsule Catcher, J.O.O.N.A.S.).
- **Upgrade Matrix:** Containers, Cleaning, Suit, Logistics and Economy perks.
- **Garage (once built):** drivable Push Sweeper, Sweeper Truck and Mega Suagrover.
- **Also:** Moon Map with waypoints and teleport, 36 flags, day/night, pause menu and a full settings screen, synthesized sound, auto-save.

Not in yet: co-op, free-placement building, save slots.

## Building the IPA
Every push to `main` runs **Actions → Build IPA**: XcodeGen project, unsigned build for iOS 15+, and
`MoonSweepers-<version>-b<build>.ipa` published as a GitHub Release. Sign it before installing.

Bump `MARKETING_VERSION` in `project.yml` for new versions; the build number is the Actions run number, so it always goes up.
