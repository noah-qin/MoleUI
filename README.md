# Mole UI

> [!WARNING]
> **MoleUI is archived and no longer maintained.**
>
> MoleUI was an unofficial community GUI for the [Mole](https://github.com/tw93/Mole) CLI. Mole now has an official native app: please use **[Mole for Mac](https://mole.fit/)** instead.
>
> The last release, v0.1.5, bundles the Mole CLI from March 2026 and is not compatible with current Mole releases. The code stays available under the MIT license.

Native macOS GUI for [Mole](https://github.com/tw93/Mole). Built with SwiftUI, with Mole Go+Shell as the core kernel.

![screenshot](./Resources/screenshot.png)

## 📚 Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines
- **[CHANGELOG.md](CHANGELOG.md)** - Version history
- **[SECURITY.md](SECURITY.md)** - Security policy
- **[AUTO_UPDATE.md](AUTO_UPDATE.md)** - Auto-update system details

## Features

| Feature | CLI Command | GUI Support |
|---------|------------|-------------|
| System Status Monitor | `mo status` | ✅ Real-time Dashboard (JSON mode) |
| Disk Space Analyzer | `mo analyze` | ✅ Visual Analysis (JSON mode) |
| System Cleanup | `mo clean` | ✅ Dry Run Support |
| System Optimization | `mo optimize` | ✅ Dry Run Support |
| Large File Purge | `mo purge` | ✅ |
| Installer Management | `mo installer` | ✅ |
| App Uninstaller | `mo uninstall` | ✅ |
| Full Disk Access Detection | - | ✅ GUI only |
| Touch ID sudo | `mo touchid` | CLI only |
| Shell Completion | `mo completion` | CLI only |
| Self Update | `mo update` | CLI only |
| Uninstall Mole | `mo remove` | CLI only |

### UI/UX Highlights

- **Unified Theme System**: Consistent color palette with pine, moss, and meadow tones
- **Full Disk Access Helper**: Automatic detection and one-click navigation to System Settings
- **Modern Design**: Rounded panels with material effects and adaptive dark mode
- **Improved Accessibility**: Better contrast, clear visual hierarchy, and readable typography

## Installation

Download the latest DMG from [GitHub Releases](https://github.com/imnotnoahhh/MoleUI/releases), open it, and drag Mole UI into Applications.

Mole CLI is bundled inside the app, no additional installation required.

## Requirements

- macOS 14.0 (Sonoma) or later

## Build from Source

```bash
# Install just (build runner)
brew install just

# Clone repository
git clone https://github.com/imnotnoahhh/MoleUI.git
cd MoleUI

# Build
just build

# Or open with Xcode
open MoleUI.xcodeproj
```

## Development

```bash
just run              # Build and launch
just clean            # Clean build artifacts
just fmt              # Format code (swiftformat)
just lint             # Lint (swiftlint)
just update-mole      # Update bundled Mole CLI from Homebrew
just info             # Show Swift/Xcode/Mole versions
```

Run tests from Xcode (Cmd+U) or command line:

```bash
# Run all tests
xcodebuild -scheme MoleUI test \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Run only unit tests
xcodebuild test -scheme MoleUI \
  -destination 'platform=macOS' \
  -only-testing:MoleUITests \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Test suites:
# - MoleCoreTests: 44 core functionality tests
# - UIFlowTests: 15 critical user flow tests
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- 🎨 UI/UX improvements
- 🧪 Mole CLI compatibility testing
- 🛡️ Stability and bug fixes
- ⚡ Performance optimization

Quick start:
1. Fork the repo and create a feature branch
2. Follow the existing MV architecture — logic in `Model/`, UI in `View/`
3. Run `just fmt && just lint` before committing
4. Open a PR against `main`

## Auto-Update System

MoleUI implements a complete auto-update workflow that automatically detects, validates, and releases new versions when upstream Mole CLI updates. See [AUTO_UPDATE.md](AUTO_UPDATE.md) for details on:
- Automatic compatibility checking
- Auto-merge and auto-release workflow
- Version number synchronization
- User-facing update notifications

## Architecture

MV (Model-View) architecture with Swift's `@Observable` macro, acting primarily as a UI wrapper over the Mole CLI, with native bridging for JSON parsing and file system operations:

```
MoleUI/
├── Model/          # @Observable domain models (state + logic)
│   ├── MetricsModel.swift      # System metrics & dashboard data (via mole status --json)
│   ├── CleanModel.swift        # Cleanup scanning & execution (via mole clean)
│   ├── DiskModel.swift         # Disk space analysis (via mole analyze --json)
│   ├── OptimizeModel.swift     # System optimization (via mole optimize)
│   ├── PurgeModel.swift        # Large file purge (via mole purge)
│   ├── InstallerModel.swift    # Installer management (via mole installer)
│   ├── UninstallModel.swift    # App scanning & uninstall (via mole uninstall)
│   ├── VersionModel.swift      # CLI version checking
│   ├── SafetyController.swift  # Confirmation & dry-run
│   ├── CLIExecutor.swift       # Mole CLI process wrapper & JSON parser
│   ├── ErrorTranslator.swift   # User-friendly error mapping
│   └── SudoHelper.swift        # Privilege escalation
└── View/           # Pure SwiftUI views (UI only)
    ├── MoleApp.swift           # @main entry, @Environment injection
    ├── ContentView.swift       # NavigationSplitView layout
    ├── DashboardView.swift     # System status dashboard
    ├── CleanView.swift         # Cleanup interface
    ├── DiskAnalyzerView.swift  # Disk usage visualization
    ├── OptimizeView.swift      # Optimization interface
    ├── PurgeView.swift         # Large file purge interface
    ├── InstallerView.swift     # Installer management
    ├── UninstallView.swift     # App uninstaller
    ├── SettingsView.swift      # Preferences & about
    ├── MoleVersionView.swift   # CLI version display
    └── SidebarView.swift       # Navigation sidebar
```

**Key principles:**
- Model: `@Observable @MainActor` classes, injected via `.environment()`. Delegates to Mole CLI for core operations.
- View: reads Model state through `@Environment(XxxModel.self)`
- Swift 6 strict concurrency
- Hybrid architecture: GUI wraps Mole CLI Go/Bash kernel for data accuracy and feature parity

## Credits

- [tw93/Mole](https://github.com/tw93/Mole) — Original CLI tool, Mole UI is based on this project
- Built with SwiftUI + NavigationSplitView for native macOS experience

## Troubleshooting

**App won't open:** Right-click → Open, or run `xattr -cr "/Applications/Mole UI.app"`

**Dashboard not loading:** Restart the app. If issue persists, check Console.app for errors.

**Slow disk scanning:** Large directories take time. Scan smaller folders first.

**Full Disk Access needed:** For comprehensive disk analysis without repeated permission prompts, enable Full Disk Access in System Settings → Privacy & Security → Full Disk Access. Mole UI can guide you there from the Settings tab.

For more issues, check [GitHub Issues](https://github.com/imnotnoahhh/MoleUI/issues).

## License

MIT
