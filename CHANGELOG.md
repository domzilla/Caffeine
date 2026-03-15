# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Update default editor for publishing
- Add post_publish_commands to update website config
- Improve Ukrainian translation

### Fixed

- Fix wrong indentation

## [1.6.3] - 2026-01-26

### Added

- Add Ukrainian translation

### Changed

- Migrate to Sparkle SPM version
- Move Sparkle binaries to central directory
- Remove obsolete assets

### Fixed

- Fix activity simulation to properly reset system idle timer

## [1.6.2] - 2025-12-14

### Added

- Add optional "Keep apps active" preference toggle
- Add activity simulation to prevent apps from going idle
- Add project documentation (CLAUDE.md)

### Fixed

- Fix control-click instruction to use correct symbol

## [1.6.1] - 2025-11-13

### Fixed

- Fix tinting of menu bar icon

## [1.6.0] - 2025-11-12

### Added

- Rewrite the app in SwiftUI
- Add Sparkle 2.8.0 with gentle scheduled update reminders
- Add accent color
- Add app category

### Changed

- Update icon for Tahoe with static gradient
- Update privacy info
- Reposition menu items

### Fixed

- Fix entitlements
- Fix deprecation warnings
- Fix a typo on the preference screen

## [1.5.3] - 2025-06-25

### Added

- Add Control+Click as equivalent to right-click

## [1.5.2] - 2025-05-23

### Fixed

- Fix default duration not being respected

## [1.5.1] - 2025-03-03

### Fixed

- Fix presentation of preference window on launch

## [1.5.0] - 2025-01-22

### Added

- Add Sparkle updater for automatic updates
- Add sandbox entitlement for Sparkle

### Changed

- Migrate project to Swift
- Update to macOS Sequoia

### Fixed

- Fix typo

## [1.4.0] - 2023-10-17

### Changed

- Update Sonoma icon

## [1.3.0] - 2023-10-17

### Added

- Add Japanese localization
- Add localizations with dynamic layout support
- Add preference to deactivate when device manually goes to sleep
- Add Sonoma icon
- Add GitHub sponsorship support

### Changed

- Refactor preferences window
- Update repository URL in credits
- Update copyright in license

### Fixed

- Fix IOPMAssertionCreateWithDescription timeout (deactivating app now works correctly)
- Fix app icon drop shadow
- Fix autoresizing
- Fix code signing issues

## [1.1.3] - 2020-05-12

### Added

- Initial public release

### Changed

- Update macOS SDK version for deployment
- Remove CocoaPods directory from repository
