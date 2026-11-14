# Moon Sweepers — iOS mockup

First-person (no hands) iOS mockup of Moon Sweepers: clean the Moon, starting with a toothbrush.

## What's in it
- Low-gravity first-person movement on a cratered moon map (160 × 160 m), starfield sky and Earth overhead
- Dust layer over the whole map that you brush away (cleaned ground stays clean and is saved)
- Dust bag → empty it at the **Dust Silo** for credits
- **Upgrade Terminal**: Toothbrush → Scrub Brush → Push Broom → Dust Vacuum → Sweeper Cannon, bigger bags, faster boots, jetpack, night-vision goggles, D.U.S.T.Y. sweep-bots, dust teleporter
- Lunar day/night cycle with a helmet lamp
- Touch controls: floating joystick (left), drag to look (right), SCRUB / JUMP (hold JUMP in the air for jetpack) / USE
- Auto-save

All art is placeholder geometry made in code. No assets from the PC game are included.

## Building the IPA
Every push to `main` runs **Actions → Build IPA**. It generates the Xcode project with XcodeGen, builds unsigned for iOS 15+, and publishes
`MoonSweepers-<version>-b<build>.ipa` as a GitHub Release (and a workflow artifact). Sign it with Mango Signer before installing.

Bump `MARKETING_VERSION` in `project.yml` for new versions; the build number is the Actions run number, so it always goes up.
