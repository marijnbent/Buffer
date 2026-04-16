# clippie Agent Notes

## Signed Builds

- Build this app with signing enabled.
- When the user asks to build the app, build a signed local Release build.
- When the user asks to build the app, move the built app to `/Applications` after a successful build, then open it from there.
- Do not use ad-hoc or unsigned signing unless the user explicitly asks for it.
- Unsigned builds can cause macOS Accessibility permission to be requested again after rebuilds.

Use:

```bash
./scripts/release-local.sh
```

Build a signed local release app without installing it:

```bash
./scripts/build-release.sh
```

## Signing Expectations

- The app compiles with Swift Package Manager and is packaged/signed by the repo-local release scripts.
- The user has already confirmed local Release builds can use the existing signing setup.
- Use bundle identifier `nl.bentjes.clippie` unless the user asks to change it.
- If signing fails, do not silently switch to an unsigned build. Tell the user what failed.

## UI Copy

- When the user explains why they want a UI change, treat that as internal context unless they explicitly ask for it to appear in the product.
- Do not turn their rationale, business goals, or implementation notes into visible UI copy.

## Configuration

- Do not default to turning every setting into an environment variable.
- Only introduce environment variables when explicitly requested or when clearly necessary.
- If adding an environment variable is optional, ask first.
