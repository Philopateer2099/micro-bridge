# Configuring the pad

Everything the pad does comes from one file. Save it and the daemon picks it up within a second.

The MicroBridge window (open the app in `~/Applications`) changes the same file: what each key,
the Agent Keys, the dial and the stick do, every command, the lights and the settings on this
page. It keeps the file's order, rewrites its layout, and before its first change copies the
file to `config.json.before-app`.

- A key with its own actions is written as an object of triggers (`{"press": …, "hold": …}`),
  never as one command on its own, which would mean every trigger of that command.
- A command the window changes is written whole, with what it does in every app.
- An action typed in the window is saved on Return or with its Save button, and only when the
  bridge would take it.
- Still file only: the app groups (`apps`), a command's actions for one app that is in no
  group, and `keystrokeApps`.

- File: `~/Library/Application Support/micro-bridge/config.json` (hold the dial to open it)
- Check it: `~/Applications/MicroBridge.app/Contents/MacOS/micro config check`
- See what is active: `... micro config show`
- Start over: delete the file, then `... micro config init`
- A broken file is ignored (the last good settings stay) and the problems are written to
  `~/Library/Logs/micro-bridge.log`.

Whatever the file leaves out keeps its default. A control, command or app group the file
mentions does exactly what the file says and nothing else.

## The controls

```
 [AG00] [AG01]                    agentKeys   (top six, one per session)
 [AG02] [AG03] [AG04] [AG05]
 [ACT06] [ACT07] [ACT08] [ACT09]  keys
 [    WIDE     ] [ACT12]          keys        (WIDE is ACT10 + ACT11 under one cap)
 dial                             dial: cw, ccw, and the press
 stick                            stick: up, right, down, left
```

| Section | Entries | Triggers |
|---|---|---|
| `agentKeys` | one binding for all six keys; the action knows which key it was | `press`, `release`, `doubleTap`, `hold`, and `empty` (a press on a key with no session; no action by default, so a dark key does nothing. `"empty": "open:claude://code/new"` brings back the new-session page) |
| `keys` | `ACT06`, `ACT07`, `ACT08`, `ACT09`, `WIDE`, `ACT12` (or `ACT10` and `ACT11` separately) | `press`, `release`, `doubleTap`, `hold` |
| `dial` | the dial | `cw`, `ccw`, `press`, `release`, `doubleTap`, `hold` |
| `stick` | the analog stick | `up`, `right`, `down`, `left` |

A binding is one action, a list of actions, or an object of triggers:

```json
"ACT07": "cmd:APPR",
"ACT09": ["sh:git stash", "text:stashed, carry on\n"],
"ACT12": { "press": "key:return", "hold": "key:escape" }
```

A bare action means `press`. `doubleTap` is a second press within 350 ms; `hold` fires after
half a second. An Agent Key with a `hold` action fires its `press` when the key comes up, so
holding it does not open its session first. Every other control presses on the way down, and a
hold on it fires `press` and then `hold`.

## Commands: a key is a keycap

Put a keycap on a key, then name it in the file. The key does that command's job in whichever
app is in front:

```json
"keys": { "ACT09": "cmd:NEW" }
```

`commands` says what each name does, per app. `apps` names the app groups:

```json
"apps": {
  "claude":   ["com.anthropic.claudefordesktop"],
  "terminal": ["com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2"]
},
"commands": {
  "SPLIT": { "claude": "key:cmd+opt+o", "terminal": "text:/branch\n" },
  "MIC":   { "claude":   { "press": "key:cmd+d", "release": "key:cmd+d" },
             "terminal": { "press": "keydown:space", "release": "keyup:space" } }
}
```

- A command's entries are an app group, a bundle id, or `default` (any other app). Each is an
  action, a list, or an object of triggers. No entry for the app in front: the key does nothing.
- A key set to just `"cmd:NAME"` takes all of the command's triggers (press, release, hold,
  double tap). `cmd:NAME` inside one trigger, a stick direction or a dial turn runs the
  command's `press`.
- Add your own: any name of letters, digits, `+`, `-`, `_`.

### The stock keycaps

All 39 ChatGPT keycaps are defined. "none" means Claude has no key or command for it yet; give
it one in `commands`.

