# Caffeine - CLAUDE.md

## Project Overview
macOS menu bar app that prevents your Mac from sleeping.

## Tech Stack
- **Language**: Swift 5
- **UI Framework**: SwiftUI
- **IDE**: Xcode
- **Platforms**: macOS
- **Minimum Deployment**: macOS 13.5

## Style & Conventions (MANDATORY)
**Strictly follow** the Swift/SwiftUI style guide: `~/Agents/Style/swift-swiftui-style-guide.md`

## Changelog (MANDATORY)
**All important user facing changes** (fixes, additions, deletions, changes) must be written to CHANGELOG.md.
Changelog format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Localization (MANDATORY)
**Strictly follow** the localization guide: `~/Agents/Guides/localization-guide.md`
- All user-facing strings must be localized
- Follow formality rules per language
- Consistency is paramount

## Additional Guides
- Modern SwiftUI patterns: `~/Agents/Guides/swift-modern-development-guide.md`
- Observable migration: `~/Agents/Guides/swift-observable-migration-guide.md`
- Swift 6 concurrency: `~/Agents/Guides/swift6-concurrency-guide.md`
- Swift 6 migration (compact): `~/Agents/Guides/swift6-migration-compact-guide.md`
- Swift 6 migration (full): `~/Agents/Guides/swift6-migration-full-guide.md`

## Logging (MANDATORY)
This project uses **DZFoundation** (`~/GIT/Libraries/DZFoundation`) for logging.

**All debug logging must use:**
- `DZLog("message")` — General debug output
- `DZErrorLog(error)` — Conditional error logging (only prints if error is non-nil)

```swift
import DZFoundation

DZLog("Starting fetch")       // 🔶 fetchData() 42: Starting fetch
DZErrorLog(error)             // ❌ MyFile.swift:45 fetchData() ERROR: Network unavailable
```

**Do NOT use:**
- `print()` for debug output
- `os.Logger` instances
- `NSLog`

Both functions are no-ops in release builds.

## API Documentation
Local Apple API documentation is available at:
`~/Agents/API Documentation/Apple/`

The `search` binary is located **inside** the documentation folder:
```bash
~/Agents/API\ Documentation/Apple/search --help  # Run once per session
~/Agents/API\ Documentation/Apple/search "view controller" --language swift
~/Agents/API\ Documentation/Apple/search "NSWindow" --type Class
```

## Xcode Project Files (CATASTROPHIC — DO NOT TOUCH)
- **NEVER edit Xcode project files** (`.xcodeproj`, `.xcworkspace`, `project.pbxproj`, `.xcsettings`, etc.)
- Editing these files will corrupt the project — this is **catastrophic and unrecoverable**
- Only the user edits project settings, build phases, schemes, and file references manually in Xcode
- If a file needs to be added to the project, **stop and tell the user** — do not attempt it yourself
- Use `xcodebuild` for building/testing only — never for project manipulation
- **Exception**: Only proceed if the user gives explicit permission for a specific edit
  
## File System Synchronized Groups (Xcode 16+)
This project uses **File System Synchronized Groups** (internally `PBXFileSystemSynchronizedRootGroup`), introduced in Xcode 16. This means:
- The `src/Caffeine/Classes/` and `src/Caffeine/Resources/` directories are **directly synchronized** with the file system
- **You CAN freely create, move, rename, and delete files** in these directories
- Xcode automatically picks up all changes — no project file updates needed
- This is different from legacy Xcode groups, which required manual project file edits

**Bottom line:** Modify source files in `src/Caffeine/Classes/` and `src/Caffeine/Resources/` freely. Just never touch the `.xcodeproj` files themselves.

## Build & Format Commands
```bash
# Build
xcodebuild -scheme "Caffeine" -destination "platform=macOS" build

# Run tests
xcodebuild -scheme "Caffeine" -destination "platform=macOS" test

# Clean
xcodebuild -scheme "Caffeine" clean
```

## Code Formatting (MANDATORY)
**Always run SwiftFormat after a successful build:**
```bash
swiftformat .
```

SwiftFormat configuration is defined in `.swiftformat` at the project root. This enforces:
- 4-space indentation
- Explicit `self.` usage
- K&R brace style
- Trailing commas in collections
- Consistent wrapping rules

**Do not commit unformatted code.**

---

## Notes
- The style guide emphasizes native SwiftUI patterns over MVVM boilerplate
- Prefer `@Observable` (macOS 14+) over `ObservableObject`
- Use `async/await` and `.task` modifier for async work
- Avoid Combine unless specifically needed
- Use `DZLog`/`DZErrorLog` for all debug logging — never `print()`
- Always run `swiftformat .` after successful builds before committing