# Releasing

How a version goes from a commit to a download. Only the maintainer does this, and only the
last step publishes anything.

## Once

1. Join the Apple Developer Program, then create a "Developer ID Application" certificate in
   Xcode (Settings, Accounts, Manage Certificates) or on developer.apple.com.
2. Save the notary login in the keychain, so the release script never sees a password:

   ```sh
   xcrun notarytool store-credentials micro-notary --apple-id <apple id> --team-id <team id>
   ```

   It asks for an app-specific password, made at account.apple.com.

## Each release (about 1 hour, most of it the install test)

1. Write the version in `VERSION` and in `plugin/.claude-plugin/plugin.json`, and the changes
   in `CHANGELOG.md`. Commit.
2. Run the install test on a new Mac account ([install-test.md](install-test.md)), from a test
   zip (`scripts/release` with no options) as well as from source.
3. Build the real zip:

   ```sh
   scripts/release --identity "Developer ID Application: <name> (<team id>)" --notary-profile micro-notary
   ```

   It signs with the hardened runtime, waits for Apple's notarization (usually a few minutes),
   staples the ticket to the app, checks it with Gatekeeper, and prints the zip's SHA-256.
4. Tag the commit `v<version>` and push the tag. On GitHub, make a release from the tag, paste
   the changelog entry, and attach `dist/MicroBridge-<version>.zip`. **This publishes it.**

## What the script checks, and what it cannot

- The Developer ID build must come from a clean commit, and needs both `--identity` and
  `--notary-profile`.
- The test zip has the same hardened runtime, so trying it tries what people will download.
  The bridge asks for no entitlements: reading the pad, posting keys and using Accessibility
  need none.
- A notarized app still asks each user for Input Monitoring and Accessibility. Nothing can
  grant those for them.