| Keycap | In ChatGPT | In the Claude app | In Claude Code in a terminal |
|---|---|---|---|
| `FAST` | toggle Fast mode | types `/fast` | types `/fast` |
| `APPR` | approve | presses the next-step box's first button, a permission card's "Allow once", or a question card's "Next" or "Submit"; with none on screen, Cmd+Return | Return |
| `REJ` | decline | presses the next-step box's second choice (its "Dismiss" when it has one choice), a permission card's "Deny", or a question card's "Skip"; with none on screen, Esc | Esc |
| `SPLIT` | fork the chat | Cmd+Opt+O (fork session) | types `/branch` |
| `MIC`, `MIC1` | push to talk | Cmd+D when you press and again when you let go: dictation runs while you hold the key | holds Space (turn on with `/voice` first) |
| `CODEX` | send | with nothing typed and a grey suggestion in the message box, takes the suggestion (Tab) and sends it; otherwise Return | Return |
| `NEW` | new task | Cmd+N | types `/clear` |
| `NAV` | new tab | Cmd+Ctrl+\ (new session pane) | none |
| `TERM` | toggle terminal | Cmd+J | none |
| `DIFF` | toggle review | Cmd+Shift+D | types `/diff` |
| `DEL` | archive the chat | Cmd+Opt+A | none |
| `MAGIC` | pin the chat | Cmd+Opt+P | none |
| `PARTY` | side chat | Cmd+; | types `/btw ` and waits for your question |
| `MIND+`, `MIND-` | reasoning up, down | Cmd+Shift+E (effort menu) | types `/effort` (slider) |
| `UPL`, `PAINT` | add files, add photos | Cmd+U | none |
| `FOLD` | open folder | Cmd+Shift+O | none |
| `LAB`, `SETUP` | settings | Cmd+, | types `/config` |
| `APPS` | open skills | types `/` (opens the command list) | types `/skills` |
| `TIME` | manage tasks | none | types `/schedule` |
| `DWN` | copy chat as Markdown | none | types `/export` |
| `BUG` | feedback | types `/feedback` | types `/feedback` |
| `OAI` | open the docs | opens code.claude.com/docs | same |
| `GIT`, `BRANCH`, `PR`, `BRCH`, `MRG` | commit, branch, PR, draft PR, merge | types the request, does not send it | same |
| `YOLO`, `YEET` | type `:yolo:`, `:yeet:` | same | same |
| `PLAY`, `EMPT1` to `EMPT5` | yours to set | none | none |

Extra commands, not ChatGPT keycaps: `PLAN` (permission mode: Cmd+Shift+M in the app, Shift+Tab
in a terminal), `FORWARD` and `BACK` (next and previous session), `SIDEBAR` (Cmd+B),
`PADSETTINGS` (opens this file), `COMPUTER` (types "Use computer use to " and waits for the
rest; Claude has no key that starts computer use, it is a setting Claude uses when asked),
`LOCK` (runs `lock`: the lights go off, then the Mac locks).

The dial runs three more: `NEXT` (turn right), `PREV` (turn left) and `PICK` (press). In the
Claude app, on a multiple-choice card:

- One answer allowed: a turn selects the next or previous answer, "Other" included. The press
  goes to the next question ("Next") or sends the card ("Submit").
- Several answers allowed: a turn moves a highlight and ticks nothing, the press ticks or
  unticks the highlighted answer, and one more turn past the last answer ("Other") reaches
  "Next" or "Submit", where the press goes on or sends the card.
- "Other" opens a text field. Type your answer on the keyboard, then press the dial to go on.
  With nothing typed the press does nothing.
- A card with several questions shows one at a time ("1 of 2"). Approve presses "Next"
  and, on the last question, "Submit". Decline presses "Skip".

With no card on screen, and in every other app, they type Down, Up and Return as before.

## Actions

