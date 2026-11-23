# Contributing

Thanks for wanting to help. MicroBridge is a small project kept by one person in their spare
time, so a short, focused change with tests is the one most likely to land.

## What is in scope

- **macOS 14 or later.** Windows and Linux are out of scope.
- **The Codex Micro** made by Work Louder, tested on firmware v0.6.1, over USB. Bluetooth is
  untested: reports from Bluetooth users are welcome.
- **Claude Code**, in the Claude app and in a terminal (Terminal, Ghostty).

Not in scope: anything that writes the pad's storage or firmware, network features, and code
taken from the ChatGPT, Codex, Work Louder or Claude apps. Facts about how they behave are fine;
their code is not ours to copy.

## Build and test

You need a Swift 6 toolchain. The Command Line Tools are enough; Xcode is not needed.

```sh
swift build
scripts/test               # every test; plain `swift test` works when Xcode is installed
scripts/micro app --demo   # the window with made-up sessions; it writes nothing
.build/debug/micro snapshot /tmp/shots   # every screen of the window as a PNG file
```

To try a change on a real pad, `scripts/install` builds the app into `~/Applications` and
restarts the bridge. Its log is `~/Library/Logs/micro-bridge.log`.

## Rules the code keeps

A change that breaks one of these will not be merged, however useful it is.

1. **Five pad methods, no others.** The bridge sends `sys.version`, `device.status`,
   `v.oai.thstatus`, `v.oai.rgbcfg` and `lights.preview`. Nothing that writes the pad's files,
   settings or firmware.
2. **No network.** The hook and the daemon talk over a Unix socket on the Mac. Nothing leaves it.
3. **Keys go where the user expects.** Typed keys and clicks go to the app in front, and only to
   the apps in `keystrokeApps` when that list is set. A test or tool that types must check the
   intended app is in front first.
4. **No dependencies at run time.** Swift and Apple's frameworks only.
5. **Tests pass and the compiler is quiet.** `scripts/test` passes with no warnings. A fix comes
   with a test that fails without it, where one can be written.
6. **Root only in MicroBridge Helper, and the helper stays small.** It links only `PadWire`,
   holds or shares the pad, and writes the five methods after `HelperWire.checkedRequest`
   rebuilds them. Anything else, parsing config or acting on keys included, belongs in the
   daemon, which runs as the user (D-027).
7. **No private data.** No home folder paths, real email addresses, session ids or keys, in code,
   tests or docs. CI runs `scripts/check-public`; use `/Users/x`, `example.com`, and the made-up
   id listed in that script.

## How the code is laid out

- `Sources/PadWire`: what the daemon and the helper share: the pad's reports (`Framing.swift`),
  finding it and the five methods (`Device.swift`), and the helper's socket protocol
  (`HelperWire.swift`).
- `Sources/micro-helper`: MicroBridge Helper, the optional root program (`scripts/helper`
  installs it).
- `Sources/MicroKit`: the pad (`Pad.swift`, `RPC.swift`), sharing it with ChatGPT (`Sharing.swift`),
  the daemon (`Daemon.swift`), the config (`Config.swift`), what controls do (`Gestures.swift`,
  `Actions.swift`) and the Claude app's buttons (`ScreenButtons.swift`).
- `Sources/MicroUI`: the window, in SwiftUI. The Command Line Tools have no `@State` macro
  plugin, so state lives in plain observable objects.
- `Sources/micro`: the one program: the daemon, the hook, the window and every command.
- `plugin/`: the Claude Code plugin, which only hands each event to the installed app.
  `.claude-plugin/marketplace.json` lists it, so this repository is its marketplace.
- Swift 6 with strict concurrency. The daemon runs on the main actor.

## When a Claude app update breaks a button

Approve, Decline and the dial find buttons in the Claude app by their accessibility labels and
class names, and an update can rename them.

1. With the button on screen, run `scripts/micro buttons --match <text>` to see what it is called
   now, or `scripts/micro tree <box>` for everything inside its box.
2. Change the rule in `Config.builtIn` (in `Config.swift`) and in `docs/configuration.md`.
3. Say which Claude app version you checked in the pull request.

Until a release has the fix, anyone can patch their own `config.json` the same way.

## Sending a change

1. Open an issue first for anything bigger than a small fix, so we can agree on the shape.
2. Keep one change per pull request. Say what it does, why, and how you checked it: tests, and
   on a real pad if it touches the hardware.
3. Write user-facing text in plain words: what happens, not how it is built.
4. A design choice goes in the pull request's description. The maintainer records it in
   `docs/decisions.md`.

Contributions are under the [MIT license](LICENSE), like the rest of the project.

## Reporting problems

Bugs and ideas: open an issue and fill in its form. Security problems: in private, as
[SECURITY.md](SECURITY.md) says, not in a public issue.

Be kind to each other. Disagreement about code is welcome; unkindness to people is not.
