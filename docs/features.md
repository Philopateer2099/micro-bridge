# What the Codex Micro does in ChatGPT, and what we have

Researched 2026-11-11. Sources: OpenAI's help page
(https://learn.chatgpt.com/docs/features/codex-micro) and the settings schema and event handling
inside ChatGPT.app 26.1103 (facts only, no code copied).

Status column: ✅ built, ◐ partly, ◻ not built, ✗ cannot be built. "Bindable" means no default, but `config.json`
can attach any action to it (see `configuration.md`).

## Agent Keys (top six)

| ChatGPT behavior | Ours | Notes |
|---|---|---|
| Light per chat: white idle, blue working, green done and unread, amber needs input, red error, off unassigned | ✅ | per Claude Code session; colors configurable |
| The selected chat's key pulses | ✅ | `lighting.pulseSelected` (on by default) pulses the key of the session the Claude app's window shows; a session in a terminal does not pulse |
| Tap: switch to that chat. Double tap within 350 ms: also bring the app forward | ✅ | tap clears green or red and shows that session (`ack`, `jump`); a pad key that presses a button in the session on screen clears it too; looking at it does not: its Code session in the Claude app, raising the app. Terminal and Ghostty sessions only get their app raised. Sessions started in an Orca terminal take no key (the owner's choice, 2026-11-13) |
| Tap an empty key: start a new chat on that key | ◻ off by default (2026-11-18) | a dark key does nothing; a key bound to `cmd:NEW` starts sessions. `agentKeys.empty` can turn it back on |
| Hold a key: clear it | ✅ | ours, not ChatGPT's: holding an Agent Key for half a second drops its session from the pad (`forget`); a tap still opens it |
| A chat keeps its key while it is not running | ✅ | a Claude app session that ended keeps its key until another session takes it (`rememberHours`: "always") and a press opens it again; keys survive a restart of the bridge; a session in a terminal frees its key when it ends |
| Which chats get keys: most recent (default), pinned, priority (needs input first), custom | ◐ | first come, first key; when all six are taken, a session without a key takes the key of a less urgent one: needs you, unread, working, idle, ended (`urgentFirst`). Pinned: a pinned session keeps its key against all of that, and you choose its key (the window, `micro ctl pin <session> [slot]`, or the `pin` action on a double tap). No "most recent" order |

## Command Keys (default layout)

Each key is set to a named command (`cmd:FAST`), and each command says what to do in the Claude
app and in Claude Code in a terminal. All 39 ChatGPT keycaps exist as commands: `configuration.md`.

| Key | Slot | ChatGPT action | Ours | Claude app | Terminal |
|---|---|---|---|---|---|
| Fast | `ACT06` | toggle Fast mode | ✅ | types `/fast` | types `/fast` |
| Approve | `ACT07` | approve the current request | ◐ front session only | presses the next-step box's first button, "Allow once", or a question card's "Next" or "Submit", else Cmd+Return | Return |
| Decline | `ACT08` | decline the current request | ◐ front session only | presses the next-step box's "Dismiss", "Deny", or a question card's "Skip", else Esc | Esc |
| Fork | `ACT09` | continue the chat in a new chat | ✅ | Cmd+Opt+O | types `/branch` |
| Mic (wide) | `ACT10`+`ACT11` | hold to talk; double tap for hands-free; lights animate while recording | ◐ no light animation, no double tap | Cmd+D on press and again on release | holds Space (after `/voice`) |
| Codex | `ACT12` | send the composer message | ✅ | Return; with nothing typed, takes the grey suggestion (Tab) and sends it | Return |

ChatGPT lets every command key be remapped to an app command, an enabled skill, or fixed text.
Ours: ✅ any key to any of the 49 named commands, or straight to a key combination, typed text,
a shell command or something to open, on press, release, double tap or hold.

## Analog stick (fires past half travel)

| Direction | ChatGPT action | Ours | Claude app | Terminal |
|---|---|---|---|---|
| Up | toggle Plan mode | ◐ | Cmd+Shift+M opens the permission mode menu | Shift+Tab cycles modes |
| Right | forward in app history | ◐ | Cmd+Shift+] next session | none |
| Down | show or hide the sidebar | ✅ | Cmd+B | none |
| Left | back in app history | ◐ | Cmd+Shift+[ previous session | none |

Up and down can scroll instead (not ChatGPT's): `scroll:up` and `scroll:down` scroll what is under
the pointer for as long as the stick is pushed, faster the farther. The Claude app only scrolls for
a wheel aimed at the window under the pointer, so the pointer has to be over the chat.
Left and right can pick what scrolls: `pane:left` and `pane:right` move the pointer to the next
pane that way (the chat, a web page in the side pane, the sidebar).

## Dial

| Input | ChatGPT action | Ours | Our default |
|---|---|---|---|
| Turn | depends on mode: composer navigation (default), reasoning effort, conversation scroll, or custom left and right actions | ✅ | in the Claude app on a multiple-choice card: moves between the answers, "Other" included; on a card that takes several, one more turn reaches "Next" or "Submit". Anywhere else a turn to the right types Down, to the left Up |
| Press | select the focused control; in scroll mode jump to the latest message | ✅ | on a card: goes to the next question or submits, or ticks the highlighted answer on a card that takes several. Anywhere else Return |
| Hold | open the pad's settings | ✅ | opens `config.json` in a text editor |
| While a menu is open | the Agent Key right of the dial lights red; pressing it cancels | ◻ | |

Both `ENC_CW` and `ENC_CC` arrive on our unit (2026-11-11). A turn to the right arrives as
`ccw` (confirmed on the pad, 2026-11-12), so the defaults bind `ccw` to next and `cw` to previous.

## Device

| Feature | Ours |
|---|---|
| Brightness 0 to 100 | ✅ `lighting.brightness` |
| Auto-dim after 30 s to 1 h, default 3 minutes; lights return on use or on a status change | ✅ `lighting.autoDimSeconds`, off by default |
| Turn off lights when the Mac is locked; show the agent states again on unlock | ◐ for ⌃⌘Q and the pad's own lock: `lighting.offWhenLocked` catches ⌃⌘Q, turns the lights off and lets the lock through; the `lock` action (the `LOCK` command) does the same from a pad control. The Touch ID button and the Apple menu leave the lights as they were: macOS refuses every write to the pad while the Mac is locked, and the first refusal comes before the lock notice |
| Battery level shown in the app | ✅ the MicroBridge window shows the battery and whether it charges, in its sidebar and on its Setup screen; `micro ctl state` prints the same; `batteryWarning` shows a notification at 20% while the pad is not charging (it cannot fire on USB, where the pad charges) |
| A settings screen for the pad | ✅ the MicroBridge window: Keys (a command or its own list of actions for each key, the Agent Keys, the dial and the stick, per press, release, double tap and hold), Commands (what each command does in the Claude app, in a terminal and everywhere else; new commands), Lights (colors, brightness, auto-dim, pulse) and Behavior. Whatever it does not show (app groups, a command's actions for one app outside a group, the apps typed keys go to) is edited in `config.json` |
| Setup help | ✅ the window's Setup screen checks the bridge, Input Monitoring, Accessibility, the Claude Code hooks, the config file and the pad, and names the next step |
| Detects the pad on layer 1 | ✅ reads the layer every 5 s, logs changes, notifies when the pad is on another layer (`layerWarning`) |
| Reconnect after unplug | ✅ |
| Bluetooth, three channels, chosen with the touch strip (hold 3 s) | ◻ untested |
| Layers 2 to 6 for other apps, set up in Work Louder Input | not ours to build |

## Two ways to act on a key press

1. **Keystroke to the focused app** (Enter, Esc, Shift+Tab, hold-to-talk). ✅ Built. Works for
   whichever Claude Code window is in front. MicroBridge has the macOS Accessibility permission
   for this, and only types into the apps listed in `keystrokeApps`.
2. **Targeted at one session.** Jump to it: ✅ built (`jump`). Approve it while it is in the
   background: ◻ needs a `PermissionRequest` hook that waits for the pad's answer.
