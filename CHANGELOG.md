# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Automatic lid handling on the ordinary Caffeine toggle: darken the built-in display and keyboard without locking on closure, lock on reopening, then restore the saved brightness levels.
- First-use administrator helper installation, reused across activations. The existing version-1 helper also supports the new automatic behavior.
- Arabic interface, universal build and helper removal scripts, heartbeat/crash recovery, battery/thermal stopping, and isolated helper/transition tests.

### Changed

- Replaced the large lid-control panel with one persistent checkbox and a short description; enabled by default.

- Replaced the earlier lock-at-activation session button with automatic behavior. Activation no longer locks; unlocking no longer ends Caffeine.
- Disabled upstream automatic updates for the separately identified direct-distribution fork.
- Improved Ukrainian translation.

### Fixed

- Rapid off/on toggling waits for the previous helper session to finish restoring power instead of failing and opening preferences. Canceled startup attempts cannot overwrite a newer session.

- Removed the two-second gap between sleep-prevention assertions, and suppressed simulated mouse activity while the lid is closed.
- Timer no longer stays active and shows negative seconds after the Mac sleeps past the activation period.

## [1.6.3] - 2026-01-26

### Added

- Ukrainian translation.

### Fixed

- Activity simulation now properly resets the system idle timer.

## [1.6.2] - 2025-12-14

### Added

- Optional "Keep apps active" preference that simulates activity to prevent apps from going idle.

### Fixed

- Corrected the Control-click instruction symbol.

## [1.6.1] - 2025-11-13

### Fixed

- Menu bar icon tinting.

## [1.6.0] - 2025-11-12

### Added

- Rewritten in SwiftUI.
- Automatic update reminders via Sparkle.
- App accent color and category.

### Changed

- Updated the icon for Tahoe with a static gradient.
- Repositioned menu items.

### Fixed

- Entitlements.
- Deprecation warnings.
- Typo on the preferences screen.

## [1.5.3] - 2025-06-25

### Added

- Control-click is now treated the same as a right-click.

## [1.5.2] - 2025-05-23

### Fixed

- Default duration is now respected.

## [1.5.1] - 2025-03-03

### Fixed

- Preferences window no longer appears unexpectedly on launch.

## [1.5.0] - 2025-01-22

### Added

- Automatic updates via Sparkle.

### Changed

- Migrated the project to Swift.
- Updated for macOS Sequoia.

## [1.4.0] - 2023-10-17

### Changed

- Updated icon for macOS Sonoma.

## [1.3.0] - 2023-10-17

### Added

- Japanese localization, plus localizations with dynamic layout support.
- Preference to deactivate Caffeine when the device is manually put to sleep.
- Sonoma-styled app icon.
- GitHub sponsorship support.

### Changed

- Refactored the preferences window.

### Fixed

- Deactivating the app now reliably releases the system sleep assertion.
- App icon drop shadow.
- View autoresizing.

## [1.1.3] - 2020-05-12

### Added

- Initial public release.
