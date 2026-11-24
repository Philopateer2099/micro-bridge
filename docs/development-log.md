# micro-bridge: development log

This is the working journal kept while the bridge was built, in the order things happened. It
is here for anyone who wants to know why something works the way it does. To use the bridge,
read the [README](../README.md) and [configuration.md](configuration.md) instead.

- "The owner" is the person whose pad the bridge was built and tested on.
- Times are UTC. "Seen" means seen on that one pad (firmware 0.6.1, and 0.6.3 from 2026-11-22 16:09) and that one Mac.
- Files named `config.json.before-…` were backups on that Mac. They are not in the repository.
- The plan at the top is the first plan. Later sections say where the work left it.
- `PROTOCOL.md` holds the notes on how the pad talks to a host. It is kept out of the repository.

Our own driver for the Codex Micro that lights one Agent Key per Claude Code session, in the
Claude app or a terminal. Orca was in the first plan and was taken out on 2026-11-13 (see
"Orca support removed" below). Protocol facts: `PROTOCOL.md`.

## Goals

- Six Agent Keys show live state: working, needs you, done, idle, error.
- Tap a key: jump to that session.
- Approve / reject keys answer the prompt in the focused agent.
- Every key, the stick, the dial and the lights are set in one config file: `configuration.md`.
  Full feature list and gaps: `features.md`.
- No third-party runtime code. No writes to the pad's storage or firmware.

## Shape

```
 Claude Code ──(1)──► micro-bridge daemon ──HID──► Codex Micro
   hooks              (owns the pad, maps        ◄── key / dial / joystick events
                       state → colors)
                              │
                              └──► actions: typed keys, on-screen buttons, Claude app links
```

1. **Claude Code source**: command hooks that call `micro hook`, a fast native binary, so
   tool calls don't slow down.
2. **Daemon**: one process, macOS LaunchAgent, Unix socket at `~/Library/Application Support/micro-bridge/` (mode 0700 dir, 0600 socket).
   Opens the pad non-exclusively, sends only allowlisted RPC methods, reconnects on unplug and
   Bluetooth handoff.

## State → light

| Status | Claude Code event | Light |
|---|---|---|
| `working` | prompt submitted, tool running | blue `0x304FFE`, solid |
| `needs-you` | permission prompt | amber `0xFF6D00`, breath |
| `idle` | idle prompt | white `0xFFFFFF`, solid |
| `done` | Stop | green `0x00FF4C` until you look at it |
| `failed` | error | red `0xFF0033` |
| `off` | none | off |

Colors match ChatGPT's so the pad behaves the same in both apps.

## Language: Swift (recommended)

- IOKit HID is built into macOS, so the daemon has **zero dependencies**.
- Input Monitoring is granted to this one signed binary. A Node daemon would need it granted to
  the `node` binary, which hands it to every Node script on the machine.
- Swift 6.4 is already installed (Command Line Tools).
- Cost: macOS only. Rebuilding with a new ad-hoc signature re-prompts Input Monitoring, so we
  sign with one stable local certificate.

