# Changelog

What changed in each release, newest first. The dated story of how each piece was built and
checked is in [docs/development-log.md](docs/development-log.md); the reasons behind the design
are in [docs/decisions.md](docs/decisions.md).

## Unreleased: the first public release

Built from 2026-11-10 to 2026-11-22 against a real Codex Micro on firmware v0.6.1 (0.6.3 from
2026-11-22), over USB.

### The Agent Keys follow your Claude Code sessions

- Each of the six keys follows one session, in the Claude app or a terminal, and lights by what
  it is doing: blue working, amber needs you, green done and unread, white idle, red failed.
- A tap clears green or red and shows the session; holding a key forgets its session.
- With more than six sessions, the six most urgent hold the keys. A pinned session keeps its key
  however urgent the others are.
- A Claude app session that ends keeps its key, and a tap opens it again. Keys survive a restart
  of the bridge.
- The key of the session on screen pulses slowly.
- **Next to ChatGPT:** while ChatGPT is in front, MicroBridge leaves the pad to it, with no
  lights and no key actions. In any other app, MicroBridge's lights win.
- **MicroBridge Helper (optional):** a small root helper that keeps the pad from ChatGPT while
  ChatGPT runs behind another app, so presses meant for Claude stay in Claude. It is installed
  with `sudo scripts/helper install`, plus one entry under Input Monitoring.
- **Two taps pass the pad to ChatGPT (optional):** with `"layers": {"2": "com.openai.codex"}`,
  a tap on the touch sensor to layer 2 and a tap back give ChatGPT the pad, and the same two
  taps take it back. Both apps use layer 1's keys, the only Codex keys the pad has. A
  notification says who has the pad.
- **One tap instead (optional):** a profile imported with Work Louder Input can give layer 2
  the Codex keys too. With `"layerKeys": true` the layer the pad is on then says who has it:
  ChatGPT on layer 2, MicroBridge on layer 1.
- **A second layer of MicroBridge's own (optional, for Orca):** `"layerApps": {"2":
  ["com.stablyai.orca"]}` makes layer 2 a layer MicroBridge drives itself, on a pad that has the
  Codex keys there. The layers are kept apart: on layer 1 the keys, the dial and the stick do
  nothing in Orca, and on layer 2 nothing in the Claude app or a terminal. In any other app they
  act on both layers. Layer 2's six Agent Keys are its own.
- **Orca's chats on the keys of Orca's layer:** the six Agent Keys of the layer `layerApps`
  gives Orca hold Claude chats from Orca's chat view, put there by hand. Hold an empty key and
  it takes the chat whose tab shows in Orca; hold a taken key and it lets the chat go. A key
  lights by what its chat is doing, in the colors of Claude's layer. A tap brings the chat on
  screen: Orca comes forward, the chat's workspace opens and its tab is pressed. A chat whose
  tab was closed stays on its key, dim: a tap does nothing and a hold frees the key. Approve
  and Decline press "Allow" and "Deny" on a chat's permission card. A chat in Orca never takes
  a key on Claude's layer. `micro orca` prints what the bridge sees of Orca. Tried on a real
  Orca through the bridge's socket. On the pad the hold that takes a chat and the tap were
  tried; the hold that frees a key and the dim key were not.
- **Orca in the MicroBridge window:** Behavior has one switch that gives Orca layer 2 and moves
  ChatGPT's layer to 3. Pad lists Orca's keys with each chat's title, "Show", "Free" and a menu
  that puts a chat on an empty key, and its drawing shows the keys of the layer the pad is on.
- **A MicroBridge panel in Orca** (`orca-plugin/`): the same six keys in Orca's right sidebar,
  and what each command does while Orca is in front, changed there and saved to the config
  file by the bridge. Tested with Orca's plugin tools and loaded into a running Orca, where it showed the pad's
  keys; its buttons have not been pressed there yet.

### The other controls

- **Approve and Decline** press the next-step box's first and second choices, a permission
  card's "Allow once" and "Deny", and a question card's Next, Submit or Skip. In a terminal:
  Return and Esc.
- **The dial** moves between a question card's answers and ticks or submits them, card by card.
- **The stick** can scroll what is under the pointer, faster the farther it is pushed, and move
  the pointer between panes, such as the chat and a web page beside it. A tap on an Agent Key
  puts the pointer on that session's chat, so the stick scrolls it at once.
- **Fork, Fast, Send and Mic** (hold to talk), in the Claude app and in a terminal.
- **Send with nothing typed** takes the grey suggestion in the Claude app's message box and
  sends it, as Tab then Return would. With text typed, or no suggestion, it is a plain Return.
- **Lock**: the lights go off, then the Mac locks, from a pad control, or on ⌃⌘Q once that
  setting is on.

### Make it yours

- One config file binds every control to any of 49 named commands or a list of actions: keys,
  text, shell commands, links, buttons on screen, scrolling and more, on press, release, double
  tap or hold, per app. It is picked up within a second of saving.
- The MicroBridge window shows the pad and its sessions, and edits keys, commands, lights and
  behavior without touching the file by hand. Its Setup screen checks the permissions, the hooks
  and the pad.
- Colors per state, brightness, dimming when idle, and a low-battery warning.

### Install and remove

- `scripts/install` builds the app into `~/Applications` and starts the bridge at login;
  `scripts/claude-hooks install` adds its Claude Code hook; `scripts/uninstall` removes it all.
- Or set it up from the app itself: the Setup screen's "Start at login" puts the bridge under
  Login Items, and "Copy the command" copies the one line that adds the hook
  (`micro hooks install`).
- Or let Claude Code add the hook: the MicroBridge plugin (`/plugin install micro-bridge
  --marketplace Philopateer2099/micro-bridge`). It stays quiet when the hook is already in your
  settings.

### Known limits

- Tested on one pad, on firmware v0.6.1, over USB. The two-tap and one-tap switches were tried on 0.6.3. Bluetooth is untested.
- Buttons in the Claude app are found by their labels and class names: a Claude app update can
  rename them until the config or a release catches up.
- A tap on a terminal session's key brings its app forward, not its tab.
- Without MicroBridge Helper, ChatGPT hears and acts on every key too, also while another app
  is in front: macOS lets only root keep the pad to itself, and ChatGPT has no setting to
  ignore the pad in the background. Install the helper, or quit ChatGPT, to keep presses in
  Claude alone.
- Once, after 29 idle minutes, the pad stopped answering over USB until it was replugged. This
  also happened to ChatGPT, so it looks like the pad's own problem.
