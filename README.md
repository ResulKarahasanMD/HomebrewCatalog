# HomebrewCatalog

A native macOS app (SwiftUI, Swift 6) for browsing the Homebrew catalog and managing what is installed
on your Mac: discover and search formulae and casks, see download rankings, and install, upgrade,
uninstall or clean up through the local `brew` command, with a preview before anything changes.

This is an independent project. It is not affiliated with or endorsed by the Homebrew project.

## What it does

- **Catalog:** Discover, Categories, Formulae, Casks and download rankings, read from the public
  Homebrew JSON API (`formulae.brew.sh`); detail pages with dependencies and the project README.
- **Your machine:** Installed, Outdated, Pinned, Leaves, Services, Taps and Mac App Store apps
  (through `mas`, if installed), read from the local `brew`.
- **Changes:** install, upgrade and uninstall sheets, maintenance commands with a dry-run preview,
  and an action history. Secrets such as GitHub tokens are redacted from captured `brew` output
  before it is shown or stored.
- **Library:** Favorites, History and Groups, stored locally with SwiftData.

The app runs `brew` as a subprocess, so it is not sandboxed and cannot be distributed through the Mac App Store.

## Requirements

- macOS 27.0.1 or later (deployment target 27.0)
- Xcode 27
- Homebrew at `/opt/homebrew` or `/usr/local`

## Build and test

```bash
xcodebuild -project HomebrewCatalog.xcodeproj -scheme HomebrewCatalog -destination 'platform=macOS' build
xcodebuild -project HomebrewCatalog.xcodeproj -scheme HomebrewCatalog -destination 'platform=macOS' test
```

`project.yml` is the [XcodeGen](https://github.com/yonaskolb/XcodeGen) definition the Xcode project is generated from.
The bundle identifier in it is the author's; change it if you sign the app yourself.

## Documents

- [`Docs/PRD.md`](Docs/PRD.md): the original product requirements (written before the app grew local `brew` management).
- [`Docs/Sidebar-Navigation.md`](Docs/Sidebar-Navigation.md): the sidebar selection architecture (in Turkish).

## License

[MIT](LICENSE).