| Action | What it does |
|---|---|
| `none` | nothing |
| `cmd:NAME` | what the named command does in the app in front |
| `ack` | mark the key's finished (green or red) session as seen |
| `jump` | show that key's session: its Code session in the Claude app. Anywhere else (Terminal, Ghostty) it acts like `focus` |
| `focus` | bring the app that session runs in to the front |
| `forget` | drop that key's session and free the key. The default for holding an Agent Key (`agentKeys.hold`). A session that is still running takes a key again the next time it does something |
| `pin` | pin that key's session to its key, or unpin it when it is pinned. A pinned session keeps its key however urgent other sessions are, and after it ends, until it is unpinned or forgotten. The key goes dark twice when it pins and once when it unpins. Not bound by default: `"agentKeys": {"press": ["ack", "jump", "pane:chat"], "hold": "forget", "doubleTap": "pin"}` puts it on a double tap (the first tap still opens the session). The window's Pad screen and `micro ctl pin <session> [slot]` pin too, and can name the key |
| `lock` | turn every light off, then lock the Mac as ⌃⌘Q does. macOS refuses writes to the pad once the Mac is locked, and before any app hears of the lock, so locking any other way leaves the lights as they were. The keys show their sessions again when the Mac is unlocked, or 5 s later if it did not lock. Needs Accessibility, as typing keys does. Not bound by default: `"dial": {"hold": "cmd:LOCK"}` puts it on a held dial, or pick the LOCK keycap for a key in the window |
| `scroll:up` / `scroll:down` | scroll what is under the pointer, as a mouse wheel does. On the stick it scrolls for as long as the stick is pushed, faster the farther (60 to 800 points a second); on a key, one step of 120 points. The Claude app scrolls only for a wheel macOS aims at the window under the pointer, so keep the pointer over the chat. Needs Accessibility, as typing keys does. Not bound by default: `"stick": {"up": "scroll:up", "down": "scroll:down"}` |
| `pane:left` / `pane:right` | move the pointer to the middle of the next pane that way in the front window, so scrolling goes there. A pane is a part that scrolls on its own and is at least 150 points each way: the Claude app's chat, its sidebar, a web page in its side pane, a native scroll area. From the chat, `pane:right` goes to a web page on the right and `pane:left` back. With the pointer in no pane (on another screen, over the message box), it goes to the nearest pane that way, else the largest. Copies of one pane, such as browser tabs hidden under the one on show at the size the side pane had before, count as one, and a move never lands in the pane the pointer is already in. `micro panes` lists what it finds without moving anything, and marks the chat. Needs Accessibility. Not bound by default: `"stick": {"left": "pane:left", "right": "pane:right"}` |
| `pane:chat` | put the pointer in the middle of the Claude app's chat, the pane right above its message box, so the stick scrolls the chat. After `jump`, it first waits up to 3 s for that session to show. The pointer stays where it is when it is on the chat already or was moved since the press, and for a session in a terminal. The default for tapping an Agent Key: `"agentKeys": {"press": ["ack", "jump", "pane:chat"]}`. Needs Accessibility |
| `key:shift+tab` | type a key combination into the app in front |
| `keydown:space` / `keyup:space` | hold a key down, let it go. While held it repeats like a real key |
| `text:/fast\n` | type text; `\n` presses Return |
| `sh:<command>` | run a shell command in the session's folder |
| `open:<url, file or app path>` | open it |
| `click:<box>/<pick>` | press a button on screen in the app in front. `<box>` is the label, the id or one class of the box around the button, in full (`*` means anywhere in the window). `<pick>` is `first`, `last`, a number, the button's label (the whole label, else a label that contains it), or `=Label` for the whole label only (`=Next` leaves "Show next question" alone). `<box>^2` also tries the two containers around the box, nearest first. When it presses a button the rest of the list is skipped; when there is none the list carries on. Example: `["click:Suggested next actions/first", "key:cmd+return"]` Add `!` after the pick (`…/Submit!`) for a button that goes away when it works: while it is still there, usable and holding the keyboard focus, it is pressed again every quarter second, for up to a second. It stops as soon as the box's title changes (a card that moved on to its next question) |
| `choose:<box>/<class>/next` | move the selection among a box's options in the app in front: the checkboxes or radio buttons inside `<box>` that carry `<class>`. In a box that takes one answer, `next` turns on the option after the one that is on, `prev` the one before; an option that is not on after its press is pressed again every quarter second, for up to a second. In a box that takes several answers nothing is turned on: `next` and `prev` move the keyboard focus, the highlight, from one option to the next (the first step puts it on the first option), and `<class>+<button>` lets it go on to the button with that label after the last option (`+Next|Submit` names several; the one the box shows is used). A toggle without the class that sits inside a container carrying it (the card's "Other") counts as an option. The ends do not wrap. When the box shows such options, the rest of the list is skipped, even at an end; when it does not, the list carries on, so put the old keystroke after it. No quiet time: a dial can keep stepping |
| `complete:<box>` | when the focused text box `<box>` (its label, id or one class) holds nothing typed and shows a suggestion, fill the suggestion in; the next action, Return, sends it. With text typed or no suggestion it does nothing. Grey text the box exposes is typed in. The Claude app exposes none: it takes the box's hint away while a suggestion shows, so there it presses Tab, as you would, and checks the box filled. If Tab leaves the box it moves back and stops the press; if Tab types blank space it takes it out and sends nothing. The log gives lengths, never the text. The Claude app's `CODEX` is `["complete:Prompt", "key:return"]` |
| `choose:<box>/<class>/mark` | in a box that takes several answers, type Space on whatever has the highlight: it ticks or unticks an option and presses a button. With nothing highlighted, or in a box that takes one answer, it does nothing and the list carries on. While the box's own text field ("Other option") holds the keyboard focus: with nothing typed it does nothing and the list stops there; with text typed the list carries on, so the click after it ("Next" or "Submit") sends the answer |