Alternative: TypeScript + `node-hid` (the vendor's own stack). Faster to write, cross-platform,
but brings back a native npm dependency and the broad `node` permission.

## Coexisting with ChatGPT

Both apps can open the pad at once, but both would write the lights. The daemon checks whether
ChatGPT is running. If it is, the daemon either leaves the lights alone or owns only the slots
ChatGPT leaves dark (decide after the spike, step 4 in `PROTOCOL.md`).
Built differently on 2026-11-21: see "Sharing the pad with ChatGPT" below.

## Phases

| # | Step | Done when | Estimate |
|---|---|---|---|
| 1 | Probe CLI: find pad, `device.status`, paint 6 keys, print raw events | every control's event name recorded in `PROTOCOL.md` | 1 to 2 h, needs the pad plugged in |
| 2 | Daemon + socket API + LaunchAgent | lights survive unplug and Bluetooth switch | 2 to 3 h |
| 3 | Key actions (the Orca source first planned here was dropped, 2026-11-13) | tap a key, its session comes up | 2 to 3 h |
| 4 | Approve / reject / dial for Claude Code and Codex | answer a prompt from the pad in both agents | 1 to 2 h |
| 5 | Claude Code hooks | Claude Code sessions light keys | 1 h |

Total: about 1 to 1.5 days of work.

## Open questions

- Exact keystrokes that approve / reject in Claude Code vs Codex TUIs.

## Status

- **Phase 1 done** (2026-11-10): probe CLI, every control mapped in `PROTOCOL.md`.
- **Phase 2 done** (2026-11-11): daemon installed as LaunchAgent `local.micro-bridge`, app at
  `~/Applications/MicroBridge.app`, log at `~/Library/Logs/micro-bridge.log`. Signed with the
  self-signed keychain certificate "MicroBridge Local Signing" (`scripts/make-cert`), so the
  Input Monitoring grant survives rebuilds. USB unplug/replug repaints within about 9 s.
  `scripts/install` rebuilds and reinstalls; `scripts/uninstall` removes it.
- **Claude Code done** (2026-11-11, was phase 5): every Claude Code session (desktop app or CLI)
  takes the lowest free Agent Key and keeps it until the session ends (since 2026-11-18 a
  Claude app session keeps it after that too, see "Keys remember their sessions"). Hooks in
  `~/.claude/settings.json` run `micro hook` on 11 events; it takes 7 to 9 ms, prints nothing and
  exits 0 even when the daemon is off. `scripts/claude-hooks install|remove|status` manages the
  entries and leaves every other hook alone. Checked with two live sessions and a question prompt
  (key went amber while it waited, blue after the answer).
- **Configurable controls done** (2026-11-11): `~/Library/Application Support/micro-bridge/config.json`
  binds every control to actions (`key:`, `keydown:`/`keyup:`, `text:`, `sh:`, `open:`, `ack`,
  `focus`) on `press`, `release`, `doubleTap` and `hold`, and sets brightness, auto-dim, pulse
  and colors. The daemon reloads it within a second; a broken file keeps the last good settings.
  Reference: `configuration.md`. Code: `Config.swift`, `Gestures.swift`, `Actions.swift`. 53 tests pass.
  MicroBridge has the Accessibility permission (needed to type keys). Typed keys only go to
  Claude, Terminal and Ghostty (`keystrokeApps`; Orca was on that list until 2026-11-13). Checked on the pad: typing, dial, live
  reload. Not yet tried on the pad: hold, double tap, stick, `focus`, the light settings.
- Bluetooth untested: the Mac lists the pad as paired but it does not connect.

- **Jump to session done** (2026-11-11): tapping an Agent Key runs `ack` then `jump`. The hook
  reads where the session lives from its own environment and sends it as `host` with each
  report: `CLAUDE_CODE_HOST_SESSION_ID` (`local_…`, set by the Claude desktop app). `jump` then
  runs `open -b com.anthropic.claudefordesktop "claude://code/continue?session=local_…"`. A
  session with no host (Terminal, Ghostty) gets its app raised. Ids are checked to be plain id
  characters before use. Checked by hand: the link moved the Claude window to the named
  session. Checked on the pad: a tap on key 2 opened that key's Claude app session. This
  entry first had a second half for Orca terminals; it was removed on 2026-11-13.
  Facts behind the link (Claude.app 2026-11-10 build, no code copied): `claude://code/continue`
  takes `session=last` or an id matching `local_[A-Za-z0-9-]{1,64}` and opens that session if
  it is not archived.

- **Commands per app done** (2026-11-11): a key is set to a named command (`cmd:SPLIT`) and
  `commands` in the config says what each does per app group (`apps`: `claude`, `terminal`), by
  bundle id, or by `default`. All 39 ChatGPT keycap ids are defined plus `PLAN`, `FORWARD`,
  `BACK`, `SIDEBAR`, `PADSETTINGS`, `COMPUTER`. The default layout is the stock one: Fast,
  Approve, Decline, Fork, Mic, Send; stick up/right/down/left; dial hold opens the config.
  `keydown:` now repeats like a held key (a terminal only sees a hold through repeats). A press
  on an Agent Key with no session runs `agentKeys.empty` (then `open:claude://code/new`; since
  2026-11-18 nothing by default, the owner's choice) and
  holds that key for the next session to appear (120 s). 61 tests pass.
  Sources of the key facts: ChatGPT.app's keycap table (keycap id → command), Claude.app's
  shortcut table and approval prompt (Cmd+D dictation, Cmd+Opt+O fork, Cmd+N new, Cmd+Return
  allow once, Esc deny, Cmd+J terminal, Cmd+Shift+D diff, Cmd+B sidebar), code.claude.com docs
  for the CLI (`/branch`, `/clear`, `/fast`, `/voice` with hold Space, Shift+Tab, `/effort`).
  Checked by hand: `claude://code/new` opens the new-session page. Not yet tried on the pad:
  every `cmd:` key.

- **Crash fixed** (2026-11-11): the daemon died from SIGPIPE when a client hung up before its
  answer (a hook gives up after 1 s while the daemon waits on a slow pad). `SO_NOSIGPIPE` cannot
  be set on a socket whose other end is already gone, so `micro` now ignores SIGPIPE for the
  whole process. Reproduced with 21 early hang-ups before the fix; 500 survive after it.
  Until 2026-11-18 a restart forgot every session until its next hook event; now the keys
  come back from `sessions.json`.

- **Silent pad** (2026-11-11 18:21 to 2026-11-12 02:48 UTC): the pad stayed on USB, took every
  command and answered none (`sys.version` included), and sent no key events.
  Checked on the Mac, 22:04 to 22:43 UTC:
  - The pad sent no input report of any kind in that time. Every write succeeded (no errors).
  - ChatGPT, opened at 18:30 UTC, wrote 2,600 times and also received nothing.
  - MicroBridge has Input Monitoring and Accessibility, no program seized the pad, and no
    program holds secure keyboard input. So the Mac is not dropping replies.
  - The owner ran the touch-control switch back to USB and saw the lights return. The pad
    stayed silent, so Bluetooth mode alone does not explain it.
  **Fixed by a cable replug** at 02:48 UTC on 2026-11-12: the pad re-attached, answered
  `sys.version` (v0.6.1) and `device.status` at once, and every program with the pad open
  started receiving again. So the USB input path was stuck, on the pad or on the Mac; which
  end is not known. The firmware itself was alive the whole time (the touch control worked).
  Done 2026-11-12: the daemon's "pad is not answering" log line now names the replug first.
  Background: OpenAI's page says a 3 s hold on the touch control switches to Bluetooth (lights
  blue) and that a cable then only charges; back to USB is the selector again, tapping until
  the lights turn white.
  The daemon used to close and reopen the pad every 11 s, blocking 10 s each time and logging
  1,100 lines. It now keeps the pad open, waits 2 s for an answer, retries after 5, 10, 20, 40,
  60 s, logs once, and repaints as soon as any key event arrives.

- **Wrong layer** (2026-11-12, from 02:48 UTC): after the replug the pad reported
  `layer_index: 2`, an empty layer in the owner's key map, so key presses sent nothing. A tap
  on the touch sensor cycles layers. One press of key 7 did arrive at 02:54:26 UTC (the owner
  had tapped back to layer 1), then the pad was on layer 2 again. The earlier "tap until the
  lights turn white" step can leave the pad one tap past layer 1.
  Done 2026-11-12: the daemon reads `device.status` every 5 s, logs layer changes and shows
  a macOS notification when the pad leaves layer 1 and when it returns (`layerWarning`).
  `micro ctl state` now carries `layer`, `battery` and `charging`. Checked live: layer 1 and
  battery 100 read through the daemon. Not seen yet: the warning itself, which needs a tap to
  layer 2. Permanent fix on the owner's side: delete the empty layer in Work Louder Input.

- **USB drops** (2026-11-12): the pad left USB and came straight back three times at
  02:54:42 to 02:54:49 UTC, and left USB altogether at 03:45:05 UTC, ten seconds after a run of
  key presses. Cause not known: a loose cable or port, the rear power button, or the owner
  unplugging it. Together with the silent pad above, the cable and port are worth swapping.

### Bridge went deaf to the pad (2026-11-12 18:44 UTC), fixed

- Seen: 39 s after a restart the bridge logged "pad is not answering" and stopped reacting to
  keys, while Work Louder Input kept logging the pad's well-formed replies to the bridge's own
  requests (ids 9 to 14) and a fresh `micro status` got answers in milliseconds.
- Cause in our code: `MessageAssembler` joined RPC lines from the first `{` until the text
  parsed. One line that never parses (cut short, or two messages run together) made every later
  line pile onto it, for up to 16 KiB.
- Fix: a later line that parses on its own replaces the stuck text, and text is dropped after 4
  lines. The daemon logs what it dropped ("pad sent text that is not a message").
- Not known: what the unreadable text was, or why the pad (or a lost report) produced it. The
  pad answered nothing for the bridge's ids 5 to 8 just before. The new log line will show it
  next time. Some earlier "pad is not answering" episodes may have been this.

### A key stayed amber after its turn was stopped by hand (2026-11-12 19:04 UTC), fixed

- Seen: a thread showed a multiple-choice card (`AskUserQuestion`), its key went amber, the owner
  pressed key 7. Escape closed the card and stopped the turn (the record ends with the tool
  rejected and "[Request interrupted by user for tool use]"), and the key stayed amber.
- Cause: Claude Code fires no hook when a turn is stopped by hand (Escape, a declined question
  or permission prompt), so the bridge never heard that the session stopped waiting.
- Fix: the hook now passes `transcript_path`; once a second the daemon reads the tail of the
  record of each busy or waiting session, and when the latest entry from either side is that
  interruption, no older than the last report, the session goes to `idle`.
- Checked: `micro record <file>` on the real record says "stopped by hand at 13:04:43"; a
  stand-in session on the live daemon went from `needs-you` to `idle` within 2.5 s.
  Seen on a real thread at 19:25:23 UTC: key 7 on a multiple-choice card in this chat, the log
  says "session fdc65c7a was stopped by hand", and the owner saw the amber light go.

### The dial answers multiple-choice cards (2026-11-12 19:57 UTC), built

- Asked: use the dial and its press for a multiple-choice card.
- Seen first: the dial's old keys (Up, Down, Return) never reach the card. In a chat they scroll
  it; in the text box they walk the prompt history.
- Built: `choose:<box>/<class>/<next|prev>` presses the answer after or before the one that is
  on (`ScreenButtons.choose`, `OptionRule`). Commands `NEXT`, `PREV`, `PICK` put it on the dial:
  in the Claude app `choose:epitaxy-approval-card/epitaxy-answer-option/next` (or `prev`), then
  the old key; the press runs `click:epitaxy-approval-card/Submit!`, then Return.
- With no card on screen the first dial step pays one look at the window (0.1 to 0.3 s); further
  steps skip the look until the dial has rested 0.4 s. `clickGuard` now follows a `click:` only.
- Seen on a real 4-answer card: every turn logged `selected "<answer>"` in about 20 ms; the press
  logged `pressed "Submit"` at 19:57:13 UTC and the highlighted answer arrived.
- Found in that log: five fast clicks all pressed the same answer, because the app had not shown
  the first press yet. Since then a step within 0.5 s of the last one starts from the answer the
  bridge itself turned on.
- A step now keeps the card it found for 5 s and looks only inside it: 2 ms and 14 elements a
  step, against 120 ms and 1,590 for a search of the window. The searches had slowed the app
  enough that it showed an old answer for over a second.
- Found by experiment at 20:08 and 20:12 UTC (`micro choose` and `micro click` on cards nobody
  touched): while the keyboard focus is outside the card, the first press on an answer or on
  "Submit" only moves the focus onto it. A press half a second later works. That is why the
  first spin on every card was lost.
- Fix: `choose:` presses an answer again every quarter second, for up to a second, until the
  app shows it on, when no answer had the focus. `click:<box>/<pick>!` does the same for a
  button that goes away when it works (`ScreenButton.pressUntilGone`); `PICK` uses it.
- Seen from the pad: one dial press closed a fresh card at 20:21:49 UTC (3 presses); the first
  turn on a fresh card selected the next answer at 20:23:12 UTC (3 presses, 0.54 s), later
  turns 2 ms; the answer sent matched the log each time.
- Direction: on this pad a turn to the right arrives as `ccw`, so `ccw` runs `NEXT` and `cw` runs
  `PREV` (swapped at 20:27 UTC; the owner confirmed it).
- Mic key in the Claude app: Cmd+D is an on/off switch, so the key sends it once on press and
  once on release (was `keydown`/`keyup`, which the app did not treat as hold-to-talk). The
  owner confirmed hold-to-talk works.
- Untried: cards that take several answers; "Other" (the dial skips it); whether "Allow once"
  and "Deny" on a fresh permission-mode card need the same `!`.

### The dial ticked every answer on a card that takes several (2026-11-12 20:37 UTC), fixed

- Seen: on a multi-select card each dial step pressed an answer, so turning ticked them all.
- The owner asked for: focus the card by itself, turn = like the Up and Down arrows, press = Space.
- Built: `ScreenButtons.card` reads a card's places (every usable toggle and button) and whether
  it takes several answers (its screen-reader counter, "N selected", is filled in). On such a
  card `choose:…/next` and `prev` move the keyboard focus through Accessibility over the answers
  and then the button named by `+Submit`; the first step also types Left and Right once the focus
  has arrived, so the app draws its focus outline. `choose:…/mark` types a real Space on the
  place that has the focus. `PICK` is now `mark`, then `click:…/Submit!`, then Return.
- One-answer cards are unchanged: a turn selects, the press submits.
- Seen from the pad at 01:23 UTC on 2026-11-13: highlight moved, Space ticked "Banana" and
  "Cherry" and nothing else, Space on "Submit" sent the card with those two.
- Two probes went wrong on the way and are gone: one typed test keys into Orca because it typed
  into whichever app was in front (9 keys: Tab, Down, Space, Shift+Tab, Up, Tab x4), one timed
  out waiting. `micro key` now needs the app's bundle id and types only while it is in front.
- Untried: "Other" on either kind of card (the highlight skips it).

### Orca support removed (2026-11-13), the owner's choice

- Why: Agent Keys 1 and 2 held Claude Code sessions that ran in Orca terminals. A press ran
  `orca terminal switch` and `open -b com.stablyai.orca`, which started Orca when it was closed
  (log, 03:21 to 03:22 UTC). The owner wants no Orca tie in the bridge.
- Taken out: the `orca:term_…` host and its jump (`Control.swift`, `Actions.swift`), Orca in the
  default `terminal` app group (`Config.swift`), and Orca in this Mac's `keystrokeApps` and
  `apps.terminal` (`config.json`; the file as it was is `config.json.before-orca-removal`).
- Left in, one check: `ClaudeHook.isLeftAlone`. A hook whose environment has
  `ORCA_TERMINAL_HANDLE` and no `CLAUDE_CODE_HOST_SESSION_ID` sends nothing, so a session started
  in an Orca terminal takes no Agent Key and no light. Without the check it would light a key
  like any terminal session, and a press would raise Orca through `focus`.
- The Orca source planned as phase 3 was never built and is off the list.
- Seen on the installed build at 16:53 UTC: a `micro hook` run with `ORCA_TERMINAL_HANDLE` set
  added no session, the same run without it added one (ended right after), a report with host
  `orca:term_abc` was refused, and the loaded config names Orca nowhere. 88 tests pass.
- Seen from the owner's own presses later that day (log, 16:59 to 18:31 UTC): Agent Keys 1 to 4
  each ran `ack`, `jump` and the Claude app came to the front. One press came with Orca in
  front (17:24:45) and also went to the Claude app. No Orca line in the log since the reinstall.
  Still not seen: a Claude Code session started inside an Orca terminal staying dark.

### Where it stands (2026-11-16 22:40 UTC)

- The bridge runs (LaunchAgent, started at login 17:43 UTC). The pad has been off USB since
  2026-11-14 05:11:49 UTC; macOS lists it under Bluetooth as paired, not connected. Nothing on
  the pad works until it is plugged in.
- No error line in the log since the reinstall of 2026-11-13 16:53 UTC.
- Needs-you-first Agent Keys: chosen by the owner and built on 2026-11-17 (next section).

### Needs-you-first Agent Keys (2026-11-17), built

- Before: a seventh session got no key until another session ended, also when it was waiting
  on its person.
- Now (`BridgeState.promote`, `Control.swift`): while a session that needs you has no key and an
  idle session holds one, the key changes hands. The idle session heard from longest ago gives
  its key up first and then waits like any session without a key. Busy (blue) and unread (green,
  red) sessions keep their keys, so a seventh session still waits when none of the six is idle.
- The rule is checked after every report, after a press that marks a key seen, and after a turn
  stopped by hand. A freed key goes first to a waiting session that needs you.
- Switch: `"needsYouFirst": false` in `config.json` (default true). The log says
  `key N goes from idle session … to session …, which needs you`.
- Side effect: a press on a green key marks it seen (idle), so with a session waiting, that key
  can turn amber for the other session at once. The press itself still opens the session it
  was pressed for.
- Seen on the installed build at 16:38:23 UTC, pad unplugged, with seven test sessions sent over
  the socket: two real sessions held keys 1 and 2, test sessions took 3 to 6 (3 and 4 idle), two
  more waited. A test session reporting needs-you took key 3 from the idle one heard from
  longest ago; the log line appeared; the busy waiting sessions stayed without a key. The test
  sessions were ended afterwards. 93 tests pass.
- Not seen yet: the amber light on the pad itself, and a real seventh session.

### Question cards with several questions (2026-11-18 UTC), built

Why: on 2026-11-18 00:44 UTC the owner pressed Approve on a card with several questions and
nothing happened; the dial could not reach "Other".

What changed:

- Approve presses "Next", and "Submit" on the last question. Decline presses "Skip" (the
  owner's choice).
- The dial reaches "Other", then "Next" or "Submit". The press ticks, goes on, or sends.
- With "Other" chosen and its text field empty, the dial press does nothing; with text typed it
  goes on.
- `=Label` picks a button by its whole label, so "Next" never matches "Show next question".
- An insisted click stops once the card shows its next question.

Seen on a real 2-question card (02:15:59 to 02:16:17 UTC): Approve moved it from question 1 to
question 2; the dial ticked two answers, reached "Other" and "Submit", and the press sent it.

Not tried yet: Decline on "Skip" (one question or the whole card: not known), a dial press on
"Other" with typing, a dial press on "Next", "Other" on a one-answer question.

### The key of the session on screen pulses (2026-11-18 UTC), built

The owner picked this. The Claude window's web page has the address
`https://claude.ai/epitaxy/local_<id>`; that id is the one a session reports as its host. Once a
second the bridge reads it (`ScreenButtons.shownSessions`, about 15 elements, never inside the
page) and the matching Agent Key breathes. `lighting.pulseSelected` turns it on (default now
true; set to true in the owner's config, backup `config.json.before-pulse`).

- Log lines: `on screen: claude:local_…`, `key 3 pulses: its session is on screen`.
- `micro ctl state` adds `onScreen` and `pulsing`.
- A slow answer from the Claude app (over 0.3 s) pauses the reading for 10 s.

Seen at 02:28 UTC: the address followed the owner to another session; with it on key 3 the state
said key 3 pulses; 0.0% CPU. Not seen: the pulse on the pad (the owner's eyes), split view, a
session in a terminal (it cannot pulse: no page address).

### Low battery warning (2026-11-18 UTC), built, cannot fire yet

The owner picked this. `batteryWarning` (percent, default 20, 0 is off): one macOS notification
when the battery is at or under it and the pad is not charging; it is ready again after a charge
or once the battery is 5 points above. The reading comes with the 5-second layer check.

The bridge reaches the pad over USB only, and on USB the pad charges. So the warning fires only
if the pad stops charging on USB, or after Bluetooth support is built. Covered by unit tests
(`BatteryWatch`); not seen for real.

### Keys remember their sessions (2026-11-18 UTC), built

The owner's report: "I check on the session and I exit it and the light goes dark, it loses the
session and clicking it now opens a new session."

Cause, from the log: a session was dropped as soon as its process ended (`SessionEnd`, or the
pid gone), and every restart of the bridge dropped all of them. A press on the dark key then
ran `agentKeys.empty`, which opens a new session (five such presses at 02:27:28 to 02:27:31
UTC, right after a reinstall).

What changed (`BridgeState.end`, `settle`, `snapshot`, `restore`):

- A Claude app session that ends keeps its key for `rememberHours` (default 24 at first,
  "always" since the next section). The key shows
  white, or stays green or red if its result is unread. A press opens the session again.
- When the session reports again it is back on the same key. A new Claude Code session in the
  same Claude app session takes the key over.
- A session that waits for a key takes an ended session's key: longest ended first, read before
  unread. So ended sessions never keep a running one off the pad.
- A session with no place to open again (a terminal) frees its key as before.
- The keys are written to `sessions.json` every 5 s when changed and on quit, and read back at
  start. A session whose process is gone by then counts as ended at the time of the last write.
- `micro ctl forget <session>` drops one by hand. The log now says who gets, keeps, takes over
  and loses each key.

Seen on the running bridge (02:44 to 02:45 UTC) with a test session: ended, it stayed on key 2
as idle; after a restart the log said `2 keep their keys (1 running, 1 ended)` and both were on
the same keys. At 02:50:33 UTC a restart kept two real sessions on their keys. Not seen: a real
session ending and a press opening it again (the owner's hands).

Hold to clear (the owner said yes, same day): `agentKeys.hold` is `forget`, which drops the
key's session and frees the key. An Agent Key with a hold action now fires `press` when the key
comes up (`Gestures.handle(waitsForHold:)`), so a hold does not open the session first. Other
controls are unchanged: the dial still presses on the way down. In the owner's config, backup
`config.json.before-hold`. Unit tests cover it; not seen on the pad yet.

### Dark keys do nothing; the six most urgent sessions hold the keys (2026-11-18 UTC), built

The owner asked: a press on a dark Agent Key must not open the new-session page (key 9 does
that); a key keeps its session until another thread takes its place ("incremental
replacement"); and more than six running threads must be handled.

- `agentKeys.empty` has no default action. In the owner's config too (backup
  `config.json.before-empty`). The log says `AG.press key N: no session on this key`.
- `rememberHours` is "always" by default: an ended session keeps its key until it is replaced
  or cleared by a hold.
- `urgentFirst` (was `needsYouFirst`): with all six keys taken, a session without a key takes
  the key of a less urgent holder. Urgency: needs you 4, finished or failed unread 3, working 2,
  idle 1, ended 0. Victim: lowest urgency, then heard from longest ago (ended: ended first).
  Equals never replace each other, so busy sessions do not swap keys back and forth.
- A replaced session that still runs waits (it is still known) and returns when it becomes
  more urgent than a holder or a key frees. A replaced ended session is forgotten.
- Protected: the session on screen, and a session whose key was pressed in the last 5 s
  (`BridgeState.touch`, `rebalance` every second). Without this a second quick press on the
  same key could land on the session that just took the key.

Seen at 02:59:34 UTC with test sessions (see configuration.md, facts). Not seen: more than six real
sessions.

When a finished session counts as read: the owner's choice (2026-11-18) is "when an action is
taken", not when it is merely on screen. So green or red clears on: a press on its Agent Key; a
new prompt or answer (it turns blue); and, added the same day, a pad key that presses a button
in the Claude app while that session is on screen (for example Decline dismissing its next-step
box). Looking at it, or clicking in the app with the mouse without sending anything, does not
clear it. The last rule is covered by a unit test; not seen on the pad.

### The MicroBridge window (2026-11-19 UTC), built

Open MicroBridge.app and it shows a window. Five screens: Pad (the six keys live, the session
on each, sessions waiting for a key), Keys (click a control on a drawing of the pad, pick its
command, read what it does in plain words), Lights, Behavior and Setup (six checks and the
next step).

- It is the same `micro` binary: no command and launchd as the parent means "opened from
  Finder", and `micro app` does the same from a shell. The bundle and its code signature stay
  as they were, so the Input Monitoring and Accessibility grants carried over the reinstall
  (seen 04:10 UTC: `"inputMonitoring":"granted","accessibility":true` in `micro ctl state`).
- SwiftUI in the same binary costs the hook nothing that can be measured: `micro hook` still
  takes about 10 ms from a shell.
- The window is a client. It sends `{"op":"state"}` once a second and `forget` on request, and
  never opens the pad. `state` now also carries `firmware`, `inputMonitoring` and
  `accessibility`.
- It edits `config.json` through `ConfigFile`, which keeps the file's key order
  (`JSONValue.parseKeepingOrder`). A change is parsed with `Config.parse` before it is written,
  so the window cannot write a file the bridge would refuse. The first save copies the file to
  `config.json.before-app`. Checked on a copy of the owner's file: same meaning after a rewrite.
- `@State` does not compile with the Command Line Tools on the macOS 27.2 SDK (its macro plugin
  ships with Xcode only). The window keeps its state in `ObservableObject`s.
- `micro snapshot <folder>` draws every screen to a PNG without a window; `--live` draws the
  running bridge. That is how the layout was checked. Seen live at 04:07 UTC: six real sessions
  on their keys, the owner's key mapping on the drawing, "The pad is not connected" as the
  next step.
- Seen: the installed app opened from Launch Services as a foreground app with one window.
  Not seen: a click in the real window (the changes behind every control are unit tested), the
  window with the pad plugged in.

### Pinned sessions (2026-11-19 UTC), built

A pinned session keeps its key until it is unpinned or forgotten.

- What a pin holds against: a more urgent session that waits (`urgentFirst`), the hours an
  ended session is remembered (`rememberHours`, also at 0), and a waiting session taking an
  ended session's key with `urgentFirst` off.
- `pin` can name the key. A session already on that key trades places with the pinned one, and
  keeps its own pin if it had one. When the pinned one had no key to trade, the other waits and
  loses its pin. With no key named, a session stays where it is; one that waits takes a free
  key, or the key of the holder that would give up first among those not pinned. With every key
  pinned and none named, the answer is `every key is pinned`.
- The pin is on the Claude app session. A new Claude Code session in the same Claude app
  session takes over the key and the pin, whether it starts after the old one ended or before.
- A pinned session in a terminal frees its key when it ends: there is nothing for a press to
  open.
- Pins are in `sessions.json` and are written at once, not at the next 5 s save.
- Ways in: the window's Pad screen (a pin menu on every session, a pin mark on the drawing),
  `micro ctl pin <session> [slot]` and `micro ctl unpin <session>`, and the `pin` action, which
  the window's Keys screen can put on a double tap of an Agent Key. From the pad the key goes
  dark twice for pinned and once for unpinned.
- Seen on the running bridge at 14:10 UTC with a made-up session: it took the free key 4, was
  pinned (`"pinned":true` in `micro ctl state` and in `sessions.json`), unpinned, pinned by
  slot, and forgotten; a pin for an unknown session and for slot 9 were refused. The real
  sessions kept their keys.
- Not seen: the `pin` action and its blink on the pad (unplugged), a pin holding against a
  real seventh session, a pin across a real session's end. Those rules are unit tested.
- The window's made-up sessions (`micro app --demo`) are now kept by `BridgeState` itself, so
  Pin, Unpin and Forget act there as they do for real.

### Actions and commands in the window (2026-11-19 UTC), built

The window now edits every list of actions, and every command.

- Keys screen: a key is a command (as before), nothing, or "its own actions": one ordered list
  each for press, release, double tap and hold. The Agent Keys, the dial and the stick have the
  same lists for their triggers. An action is a kind from a menu (14 kinds, the file's own) and,
  for most kinds, a field. Rows can be added, moved and removed.
- Commands screen (new, sixth screen): all 48 commands, the ones on the pad first, then the
  owner's own, then the rest. For each: what it does in the Claude app, in a terminal and
  everywhere else, per trigger. New commands are made there; one the owner made can be deleted
  once no control runs it; a built-in one goes back to its default.
- A field is saved with Return or its Save button, never while it is typed, and only when
  `Action.parse` takes it: a key must not run half a shell command. What is typed and not yet
  saved lives in `WindowState.drafts`.
- How it is written. A key with its own actions is always an object of triggers, because a key
  written as one `cmd:` on its own means every trigger of that command. A command is written
  whole (a command the file mentions replaces the built-in one), under the name the file
  already uses for it. An app left with no actions is taken out, so it does what `default` does.
- A command cannot run a command (the bridge refuses it), so that kind is not offered inside
  one.
- Checked: 18 new tests. 14 are on files in a temp folder (every form the file can have, exact
  text written). 4 drive the editor: two call the steps behind its menus and buttons, two type
  into the real text fields in a window that is never shown (typing makes a draft, Return on
  half a key saves nothing, Return on a whole key saves; a new command is named in its field).
- Seen: every screen drawn at 1020x700 and at the smallest size, 900x620, with nothing cut off;
  the installed build drawn with the owner's config at 18:50 UTC, the file's checksum the same
  before and after.
- Not seen: a click on a menu or a button in the real window. A hidden window has no
  accessibility tree, so the tests cannot press those; the steps behind them are the ones
  tested.

### The window redrawn after the real pad (2026-11-19 UTC), fixed

The owner said the window was bland and its drawing of the pad was wrong. It was: the dial sat
top right, two keys wide, the stick bottom right, and the body was a dark slab.

- The layout now follows the pad as it is built. Row 1: dial, Agent Keys 1 and 2, stick. Row 2:
  Agent Keys 3 to 6. Row 3: the four keys. Row 4: the round layer button, the wide key, the last
  key. `PadDrawing.rows` holds that order and a test pins it.
- The look follows it too: a white plate with four screws on a clear base lit white from below,
  a metal dial, a black stick in a square well, frosted Agent Keys that glow through their caps,
  white keys with a dished top. The lower keys show a picture for their command (a check for
  Approve, a cross for Decline) where the drawing used to print a word.
- The layer button is drawn and does nothing in the window: the bridge reads the layer and binds
  nothing to that button.
- The pad stands on a dark stage in a light window too, because its lights need the dark. Around
  it: darker window colors, a mark of the pad beside the app's name, a battery bar, chips for
  the pad's facts, small capital section titles, the command's picture on each row of the
  Commands list. The window's own chrome stays grey; color is kept for the lights.
- The drawing is sized by the window: a key is 62 points wide from 999 points of window, 50
  below. The window opens at 1080x720 (was 1020x700). The app's icon and the project page's
  drawing of the pad follow the same layout.
- Where the layout came from: the drawing of the pad on OpenAI's public Codex Micro help page
  and the product photos on its shop page, read on 2026-11-19. Positions and proportions are
  facts about the hardware; the artwork here is drawn from scratch, with no logo and none of the
  pad's printed text.
- Checked: 1 new test for the layout, 4 new checks on the key pictures. Every screen drawn at
  1080x720 and 900x620 with nothing cut off, in the dark and the light.
- Seen: the installed build drawn with the owner's config at 19:35 UTC (Decline, Approve, New
  chat, Fork, Mic, Send on the lower keys), the file's checksum the same before and after.
- Not seen: the Codex app's own settings screens. The owner asked for them as the model, and the
  request to look at that app was declined twice, so the window's layout of settings is still
  this project's own. Also not seen: the real window on screen after this change.

### The window matched to the Codex app's settings page (2026-11-19 UTC), fixed

The owner opened the Codex app's Settings > Codex Micro page and allowed a look at it. It
corrects the entry above: that page does not draw the hardware. It draws a dark, flat diagram of
the pad in a wide card, on one centered column of cards.

- The page, as seen: a title, then a card of rows (Connection, Battery, Input Monitoring,
  Brightness, Auto-dim, a lock toggle), a "Layout" section with the pad centered in a wide card,
  then an "Options" card. Each row is a title, a grey line under it and one control at the
  right.
- The window now has that shape. Every screen but Commands is one column 680 points wide,
  centered. The Pad screen is a status card (Connection, Battery), "Layout" with the pad in a
  wide card, then the Agent Keys list. The Keys screen is "Layout" with the pad, then the chosen
  control's settings under it, where they used to sit beside it.
- The pad is drawn as a dark diagram in both a dark and a light window: a near-black body, grey
  Agent Key caps with a dot of the status color and a glow, dark command keys with a white line
  picture, a flat two-tone dial, a black stick in a well, a dim layer button with three dots. On
  the Keys screen the Agent Keys are plain caps with no light, because that screen shows the
  layout and not what the pad is doing.
- The greys are the page's own values (window 181818, sidebar 1D1D1D, card 232323, chosen row
  2F2F2F). The sidebar keeps the mark of the pad and the battery bar. The window opens at
  1080x800 (was 1080x720). The app's icon and the project page's drawing still show the white
  hardware: they picture the product, and the window pictures its layout.
- Facts taken from the page: its structure, its proportions and its colors. Nothing of its
  artwork, text or code is copied; the drawing here is SwiftUI shapes and SF Symbols.
- Checked: the same 182 tests. Every screen drawn at 1080x800 and 900x620, in the dark and the
  light, with nothing cut off and the sidebar the same width on each.
- Seen: the installed build drawn with the owner's config at 21:18 UTC (Decline, Approve, New
  chat, Fork, Mic, Send on the lower keys; connected over USB, 100%, firmware v0.6.1), the
  file's checksum the same before and after.
- Not seen: what the Codex app shows when a key in its layout is clicked. Two presses sent in
  the background opened nothing, and the screen was not taken over to try by hand. The key
  editor here is still this project's own. Also not seen: the real MicroBridge window on screen
  after this change; the checks are offscreen drawings.

### The keycap dialog (2026-11-20 UTC), built

The entry above ended with the Codex app's key editor not seen. The owner opened it, and it
was seen at 02:29 UTC: a dialog over the settings page with a search box, a grid of keycaps six
wide (a line picture over a short name), the picked one lighter with a white edge, a row for
the assigned action with a menu, then Cancel and Save.

- A key on the Keys screen now opens a dialog of that shape: "Keycap for Key 8", a search box,
  every command that does something as a keycap (the ones on the pad first), a row that says
  whether the key runs the keycap's command, its own actions or nothing, then Cancel and Save.
- Nothing is written until Save. The drop-down it replaces wrote the file as soon as an item was
  picked, so a slip of the pointer rebound a key. Cancel, the cross, Escape and a click beside
  the dialog close it with the file as it was. Save with nothing changed writes nothing.
- The dialog opens with the key's own keycap scrolled into view. Search matches a command's name
  in the file and its plain name ("decl" finds REJ, Decline).
- 27 more commands have a picture (an SF Symbol each), so most keycaps in the grid show one and
  so do their keys on the drawing and their rows on the Commands screen. A command with no
  picture shows a bare ring in the grid.
- The row under the pad shows the key's keycap and a Change button that opens the same dialog.
  The dial, the stick and the Agent Keys are set up under the pad as before.
- How it was seen: a background click and a key press sent to the Codex app opened nothing; a
  press and release at one point on the Approve key did. The dialog was closed with Cancel,
  nothing was saved, and the layout read the same afterwards. Its structure, proportions and
  colors are the facts taken; the title, the words and the pictures here are this project's own.
- Checked: 6 new tests (188 in all): a pick waits for Save, Cancel leaves the file alone, an
  unchanged Save writes nothing, own actions and nothing, search, every picture is a real
  symbol, and typing in the search box of a hidden window.
- Seen in the real window at 03:00 UTC, with clicks sent to it in the background. In a demo
  window (made-up sessions, nothing written): a click on Key 9 opened the dialog with REJ lit
  and Save dim; a click on PLAN lit it and Save; Save closed the dialog and Key 9 showed the
  Permission mode picture; "decl" in the search box left REJ alone; Cancel after a pick, Escape
  and a click beside the dialog each closed it with the key as it was. In the window on the
  owner's config: Key 9 opened with NEW lit, Cancel closed it, and the file's checksum was the
  same before and after.
- Fixed from that look: a key on the drawing told a screen reader its picture's stock name
  ("Close" for the cross of Decline, "Selected" for the check of Approve). Every control on the
  drawing now says what it is ("Key 9: Decline", "Agent Key 3", "Dial"), the keycaps in the
  dialog say their plain name, and the search box has a name. A search that finds nothing says
  so. 1 more test (189 in all).
- Not seen: the Actions menu of the dialog opened by a click. A menu cannot be opened in a
  window that is not in front; its three choices are tested as steps.

### The rest of the Codex page, and lights off on lock (2026-11-21 UTC), built

The Codex app's Micro page has two cards the window did not copy yet: a top card with the pad's
state and its lights, and an Options card under the layout.

- New in the bridge: `lighting.offWhenLocked` (off by default, as in ChatGPT). The daemon
  listens for macOS's `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notices. With
  the setting on, a lock turns every light off and an unlock shows the keys' sessions again and
  starts the auto-dim wait over. A key press or a new status while the Mac is locked keeps the
  lights off. With the setting off, the lock changes nothing.
- The Pad screen's top card now has the Codex card's rows in its order: Connection, Battery,
  Input Monitoring, Brightness, Auto-dim, Lights off while the Mac is locked. The light rows are
  one view, also on the Lights screen (with the pulse). Auto-dim gained 3 minutes, ChatGPT's
  default. The slider has no tick marks.
- An Options card at the end of the Pad screen: Agent Keys (the most urgent sessions, or the
  first six; the `urgentFirst` setting) and Dial (turning moves through the answers in a
  prompt, or through sessions; a press and a hold stay as they are; anything else shows as
  "Your own"). Codex's microphone and single-tap options were left out: the bridge's mic key
  already works as push to talk, a toggle would leave space held down in a terminal, and a
  single tap already opens an Agent Key's session.
- Checked: 3 new tests (192 in all): the setting is read, off by default and dark only when
  locked with it on; the dial's two choices keep its press and hold; the window writes the
  lock setting. The installed bridge prints "off while the Mac is locked off" for the owner's
  file, whose checksum is the same before and after.
- Not seen: the pad going dark on a real lock. That needs the setting turned on and the Mac
  locked, which is the owner's to do.
- Taken out the same day: it could not work. See the next entry.

### A locked Mac refuses writes to the pad (2026-11-21 UTC), fixed

The owner turned `lighting.offWhenLocked` on and locked the Mac twice (03:48:51 and 03:49:14
UTC). The lights stayed on, and the pad seemed to play a turn-on sequence.

- Cause: from the moment the Mac locks, macOS refuses every write to the pad with IOReturn
  0xE00002E2 (not permitted). The pad has a single HID interface whose main usage is a keyboard
  (0001:0006), and the bridge's channel (ff00:0001) is part of it. A locked Mac keeps keyboards
  to itself. Opening the pad still works.
- Too late to act: the first refused write came before macOS's `com.apple.screenIsLocked`
  notice, in the same second. This Mac locks at once (`sysadminctl -screenLock status`:
  immediate), and Amphetamine keeps the display awake, so no screen-saver or display-sleep
  notice comes first either. Writes work again about 1 s before the unlock notice.
- A second fault: the daemon took a refused write for a lost pad. It closed the pad and
  reopened it every second for as long as the Mac stayed locked (8 times in the first lock).
- Fixed: a refused write is its own error (`PadError.writesRefused`). The daemon keeps the pad
  open, logs it once, leaves the lights as they are and tries again every 2 s. The first write
  that goes through logs "macOS takes writes to the pad again". The layer check waits too.
- Taken out: the lock switch in the window, the lock watch in the daemon, and the setting's
  line in `micro config show`. A file that still has `lighting.offWhenLocked` loads, and the
  setting does nothing. The owner's file has it on.
- Not known: what the turn-on sequence was. During the lock no write reached the pad, and
  opening the pad sends nothing to it. The Codex app was not running. It is either the pad's
  own doing or the writes at unlock.
- Checked: 192 tests pass (150 for the bridge, 42 for the window): a refused write maps to its
  own error and any other failure stays a failed write; a file with the old setting loads.
  `micro config check` passes on the owner's file, whose checksum is the same before and after
  the install. Not seen on the pad: it dropped off USB at 03:58:32 UTC, before the install.

- Seen on the pad after the install: it came back on USB at 04:09:58 UTC. During the owner's
  lock at 04:10:07 the bridge logged the refusal once and kept the pad, and the keys showed
  their sessions again at 04:10:12.

### Lights off, then lock, from the pad (2026-11-21 UTC), built

The only lock that can leave the pad dark is one the bridge starts, writing before it locks.
The owner asked for it.

- New action `lock` and built-in command `LOCK`, not bound by default. The daemon turns every
  light off, waits for the pad to take the write, then types ⌃⌘Q (Accessibility, whichever app
  is in front). A write already on its way finishes first.
- The lights come back on macOS's `com.apple.screenIsUnlocked` notice, or on the first write
  macOS lets through after refusing one. The lock notice starts such a write, so the second
  way works even if the unlock notice is missed. If no lock notice comes within 5 s, the lights
  come back and the log says the Mac did not lock.
- The window offers the LOCK keycap (a lock picture) and "Turn the lights off and lock the Mac"
  in a key's own actions. There are 49 built-in commands.
- Checked: 193 tests pass (151 for the bridge, 42 for the window): `lock` reads and writes,
  `cmd:LOCK` runs it in any app and makes the file ask for Accessibility, and the window
  reads and writes it.
- Not seen: a real lock from the pad. Binding it is the owner's choice, and locking the Mac is
  the owner's to do.

- The owner put LOCK on holding the dial (`dial.hold`, which opened the config file before).

### Lights off before a ⌃⌘Q lock (2026-11-21 UTC), built

The owner asked for it to happen without a special control. They lock with ⌃⌘Q, the one lock
an app can see before it starts.

- `lighting.offWhenLocked` is back, off by default, now meaning: catch ⌃⌘Q, turn the lights
  off, then let the lock through. The owner's file already had it on.
- `LockShortcut`: an active event tap at the HID level, on its own thread so a busy daemon
  never holds up the keyboard. It holds back exactly Control+Command+Q (with Caps Lock or Fn
  too, not with Shift or Option), and the Q's repeats and release. The daemon turns the lights
  off and says so; then the tap types ⌃⌘Q again, marked so it passes. It types it after 2.5 s
  at most, whatever the daemon is doing.
- Safety: if no lock notice comes within 5 s, the lights come back, the bridge stops catching
  ⌃⌘Q until it restarts and a notification says to press ⌃⌘Q again. The pad's LOCK types the
  same marked shortcut. The tap reads each key's code, modifiers and mark, and logs nothing.
- The window's Pad and Lights screens have the switch again: "Lights off when you lock with
  ⌃⌘Q", saying that other locks leave the lights on.
- Checked: 195 tests pass (152 for the bridge, 43 for the window): only ⌃⌘Q counts, the Q key
  code matches, the setting is read and off by default, the window writes it.
- Seen on the owner's Mac: ⌃⌘Q at 04:46:20 UTC logged "⌃⌘Q: lights off, locking the Mac",
  the pad went dark and the Mac locked. On unlock at 04:46:25 the keys showed their sessions
  again.

### The stick scrolls (2026-11-21 UTC), built

The owner asked for the stick to scroll the chat by how far it is pushed, instead of toggling
the sidebar.

- New actions `scroll:up` and `scroll:down`. On the stick they scroll for as long as it is
  pushed: past a dead zone of 0.15, 60 points a second, rising with the square of the push to
  2400 at full push. A 60-a-second timer scrolls between the stick's reports, keeping the
  fractions of a point, and stops when the stick comes back to the center, or after 3 s without
  a report. Each push logs how far it scrolled and how many reports the stick sent. On a key,
  one step of 120 points. The window offers "Scroll up or down" among the actions.
- Where a scroll lands, tried on the Claude app with window pictures before and after: a wheel
  sent to the app alone did nothing, with or without the window's number (fields 91 and 92),
  in lines or pixels, with gesture phases, and posted already routed. A wheel with a place of
  its own posted at the HID or session level scrolled the chat, and moved the pointer there
  (once in testing; put back at once). So the stick scrolls whatever is under the pointer, as
  a mouse wheel does (D-013).
- The owner's file: stick up and down are now `scroll:up` and `scroll:down`, replacing Plan
  mode and the sidebar. The built-in stick is unchanged.
- Checked: 198 tests pass (155 for the bridge, 43 for the window): the speed curve, the dead
  zone, sideways pushes, kept fractions, the spelling and the window's round trip.

### Slower stick, and Decline takes the second choice (2026-11-21 UTC), built

- First pushes on the owner's pad (12:57 UTC): each scrolled about 2,000 points in under a
  second, near full speed, and the owner found it too fast. The stick sent only 3 or 4 reports
  a push: it reports when it moves, not while held. Full speed is now 800 points a second (a
  third), and scrolling stops after 20 s without a report instead of 3, so a push held still
  keeps going.
- The owner answered the next-step box's second choice with Decline (key 7) and it closed the
  box. Decline now presses the box's second button, and Dismiss only when there is one
  (D-014). Changed in the built-in REJ and in the owner's file.

- Seen on the owner's pad: at 13:20:02 UTC a push scrolled 1,160 points down in 1.8 s (21
  reports), and the owner said the speed feels right. At 13:21:22 UTC Decline (key 7) pressed
  "Second choice" on a real box with two choices.

### Stick left and right pick the pane (2026-11-21 UTC), built

The owner asked to switch what the stick scrolls between views: the chat, or a website beside
it.

- New actions `pane:left` and `pane:right` move the pointer to the middle of the next pane that
  way, with a real mouse move. A pane is a part of the front window that scrolls on its own and
  is at least 150 points each way: a native scroll area, a web page that does not fill the
  window, or a web element with an `overflow-y` class. The walk does not go inside a pane, and
  looks inside what fills the window (an Electron window is one web page in one scroll area).
- Next pane: the nearest by its middle that way, then the one level with the pointer. From no
  pane, the nearest that way, else the largest. At the edge, nothing.
- `micro panes [app]` lists the panes and where each way would go, without moving anything.
  On the owner's Claude window: with a website on the right, two panes (the chat and the page);
  with the session details on the right, one (the chat, 18…1012), in 100 to 350 ms.
- The owner's stick left and right are now `pane:left` and `pane:right`, replacing the
  previous and next session (D-015).
- Checked: 200 tests pass (157 for the bridge, 43 for the window): the next pane each way,
  at the edges, from outside every pane, stacked panes, and the spelling.
- Seen on the owner's pad (13:32 UTC): right moved the pointer to a website beside the chat
  (x 558…1432) and the stick scrolled it; left moved it back to the chat (x 18…558), which
  scrolled too. A second right "moved" to a pane in the same place, likely a browser tab hidden
  under the one on show: a pane less than 20 points away sideways no longer counts as the next.

### Open-source groundwork (2026-11-21 UTC), built

The owner chose to make MicroBridge an open-source project, with a download and a blog later.
The plan is a checklist in `open-source-plan.md`; the owner's five decisions are D-016 to D-020.

- Added `CONTRIBUTING.md` (scope, build and test, the five rules the code keeps, fixing a
  renamed Claude app button), issue forms for bugs and ideas (a security problem goes to a
  private report), and `CHANGELOG.md` with the first public release.
- The README and the site already said plainly that the project is unofficial and not
  affiliated; the README's test count is now 200.
- Nothing is published. With the owner's go-ahead, the work went onto the release pull
  request's branch (still private), and CI ran for the first time. It failed: GitHub's Mac has
  an older Swift than the 6.4.2 here, which refused two places in the window's model that sent
  `self` from a background task to the main actor. The background work now hands back plain
  values. The second run passed: all 200 tests, no code warnings.

### The install from nothing (2026-11-21 15:00 UTC), two fixes

The part of the new-account install test that needs no second account:

- A fresh clone of the release branch built in 26 s, passed all 200 tests and bundled a signed
  app with its icon. Nothing the build needs is missing from git.
- `scripts/claude-hooks` stopped with a Python traceback when `~/.claude/settings.json` did not
  exist, which is likely on a new account. A missing file now counts as empty settings: install
  creates it (private to the user, 600), and status and remove leave it missing.
- Two changes in the same second picked the same backup name, and the second stopped with
  `FileExistsError`. The later backup now gets a number.
- `scripts/test-hooks` runs the script against throwaway home folders (no settings file,
  another tool's hooks, broken JSON, the app not installed) and never touches the real
  settings. `scripts/test`, and so CI, runs it first. Against the old script 13 of its checks
  fail.
- The account test itself, with what each step should print, is in `install-test.md`. It is
  still to run.

### A download sets itself up (2026-11-21 18:20 UTC), built

The owner chose how a downloaded app, which has no `scripts` folder, adds its hook and starts
at login: a command in the app and a Claude Code plugin for the hook (D-024), and a Login Items
button for the start (D-025).

- `micro hooks status|install|remove [--dry-run]`, in Swift, replaces the Python script, so a
  Mac without the Command Line Tools can run it. `scripts/claude-hooks` now just calls it. On
  a copy of the owner's settings file, its remove and install write the same bytes as the old
  script did. It also points the hook at a moved app instead of adding a second one, removes
  the hook wherever the app is, and refuses to run from the temporary copy macOS makes of an
  app opened straight from Downloads.
- The Setup screen's banner copies that one line ("Copy the command"); the window still never
  writes Claude Code's settings itself.
- The plugin lives in `plugin/`, with this repository as its marketplace
  (`.claude-plugin/marketplace.json`); `claude plugin validate` passes both with no warnings.
  Its hook hands each event to the installed app, and stays quiet when the hook is in the
  settings file too, so no event arrives twice. `micro hooks install` refuses while the plugin
  is on.
- "Start at login" registers a login item that the app carries
  (`Contents/Library/LaunchAgents`); the bridge then logs through `micro daemon --log`. A Mac
  with `scripts/install`'s LaunchAgent, like the owner's, shows "Started at login by
  scripts/install" and no button. The login item has not been tried on a real login yet: that
  is in the install test.
- 12 new tests (212: 169 for the bridge, 43 for the window), and the shell test they replace
  is gone.

### Approve did nothing in Orca: Orca was not in `keystrokeApps` (2026-11-24 21:35 UTC), fixed in the file and in the tools

The owner set a test chat to "Ask for approval", got the card "Allow Write?" and pressed the
✓ key four times and the ✗ key once. Nothing happened.

- The log had the cause on each press: `ACT07.press in com.stablyai.orca:
  click:native-chat-appearance/=Allow`, then `not typing: com.stablyai.orca is in front and is
  not in keystrokeApps`. The owner's file lists the apps the bridge types in. Orca came off
  that list on 2026-11-13, and the setup of Orca's layer on 2026-11-24 did not put it back.
- Why it was not seen before: the night's test pressed Allow with `micro click`, which does not
  go through this check. No press from the pad had been tried on a card.
- On this Mac, with the owner's yes: `com.stablyai.orca` was added to `keystrokeApps` in their
  `config.json` (the file from before is `config.json.before-orca-typing`). The bridge loaded
  it at 21:41:31 UTC.
- In the tools (D-067): `Config.warnings` names a layer's app that the list leaves out, the
  bridge logs it when the config loads, `micro config check` prints it, the window shows it as
  the next step with a button that adds the app, and the Orca switch adds Orca to a list that
  is in use. 4 tests; `scripts/test` passes 347.

Not seen yet: Approve pressing Allow from the pad with the corrected file.

### Pull request 7 was merged (2026-11-24 16:18 UTC)

The owner pressed Create PR at 14:21 UTC and said to merge at 16:18.

- Before the push, on f48f4df: `scripts/test` passed 343 tests, `scripts/test-plugin` 11, and
  `scripts/check-public` found nothing.
- Pull request 7 was opened against main with the text prepared the night before. The app
  could not turn on its CI monitor for this account, so CI was read by hand: `test` passed in
  2m24s and the secret scan passed.
- Merged with a merge commit, 27fb338. Its files are those of f48f4df, which is also what the
  installed build runs but for docs.

### The owner's second go on the pad (2026-11-24 16:14 to 16:16 UTC), the other gestures work

From the bridge's log, on layer 2:

- A hold on a taken key freed it (`AG.hold key 1 on layer 2: the key lets its chat go`), on
  key 1 and on key 2.
- A hold on an empty key took the chat on screen, three times, with two different chats.
- A tap showed a chat from another tab: `key 1: chat …: its tab is on screen now`, and the same
  for key 2 a second later. This is the jump the first test had not run.
- A tap on an empty key said `no chat on this key. Hold it to take the chat on screen in Orca`.
- Once a key took nothing: `key 1 takes no chat: Orca's window shows no tabs`. That line and
  one `key 1 is free` have no `AG.hold` before them, so they came over the socket, from the
  panel or the window. The log does not say which.
- Four taps between 16:16:19 and 16:16:39 are in the log twice, under a second apart. The
  second of each pair found the tab on screen already. Two quick taps or the doubled key press
  of issue 2: the log cannot tell.

Still not tried on the pad: the dim key, and Approve and Decline on a permission card.

### The new window against the running bridge (2026-11-24 14:23 UTC), it shows Orca's keys

Opened in the background after the install and looked at with a screenshot of the window only.

- The Pad screen said the pad is on layer 3, where its keys are off, and named the connection
  with "layer 3".
- "Claude's keys · layer 1" listed the six sessions.
- "Orca's keys · layer 2" listed key 1 with its chat's title, Idle, Show and Free, and keys 2
  to 6 with "Put a chat here".

Not pressed in the running window: Show, Free, the menu of an empty key, and the switch on
Behavior.

### The panel loaded into the owner's Orca (2026-11-24 13:50 UTC), it shows the keys

The owner said to load it, read what Orca would grant, and said to approve it. Every command
carried `--environment local`.

- `orca plugin dev load <the folder>` put the folder in Orca as `local.microbridge 0.1.0`,
  pending. Orca named the grant: its own code in a separate Node.js process with the user
  account's access to the machine, and one panel. The same command with `--approve` and the
  fingerprint Orca printed made it run.
- `orca plugin dev request local.microbridge pad.state` answered through the worker: the bridge
  running, the pad connected, layer 2 as Orca's, key 1 with its chat and the chat's title, and
  the 2 chats open in this Mac's Orca. `pad.commands` answered with 10 commands. So a worker
  inside Orca can open the bridge's Unix socket, which had only been read from Orca's own words.
- `orca plugin shot local.microbridge --panel pad` showed the panel in the right sidebar and
  saved its picture: "Pad connected", "Layer 2 of the pad. The pad is on layer 3 now.", key 1
  with its chat, Idle, Show 1 and Free 1, keys 2 to 6 empty with "Put a chat here", the closed
  section "What the controls do in Orca", Refresh. `orca plugin logs` had no line from it.

Not tried in the running Orca: a press on Show or Free, a chat put on a key from a menu, and
Save in "What the controls do in Orca", which writes the owner's config file. A picture with
that section opened was refused, because Orca presses a control for a picture only while its
window is hidden.

### The owner's finger test on Orca's layer (2026-11-24 13:42 UTC), works

The owner did the test on the pad and said it worked. The bridge's log of those two minutes:

- 13:40:47, 13:40:57, 13:41:45: taps on the touch sensor. The pad went to layer 2, to layer 3
  and back to layer 2, and the bridge said whose each layer is. On layer 3 it kept the pad,
  because ChatGPT was not open.
- 13:42:04: `AG.hold key 1 on layer 2: the key takes the chat on screen in Orca`, then
  `key 1 takes chat 564f669d (done)`.
- 13:42:16: `AG.press key 1 on layer 2 in com.stablyai.orca: ack, jump, pane:chat`, then
  `its tab is on screen already`.

Not in the log, so not tried on the pad yet: a tap that shows a chat from another tab, the
hold that frees a key (key 1 still holds the chat), the dim key, Approve and Decline on a
permission card. The lights are the owner's word; the log does not show them.

### The finished build was installed (2026-11-24 13:36 UTC), the bridge runs

The owner plugged the pad in and said to install. `scripts/install` built the release from
85feb80 and restarted the bridge.

- The bridge started, loaded the owner's config (34 bindings) and found the pad over USB
  through the helper, on layer 1.
- The 6 Claude sessions from before the restart kept their keys.
- The state answer names layer 2 as Orca's, with no chat on its keys.
- The new socket commands answer: `orca.chats` lists the 2 chats open in this Mac's Orca, and
  `commands` for `orca` lists 10 commands.

Not tried yet: the pad's own keys on Orca's layer, the window opened again against this
bridge, the panel inside Orca.

### Orca in the MicroBridge window and a panel in Orca (2026-11-24 04:55 UTC), built, not in a running Orca yet

Step 4 of the Orca build (D-062 to D-066, on D-044 and D-048). On the branch `orca-layer`, not
pushed. The installed app is still the build of step 3, so none of this runs on the owner's
Mac yet. The owner was asleep and had said to leave every running process alone.

- **Window, Pad.** The drawing shows the six keys of the layer the pad is on. A new section,
  "Orca's keys", lists each key with its chat's title, "Show", "Free", and on an empty key a
  menu: the chat on screen in Orca, or one of Orca's open Claude chats. A closed chat's key is
  dim in the list and in the drawing. Orca's section comes first while the pad is on its layer.
- **Window, Behavior.** One switch, "Orca's chats have a layer of their own", writes
  `layerApps.2 = ["orca"]` and moves a ChatGPT entry from `layers.2` to `layers.3`, and back
  (D-064). The ChatGPT rows name the layer the file gives it. The old switch always wrote
  `layers.2`, which the config check refuses once layer 2 is Orca's.
- **Socket.** `orca.chats` lists Orca's open Claude chats. A key remembers its chat's title in
  memory only, so the key of a closed chat can still be named; the keys file and the log hold
  no title (D-063). `commands` lists what each command does in one app group, and
  `command.set` writes one change to the config file (D-065). `micro ctl orca chats` asks the
  first by hand.
- **One rule for two screens.** `ConfigFile.setCommand` changes a command in the file. The
  window calls it and so does the bridge, for the panel. The names of commands and controls
  moved into MicroKit.
- **This machine only.** The bridge takes `ORCA_ENVIRONMENT` and `ORCA_PAIRING_CODE` out of
  the environment of Orca's command line, so it always asks the Orca on this Mac (D-062).
- **Panel.** `orca-plugin/` is an Orca plugin: a panel in the right sidebar and a worker that
  sends each request to the daemon's socket (D-066). It shows the six keys, takes, frees and
  shows chats, and changes what a command does on a press in Orca. It stores nothing.

What was tried:

- `scripts/test`: 343 tests pass (326 before): PadWire 7, MicroUI 52, MicroKit 284. New ones
  cover the titles (in the state answer, not in the file, not in the log), `orca.chats`, the
  environment of Orca's command line, the layer switches, the demo keys, `setCommand` on a
  file with and without its own command, and the two command operations on the daemon bench.
- `scripts/test-plugin`: Orca's `plugin validate` says the manifest is valid; `plugin test`
  passes 11 tests (the worker against a stand-in daemon on a Unix socket, the panel against a
  stand-in worker); `plugin check` renders the panel with no refused call or dropped prop.
- The two new window screens were drawn to pictures with `micro snapshot` and looked at.
- `scripts/check-public`: no private data found.

What was not tried, and why:

- **The panel inside a running Orca.** A hidden sandbox Orca with its own data folder was
  started for it, with a stand-in daemon. Its main thread hung at start: the Mac had 71 MB of
  memory free and 10.3 of 11 GB of swap in use. It was stopped after two minutes, with its
  helpers. Nothing was loaded into the owner's Orca: `orca plugin list` there shows no
  MicroBridge plugin. So that a worker may open a Unix socket inside Orca is read from Orca's
  own words for a `trusted-worker` ("its own code in a separate Node.js process … with your
  user account's access") and from the test run, not seen in the app.
- **The window against the running bridge.** The installed bridge is the step 3 build and
  does not know `orca.chats`. Installing restarts the bridge, which the owner said not to do
  tonight.
- **The pad.** It has been unplugged since 03:57 UTC.
- The plugin was not type-checked with `tsc`, which is not installed here. Orca strips the
  types when it loads the files.

Left as it is for the owner (04:57 UTC): the six keys of Orca's layer hold nothing. Key 1 was
freed of the test chat with `ctl orca free 0`. One test chat stays open in the test
workspace, so a hold on the pad has a chat to take; the other was closed in the dim test. The decisions of the build are told in
chapters 15 to 17 of `docs/story.md`. Nothing was pushed, installed or restarted.

### Step 3 tried on a real Orca through the socket (2026-11-24 04:05 UTC), works

The owner said Orca was theirs to leave and mine to use for the night, on two conditions:
this Mac only, and no running process touched. Everything below used two test chats of my own
in a test workspace, started with `orca agent launch --environment local`, and the bridge's
socket. The pad was unplugged, so no light was seen.

- `ctl orca take 0 <id>` put a test chat on key 1; the log said so with the chat's state.
- `ctl orca show 0` brought the chat's tab on screen, also from another workspace: the
  workspace was activated, then the tab pressed.
- `ctl orca free 0`, then `ctl orca take 0` with no ID, as a hold does: the key took the chat
  on screen.
- The hook's reports arrived under Orca's session ID, with the process, the folder and the
  record.
- Closing a chat's tab: within about 2 seconds the log said the chat was closed and its key
  keeps it and goes dim, and the state answer had `"closed": true`.
- Refusals read as written: a closed chat, a key that holds a chat already, a key that holds
  none, a chat that is on another key already.
- Seen and left as it is: when Claude's turn ends while a command it started still runs in the
  background, the bridge says done and Orca says working until that command ends. And a chat
  on no key is forgotten when its process exits, so a key that takes it later starts from
  Orca's state with no process to watch.
- Orca's view was put back to the chat the owner had on screen (three presses on "Go back"),
  and checked.

Not tried: anything from the pad's own keys.

### The pad test of step 3 was set up (2026-11-24 00:45 UTC), nothing built

The owner said yes to the setup, on one condition: everything stays on this Mac. Their Orca
also shows work that runs on another Mac.

- **Which machine.** Orca's `host list` names this machine `local`, and the other Mac is a
  saved environment. The command line goes to this machine unless a command names an
  environment or the shell has `ORCA_ENVIRONMENT` or `ORCA_PAIRING_CODE`. The bridge's own
  calls name none, and the daemon's environment has neither variable. Every command of this
  setup carried `--environment local`.
- **Profile.** MicroBridge was stopped for 92 seconds. One click on the row "Three layers" in
  Input set it active, and Input was quit after. The pad answered `profile_index` 2,
  `layer_index` 1.
- **Config.** The owner's file got `"layers": {"3": "com.openai.codex"}`,
  `"layerApps": {"2": ["orca"]}` and an `orca` entry in its own `APPR` and `REJ`. The file from
  before is `config.json.before-orca-layer`. `micro config check` said ok.
- **Install.** `scripts/install` put the build of `b210ddd` in place. The bridge started,
  found the pad, kept the six Claude keys, and answered Orca's layer as 2 with six empty keys.
- **Test chat.** One chat was started on this machine in the test workspace of step 2, with
  no `--focus`, so Orca's window stayed as it was. Orca lists it on host `local`.
- **A hold with other work on screen.** `micro orca` read the window as the owner had it: one
  tab, and no chat of this machine with its title. It said a hold would take no chat. So a
  hold cannot take a chat that runs on the other Mac.
- Not done yet: the owner's taps and holds on the pad.

### Main's new README came into the branch (2026-11-24 00:40 UTC), nothing built

- Pull request 6 from the website's session was merged on main (`e462d71`). The README is a
  front page now, and the long ChatGPT sections are in `docs/chatgpt.md` (D-061). Main was
  merged into `orca-layer` with no conflict. The sentence on Orca's layer is in the new README,
  and its test count says 326.
- `scripts/check-public` failed on `Tests/MicroKitTests/OrcaTests.swift` once that file was
  committed. It held a made-up home folder path with a name longer than one letter, and three
  made-up session IDs in the shape of a real one. The check reads only the files git tracks, so
  it had passed while the file was new. The test now uses `/Users/x/…` and IDs that are not in
  that shape. Run the check after `git add`, not before.
- `scripts/test`: 326 tests pass. `scripts/check-public`: no private data found.

### Orca's chats on the keys of Orca's layer (2026-11-24 00:30 UTC), built, not on the pad yet

Step 3 of the Orca build (D-056 to D-060, on D-043 to D-055). On the branch `orca-layer`, not
pushed. The installed app is still the one from before step 1.

- **Hook.** A session whose environment has `ORCA_AGENT_SESSION_ID`, no `ORCA_TERMINAL_HANDLE`
  and no Claude app session ID is an Orca chat. It reports under Orca's ID with
  `"host":"orca:<id>"`. `/clear` sends no end. A Claude Code started by another Claude Code
  sends nothing (D-058).
- **Keys.** `OrcaKeys` holds the six keys of Orca's layer. The daemon sends a chat's reports
  there and never to Claude's keys. With no layer for Orca the report is dropped and said once
  in the log. The keys are saved in `orca-keys.json`.
- **Hold.** On an empty key it takes the chat whose tab shows in Orca; on a taken key it frees
  it. A hold that cannot tell which chat flashes the key red twice (D-056).
- **Tap.** `agentKeys.press` with the chat: `ack`, then the jump: `orca agent show`,
  `open -b com.stablyai.orca`, `orca worktree activate --worktree id:…`, then a press on the
  tab with the chat's title (D-059).
- **Closed chat.** When a chat's process ends the bridge asks Orca whether its tab is still
  there. No tab: the key goes dim, a tap does nothing, a hold frees it (D-054, D-057).
- **Config.** The app group `orca` is built in, and Approve and Decline press "Allow" and
  "Deny" on the chat's card in Orca (D-060). The MicroBridge window lists "In Orca" for each
  command.
- **By hand.** `micro ctl orca take|free|show <slot>`, the socket's `orca.take`, `orca.free`
  and `orca.show`, an `orca` part in `micro ctl state`, and `micro orca`, which prints what the
  bridge sees of Orca and changes nothing.

What was tried:

- `scripts/test`: 326 tests pass (297 before): PadWire 7, MicroUI 45, MicroKit 274. The daemon
  tests run the real daemon on the fake pad with a made-up Orca.
- In the sandbox copy of Orca (D-049, headless, two scratch projects):
  `orca worktree activate --worktree id:<id> --json` answered `ok: true` with
  `"activated": true` and the window showed that project. For the project already on screen it
  answered the same and nothing changed. For an unknown ID it answered `ok: false`,
  `selector_not_found`. A sleeping project woke. The sandbox was quit afterwards.
- In the owner's Orca, reading only, through `micro orca` from the dev bundle: the command line
  was found at `/usr/local/bin/orca`, its list of chats was read, and the tab strip was read in
  0.08 s with the showing tab marked. Nothing was pressed and no chat was taken.
- Found there: a tab that cannot be closed (a bot's Home) has a label of its own, without the
  words "Close tab". So a tab's title is now read from the text the tab shows, and the label is
  only the fallback. That Home chat was not in `orca agent list`, so a key cannot take it.
- Found there: at that look no process carried the listed chat's ID while Orca listed the chat
  as done. A chat's process can be gone while its tab stays, which is why D-057 asks Orca
  before a key goes dim.

Not tried: anything on the pad. A real hold, tap and jump in the owner's Orca. How the dim
light looks. Whether `SessionEnd` reaches the new hook when a tab is closed. Whether a chat's
Claude process is found as the hook's ancestor. A split view. Bluetooth.

### The pad took the three-layer profile (2026-11-23 23:36 UTC), nothing built

The owner left the import to Claude. MicroBridge was stopped for it for about 7 minutes,
because Work Louder Input cannot read the pad while the bridge holds it, and started again
after.

- Input's profile list has "Import". The file came in as the profile "Three layers", with
  layers 1, 2 and 3. Layers 2 and 3 show the names "Orca" and "ChatGPT", and each layer shows
  the pad's own layout ("To edit this layer please use ChatGPT app").
- A click on a profile's row sets it active at once. Input counts down "Updating device in 3"
  and writes the pad. It asks nothing first.
- With "Three layers" active the pad answered `device.status` with `profile_index` 2 and
  `layer_index` 2. With "One tap" active again it answered `profile_index` 1 and `layer_index`
  2. So the profile index follows Input's list from 0, and the pad keeps its layer number
  when the profile changes.
- Choosing a layer in Input's window does not move the pad: with layer 3 chosen there, the pad
  still answered layer 2. Only the touch sensor moves it. That a tap takes the pad to layer 3
  is not seen yet: it needs the owner's finger.
- `scripts/micro status` read those answers. It opens the pad itself, so it runs only while
  no daemon does.
- Input's file window could not be worked in the background. Picking the file took the screen
  for one click.
- Left as it was found: "One tap" is the active profile, the pad is on layer 2, the bridge is
  running and connected. "Three layers" stays saved in Input. With MicroBridge stopped, one
  click on its row makes it active.

### Orca's plugin resume does not bring a chat back (2026-11-23 23:15 UTC), nothing built

The owner asked for this try before deciding what a dim key does (D-045). A throwaway worker
plugin was loaded in the owner's Orca as a development folder, with the access to read
workspaces, hear agent status and start or resume agents. It answered three requests and was
unloaded after; Orca's plugin list was the same 25 before and after.

- `agent.resume` with the closed chat's Orca session ID answered `{ terminalId, started: true }`.
  It opened a terminal that ran the Claude command with `--resume` and that ID, which is not
  an ID Claude knows. The terminal stopped on Claude's question whether to trust the folder. It
  was left unanswered and the terminal was closed.
- `agent.resume` with the Claude session ID of the same chat failed: "Orca could not prepare
  this session to resume" (the plugin's log: `agent_session_ownership_unknown`).
- So no way is known to reopen a closed chat as a chat: not this method, and not the command
  line, the new-tab menu, the search or the menu bar (the entry below). D-045 cannot be built
  as written.
- `workspace.readContext` gave the workspace on screen with an empty list of terminals while a
  chat was its only tab: a plugin does not see chat tabs there. `workspace.open` is documented
  to show a workspace as a click in the sidebar does (not tried). `agent.listSessions` needs
  the access `history:read`, which the probe did not ask for.
- Seen once: setting a chat's permission mode gave the chat a new Claude session ID, while its
  Orca session ID stayed. A key that holds Orca's ID (D-053) is not thrown by that.

### Orca's chat, tried in the owner's working Orca (2026-11-23 23:10 UTC), nothing built

Step 2 of the Orca build. The owner allowed their working Orca for it (D-049). Three test chats
were started and closed there and one test file was written and deleted; the owner's own chat
and its settings were left as they were.

- An Orca chat runs Claude Code, so the bridge's hook already fires in it. Each test chat
  reported to the bridge and waited for one of Claude's keys, and the one that asked for
  approval took a key from a real session. `ClaudeHook.isLeftAlone` misses a chat: its process
  has no `ORCA_TERMINAL_HANDLE`. It does have `ORCA_AGENT_SESSION_ID`, equal to the session ID
  `orca agent list` shows, with `ORCA_STRUCTURED_SESSION=1` and `CLAUDE_CODE_ENTRYPOINT=orca`
  (D-053).
- `orca agent launch --agent claude --surface chat --worktree path:<dir>` opens a chat tab
  without changing the view and prints its session ID. `--prompt` sends a first message.
- A tab is one button. Its name is the state, the title, "Close tab" and the title again. Inside
  it are a group described by the state ("Working", "Needs attention", "Unread agent
  completion", "Done"; a new chat has none), the title as text, and a button "Close tab
  <title>". The tab on screen has the class `bg-tab-active`. The tabs sit in the box
  `group/tab-strip`.
- The jump works: `micro click "*/<title>" com.stablyai.orca` pressed another chat's tab and
  then the first one again, while a browser stayed in front. Orca did not come forward. Not
  tried: a chat in another workspace, which needs `orca worktree activate` first.
- The permission mode is a menu on each chat's message box, a pop-up button named
  "Permissions <mode>": "Ask for approval", "Accept edits", "Approve for me", "Full access". It
  is the chat's own: after one chat was set to "Ask for approval" the next new chat still
  started in "Full access". The owner's chats are in "Full access" and never ask.
- In "Ask for approval" a request to write a file put a card where the message box was: a
  group named "Allow Write?" with "Cancel", "Allow", "Allow for this session", "Deny" and
  "Details". Orca listed the chat as `blocked`, its tab said "Needs attention", and the hook
  reported needs-you. `micro click "native-chat-appearance/=Deny" com.stablyai.orca` denied it
  and no file appeared. On a second request `…/=Allow` allowed it and the file was written.
  While it works the chat has a button "Stop the agent"; the message box has "Send", off
  while the box is empty.
- A closed chat does not come back as a chat by any way found. Closing the tab ends the chat's
  Claude process, `orca agent list` drops it and `orca agent show` gives no place for it.
  `orca agent read` still reads the conversation, and `orca search` finds it with a reference
  to the chat and no resume command (a terminal session gets `claude --resume`). The command
  line has nothing that reopens it, and neither the new-tab menu, the search (it offered tasks
  and "Create worktree"), nor the menu bar offered it. The plugin method `agent.resume` was not
  tried: it is documented as opening a terminal. D-045 is still unproven and waits on the
  owner.
- A three-layer pad profile is written (Claude, Orca, ChatGPT, each with layer 1's keys). It
  was imported later the same day (the entry "The pad took the three-layer profile").

### A second layer of the bridge's own, and layers kept apart (2026-11-23 22:40 UTC), built, not yet on the pad

Step 1 of the Orca build (D-050 to D-052, on D-047). No Orca was needed for it.

- A new setting, `layerApps`, says which layers are the bridge's own and which apps each one is
  for. Out of the box it is `{"1": ["claude", "terminal"]}` and nothing changes. With
  `{"2": ["com.stablyai.orca"]}` layer 2 is the bridge's too: it acts on that layer's keys,
  holds the pad there as on layer 1, and warns of nothing.
- That layer has its own six Agent Keys. They hold no agents yet, so they are dark, and a press
  of one does not act on the Claude session that has the same key on layer 1. Back on layer 1
  the sessions show again.
- The layers are kept apart. On layer 1 a key, the dial or the stick does nothing in Orca. On
  layer 2 it does nothing in the Claude app or a terminal. In a browser it acts on both layers.
  An Agent Key always acts. The log names every press that was stopped.
- With ChatGPT on layer 3 and `layerKeys`, one tap moves on each time: Claude's keys, Orca's
  keys, ChatGPT has the pad, and back.
- The layer is read four times a second while a second layer is set, so a tap counts within a
  quarter second.
- Checked on the fake pad only, in 21 new tests (297: 245 for the bridge, 45 for the window,
  7 for the helper's wire). Each new rule was also broken on purpose in a copy of the code, 16 ways, and
  a test went red each time.
- Two of the new tests failed now and then at first. They reached the daemon over its real
  socket, and with tests running side by side the socket was not read within the client's 2 s.
  The tests now hand the daemon the command directly (`take`), and wait until it has finished
  talking to the pad before the next tap (`isBusy`).
- Not done here: the pad has no layer with these keys yet (the owner imports that profile),
  nothing was tried on the real pad or in Orca, and the window has no control for the setting.

### Orca, read and talked through before any code (2026-11-23 18:50 UTC), nothing built

The owner opened the talk on Orca's layer (the issue "Orca on a layer of its own"). The
answers are D-043 to D-049. What was read on the way, on Orca 1.4.271 (`com.stablyai.orca`):

- `orca agent list --json` lists each agent with a kind (`chat` or `terminal`), a state
  (`working`, `blocked`, `waiting`, `done`), a title, a pane key and an Orca session ID.
  `orca agent show <id>` says where it is open.
- A chat is not a terminal. It has the kind `chat` and a pane key that starts with
  `structured-agent-session-`, and `orca terminal list` does not show it. `orca terminal switch`
  and the plugin methods `terminal.focus` and `terminal.send` take terminals only.
  `orca worktree activate` brings a workspace forward. No command says which tab is on screen.
- The plugin typings (`orca plugin types <dir>` writes them) give a plugin the workspace on
  screen (`workspace.readContext`, and the event `workspace.changed`), the agents with their
  state (`agents.list`, and the event `agent.status.changed`), a private store, and
  `agent.resume`, which reopens a session in a new terminal. Orca's hooks never see a prompt a
  person types.
- The chat's controls have names: the message box is "Ask anything, @ to mention files, / for
  commands", and there are "Send", "Start dictation" and "Permissions". A tab is a button named
  by its title, next to "Close tab" and that title.
- Orca's first-run screen has "Yolo mode" switched on: agents act without asking. With it on
  there is no permission prompt for Approve to press.
- The bridge has left sessions in Orca's terminals alone since 2026-11-13
  (`ORCA_TERMINAL_HANDLE`). It knows nothing of chats.
- The sandbox copy (D-049) is the installed app started with `ORCA_E2E_USER_DATA_DIR`, a `HOME`
  inside that folder and `ORCA_E2E_HEADLESS=1`. Orca's own command reaches it with
  `ORCA_USER_DATA_PATH` set to the same folder, and `--remote-debugging-port` lets a script read
  its window. The owner's Claude settings, `~/.orca`, the `orca` command, the LaunchAgents and
  the Orca app were identical before and after. It listens on one port on every interface, as
  the working Orca does.
- Started a second time with a window, so the owner could sign in to Claude there, the sandbox
  stopped inside a macOS keychain dialog: its throwaway home has no keychain. It was quit. The
  owner's keychain list and Claude sign-in were unchanged. The sandbox is for headless use.
- Not seen yet: the chat's permission prompt, the state `blocked` on a chat, and a closed chat
  reopened as a chat. Not checked: whether a Claude session in an Orca chat carries
  `ORCA_TERMINAL_HANDLE`. If it does not, it shows on Claude's layer today.
- No code and no tests changed (276 tests).

### Tests that failed now and then (2026-11-23 01:05 UTC), fixed

CI failed on PR 4 in `thePluginAndTheSettingsHookAreNeverBothOn`: permission denied writing a
settings file into a folder the test had just made. The same test and a plugin test had failed
now and then on this Mac too (D-041).

- Cause: `SocketServer` set the umask to 0o177 around `bind`. The umask is the whole process's,
  and the tests run in parallel, so a folder made by another test in that moment came out 0600,
  without the execute bit, and nothing could go into it.
- Fixed: the socket is bound, then set to 0600 with `chmod`. Its folder is 0700 already.
- Five full runs in a row pass. Before, about one run in three failed.

### The stick leaves a web page, and a tap puts the pointer on the chat (2026-11-23 00:45 UTC), works on the pad

The owner found the stick stuck in a web page in the Claude app's side pane: pushed left, the
pointer stayed there, so the stick went on scrolling the page. They also asked for a tap on an
Agent Key to put the pointer on the chat, so the stick scrolls the chat without a push right
first (D-039, D-040).

- Cause, from the log at 2026-11-22 23:57 UTC and `micro panes`: the side pane reported its web
  page three times. Two hidden browser tabs kept the widths the pane had before it was made
  narrower (x 2428…3929 and 2624…3929), under the tab on show (2835…3929). `pane:left` picked
  the nearest pane by its middle, a wider copy, and that middle lies inside the web page. Every
  push landed on the same spot.
- Fixed: copies of one pane (same top and bottom, same left or right edge) count as one, the
  part they all cover. A move whose landing spot is inside the pane the pointer is in is no
  move. The second rule covers a later layout whose copy shared no edge with the tab on show.
- Built: `pane:chat` puts the pointer in the middle of the chat, the pane right above the box
  named Prompt. After `jump` it waits up to 3 s for the session to show. The pointer stays when
  it is on the chat already, when it was moved since the press, and for a session in a terminal.
  The Agent Keys' tap is now `["ack", "jump", "pane:chat"]`. The owner's config got it by hand,
  with their yes.
- The message box was not found at first: it sits inside an element that scrolls but is smaller
  than a pane, and the walk stopped at every element that scrolls. Small ones are walked into.
- `micro panes` marks the chat and says how many hidden copies it left out; `--names` prints each
  pane's role and classes.
- On the owner's pad: at 00:42:31 UTC one push left took the pointer from the web page to the
  chat, and the stick scrolled the chat. At 00:44:46 and 00:44:52 UTC taps on keys 4 and 6 put
  the pointer on the chat (in 23 and 65 ms), and the stick scrolled it.
- 276 tests pass (2 new). Not seen yet: the 3 s wait running out.

### One tap passes the pad (2026-11-22 23:45 UTC), works on the pad

The owner tried the two taps and wanted one, and asked whether the touch sensor itself can be
changed. It cannot. What a tap lands on can (D-034).

- The sensor has no setting. Work Louder Input 1.1.0 has no entry for it in the key map, and
  its device kit (0.2.13) has 21 methods, none about touch, sensor or layer. A tap sends no
  event: six layer changes were set against the pad's event stream. The rule that a tap goes
  to the next layer is in the firmware.
- Input's window offers no Codex keys for a second layer, and it locks a layer that has them.
  That is a rule of the window, not of the file: its profile import checks the device type
  and the language only.
- So the owner's profile was exported, layer 1's keys were copied to layer 2 in a copy named
  "One tap", and the copy was imported and selected, all in Input's window. MicroBridge was
  stopped from 19:54:48 to 20:03:44 UTC, because Input cannot write to a pad the helper holds.
  The first profile is untouched. The pad's old key map file (1125 bytes) was saved first.
- 20:01 UTC, `micro listen` next to `micro status`: the pad sent key messages for three Agent
  Keys and the dial's press while it was on layer 2.
- Built: `layerKeys`. With it there are no visits. Every reading of the layer says who has
  the pad: on a layer in `layers` its app while that is open, and the bridge on layer 1 and
  while that app is closed. The bridge then acts on that layer's keys too, and holds the pad
  there. While an app in `layers` is open the layer is read four times a second. The window's
  Behavior tab has a switch, and the two-tap row changes its words when it is on.
- On the owner's pad, 23:39:51: a tap to layer 2. The bridge turned its key lights off and
  shared the pad. ChatGPT opened the pad at 23:39:59, 8 s later, wrote its lights and got an
  answer, and wrote its key lights eight more times in the next 9 s. 23:40:08, the tap back:
  the bridge lit its keys and held the pad in the same second, and ChatGPT's next write, at
  23:40:10, was refused. A second round: tap at 23:41:20, ChatGPT in at 23:41:29 (9 s), tap
  back at 23:41:35. After each tap back the bridge acted on the next presses. The owner: it
  works, and it takes a while.
- The wait is ChatGPT's own. Its log shows it trying a held pad every 10 s. Right after it
  loses the pad it tries after 1 s, 2 s and 5 s first.
- While ChatGPT had the pad it heard the bridge's readings and logged "No resolver found" for
  each: 70 lines in 15 s. None of its own requests timed out in that time.
- 274 tests pass (19 new). 29 deliberate breaks, 11 of them new, each turn a test red.
- Not tried: the dial's turn and the stick on layer 2, the bridge acting on layer 2 with
  ChatGPT closed, the new switch on screen, Bluetooth, a third layer. Not seen from here:
  the notifications.
- Still open, and older than this: one press often reaches the bridge twice. The log of this
  trial has the same Agent Key press twice within one second, at least four times.

### Send takes the Claude app's suggestion (2026-11-22 19:20 UTC), works on the pad

The owner asked for Send, with nothing typed, to take the grey suggestion in the Claude app's
message box and send it. By hand that is Tab, then Return. The owner chose the Claude app
only (D-033).

- Claude Code makes the suggestion. It shows fewer after 20 unused in a row ("Showing fewer
  prompt suggestions"), and the owner's count stood at 21. `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`
  set to `true` in the `env` of Claude Code's user settings keeps them on; the owner set it. Claude
  app sessions started after that carry it, earlier ones do not. Not part of this repository.
- The Claude app keeps a suggestion's text where accessibility cannot read it: no element and
  no attribute around the box holds it. Read 2026-11-22 between 16:02 and 18:11 UTC, with the
  box, its parents three levels up, the overlay on top of it and its announcement area. While
  a suggestion shows, the box has no `AXPlaceholderValue`.
- An empty box with no hint is not always a suggestion: seen four times without one, between
  16:10 and 16:13 UTC. So the step checks what Tab did.
- Built: `complete:<box>`. Grey text a box exposes is typed in. Otherwise, in an empty box
  with no hint, it presses Tab and reads the box again. Text there: the next action, Return,
  sends it. Focus gone from the box: Shift+Tab puts it back and the press stops. Blank space
  typed: Backspace takes it out and the press stops. The log gives lengths only.
- The Claude app's `CODEX` is now `["complete:Prompt", "key:return"]`; other apps keep Return.
  A config with its own `CODEX` keeps it: the owner's got the Claude line by hand.
- Rejected: sending the box's hint. A new session's empty box says "Describe a task or ask a
  question", and that would have gone out as a prompt.
- `micro tree <box>^N` starts N levels above the box; `--attributes` prints every attribute.
- On the owner's pad at 19:18 UTC: "took the suggestion with Tab (9 characters)", then Return
  sent it. Before the Tab step, seven presses at 16:17 UTC found nothing to take.
- 255 tests pass (3 new). Not tried on a real box: the Shift+Tab and blank-space paths.

### Two taps, tried on the pad (2026-11-22 19:19 UTC), works

The owner did the taps. The bridge's log and ChatGPT's own log agree on what happened.

- 19:19:09, a tap to layer 2: the bridge turned its key lights off and shared the pad.
  ChatGPT had the pad open 2 s later.
- 19:19:23, the tap back. From 19:19:30 to 19:19:34 ChatGPT moved between conversations ten
  times and wrote its key lights after each move. The bridge acted on nothing. ChatGPT's log
  does not print key messages, so the presses are read from what it did.
- 19:19:36, a second visit: the bridge took the pad back. 19:19:38, the tap back: the pad was
  held within the same second, and ChatGPT's next write was refused for exclusive access.
- 19:19:44: the Enter key acted in Claude, once.
- A first try at 19:17:53 saw the layer change three times in three seconds: 2, 1, 2. Every
  visit counts, so the pad went to ChatGPT and came back, and it stayed on layer 2 for 54 s.
  By then the quick readings had stopped. The owner tapped back and pressed Enter inside one
  second, before the next reading held the pad, so ChatGPT could hear that press. Its log
  shows no reaction to it. This is the limit of the 10 s: after it, a press within a second
  of the tap back can reach both apps.
- At 19:18:01 ChatGPT opened the pad while the bridge read the layer five times a second.
  ChatGPT's first light write got no answer and timed out after 10 s; its second went
  through. The bridge had the pad then, so nothing that mattered was lost. It shows that two
  programs writing at once can cost one of them a request.
- The pad reports firmware 0.6.3 now. ChatGPT's log last shows 0.6.1 at 01:42 today. At
  16:09:05 Work Louder Input was opened to look at layer 2's keys, and at 16:09:19 the pad
  went away for 21 s. Input most likely updated the pad by itself; nobody asked for an
  update. Everything in this entry ran on 0.6.3.
- Not seen from here: whether the notifications showed on screen.

### Two taps pass the pad (2026-11-22 18:35 UTC), built, not yet tried on the pad

The owner chose the two-tap switch over looking into profiles. `layers` keeps its shape and
changes its meaning: a visit to the layer passes the pad (D-032).

- Both apps use layer 1's keys. A tap to layer 2 and a tap back give ChatGPT the pad, and the
  same two taps take it back. A notification says who has the pad after the first tap, and
  that the pad is back on layer 1 after the second.
- ChatGPT must be open to get the pad, and quitting it gives the pad back. A pad that
  disconnects and comes back stays with whoever had it. A restart of the daemon gives the
  pad back to the bridge.
- The press wait from D-031 is gone. A press only comes from layer 1, so the layer at press
  time says nothing about a visit.
- New: after the bridge takes the pad back it reads the layer five times a second until the
  pad is on layer 1 again, 10 s at most. With the reading of every second alone, ChatGPT
  heard presses for up to a second after the tap back.
- The fake pad now sends key messages from layer 1 only. The earlier one sent them from every
  layer, and that hid the fault in the first design.
- One new test passed for the wrong reason on its first run. It unplugged the fake pad and
  looked at once, but the daemon drops a pad one turn of the main queue later, and its check
  matched the words "pad connected". It now waits for "pad disconnected" and counts two
  connections.
- 18 deliberate breaks on a copy of the tree. 17 turned the test named for them red. One did
  not: with the line that repaints the key lights on the way back taken out, every test
  stayed green, because the return to layer 1 had already asked for a repaint. The quit test
  now leaves the pad on layer 2, and that break is caught too.
- 252 tests pass on the committed tree.
- Not tested: the 10 s limit of the quick readings, and a pad with three layers.
- Not tried on the real pad or with the real ChatGPT yet.

### Layer 2 cannot have the Codex keys (2026-11-22 16:17 UTC), found

The owner asked for the live pass to be driven for them. Its first step was to give layer 2
the Codex keys in Work Louder Input. That step cannot be done.

- In Input 1.1.0, layer 1 shows "To edit this layer please use ChatGPT app" and cannot be
  edited. Its saved layout has the `KV_OAI_*` keys and a joystick of type `VENDOR`.
- The key picker for layer 2 was read to its end: letters, glyphs, modifiers, F1 to F24, the
  number pad, media keys, layer keys, profile keys and the cheat sheet, plus recorded macros,
  multi-actions and smart actions. No Codex key. A search for "codex" finds nothing.
- So on layer 2 the pad can type, but it cannot send the messages ChatGPT and this bridge
  listen for. "Layer 2 is ChatGPT's" (D-028) cannot work on this pad, with any amount of
  testing. With the setting on and the helper in, ChatGPT gets no keys on either layer.
- This is why layer 2 did nothing for the owner. The README told them to do a step that does
  not exist; it now says the switch does not work for ChatGPT.
- The bench could not have found it. Its fake pad sends key messages on every layer, which
  the review had flagged as kinder than the real pad.
- Nothing was changed in Input, and the pad stayed on layer 1.
- Open, the owner's call: let a visit to layer 2 switch who drives the keys of layer 1, or
  look at what a second profile holds.

### The layer switch, reviewed (2026-11-22 15:57 UTC), fixed

A second model read the layer switch and its tests and came back with eleven flags. Two were
faults in the bridge. The rest were about what the tests and the write-ups could not show.

- Fault one: when it let go of the pad, the bridge turned off the ring and the key backlight
  along with the six Agent Keys. It never lights those two, so it could not bring them back
  on layer 1. It now turns off only the Agent Keys, as the lock does (D-030).
- Fault two: a press that came in while the bridge was waiting for an answer from the pad did
  not get its fresh reading of the layer. The reading was skipped, the old one counted as
  fresh, and the press went by the layer from before the tap. Such a press now waits, 10 ms at
  a time, for the pad to be free, and after half a second goes by the last reading (D-031).
- The fake pad can now be slow, and a tap and a press can land in the middle of an answer. The
  test for fault two failed with the old code as it runs outside the tests.
- The tests waited 60 ms after a press. The bridge asks the pad at most once in 50 ms, so a
  hand-over takes about 150 ms, and one test looked too early. The bench now waits until the
  daemon has nothing left to do.
- Two new tests: the press in the middle of an answer, and an app with a layer that
  `stepAsideFor` does not name. Three more checks in the old ones: the Agent Key lights are
  written again on layer 1, the request that turns them off is exactly six keys off, and a
  layer given away logs no "tap the touch sensor" warning.
- The daemon was broken ten ways on purpose, each on a copy of the tree, and each break turned
  the test meant for it red. The earlier run of four broke files in the checkout itself, which
  another session shares; the script no longer can.
- Not shown by any test, and still to try on the pad: ChatGPT acting on a key from layer 2
  once layer 2 has the Codex keys, how the pad looks by eye at a hand-over, the switch on the
  Behavior tab by hand, and the timing of a real tap and press. The fake pad answers in
  order and at once unless told to be slow; the real one has not been timed.
- The commit that added the tests named one thing not tried on the pad. There are four, the
  ones above.
- At 15:57 UTC the pad was back on USB on layer 1, ChatGPT was closed, and Work Louder
  Input's saved layout still had `KC_NONE` on every key of layer 2.
- 2 new tests (242: 7 for the helper's protocol, 191 for the bridge, 44 for the window).

### The layer switch under test (2026-11-22 15:40 UTC), built

The owner asked whether the layer switch had been checked before a push. Only the hand-over
had, by hand. The daemon itself had no tests: it opened the real pad and asked macOS for the
app in front, so nothing could run it.

- The daemon now reaches the pad, its folder, the app in front, the running apps and its log
  through one struct, `DaemonWorld` (D-029). The real ones are the defaults.
- `DaemonLayerTests` runs the real `Daemon` on a pad made of code, which answers like firmware
  v0.6.1 and writes down every request, hold and share. Six tests: the old rule without
  `layers`; layer 1 holds and acts with ChatGPT in front; layer 2 goes dark, shares, then stays
  quiet; back on layer 1 it holds again; the first press after a tap goes by the new layer;
  and all of it without the helper.
- The tests passed in a second, so the daemon was broken four ways on purpose to see them
  fail: no wait for a fresh reading, no lights off, the old front rule for an app with a
  layer, and acting while the pad is another app's. Each break turned the matching test red.
- The first run failed for the wrong reason. The test's config was not valid, the daemon kept
  its defaults, and the tests were testing those. The bench now fails when the daemon turns
  its config down.
- A test does what the window's switch does: set `layers.2`, save, read the file back, take
  it out again.
- A limit, now in the README: the bridge reads the layer once a second, so a press in the
  first second after a tap can reach both apps (tap to layer 1) or neither (tap to layer 2).
- The old window (built Nov 20) said the config had a problem, because that build does not
  know `layers`. The new build shows no such notice.
- Still not tried on the pad: a ChatGPT key press from layer 2, the pad going dark as seen by
  eye, and the switch on the Behavior tab by hand. The pad left USB at 04:30 UTC and the Mac
  was locked.
- 7 new tests (240: 7 for the helper's protocol, 189 for the bridge, 44 for the window).

### A layer for ChatGPT (2026-11-22 12:50 UTC), built

With the helper in, ChatGPT still did not work when brought to the front. It tries to open the
pad every 10 s, and it was in front for 1 to 3 s at a time. The owner chose to let the pad's layer say who drives it,
and to keep it generic so other layers can go to other apps later (D-028).

- `layers` gives a layer to an app, such as `{"2": "com.openai.codex"}`. On that layer the
  bridge shares the pad and goes quiet, whatever app is in front. On layer 1 it keeps the pad
  and holds it, also while that app is in front. The window's Behavior tab has a switch for
  layer 2 and ChatGPT.
- The pad says nothing when its layer changes. While `layers` is set, the bridge asks every
  second, and a press after more than 0.25 s without a reading waits for a fresh one. That way
  the first press after a tap goes where the tap meant.
- When the bridge lets go of a held pad, it turns the pad's lights off first. ChatGPT's own
  lights coming on then show that ChatGPT has the pad.
- First try, 01:35 UTC: nothing changed. The config had no `layers`, and the open window was
  the build from before the switch. `scripts/install` now says when the window is still the
  old build.
- Second try, with the setting on from 01:42:00 UTC. The bridge let go at 01:42:28 and
  01:42:35 and held again at 01:42:33 and 01:42:56. ChatGPT opened the pad at 01:42:31 and
  listened for keys until 01:43:31, when one of its writes failed under a hold. Its open
  connection kept receiving across a hold and a share until it wrote.
- Layer 2 sent nothing to anyone: in Work Louder Input's saved layout, every key on layer 2 is
  `KC_NONE`. The bridge does not write the pad's keymap. Not tried yet: a ChatGPT key press
  from layer 2 once it has the Codex keys.
- Agent Key presses that looked doubled in the log were repeat taps. A recording at 02:11:29
  UTC showed three taps of key 2 within 0.41 s, each with its own down and up, and the bridge
  acted on each once.
- 4 new tests (233: 7 for the helper's protocol, 183 for the bridge, 43 for the window).

### Keeping ChatGPT out with a root helper (2026-11-21 23:55 UTC), built

ChatGPT kept acting on presses meant for the Claude app. The owner chose to build a root
helper after all, lifting the project's rule against one for this program only (D-027).

- First, a test: the bridge's own binary, run once as a root launchd job, opened the pad
  exclusively. That worked, so macOS refuses the exclusive open to the user, not to root.
- `micro-helper` is a separate program of about 300 lines that links only the new `PadWire`
  module. It listens on `/var/run/micro-bridge-helper.sock`, which belongs to the owner's
  account and nobody else can open. It serves one connection at a time, from that account,
  and only from a program signed `local.micro-bridge` with the helper's own certificate. It
  checks each request against the five methods, rebuilds it, and writes it. On a hold frame it
  reopens the pad exclusively; on a share frame, or when the bridge hangs up, it reopens it
  shared.
- The daemon goes through the helper when it is there, and opens the pad directly otherwise. It
  holds the pad while ChatGPT runs behind another app and the pad is on layer 1. If the pad
  sends keyboard or mouse input while held, it shares at once and waits 10 s before holding
  again. While on a direct connection, it tries the helper every 30 s.
- `scripts/helper install` (run with sudo, also carried in the app as
  `Contents/Resources/helper`) copies the helper to `/Library/PrivilegedHelperTools`, checks
  its signature once it is root's, and starts it as a LaunchDaemon.
- Installing showed two macOS facts. A root daemon asking for Input Monitoring does not appear
  in the list: the owner added it with + (22:10 UTC). And the helper already running kept being
  refused (`0xE00002E2`) after the switch went on; a fresh start at 23:47:44 was let in. The
  helper now starts itself again when that happens.
- Tried on the pad, 23:47 to 23:53 UTC. The daemon moved over at 23:47:50. With ChatGPT running
  behind the Claude app, the pad was held from 23:48:30. ChatGPT's Codex Micro log stopped that
  second, apart from a retry every 10 s that macOS turned away ("cannot open device"). Pad
  presses at 23:48:55 and 23:49:08 reached the bridge while it held the pad. ChatGPT came to
  the front at 23:52:36: the pad was shared, and ChatGPT reopened it 2.9 s later, lit it and
  listened for keys again. The Claude app came back at 23:52:51, and the pad was held again.
- Not tried yet: a key press in ChatGPT after a hold, a layer change while held, Bluetooth.
- 11 new tests (229: 7 for the helper's protocol, 179 for the bridge, 43 for the window).

### Sharing the pad with ChatGPT (2026-11-21 19:00 UTC), built

The owner asked for the pad to stop clashing with ChatGPT, and chose "whoever is in front"
(D-026).

- The plan was to take the pad for the bridge alone while any app but ChatGPT is in front.
  macOS refuses: an exclusive open from MicroBridge came back `0xE00002C1` (not privileged).
  A shared open beside it, the daemon and ChatGPT carried on as before. Shutting ChatGPT out
  would need a helper running as root, which this project does not use. So both apps keep
  hearing every press. (Built after all: see "Keeping ChatGPT out with a root helper" above.)
- With the Claude app in front and no key pressed, ChatGPT sent the pad nothing for 30 s. The
  only other replies were the daemon's own `device.status`, every 5 s.
- What the bridge does now: while ChatGPT is in front, it lights nothing and acts on no key.
  When another app comes to the front, it paints its keys at once. While another app is in
  front and ChatGPT writes the lights (it wakes them on a key press after its idle timeout),
  the bridge sees the pad's answer to that write and paints its own back, at most once a
  second.
- The setting is `stepAsideFor`, ChatGPT by default; `[]` turns it off. The window's Settings
  has a switch for it.
- `scripts/bundle` copied the last good binary when the build failed, which hid a compile error
  during this work. It now stops.
- 6 new tests (218: 175 for the bridge, 43 for the window).
- Tried on the pad, 19:07 to 19:09 UTC. ChatGPT came to the front at 19:07:49 and the bridge
  stood aside; the Claude app came back at 19:08:04 and the bridge took over. A key press in the
  Claude app at 19:08:07 made ChatGPT write its lights (`v.oai.thstatus`), and the bridge painted
  its own back.
- The owner saw the same presses act in ChatGPT too, while the Claude app was in front. ChatGPT
  acts on the pad's keys from the background, and nothing on the bridge's side can stop it.
  ChatGPT 26.1117.41037 has no setting for this either: its Codex Micro settings are the key layout,
  brightness, lights off when locked, lights off after inactivity, where the Agent Keys' tasks
  come from, and single-tap Agent Keys. Quitting ChatGPT is the only way to keep presses in
  the Claude app alone.

### Ready to publish, short of the owner's steps (2026-11-21 15:15 UTC), built

The open-source plan's steps that need no owner, done ahead of the ones that do:

- `scripts/check-public` looks for private data: home folder paths, email addresses, session
  ids, keys, and a tracked `PROTOCOL.md`. The repository is clean; a folder with one of each
  planted leak fails on all five. CI runs it before the build (D-022).
- `scripts/public-snapshot` makes the public repository's single commit in a new folder, with
  the noreply author, after the scan. It pushes nothing.
- `scripts/release` builds `dist/MicroBridge-<VERSION>.zip` (`VERSION` is new, 0.1.0, and goes
  into the app's Info.plist). The test zip took 19 s; unzipped, its signature is valid with
  the hardened runtime, and the binary runs and reaches the bridge's socket. With a Developer
  ID it also notarizes and staples; that path waits for the membership (D-021). Steps are in
  `releasing.md`.
- A Site workflow puts `site/` on GitHub Pages once the owner turns Pages on and sets `SITE`
  (D-023).
- The site scrolled sideways on a phone: the long `git clone` line would not shrink. Its grid
  column is now `minmax(0, 1fr)`; at 481 px the page is 481 px wide and the command scrolls in
  its own box. The site and README also say how to get the toolchain, and that the hooks
  script creates a missing settings file.
- Found: a downloaded app cannot finish its own setup. The Setup screen says to run
  `scripts/claude-hooks install`, and a download has no `scripts` folder. How the hook gets
  added is the owner's call.

### Where it stood (2026-11-21 13:28 UTC)

- Pane switching works on the owner's pad, between the chat and a website. 200 tests
  pass (157 for the bridge, 43 for the window).

### Where it stood (2026-11-21 13:23 UTC)

- Stick scrolling and Decline's second choice both work on the owner's pad. 198 tests pass
  (155 for the bridge, 43 for the window).

### Where it stood (2026-11-21 13:21 UTC)

- Stick scrolling works on the owner's pad at a speed they like. Decline's second choice is
  installed, not yet seen on a real box. 198 tests pass (155 for the bridge, 43 for the window).

### Where it stood (2026-11-21 13:15 UTC)

- Slower stick scrolling and the new Decline are installed; neither tried on the pad yet.
  198 tests pass (155 for the bridge, 43 for the window).

### Where it stood (2026-11-21 12:55 UTC)

- Stick scrolling is installed and on for the owner; not yet tried on the pad. 198 tests pass
  (155 for the bridge, 43 for the window).

### Where it stood (2026-11-21 04:50 UTC)

- The ⌃⌘Q catcher is installed, on for the owner, and works on a real lock. 195 tests pass
  (152 for the bridge, 43 for the window). The pad is on USB.

### Where it stood (2026-11-21 04:35 UTC)

- The pad's lock is installed. 193 tests pass (151 for the bridge, 42 for the window). The pad
  is on USB.

### Where it stood (2026-11-21 04:10 UTC)

- The fix for a locked Mac is installed. 192 tests pass (150 for the bridge, 42 for the
  window). The pad is not connected: it left USB at 03:58:32 UTC.

### Where it stood (2026-11-21 03:15 UTC)

- The lock setting and the Codex page's top and Options cards are installed. 192 tests pass
  (149 for the bridge, 43 for the window). The pad is on USB: connected, 100%, charging,
  firmware v0.6.1.

### Where it stood (2026-11-20 03:05 UTC)

- The keycap dialog is installed. 189 tests pass (148 for the bridge, 41 for the window). The
  pad is on USB: connected, 100%, charging, firmware v0.6.1.

### Where it stood (2026-11-19 21:20 UTC)

- The window matched to the Codex app's settings page is installed. 182 tests pass (148 for the
  bridge, 34 for the window). The pad is on USB: connected, 100%, charging, firmware v0.6.1.

### Where it stood (2026-11-19 19:40 UTC)

- The redrawn window is installed. 182 tests pass (148 for the bridge, 34 for the window). The
  pad is on USB: connected, 100%, charging, firmware v0.6.1.

### Where it stood (2026-11-19 18:55 UTC)

- The actions editor is installed. 181 tests pass (148 for the bridge, 33 for the window). The
  pad is back on USB: connected, 100%, charging, firmware v0.6.1.

### Where it stood (2026-11-19 14:15 UTC)

- The window and pins are installed. 163 tests pass (148 for the bridge, 15 for the window).
  The pad has been unplugged since 2026-11-18 03:15 UTC.

### Where it stood (2026-11-19 04:20 UTC)

- The window is installed. 146 tests pass (133 for the bridge, 13 for the window). The pad has
  been unplugged since 2026-11-18 03:15 UTC.

### Where it stood (2026-11-18 03:05 UTC)

- Dark keys do nothing. Keys keep their sessions until replaced; the six most urgent hold the
  keys. Hold clears a key. 118 tests pass.

### Where it stood (2026-11-18 02:50 UTC)

- Keys remember their sessions, across ended processes and bridge restarts. Holding an Agent
  Key clears it. 116 tests pass.

### Where it stood (2026-11-18 02:35 UTC)

- Installed build: question cards with several questions, needs-you-first keys, the pulse for
  the session on screen, the low battery warning. 102 tests pass.
- Pad on USB, layer 1, 100%, charging.
- Waiting on the owner's eyes: the pulse on the pad; Decline on a question card ("Skip").

### Resume here (stopped for the night, 2026-11-12 03:48 UTC)

The owner asked for everything off. The bridge is stopped (`launchctl bootout`); it starts
again by itself at the next login, or with
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.micro-bridge.plist`.
The pad was off USB at the time, so its own lights were not touched.

1. Start the bridge, plug the pad in, check `micro ctl state` shows `layer: 1`.
2. Approve (key 8) and Decline (key 7): both done on real permission prompts, 2026-11-12.
   Next-step boxes: in the Claude app key 8 runs `click:Suggested next actions/first` and key 7
   runs `click:Suggested next actions^2/Dismiss`, each before its old keystroke. The box's
   label and buttons come from a recording of a real box (18:23 UTC). Key 7 closed a real box at
   18:34 UTC (confirmed by the owner). Key 8 pressed a real box's first button at 18:35 UTC (log and the
   owner's answer agree). The permission-mode card (class `epitaxy-approval-card`, buttons
   "Deny" and "Allow once") is wired the same way. Key 8 pressed "Allow once" on a real card at
   19:03:50 UTC and the session switched to Auto. Key 7's click on "Deny" is unseen (Escape
   rejects the card anyway). A fast second press of key 8 used to fall through to Cmd+Return
   and could approve a prompt that appears next: since 19:08 UTC a key stays quiet for
   `clickGuard` seconds (default 1) after its click lands. Seen on a real double press at 19:09:33 UTC:
   the first press clicked the box's button, the second logged "ignored".
   The `epitaxy-approval-card` without "Deny" that key 7 met at 19:04:43 UTC was a
   multiple-choice card (`AskUserQuestion`): it is the same kind of box, its buttons are not
   "Deny"/"Allow once", and Escape closes it.
3. See the wrong-layer notification once: tap the touch sensor, wait 5 s, tap back.
4. If the pad drops off USB again, swap the cable and the port.
5. Owner's side: delete the empty second layer in Work Louder Input.

### Not built yet

1. Jump inside Terminal or Ghostty to the right tab (needs the tty and each app's scripting).
2. Approve or decline a session that is in the background (a `PermissionRequest` hook that
   waits for the pad).
3. One more Agent Key order: most recent first.
4. Mic and fork defaults; zone lighting; Bluetooth (the low battery warning can only fire
   there).
5. In the window: app groups, a command's actions for one app outside a group, the apps typed
   keys go to, the key order of the Agent Keys.

### Claude Code event → status (`Sources/MicroKit/ClaudeHook.swift`)

| Hook event | Status |
|---|---|
| `SessionStart` (not after compaction) | idle, white |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` | working, blue |
| `PermissionRequest`, `Elicitation`, `PreToolUse` of `AskUserQuestion` or `ExitPlanMode` | needs you, amber breathing |
| `Stop` | done, green, until the key is pressed or the next prompt |
| `StopFailure` | failed, red, until the key is pressed or the next prompt |
| `SessionEnd`, or the session's process is gone (checked every 5 s) | a Claude app session keeps its key for `rememberHours`: white, or still green or red if unread. Any other session: key off, freed |

A seventh session waits without a key; when one frees, the waiting session with the newest
activity takes it.

Known gaps:

- Interrupting a turn (Esc) fires no hook, so the key stays blue until the next prompt.
- After you approve a permission prompt the key stays amber until that tool finishes.
- A `PostToolUse` from a tool running in parallel with a pending question can turn the key blue
  while the question is still open. Not seen yet; fix would be to track the pending tool call id.
- ChatGPT running at the same time hears every key too, unless MicroBridge Helper holds the pad
  (D-027). While it is in front the bridge steps
  aside; in any other app the bridge paints over its light writes (`stepAsideFor`).

### Socket API (`~/Library/Application Support/micro-bridge/daemon.sock`, one JSON object per line)

| Request | Reply |
|---|---|
| `{"op":"report","session":"<id>","status":"working","pid":123,"cwd":"/x","host":"claude:local_…"}` | `{"ok":true}`; the daemon picks the key. `pid`, `cwd` and `host` (`claude:local_…`) are optional; status is working, needs-you, idle, done, failed or off |
| `{"op":"end","session":"<id>"}` | `{"ok":true}`; the session's process is over. A Claude app session keeps its key for `rememberHours`; any other frees it |
| `{"op":"forget","session":"<id>"}` | `{"ok":true}`; drops the session and frees its key now |
| `{"op":"pin","session":"<id>","slot":2}` | `{"ok":true}`; the session keeps that key until it is unpinned or forgotten. `slot` is optional: without it the session keeps the key it has. An error when the session is unknown, or when every key is pinned and none is named |
| `{"op":"unpin","session":"<id>"}` | `{"ok":true}` |
| `{"op":"set","slot":0,"status":"working"}` | `{"ok":true}`; paints one key by hand |
| `{"op":"clear"}` | `{"ok":true}`; all keys off, all sessions forgotten |
| `{"op":"state"}` | `{"ok":true,"connected":true,"slots":[…],"sessions":[{"slot":0,"session":…,"status":…,"cwd":…,"pid":…}],"model":…,"transport":…}` |
| `{"op":"subscribe"}` | `{"ok":true}`, then events: `{"event":"key","name":"AG00","action":1,"slot":0}`, `{"event":"joystick","angle":…,"distance":…}`, `{"event":"pad","connected":true}` |

CLI: `~/Applications/MicroBridge.app/Contents/MacOS/micro ctl report|end|forget|pin|unpin|set|clear|state|events`.
