# Moon Sweepers — iOS mockup

First-person (no hands) iOS mockup of Moon Sweepers, written in Swift + SceneKit. Everything — models, textures, sky and sound — is generated in code; no assets from the PC game are included.

## What's in it
- **The Moon:** 12 hexagonal sectors on a cratered, boulder-strewn map with sun shadows, a lunar day/night cycle, Earth and stars overhead, and a hex-grid overlay toggle.
- **Core loop:** sweep dust into your tool → PACK it into a capsule → carry it to a Depot intake → the shipment launches and you get paid.
- **Supply Wall:** Toothbrush → Nail Brush ($5) → Handbrush ($10) → Household Broom ($25) → Wide Broom ($75) → Extra Wide Broom ($150), Gravity Boots, Forward Jetpack, Night Vision Goggles ($350), Building Tool ($50).
- **Upgrade Matrix:** Containers, Cleaning, Suit, Logistics and Economy perks (Dust Compactor, Wide Heads, Auto Packer, …).
- **Build:** Packager, Pressure Chamber (Moon Sand ×3), Stone Press (Moonstone ×7), Battery Bank (machines stop at night without it), Robot Vacuums, Capsule Catcher, J.O.O.N.A.S.
- **Garage:** drivable Push Sweeper, Sweeper Truck (3.7 m strip) and Mega Suagrover.
- **Exploration:** 12 stations to discover and teleport between, a Moon Map with waypoints, 36 flags to claim, sector-complete bonuses.
- **Touch controls:** floating joystick (left), drag to look (right), SCRUB / JUMP (hold in the air for the jetpack) / PACK / context USE button. Auto-save.

Not in yet: co-op, free-placement conveyor building, save slots.

## Building the IPA
Every push to `main` runs **Actions → Build IPA**: XcodeGen project, unsigned build for iOS 15+, and
`MoonSweepers-<version>-b<build>.ipa` published as a GitHub Release. Sign it before installing.

Bump `MARKETING_VERSION` in `project.yml` for new versions; the build number is the Actions run number, so it always goes up.