- Key names: letters, digits, `return`, `escape`, `tab`, `space`, `delete`, `up`, `down`, `left`,
  `right`, `home`, `end`, `pageup`, `pagedown`, `f1` to `f20`, and `- = [ ] ; ' , . / \` `` ` ``.
  Modifiers: `cmd`, `shift`, `opt`, `ctrl`, joined with `+`.
- `sh:` commands get `MICRO_SESSION`, `MICRO_CWD`, `MICRO_PID`, `MICRO_STATUS`, `MICRO_HOST`
  (`claude:local_…`, when known) and `MICRO_SLOT` (0 to 5) for the session on
  the Agent Key that was pressed, or pressed last for other controls. `PATH` includes
  `~/.local/bin`, `/opt/homebrew/bin` and `/usr/local/bin`.
- Typing needs MicroBridge switched on under System Settings > Privacy & Security > Accessibility.

## Settings

| Setting | Meaning | Default |
|---|---|---|
| `lighting.brightness` | 0 to 100 | 100 |
| `lighting.autoDimSeconds` | lights off after this long without activity; they return on a key press or a status change; 0 is never (ChatGPT's own default is 180) | 0 |
| `lighting.pulseSelected` | pulse the Agent Key of the session the Claude app's window shows. The bridge reads the window's page address once a second. A session in a terminal never pulses this way | true |
| `lighting.offWhenLocked` | catch ⌃⌘Q, turn the lights off, then let the lock through; the keys show their sessions again on unlock. Only ⌃⌘Q: macOS refuses every write to the pad from the moment the Mac locks, before any app hears of the lock, so the Touch ID button or the Apple menu leave the lights as they were. Catching the shortcut needs Accessibility. The catcher reads each key's code and modifiers and nothing else, and logs nothing. The lock waits 2.5 s at most for the lights. If the Mac does not lock within 5 s, the bridge stops catching ⌃⌘Q until it restarts and shows a notification. A password field or Terminal's Secure Keyboard Entry hides keys from it: ⌃⌘Q then locks as usual, lights on | false |
| `lighting.colors` | color per status: `working`, `needs-you`, `idle`, `done`, `failed`, as `"#RRGGBB"` | ChatGPT's colors |
| `keystrokeApps` | bundle ids that may receive typed keys; an empty list means whichever app is in front | `[]` |
| `stepAsideFor` | bundle ids of apps that get the pad to themselves while one of them is in front: the bridge lights nothing and acts on no key. Without MicroBridge Helper, both apps hear every key either way, since macOS lets only root keep the pad to itself. While any other app is in front, the bridge paints its lights back over another app's light write, at most once a second. With MicroBridge Helper installed, while one of these apps runs behind another app and the pad is on its first layer, the bridge holds the pad and that app hears nothing. `[]` turns this off. The window's Settings has a switch for ChatGPT | `["com.openai.codex"]` (ChatGPT) |
| `layers` | layers whose visit passes the pad to another app, by number from 2 to 9, each to a bundle id. Going to such a layer and back (two taps on the touch sensor) gives that app the pad: from then on the bridge lights nothing and acts on no key, whatever is in front. The next visit takes the pad back, and so does that app quitting. Until a visit the bridge keeps the pad even while that app is in front, and with MicroBridge Helper holds it so that app hears nothing. Both apps use layer 1's keys: the Codex keys exist only there. The app must be open to get the pad. The window's Behavior tab has a switch for layer 2 and ChatGPT | `{}` |
| `layerKeys` | `true` when the pad has the Codex keys on every layer in `layers` as well as on layer 1; the README's "One tap instead of two" says how to put them there. Then there are no visits: the layer the pad is on says who has it. On a layer in `layers` that is its app while it is open. On layer 1, and on that layer while its app is closed, it is the bridge, which acts on that layer's keys too. So one tap on the touch sensor changes who has the pad. The window's Behavior tab has a switch | false |
| `layerApps` | the bridge's own layers and the apps each one is for, by layer number from 1 to 9: app groups from `apps`, or bundle ids. Layer 1 is always the bridge's. Any other layer listed here is one the bridge drives itself, for an app that does not drive the pad, such as Orca: `{"2": ["orca"]}`. The pad must have the Codex keys on that layer, put there the way the README's "One tap instead of two" does it. On such a layer the bridge acts on the keys, holds the pad from other apps as on layer 1, and shows that layer's own six Agent Keys: on Orca's layer they hold Orca's chats (see [Orca's layer](#orcas-layer)), on any other they stay dark. **The layers are kept apart:** while the pad is on one of these layers, every control but the Agent Keys does nothing in an app that belongs to another one. On layer 1 the keys, the dial and the stick do nothing in Orca, on Orca's layer nothing in the Claude app or a terminal. In an app on no layer, such as a browser, they act the same on every layer. An Agent Key acts whatever is in front, since it brings its own app forward. With only layer 1 here nothing is kept apart. A layer the file leaves out keeps its apps; a layer cannot be in `layers` too, and an app belongs to one layer | `{"1": ["claude", "terminal"]}` |
| `layerWarning` | show a macOS notification when the pad is on a layer other than 1, and again when it is back, and when a visit to a layer in `layers` passes the pad on; set `false` if you use layers 2 to 6 on purpose | true |
| `batteryWarning` | show a macOS notification once when the pad's battery falls to this percent while it is not charging; it can warn again after a charge; 0 turns it off | 20 |
| `clickGuard` | seconds a key stays quiet after its `click:` pressed a button, so a fast second press cannot go on to answer a prompt that appears next; `0` turns it off (default `1`) |
| `urgentFirst` | when all six Agent Keys are taken, a session without a key takes the key of a session that wants you less. Order, most urgent first: needs you, finished or failed and unread, working, idle, ended. The least urgent holder gives up first; among equals, the one heard from longest ago. Equals never push each other out. A holder that still runs then waits for a key; one that ended is forgotten. The session on screen, and a session whose key was pressed in the last 5 s, keep their keys. `false`: only an ended session gives its key up. Older name: `needsYouFirst` | true |
| `rememberHours` | how long a Claude app session that ended keeps its Agent Key. The key shows white (or stays green or red if unread) and a press opens the session again. `"always"`: until another session takes the key (see `urgentFirst`) or you hold the key to clear it. A number: that many hours. 0: the key goes dark as soon as the session ends. The keys also survive a restart of the bridge | "always" |

**Layers.** A tap on the pad's touch sensor (bottom-left edge) cycles its layers. Everything in
this file works on layer 1 only, unless the pad has its keys on more layers (`layerKeys`,
`layerApps`): on any other layer the pad sends this bridge nothing. The
bridge reads the layer every 5 seconds, writes changes to its log and shows the notification
above. While `layers` is set it reads the layer every second, and five times a second for up
to 10 seconds while it waits for the tap back to layer 1. With `layerKeys` it reads the layer
four times a second for as long as an app in `layers` is open, since one tap then changes who
has the pad. With a second layer in `layerApps` it reads the layer four times a second all the
time: one tap then changes whose keys they are. `micro ctl state` prints the current `layer`
and `battery`.

To find an app's bundle id:
`defaults read /Applications/Ghostty.app/Contents/Info CFBundleIdentifier`

## Orca's layer

Give Orca a layer, and that layer's six Agent Keys hold Claude chats from Orca's chat view:

```json
"layerApps": {"2": ["orca"]}
```

The pad needs the Codex keys on that layer (README, "One tap instead of two"). The app group
`orca` is built in. Orca's command line (`orca`) must be installed, and MicroBridge needs
Accessibility.

- **You fill the keys.** Hold an empty key and it takes the chat whose tab shows in Orca. With
  another kind of tab showing, it takes the only Claude chat among the tabs of that workspace.
  When that does not single one chat out (several chats and none showing, two chats side by
  side, two chats with one title), the key flashes red twice and the log says why. Hold a taken
  key and it lets its chat go. Nothing else takes or frees a key. On this layer the hold is
  built in, whatever `agentKeys.hold` says, and there is no double tap.
- **Lights** are those of Claude's layer: blue working, amber needs you, green done, red
  failed, white idle. They come from the same Claude Code hook. A chat is known by Orca's
  session ID, which it keeps across `/clear`.
- **A tap** does what `agentKeys.press` says, with the key's chat: `ack` clears green or red,
  and `jump` brings Orca forward, opens the chat's workspace and presses its tab. `pane:chat`
  is skipped.
- **A closed chat** stays on its key, dim. A tap does nothing and a hold frees the key. A chat
  whose process ended while its tab is still open keeps its light: the bridge asks Orca which
  of the two it is.
- **Approve and Decline** press "Allow" and "Deny" on the chat's permission card
  (`commands.APPR.orca` and `commands.REJ.orca`). A file that sets `APPR` or `REJ` itself needs
  those `orca` entries too.
- A chat in Orca never takes a key on layer 1. With no layer for Orca, its chats get no key at
  all. Other agents in Orca's chat view, such as Codex, report nothing.
- The keys are kept in `orca-keys.json` next to the config file: Orca's session IDs and their
  states, no titles. They survive a restart of the bridge and of Orca. The bridge remembers the
  title of a key's chat in memory only, so after a restart the key of a closed chat shows the
  start of its ID.
- **In the MicroBridge window:** Behavior has the switch "Orca's chats have a layer of their
  own". It writes the setting above for layer 2, and moves a ChatGPT entry in `layers` from 2
  to 3 (and back when turned off). Pad lists Orca's six keys with each chat's title: "Show"
  does what a tap does, "Free" what a hold on a taken key does, and "Put a chat here" puts the
  chat on screen in Orca, or one picked from Orca's open chats, on an empty key. While the pad
  is on Orca's layer the drawing shows Orca's keys.
- By hand: `micro ctl orca take <slot> [id]`, `micro ctl orca free <slot>` and
  `micro ctl orca show <slot>` do what a hold and a tap do (slots count from 0).
  `micro ctl orca chats` lists Orca's open Claude chats with their IDs and titles, and
  `micro ctl state` lists the keys under `orca`. `micro orca` prints what the bridge sees of
  Orca and which chat a hold would take. It changes nothing; `--titles` adds the titles.
- The bridge always asks the Orca on this Mac, also when your shell points Orca's command line
  at another machine (`ORCA_ENVIRONMENT`).
- Limits: a tab has no ID of its own, so a tab is known by its title, and a jump presses the
  first tab with the chat's title. A bot's Home chat was not in Orca's list of chats when
  looked at, so a key cannot take it. Seen in Orca 1.4.271.
- Not tried on the pad yet (2026-11-23): the hold, the tap, the dim light.

## Checked on the pad (2026-11-11 and 2026-11-12)

Key numbers in this section are the test pad's own layout: Decline on key 7 (`ACT06`),
Approve on key 8 (`ACT07`), New chat on key 9 (`ACT08`). The stock defaults put Fast on key 7,
Approve on key 8 and Decline on key 9.

- Checked: typing text, dial turns in both directions, edits applying without a restart, a tap
  on an Agent Key opening that Claude app session, the Mic key (hold to dictate), the New
  chat key and the Fork key in the Claude app, and an empty Agent Key opening the new-session
  page.
- Orca's terminals are left out on purpose since 2026-11-13: a Claude Code session started in
  an Orca terminal takes no Agent Key and no light. Chats in Orca's chat view go to Orca's
  layer, when it has one (see [Orca's layer](#orcas-layer)).
- Approve, checked 2026-11-12: key 8 approved two real permission prompts in the Claude app
  (Cmd+Return, "Allow once").
- Decline (key 7) closed a real permission prompt on 2026-11-12 (16:47 UTC). It also stops the turn.
- `click:` pressed real buttons in the Claude app on 2026-11-12 (the Context panel header, a message's Copy button). Finding a button takes about 0.15 s.
- The next-step box, seen on 2026-11-12: its reply buttons sit in a group labelled "Suggested next actions"; its "Dismiss" button sits outside that group. 
- Decline (key 7) closed a real next-step box on 2026-11-12 (18:34 UTC): the log says `pressed "Dismiss"`, 35 ms, and the box closed on screen. 
- The permission-mode card, seen on 2026-11-12: a box with class `epitaxy-approval-card` holding "Deny" and "Allow once". Cmd+Return does not press it, so Approve and Decline click those buttons. Decline rejected a real card with Escape at 18:42 UTC; Approve (key 8) pressed "Allow once" on a real card at 19:03:50 UTC (0.11 s) and the session switched to Auto. Decline's click on "Deny" has not been seen on a real card; Escape rejects the card in any case. A box is matched by its whole class name: other elements carry classes such as `has-[.epitaxy-approval-card]:shrink`.
- A turn stopped by hand (Escape, key 7 on a question or a prompt) now puts the session's key on `idle` within about 2 s. Seen on a real thread on 2026-11-12 (19:25 UTC): key 7 on a multiple-choice card, the key left amber about 1 s later.
- `clickGuard`, seen on 2026-11-12 (19:09:33 UTC): a double press of key 8 on a next-step box answered once; the log shows the second press ignored.
- Approve (key 8) pressed the first button of a real next-step box on 2026-11-12 (18:35 UTC): the log says `pressed "Key 8 worked"`, 23 ms, and that label arrived as the answer.
- The multiple-choice card (`AskUserQuestion`), seen on 2026-11-12: a box with class `epitaxy-approval-card`; each answer is a checkbox with class `epitaxy-answer-option`, the first one on; "Other" is a checkbox without that class inside a group that carries it (the dial reaches it since 2026-11-18); buttons "Skip" and "Submit". Arrow keys and Return from the pad do not reach the card (they scroll the chat or the prompt history), so the dial presses the answers themselves.
- The dial on a multiple-choice card, seen on 2026-11-12 (19:57 UTC): turns moved the highlight on a real 4-answer card; the dial press logged `pressed "Submit"` at 19:57:13 and the highlighted answer ("Cherry") arrived. A step looks only inside the card once it has found it: 2 ms and 14 elements, against 120 ms for a search of the window. Cards that take several answers are untried.
- A fresh card takes its first press as "focus here", seen on 2026-11-12 (20:08 and 20:12 UTC, with `micro choose` and `micro click` on cards nobody touched): while the keyboard focus is outside the card, a press on an answer or on "Submit" only moves the focus onto it; a press half a second later works. So `choose:` and `click:…!` press again until it takes. Seen from the pad: one dial press closed a fresh card at 20:21:49 UTC (3 presses, about 0.5 s), and the first turn on a fresh card moved the highlight at 20:23:12 UTC (3 presses, 0.54 s). After that the keyboard focus is in the card, not in the text box.
- A card that takes several answers, seen on 2026-11-12: it is built like the one-answer card, and it alone keeps a counter for screen readers ("2 selected") in a group with subrole `AXApplicationStatus`; that counter is how the bridge tells the two apart. Its "Submit" is switched off until an answer is ticked. Before 2026-11-13 the dial ticked every answer it passed on such a card.
- The dial on a card that takes several answers, seen on 2026-11-13 (01:23 UTC): the first turn moved the keyboard focus into the card and highlighted the first answer (107 ms); later turns moved the highlight in under 1 ms and stopped at "Submit"; the press logged `typed Space on "Banana": now ticked`, then the same for "Cherry", with no other answer changing; a press on "Submit" sent the card, and "Banana, Cherry" arrived.
- A card with several questions, seen on 2026-11-18 (01:56 UTC): the box's title is the question on show; its header holds "Show previous question", "1 of 2" and "Show next question"; the footer holds "Skip" and "Next", and on the last question "Skip" and "Submit". The first answer of a one-answer question is already on. Pressing "Other" turns it on and puts a focused text field ("Other option") beside it in the same group. After "Submit" every button goes off, then the box goes.
- Approve and the dial on that card, seen on a real 2-question card on 2026-11-18 (02:15:59 to 02:16:17 UTC): Approve logged `pressed "Next"` (3 presses, the card was cold) and the card went to "2 of 2"; on question 2 the dial ticked two answers, highlighted "Other", then "Submit", and the press sent the card. Not tried yet: Decline on "Skip" (whether it skips one question or the whole card is not known), a dial press on "Other" followed by typing, a dial press on "Next", "Other" on a one-answer question.
- The session on screen, seen on 2026-11-18 (02:25 and 02:28 UTC): the Claude window holds a web page whose address (`AXURL` of its `AXWebArea`) is `https://claude.ai/epitaxy/local_<id>`, the id a session reports as its host. The address followed the owner from one session to another between the two readings. With that session on key 3, `micro ctl state` said `"pulsing": [2]` (keys count from 0 there) and the bridge used 0.0% CPU. `micro tree "*"` prints the address as `url=`. Not seen: the pulse on the pad itself, a split view with two sessions.
- The low battery warning, built on 2026-11-18, has not fired: the bridge reaches the pad over USB only, where it charges (100%, charging at 02:23 UTC). It can fire when the pad stops charging on USB, or once the bridge speaks Bluetooth.
- Keys remember their sessions, seen on 2026-11-18 (02:44 to 02:45 UTC) with a test session on the running bridge: ended, it stayed on key 2 as idle with `"ended": true` in `micro ctl state`; after a restart the log said `sessions from before the restart: 2 keep their keys (1 running, 1 ended)` and both were on the same keys. `micro ctl forget <session>` freed the key. Not seen: a real session ending, and a press opening it again.
- A restart with real sessions, seen on 2026-11-18 (02:50:33 UTC): the log said `sessions from before the restart: 2 keep their keys (2 running, 0 ended)` and both were on the keys they had. Holding an Agent Key to clear it (`forget`) is covered by unit tests; not seen on the pad yet.
- Replacement by urgency, seen on 2026-11-18 (02:59:34 UTC) on the running bridge with test sessions on the four free keys: ended, they kept keys 3 to 6; a working test session then took key 3 and one that needs you took key 4 (`key 3 goes from session zz-f1 (ended) to session zz-w1 (working)`), and the two real sessions kept keys 1 and 2. Not seen: more than six real sessions at once.
- Not yet tried on the pad: the stick commands, `hold`,
  `doubleTap`, brightness, auto-dim, pulse, custom colors. The Claude app shortcuts come from the
  app's own shortcut table (build of 2026-11-10); the terminal commands from Claude Code's docs.
- The Mic key in the Claude app: Cmd+D switches dictation on and off, it is not a key to hold. Seen on 2026-11-12 (19:58 UTC): a 3 s hold of Cmd+D did not act as hold-to-talk, and it took a second press to stop. Since 20:30 UTC the key sends Cmd+D once on press and once on release. The owner confirmed on the pad that holding the key now dictates and letting go stops it (2026-11-12). Known limit: if dictation stops by itself while the key is down, letting go starts it again; tap the key once to stop it.
- On this pad a turn to the right arrives as `ccw` (the pad's own name, `ENC_CCW`), so `ccw` runs `NEXT` and `cw` runs `PREV`. Swapped on 2026-11-12 after right and left turned out reversed; the new direction was confirmed on the pad the same day. To reverse it again, swap the `cw` and `ccw` actions.

## Buttons on screen

`click:` finds buttons through the macOS accessibility tree, with the same Accessibility
permission that typing uses. For the Claude app the bridge switches that tree on
(`AXManualAccessibility`) the first time it looks; it stays on until the app quits.

- `micro buttons [app] [--match text] [--detail]` lists the buttons in an app's front window,
  with the classes and containers a `<box>` can name.
- `micro buttons --watch 60` prints the list each time it changes.
- `micro click "<box>/<pick>" [app]` presses one now.
- `micro choose "<box>/<class>/next" [app]` moves a box's selection, or its highlight, now.
- `micro key <combo> <bundle id>` types one key combination, only while that app is in front.
- `micro tree <box> [app] [--watch 60]` prints everything inside a box, one line per element
  (role, label, value, id, classes, actions): how the multiple-choice card was read.
  `<box>^2` starts two levels above the box, to see what sits beside it; `--attributes` prints
  every accessibility attribute instead, a few levels down.

Run them as the app, so they have its permission:
`open -n -a ~/Applications/MicroBridge.app --stdout /tmp/out.txt --args buttons`.
