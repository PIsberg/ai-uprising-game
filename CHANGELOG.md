# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added an "OUT OF GRENADES" message that appears when trying to throw a grenade with an empty inventory.
- The Manus Boss's weak spot (core) now has collision, allowing it to correctly take damage.

### Changed
- Headshots are now more difficult to achieve, requiring greater precision.
- Fixed an issue where the factory default Melee key (F) would steal the keybind back on restart if the user had assigned F to Zoom (or another action).
- Taking aggressive actions (like a Melee shove or a Dash) now cleanly breaks you out of Aiming Down Sights (ADS) for a smoother transition, instead of keeping the camera zoomed in while the weapon model punches out of frame.
- Changed the damage hit-flash on enemies to white, preventing them from appearing golden/red when taking rapid damage.
- Optimized 3D assets to load faster and consume less memory, resulting in a smoother gameplay experience.

