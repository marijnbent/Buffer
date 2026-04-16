# Local Release

Canonical local release commands:

```bash
./scripts/build-release.sh
./scripts/release-local.sh
```

`./scripts/build-release.sh` builds a signed app bundle at `build/Release/Clippie.app`.

`./scripts/release-local.sh` quits Clippie, builds the signed release app, verifies it, installs it to `/Applications/Clippie.app`, and opens it.

`clippie` now uses Swift Package Manager as its compile backend, so `swift build` and the release scripts go through the same package target.

Release settings live in `release/Release.plist`. Entitlements live in `release/App.entitlements`.
