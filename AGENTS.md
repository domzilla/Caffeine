# Caffeine - CLAUDE.md

## Project Overview
macOS menu bar app that prevents your Mac from sleeping.

## Tech Stack
- **Language**: Swift
- **UI Framework**: SwiftUI
- **IDE**: Xcode
- **Platforms**: macOS

## Guides (MANDATORY)
Read `~/Agents/Guides/xcode-project-guide.md` in full before planning or editing anything.

Read these in full before touching the matching code:
- Swift style (`.swift`): `~/Agents/Style/swift-swiftui-style-guide.md`
- Accessibility (UI code, XIBs, storyboards): `~/Agents/Guides/accessibility-guide.md`

## Build Commands
```bash
# Build
xcodebuild -scheme "Caffeine" -destination "platform=macOS" build

# Clean
xcodebuild -scheme "Caffeine" clean
```

## Testing (MANDATORY)
No test targets exist in this project.
