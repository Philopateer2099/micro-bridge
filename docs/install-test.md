# Testing the install on a new Mac account

Run this before a release: it is the only check that starts from nothing, the way a new user
does. It takes about 30 minutes. A fresh clone that builds and passes `scripts/test` is already
checked by CI; this covers what only a new account shows: the keychain, the privacy prompts,
a missing Claude Code settings file, and the pad answering a second daemon.

## Before: on your own account (5 minutes)

1. Stop your bridge, so two bridges do not both light the pad:

   ```sh
   launchctl bootout "gui/$(id -u)/local.micro-bridge"
   ```

2. While the repo is private, put a copy where the new account can read it:

   ```sh
   git bundle create /Users/Shared/micro-bridge.bundle <branch>
   ```

   Once the repo is public, skip this: the new account clones from GitHub.

3. In System Settings, Users & Groups, add a user. Make it an administrator, so it can turn on
   its own privacy settings.
4. Switch to it with fast user switching (Control Center, your name), so your own account
   keeps running.

## In the new account (20 minutes)

Run the README's install steps in order. For each one, write down anything that differs from
what is expected here.

| Step | Expected |
| --- | --- |
| `git clone -b <branch> /Users/Shared/micro-bridge.bundle micro-bridge && cd micro-bridge` (or the README's `git clone`) | A `micro-bridge` folder. On a Mac without the Command Line Tools, macOS offers to install them first. |
| `scripts/make-cert` | `created: MicroBridge Local Signing`, with no password prompt. |
| `scripts/install` | About 2 minutes the first time, then `installed:` and `log:` lines. No keychain prompt. |
| `scripts/claude-hooks install` | `created …/.claude/settings.json and added the hook to 11 events` if Claude Code has not made one yet; else `added the hook to 11 events in …` and a backup line. |
| `scripts/micro access` | macOS asks for Input Monitoring, then Accessibility, for MicroBridge. Turn both on in System Settings. |
| `launchctl kickstart -k "gui/$(id -u)/local.micro-bridge"` | Within a few seconds `~/Library/Logs/micro-bridge.log` says `pad connected: Codex Micro over USB`. |
| `scripts/micro ctl state` | One line of JSON with `"connected":true`. |
| `open ~/Applications/MicroBridge.app` | The window opens; the Setup screen shows what is still missing. |

MicroBridge Helper is optional, and there is one per Mac, serving one account. Skip it here
unless you mean to test it: installing it in the new account moves it off your own, and you
then run `sudo scripts/helper install` again from your account. If you test it:

| Step | Expected |
| --- | --- |
| `sudo scripts/helper install` | `MicroBridge Helper is installed and running for uid …`. |
| Input Monitoring, +, `/Library/PrivilegedHelperTools/MicroBridge Helper.app` | A MicroBridge Helper row, switched on. |
| Within a minute | The log says `pad connected: Codex Micro over USB, through MicroBridge Helper`. |

If Claude Code is signed in on this account, start a session: a key should turn blue while it
works and green when it is done.

Then try it the way a download works, without the scripts (10 more minutes):

1. `scripts/claude-hooks remove`, then `scripts/uninstall`.
2. `scripts/release`, then unzip `dist/MicroBridge-<version>.zip` and move `MicroBridge.app`
   to `/Applications`. Open it.
3. Setup says the bridge is not running. Press **Start at login**: macOS may ask you to allow
   it under Login Items. The log then says `pad connected`, and Setup shows "Start at login: On".
4. Press **Copy the command**, paste it in Terminal, press Return: `created …` or `added the
   hook to 11 events`. Setup shows all 11 events.
5. Optional: remove the hook again (`/Applications/MicroBridge.app/Contents/MacOS/micro hooks
   remove`) and install the plugin instead (see the README). A session still lights a key.
6. Press **Don't start at login**: the bridge stops, and Login Items no longer lists it.

Then save the log for reading later, and check removal:

```sh
cp ~/Library/Logs/micro-bridge.log /Users/Shared/test-account-micro-bridge.log
scripts/claude-hooks remove
scripts/uninstall
```

`scripts/claude-hooks remove` says `removed the hook from 11 events` (or `nothing to change`),
and `scripts/uninstall` prints `removed`. Drag `/Applications/MicroBridge.app` to the Trash,
then switch back to your own account.

## After: on your own account (5 minutes)

1. Start your bridge again:

   ```sh
   launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/local.micro-bridge.plist
   ```

2. Read `/Users/Shared/test-account-micro-bridge.log`, then delete it and the bundle.
3. Delete the test account in Users & Groups.
4. Fix in the README whatever a step got wrong.
