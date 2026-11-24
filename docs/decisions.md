# Decisions

One entry per decision, newest last. Format: decision, why, consequence.

## D-001 (2026-11-19): The window saves a typed action on Return or Save, never while it is typed

Decision: In the MicroBridge window, a field that holds an action (a key, text, a button rule, a shell command, an address) is kept as a draft in WindowState.drafts until the person presses Return or the row's Save button, and is written only when Action.parse takes it. Choices that need no typing (a one-word kind, a command from the menu, the 'then Return' box on a saved row) are written at once.
Why: The bridge picks up config.json within a second. Saving on every keystroke would put half a shell command or half a key combination on a live key.
Consequence: A row that is being typed shows Save and Cancel and, when the bridge would not take it, the reason. Drafts are lost when the window quits.
Rejected: Saving on every keystroke whenever the text happens to parse: 'sh:rm' parses long before the command is finished.
By: claude

## D-002 (2026-11-19): A key with its own actions is always written as an object of triggers

Decision: When the window gives a key its own actions it writes {"press": ..., "hold": ...}, never a bare action or list, even for a single press action.
Why: In the file, a key written as one cmd:NAME on its own takes every trigger of that command (press, release, double tap, hold). A bare form would silently change meaning the moment the key's list became one command.
Consequence: Switching a command key to its own actions starts it as {"press": "cmd:NAME"}: the command's release, double tap and hold do not come along, because cmd: inside a list always means the command's press. A key whose lists are all empty is written as {} and stays 'its own actions'; 'none' is the separate Nothing choice.
By: claude

## D-003 (2026-11-19): In the window, an app with no actions of a command falls back to Everywhere else

Decision: When the last action of a command for one app (claude, terminal, another group or bundle id) is removed in the window, that app's entry is taken out of the command, so the app does what 'default' says. The window does not offer 'do nothing in this one app'.
Why: The file can say both (no entry, or an empty object), and the window cannot show the difference without another control on every app of every command.
Consequence: A command that should do nothing in one app while 'default' does something needs "claude": {} written in config.json by hand. The window reads such an entry as empty and keeps it when it changes another app of the same command.
Rejected: Writing an empty object for an emptied app: the usual intent of clearing an app is to stop overriding the default.
By: claude

## D-004 (2026-11-19): A command a control still runs cannot be deleted in the window

Decision: The Commands screen disables 'Delete the command' for a command the owner made while any key, the dial, the stick or the Agent Keys run it, and says which control to take it off first. A built-in command is never deleted: 'Back to the default' removes the file's entry.
Why: The bridge refuses a file in which a control names a command that does not exist ("there is no command named ..."), so the delete would fail with that message. The button says what to do first instead.
Consequence: Deleting takes two steps for a command that is in use: change the control, then delete.
Rejected: Letting the delete fail with the bridge's message; deleting and rewriting every control that ran the command.
By: claude

## D-005 (2026-11-19): The window draws the pad as it is built, on a dark stage

Decision: PadDrawing follows the real Codex Micro: dial top left, Agent Keys 1 and 2, stick top right; Agent Keys 3 to 6; the four keys; then the layer button, the wide key and the last key. It is a white plate on a clear base, drawn the same in a light and a dark window, and always stands on the dark Stage. PadDrawing.rows is the one place that holds the order, and a test pins it. The app icon (PadMark) and the drawing on site/index.html follow the same order.
Why: The owner said the drawing looked wrong. It had the dial top right and two keys wide, the stick bottom right, and a dark body. The layout was read from the drawing on OpenAI's public Codex Micro help page and the product photos on its shop page (2026-11-19).
Consequence: The layer button is on the drawing and binds nothing: the bridge only reads the layer. Lower keys show an SF Symbol for their command (BridgeModel.symbols); a command with no picture shows the first three letters of its name. The artwork is this project's own: no logo, none of the text printed on the pad.
Rejected: Keeping the dark slab and only moving the controls: the pad is white and its lights read differently on white. Copying the artwork or the printed text from OpenAI's page: the window must not pass for theirs.
By: claude

## D-006 (2026-11-19): The window's chrome is grey; color belongs to the lights

Decision: The sidebar, lists and cards mark the chosen thing with a grey fill (Theme.chosen), not the accent color. Colors come from Theme (one set for dark, one for light). The accent color is used in one place: the ring around the control being set up on the pad drawing.
Why: The five status colors (white, blue, amber, green, red) carry meaning on every screen. A colored selection next to them reads as a sixth status; the old blue selection sat beside blue Working keys.
Consequence: A new screen takes its background, card and line colors from Theme and its section titles from SectionTitle. A new use of the accent color needs a reason of its own.
Rejected: An accent of the project's own (violet, coral, mint): each one sits too close to a status color.
By: claude

## D-007 (2026-11-19): The window follows the Codex app's Micro settings page

Decision: Every screen but Commands is one centered column of cards (680 points wide): rows of title, grey detail and one control; a 'Layout' section with the pad centered in a wide card (PadCard). PadDrawing is a dark flat diagram in both a dark and a light window (PadColors), with grey Agent Key caps that carry a dot of the status color. On the Keys screen the caps carry no light (showsLights: false). The greys in Theme are the values measured on that page.
Why: The owner asked for the window to copy the Codex app's Codex Micro settings and opened that page for a look on 2026-11-19. It draws a diagram of the pad, not the hardware, so the white plate of D-005 was the wrong model for the window.
Consequence: This replaces the look in D-005 (white plate, dark Stage, pad sized by the window); D-005's order of the controls and D-006 stand. The app icon (PadMark) and the drawing on site/index.html keep the white hardware look: they picture the product. Only structure, proportions and colors were taken from the page; the artwork is this project's own shapes and SF Symbols, with no logo and none of its text. The key editor is still this project's own design: the Codex app's per-key popup was not seen.
Rejected: Keeping the white hardware drawing in the window and changing only the page around it: the pad is the part the owner called wrong. Redrawing the icon and the project page as the dark diagram too: there the white pad is what tells a visitor which device this is.
By: claude

## D-008 (2026-11-19): A key's keycap is picked in a dialog and written on Save

Decision: Clicking a key on the Keys screen opens KeycapDialog over the window: a search box, a six-wide grid of every command that does something, a row for what the key runs (the keycap's command, its own actions, nothing), Cancel and Save. The pick is held in WindowState (keycapKey, keycapDraft, keycapSearch) and reaches config.json only on Save. The dial, the stick and the Agent Keys open no dialog; they are set up under the pad.
Why: The owner asked for the key editor to match the Codex app's, seen on 2026-11-20 (UTC): a dialog with a keycap grid, an assigned-action row, Cancel and Save. The drop-down it replaces wrote the file the moment an item was picked.
Consequence: A key takes one more click to change (Save), and a click that only wants to look at a key has to close the dialog first; the row under the pad then shows the key. A new command shows up in the grid by itself; it gets a picture only if BridgeModel.symbols names one, and a test checks every name there is a real SF Symbol. The dialog's title and words are this project's own.
Rejected: Saving on the click of a keycap, as the drop-down did: one stray click rebinds a key, and the Codex dialog does not work that way. A dialog for the dial and the stick too: each has several triggers, which one keycap cannot stand for.
By: claude

## D-009 (2026-11-20): Lights go off while the Mac is locked only when the owner turns it on

Decision: lighting.offWhenLocked (default false) makes the daemon turn every light off on macOS's com.apple.screenIsLocked notice and show the keys again on com.apple.screenIsUnlocked. The Pad screen carries the Codex page's top card (Connection, Battery, Input Monitoring, Brightness, Auto-dim, the lock) and an Options card (Agent Keys: urgentFirst; Dial: answers or sessions). The light rows are one view (LightRows) shown on both Pad and Lights.
Why: The owner asked to copy the Codex app's Micro page; its top card has 'Turn off lights when Mac is locked' (off in ChatGPT by default) and an Options card. The bridge had no lock setting.
Consequence: The lock notices are not documented by Apple, though every macOS release so far sends them; if they stop, the setting does nothing and the lights stay as they are. Brightness and auto-dim show on two screens; both write the same file entries.
Rejected: Turning the lights off on lock always: some people want to see agent states on a locked Mac. Codex's microphone option (push to talk or toggle): a toggle would leave space held down in a terminal. Its single-tap option: a tap already opens the session.
By: claude

## D-010 (2026-11-20): Take out lights off on lock; keep the pad open when macOS refuses writes

Decision: Reverses D-009. lighting.offWhenLocked does nothing and leaves the window, the daemon and micro config show; a file with it still loads. A write that comes back 0xE00002E2 is PadError.writesRefused: the daemon keeps the pad open, logs once, leaves the lights as they are and tries again every 2 s.
Why: On the owner's lock test (2026-11-21) macOS refused every write to the pad from the moment the Mac locked, before the com.apple.screenIsLocked notice arrived. The pad's vendor channel is part of its keyboard interface, and a locked Mac keeps keyboards to itself. This Mac locks at once and Amphetamine keeps the display awake, so no earlier notice exists. Taking the refusal for a lost pad reopened it every second.
Consequence: The lights stay as they were while the Mac is locked and show the sessions again within 2 s of unlock. The owner's config keeps offWhenLocked: true, which is ignored. Unlike ChatGPT's page, the window has no lock switch.
Rejected: Darkening on the screen saver or display sleep notices: they come with the lock on this Mac, not before it. Getting around the refusal: it is a macOS protection. Dropping the key from the parser: the owner's file would stop loading.
By: claude

## D-011 (2026-11-20): A pad-asked lock turns the lights off first

Decision: A new action, lock, and a built-in command, LOCK ({"default": "lock"}), not bound by default. The daemon turns every light off, waits for the pad to take the write, then posts ⌃⌘Q through ActionRunner.lockScreen (Accessibility, whichever app is in front). The lights come back on the unlock notice, on the first write macOS lets through after refusing, or after 5 s if no lock notice came.
Why: macOS refuses writes to the pad once the Mac is locked (D-010), so the only lock that can leave the pad dark is one the bridge starts itself, writing before it locks. The owner asked for it after the lock switch was taken out.
Consequence: Locking from the pad leaves it dark until the unlock. Locking with ⌃⌘Q, Touch ID or the menu still leaves the lights as they were. The window offers LOCK as a keycap and 'Turn the lights off and lock the Mac' as an action. There are 49 built-in commands.
Rejected: Locking with pmset displaysleepnow: it locks only when the Mac asks for the password at once. Private lock calls in login.framework: not a public interface. Watching the keyboard for ⌃⌘Q to darken first: a global key watch for one shortcut, racing a lock that macOS may already have engaged.
By: claude

## D-012 (2026-11-20): Catch ⌃⌘Q to turn the lights off before the Mac locks

Decision: lighting.offWhenLocked is back (default false) with a narrower meaning: an active CGEventTap at the HID level, on its own thread, holds back ⌃⌘Q (exactly Control+Command+Q), the daemon turns the lights off, and the same shortcut is typed again with a mark the tap lets through. It is typed after 2.5 s at most whatever the daemon is doing. If no lock notice comes within 5 s, the bridge stops catching ⌃⌘Q until it restarts and shows a notification. The pad's LOCK uses the same marked press.
Why: The owner wants the lights off without a special control and locks with ⌃⌘Q. macOS refuses writes once the Mac is locked (D-010), so the lights must go off before the lock starts, and ⌃⌘Q is the one lock gesture an app can see first. Their file already had offWhenLocked: true.
Consequence: On the owner's Mac ⌃⌘Q now darkens the pad, then locks, up to 2.5 s later if the pad is slow. The Touch ID button, the Apple menu and secure text entry still lock with the lights on. The bridge sees every key press while the setting is on and reads only its code, modifiers and mark. Supersedes the 'does nothing' part of D-010.
Rejected: A listen-only tap that races the lock: the first refusal comes in the same second as the keystroke. Running the tap on the main thread: slow Accessibility reads there would hold up the whole keyboard. A root helper to write while locked: it would get around a macOS protection.
By: claude

## D-013 (2026-11-21): The stick scrolls what is under the pointer

Decision: scroll:up and scroll:down post an ordinary scroll wheel at the pointer. On the stick they scroll continuously while it is pushed, 60 to 2400 points a second by push; on a key, one 120-point step. The built-in stick keeps PLAN, FORWARD, SIDEBAR and BACK; only the owner's file switched up and down to scrolling, at their request.
Why: Tried on the Claude app on 2026-11-21: a wheel sent to the app alone (with or without the window's number in fields 91 and 92, line or pixel units, gesture phases) and one posted already routed both left the chat still. A wheel posted at the HID or session level with a place of its own scrolled it but moved the pointer there. Only a wheel at the pointer scrolls without moving it.
Consequence: The pointer has to be over the chat for the stick to scroll it; over the sidebar it scrolls the sidebar. The stick's one-shot up and down gestures do nothing when they are bound to scroll, so a push does not add a jump.
Rejected: Aiming the wheel at the chat by moving the pointer there, or there and back on every step; Accessibility scroll-to-visible on messages (too coarse, the only scroll action the chat offers); changing the built-in stick, which mirrors ChatGPT's mapping.
By: claude

## D-014 (2026-11-21): Decline takes the next-step box's second choice

Decision: In the Claude app, Decline (REJ) first presses the next-step box's second button, and presses its Dismiss only when the box has one choice. Approve still presses the first. Changed in the built-in REJ and in the owner's file.
Why: The owner reads the two keys as the box's two buttons: Approve the first, Decline the second. On 2026-11-21 they pressed Decline to pick the second choice and it closed the box instead.
Consequence: A box with two choices can no longer be closed from the pad; Esc or the close button still closes it. A permission card and a question card are answered as before.
Rejected: Keeping Decline as Dismiss; putting the second choice on a held Decline, which nobody would guess.
By: claude

## D-015 (2026-11-21): Stick left and right move the pointer between panes

Decision: New actions pane:left and pane:right move the pointer to the middle of the next pane that way in the front window, with a real mouse-move event. A pane is a part that scrolls on its own, at least 150 points each way: a native scroll area, a web page that does not fill the window, or a web element with a Tailwind overflow-y class. The owner's stick left and right switched from previous and next session to these.
Why: The owner wants to switch which view the stick scrolls, between the chat and a website beside it. The Claude app scrolls only what is under the pointer (D-013), so the pointer has to move; here the owner asks for it with each push.
Consequence: The stick no longer goes to the previous or next session in the owner's setup. A panel that does not scroll on its own, such as the session details beside the chat, is not a pane. The walk stops at each pane, so a long chat does not slow it (about 100 to 350 ms).
Rejected: Keyboard focus on the pane, which takes the cursor out of the message box; warping the pointer without a move event, which leaves hover states stale; looking only for the Claude app's own class names.
By: claude

## D-016 (2026-11-21): The public repo starts from one fresh commit

Decision: When MicroBridge goes public, the public repo is made from a single clean commit of the code as it then stands. The private repo stays as it is, as the archive of the full history.
Why: The private history has the owner's personal email on every commit and one real Claude session id in its first commit. A fresh start removes both without rewriting or force-pushing anything.
Consequence: The public repo has no history before its first commit; the development log and decisions file carry the story. Nothing is rewritten in the private repo.
Rejected: Publishing the private repo as it is; rewriting its history in place and force-pushing.
By: owner

## D-017 (2026-11-21): Public commits show the owner's real name with GitHub's noreply address

Decision: Commits in the public repo carry the owner's real name and GitHub's private noreply email address, not their personal email.
Why: A real name ties the project to the owner's portfolio; the noreply address keeps their email out of a public history.
Consequence: The public repo's git identity must be set to the noreply address before its first commit, and GitHub's setting to block pushes that expose the email should be on.
Rejected: A pseudonym; the personal email.
By: owner

## D-018 (2026-11-21): Downloads are signed and notarized with an Apple Developer ID

Decision: The owner joins the Apple Developer Program (99 US dollars a year) when the project reaches downloadable releases. Until then MicroBridge is build-from-source only.
Why: An app from the web that is not notarized trips Gatekeeper's warnings, and most people stop there. A Developer ID also gives the app a stable identity, so macOS keeps its Input Monitoring and Accessibility grants across updates.
Consequence: The website's Download button waits for the first notarized release. The self-signed local certificate stays for building from source.
Rejected: Unsigned or ad-hoc signed downloads with instructions to bypass Gatekeeper.
By: owner

## D-019 (2026-11-21): MicroBridge stays under the MIT license

Decision: The project keeps the MIT license already in LICENSE.
Why: It is simple, widely understood and lets anyone use and change the code, which suits a small hobby tool.
Consequence: Contributions come in under MIT; no contributor agreement is needed.
Rejected: GPL and Apache 2.0.
By: owner

## D-020 (2026-11-21): The blog lives on the owner's portfolio site

Decision: Posts about MicroBridge go on the owner's portfolio site. MicroBridge's own site stays a single page: what it does, a demo, and the download.
Why: One site to keep up instead of two, and the writing builds the portfolio.
Consequence: The MicroBridge page links to the posts; the portfolio links back to the page and the repo.
Rejected: A separate MicroBridge site with its own blog.
By: owner

## D-021 (2026-11-21): Release builds use the hardened runtime, and so does the test zip

Decision: scripts/release signs a copy of the app with the hardened runtime and no entitlements. With a Developer ID it adds a timestamp, notarizes, staples and checks with Gatekeeper; without one it makes a test zip signed with the local identity. The bundle id stays local.micro-bridge.
Why: Notarization requires the hardened runtime. Giving the test zip the same runtime means trying the test zip tries what people download. Reading the pad, posting keys and Accessibility need no entitlements.
Consequence: The app scripts/install puts in ~/Applications is still unhardened; only release zips are hardened. The pad, keys and buttons under the hardened runtime are first tried in the new-account install test.
Rejected: A new bundle id for releases: it would reset everyone's Input Monitoring and Accessibility grants and the login item's label for no gain.
By: claude

## D-022 (2026-11-21): CI looks for private data in every change

Decision: scripts/check-public scans the tracked files for home folder paths, email addresses, session ids and keys, and fails if PROTOCOL.md is tracked. CI runs it before the build; scripts/public-snapshot runs it on the public tree. Made-up ids used in tests are listed in the script.
Why: The public repo starts fresh because the private history leaked a real session id and a personal email (D-016, D-017). A check on every change stops the next one before it lands.
Consequence: A test that needs a new made-up id must add it to madeup in scripts/check-public. Example addresses must use example.com or example.org.
Rejected: Searching for the owner's own email and names: the script is public, so it would publish exactly what it guards.
By: claude

## D-023 (2026-11-21): The site deploys from site/ through Actions, once SITE is on

Decision: The Site workflow puts site/ on GitHub Pages on pushes to main that change site/, or by hand. It runs only when the repository variable SITE is on.
Why: Pages can serve a branch only from the root or docs/, and the site lives in site/. The variable keeps the job skipped, not failing, until the owner turns Pages on.
Consequence: Publishing the site takes two owner settings: Pages source GitHub Actions, and SITE set to on.
Rejected: Moving the site into docs/, where Pages would also render the Markdown notes; running whenever the repo is public, which fails the first push if Pages is still off.
By: claude

## D-024 (2026-11-21): A downloaded app adds its hook two ways: a command, or a Claude Code plugin

Decision: The app gets `micro hooks install|remove|status`, written in Swift, which the Setup screen shows with a Copy button for the user to run. A MicroBridge Claude Code plugin is the second way: Claude Code loads the hook from the plugin, and no settings file is edited.
Why: A download has no scripts folder and may have no Python. The command keeps the rule that the window itself never writes ~/.claude/settings.json. The plugin is the most Claude-native way.
Consequence: scripts/claude-hooks is replaced by the Swift command. A user who has both the plugin and the settings hook would report each event twice, so each way checks for the other.
Rejected: A Setup button that writes the settings file from the window: it breaks the owner's rule that the app never writes it.
By: owner

## D-025 (2026-11-21): A downloaded app starts at login through Login Items

Decision: A Setup button registers the bridge with macOS through SMAppService, so it shows in System Settings, General, Login Items, where the user can switch it off.
Why: It is how macOS expects an app to start a helper at login, and it needs no Terminal step.
Consequence: The app carries its own LaunchAgent property list. A Mac that also has the LaunchAgent scripts/install writes would start two bridges, so the two must not both be on.
Rejected: A `micro install` command that writes the LaunchAgent file: one more Terminal step for people who download.
By: owner

## D-026 (2026-11-21): Next to ChatGPT, whoever is in front drives the pad, as far as macOS allows

Decision: While an app in stepAsideFor (ChatGPT by default) is in front, the daemon writes no lights and acts on no key. When another app comes to the front it repaints at once. While another app is in front, a light write by another app (seen as the pad's answer to it) is painted over with the bridge's lights, at most once a second.
Why: The owner chose whoever is in front. Taking the pad exclusively, so ChatGPT hears nothing while another app is in front, is refused by macOS for a user process (0xE00002C1, not privileged).
Consequence: ChatGPT still hears every key while Claude is in front; what it does with them is not known yet. The pad is opened shared, as before. stepAsideFor set to [] gives the old behavior: both apps act and the last light write wins.
Rejected: A root helper that seizes the pad (the project does not work around macOS protections); leaving it as last writer wins.
By: owner (whoever is in front), claude (the fallback once the exclusive open failed)

## D-027 (2026-11-21): A root helper keeps the pad from ChatGPT while it is behind

Decision: MicroBridge Helper (micro-helper), an optional LaunchDaemon run as root, opens the pad for MicroBridge and holds it exclusively (seize) while an app in stepAsideFor is running but not in front, and the pad is on layer 1. It shares the pad while that app is in front, when MicroBridge hangs up, and as soon as the pad sends keyboard or mouse input. It writes only the five allowed methods, rebuilt from a checked request, and serves one account and only a program signed as local.micro-bridge with its own certificate. It installs from the app with sudo into /Library/PrivilegedHelperTools and needs its own Input Monitoring row.
Why: ChatGPT acts on Codex Micro presses even while it is behind other apps and has no setting against it. macOS lets only root take a keyboard-class device for itself (0xE00002C1 as the user, success as root, 2026-11-21). The owner chose to build the helper after seeing that, lifting the project's rule against root helpers for this one program.
Consequence: With the helper installed ChatGPT hears nothing while Claude is in front; it retries every 10 s and reopens the pad about 3 s after it is shared again. Without it, everything works as in D-026. Installing takes the owner's password and a manual Input Monitoring entry (a root daemon cannot add itself). Off layer 1 the pad is never held, and the first keyboard report after a layer change is lost.
Rejected: Staying with D-026 alone (ChatGPT keeps acting from the background); SMJobBless or SMAppService.daemon (need a Developer ID team and an approval flow for a helper the user builds themselves); running the whole bridge as root (far more code with root rights).
By: owner (build the root helper), claude (the design)

## D-028 (2026-11-22): A tap on the touch sensor says who drives the pad

Decision: A new setting, layers, gives a pad layer to an app by bundle id, such as {"2": "com.openai.codex"}. On that layer the bridge shares the pad and acts on nothing, whatever app is in front. On layer 1 the bridge keeps the pad, and holds it through MicroBridge Helper, even while that app is in front. An app given a layer no longer gets the pad by being in front. While layers is set, the bridge reads the layer every second, and a press after more than 0.25 s without a reading waits for a fresh one. The window's Behavior tab has a switch for layer 2 and ChatGPT. The setting is generic, with no app-specific code, so other layers can go to other apps later.
Why: With the front-app rule (D-026, D-027) ChatGPT never worked: it retries the pad every 10 s, and the owner brought it forward for only 1 to 3 s at a time. The owner asked for the layer switch for direct control, and to hand layers to Orca later.
Consequence: A layer given to an app needs keys that app listens to; a new pad's layer 2 is empty (KC_NONE), so the owner sets the Codex keys there in Work Louder Input. After a hold, ChatGPT can take up to 10 s to open the pad again; the pad stays dark until it lights it. Without the helper, ChatGPT still hears layer 1's keys.
Rejected: Writing the pad's keymap or firmware from MicroBridge (unknown write protocol, a risk of bricking the pad; Work Louder Input does it safely). Changing ChatGPT's settings (it has none for this). Switching profiles instead of layers (the pad has one profile).
By: owner (the layer switch), claude (the design)

## D-029 (2026-11-22): The daemon reaches the outside through DaemonWorld

Decision: Daemon takes a DaemonWorld: how to open the pad, its folder, the app in front, the running apps, the Accessibility prompt and the log. The real ones are the defaults. Tests build the real Daemon with a fake PadLink (FakePad) in a scratch folder and call tick() by hand.
Why: The layer switch was committed with only a hand check, and the daemon had no tests because it opened the real pad and asked macOS directly. The owner asked whether it had been checked before a push.
Consequence: Daemon behavior can be tested without a pad: DaemonLayerTests covers hold, share, lights off, quiet layers and the first press after a tap. Pad.init(link:info:note:) and Daemon.tick() are internal instead of private. New code in Daemon that reaches for the pad, NSWorkspace or a fixed path goes through the world, or tests cannot see it.
Rejected: An environment variable that points the shipped daemon at a fake pad (a test door left open in a program that works with a root helper). A fake helper on a socket (the helper's path is fixed in /var/run, and it would not cover running without the helper).
By: claude

## D-030 (2026-11-22): At a hand-over the bridge turns off only its own lights

Decision: When the bridge lets go of a held pad it turns off the six Agent Key lights and leaves the ring and the key backlight as they are. Pad.slotsOff does it; Pad.allOff stays for the daemon's exit.
Why: The bridge writes only the Agent Key lights and never lights the two zones, so after turning them off at a hand-over it could not bring them back on layer 1. A short visit to layer 2, or one with ChatGPT closed, left the ring and backlight dark for good. A review by a second model led to the check that found it.
Consequence: A hand-over changes only lights the bridge can write again, the same as the lock. The sign that ChatGPT has the pad is its own Agent Key lights coming on; with no session lit before, a hand-over shows nothing until then. Not yet looked at on the pad.
Rejected: Keeping both zones off at a hand-over (D-028's first form): a clearer dark pad, at the cost of a state the bridge cannot restore. Reading the zones first to restore them later: no read method is among the five the bridge sends.
By: claude

## D-031 (2026-11-22): A press that waits for the layer also waits for the pad to be free, half a second at most

Decision: A press that needs a fresh reading of the layer is taken up by a run-loop timer. While the bridge is in another conversation with the pad the timer comes back every 10 ms, at most 50 times, then reads the layer and acts. After the 50th time it acts by the last reading.
Why: The wait used a main-queue block. It ran inside the wait for another answer from the pad, where the reading is skipped, marked the old reading fresh and acted by the layer from before the tap. The fake pad answered at once, so no test saw it; a second model's review pointed at it.
Consequence: A tap followed by a press during a light write or a status read goes by the new layer. DaemonLayerTests has a slow fake pad and a test that fails without the wait. The bench waits for Daemon.isSettled instead of a fixed time. A press can act up to half a second late when the pad is slow to answer.
Rejected: Waiting without a limit: a pad call can take 10 s, and a key that types acting 10 s late could land in another app. Dropping the press after the limit: the rule so far is that a failed reading leaves the last one standing.
By: claude

## D-032 (2026-11-22): A visit to a layer passes the pad, and both apps use layer 1's keys

Decision: `layers` keeps its shape and changes its meaning. Coming to a layer in `layers` from another layer is a visit: it gives that layer's app the pad, and the next visit takes it back. In between that app has the pad on layer 1, whatever is in front. The app must be open to get the pad, quitting it gives the pad back, and a pad that disconnects and comes back stays with whoever had it. A notification says each change (under `layerWarning`). The press wait of D-031 is removed. While the pad is off layer 1 and would be held there, the bridge reads the layer five times a second, for 10 s at most.
Why: The Codex keys exist only on layer 1, and Work Louder Input offers none for other layers. So D-028's rule, layer 2 is ChatGPT's, could never work: on layer 2 the pad sends neither app a key message. The owner chose two taps over looking into profiles. A press only ever comes from layer 1, so reading the layer at press time says nothing about a visit; that is why D-031's wait went.
Consequence: Who has the pad lives in the daemon, not on the pad: a restart of the daemon gives the pad back to the bridge. A visit shorter than the one-second reading goes unseen, so the notification is the sign to tap back. With more than one app in `layers`, the layer you pause on picks the app; that is thought through, not tested on a pad with three layers. The fake pad now sends keys from layer 1 only, as the real pad does. Replaces the layer ownership of D-028 and all of D-031.
Rejected: A second profile for ChatGPT: learning what a profile holds means writing to the pad, and switching profiles from the pad needs profile keys on layer 2. Handing over on the return to layer 1 instead of on arrival: the notification would come after the second tap, too late to say the visit was seen. Forgetting who has the pad when the pad disconnects: a loose cable would take the pad from ChatGPT without a tap.
By: owner (two taps over profiles), claude (the design)

## D-033 (2026-11-22): Send takes the Claude app's suggestion with Tab

Decision: A new action, complete:<box>, fills the focused box with its suggestion before Return. Grey text the box exposes is typed in. In the Claude app, which exposes none, an empty box with no hint gets Tab, and the step checks the box filled; if Tab left the box it moves back and stops the press, and blank space is taken out. The Claude app's CODEX is complete:Prompt then Return; every other app keeps Return.
Why: The owner wanted Send with nothing typed to take the grey suggestion, as Tab then Return does by hand. The app keeps the suggestion's text away from accessibility; the only sign is that the box's hint disappears, and that also happens without a suggestion, so the step checks what Tab did.
Consequence: Send in the Claude app presses Tab when the box is empty and hintless. A user config with its own CODEX keeps it and gets no suggestion step. The log records lengths, never the suggestion's text.
Rejected: Sending the box's hint text (a new session's hint would go out as a prompt). Doing it in terminals: the bridge cannot see a terminal's prompt, so Tab would be blind and completes file names when text is typed; the owner chose the Claude app only.
By: claude

## D-034 (2026-11-22): With the pad's keys on its layers, the layer says who has the pad

Decision: A new setting, `layerKeys`, says the pad has the Codex keys on every layer in `layers` as well as on layer 1. Then there are no visits: every reading of the layer says who has the pad. On a layer in `layers` it is that layer's app while the app is open. On layer 1, and on that layer while its app is closed, it is the bridge, which acts on that layer's keys and holds the pad there too. While an app in `layers` is open the daemon reads the layer four times a second. The two-tap visit of D-032 stays the default, for a pad as it ships.
Why: The owner wanted one tap, and turned down two taps and key chords. The touch sensor has no setting, no host method sets the layer, and a tap sends no event (Work Louder Input 1.1.0 and its device kit, read on 2026-11-22). But Input imports a profile whose layer 2 repeats layer 1's Codex keys, although its window offers none there, and on firmware 0.6.3 the pad sends the same key messages from layer 2. So a layer can be an app's after all, which D-032 took to be impossible.
Consequence: One tap changes who has the pad: within a quarter second for the bridge, and within 10 s for ChatGPT, which retries opening a held pad every 10 s (8 s and 9 s on the owner's pad). Who has the pad now lives on the pad, so a restart of the daemon changes nothing. A key message carries no layer, so only the reading tells the layers apart, and a press in the quarter second after a tap can go to the wrong app. While another app has the pad it hears the bridge's readings; ChatGPT logs a warning for each. The owner's pad runs a second profile, One tap, made with Input's own export and import; the first profile is untouched and backed up.
Rejected: Patching the firmware, or writing the pad's key map file from the bridge: fs.* is outside the five methods the bridge may send. host.focused_app, which lets the pad pick a layer by the app in front: that is the app-in-front rule again, and not one of the five methods. Reading the layer once a second: a press right after the tap back would reach ChatGPT. Dropping the two-tap rule: a stock pad has no keys on layer 2.
By: owner (one tap, and the yes to the profile), claude (the design)

## D-035 (2026-11-22): ChatGPT's wait after a tap stays

Decision: After a tap to its layer ChatGPT needs up to 10 s to get the pad, and the bridge does nothing about it. The bridge keeps holding the pad on its own layers, which is what shuts ChatGPT out. ChatGPT moves to layer 3 once Orca has layer 2 (the issue "Orca on a layer of its own").
Why: The wait is ChatGPT's own: it tries a held pad every 10 s. The owner uses ChatGPT little now and said the fix is not worth its cost.
Consequence: One tap to ChatGPT's layer takes 8 to 10 s to count; the tap back takes a quarter second. The README says so. A layer the bridge drives itself, as planned for Orca, has no such wait.
Rejected: Rebuilding the bridge's own layer on plain keyboard keys, so ChatGPT is never shut out: about half a day, the stick would probably lose its push-farther-scroll-faster, ChatGPT's light writes could flash over the bridge's, and the root helper would change. macOS shows the pad's keyboard as a device apart from the Codex channel, so it is possible in principle; not tested. Waiting for OpenAI to shorten the retry: not ours to do.
By: owner

## D-036 (2026-11-22): Public and posted before the signed download

Decision: The repo goes public now, and the LinkedIn and Reddit posts go out right after, before the Apple Developer ID build exists. The README and both posts say to build from source.
Why: The owner asked for it on 2026-11-22: the bridge works on their desk and they want it seen now. The plan had every post after the signed download (Phase 4 after Phase 2), and that download waits on the Apple membership.
Consequence: First visitors need Xcode or the Command Line Tools to build it. The demo video and the install test on a fresh account are still open on the day of this entry. Show HN and the letter to Work Louder stay where the plan had them, after the download.
Rejected: Waiting for the notarized zip first: it adds days of waiting on Apple before anyone sees the project.
By: owner

## D-037 (2026-11-22): The public repo takes the name micro-bridge

Decision: On 2026-11-22 the private repo was renamed micro-bridge-private and stays private, as the archive. A new public repo took the name micro-bridge. It holds one commit, 454e7ee, with the files of main as they stood after pull request 2.
Why: The README, the plugin and the site already link that address, so no link changed. The owner picked it when asked.
Consequence: An old clone that still points at the old address now points at the public repo. The working folder on the owner's Mac was pointed at micro-bridge-private before the public repo was made, and no other clone was found on that Mac. The private history must never be pushed to micro-bridge: it carries the owner's email and a session id (D-016). Work for the public repo starts from its main. Issues do not move between repos, so the open ones were written again there.
Rejected: Calling the public repo MicroBridge and leaving the private name alone: no old address could reach the public repo, but two names that are easy to mix up, and links to change in three files.
By: owner

## D-038 (2026-11-22): Public commits carry the name on the owner's GitHub profile

Decision: The name on public commits is the one on the owner's GitHub profile, with that account's noreply address (D-017). The owner's Mac has another name in its git settings; that one stays on the private history.
Why: The owner picked it on 2026-11-22 when asked which of the two to use. The public repo sits under that profile.
Consequence: A folder that commits to the public repo sets user.name and user.email for itself before its first commit. The Mac-wide git name and email are not used there.
Rejected: The name in the Mac's git settings.
By: owner

## D-039 (2026-11-22): Copies of a pane count as one, and a pane move must leave the pane

Decision: Panes.next merges panes with the same top, bottom and left or right edge into the part they all cover, and skips any pane whose middle lies inside the pane the pointer is in. The pane walk goes into elements that scroll but are smaller than a pane.
Why: The Claude app's side pane reports hidden browser tabs at the widths the pane had before it was resized. pane:left from the web page went to a wider copy whose middle is in the same page, so the pointer never left it and the stick kept scrolling the page. A later layout had a copy that shared no edge, so merging alone was not enough.
Consequence: From a web page in the side pane, one push left reaches the chat. A pane hidden under another can still be a stop when its middle shows outside the pane the pointer is in. The message box, inside a small scrolling element, is now found by the walk.
Rejected: Asking accessibility which element is under each pane's middle (a hit test per pane, slower, and unproven on Electron web views). Taking the smallest pane at each point as the one on show (wrong when the pane on show is the wider one).
By: claude

## D-040 (2026-11-22): A tap on an Agent Key puts the pointer on the chat

Decision: A new action, pane:chat, moves the pointer to the middle of the Claude app's chat, the pane right above the box named Prompt. After jump it waits up to 3 s for that session to show. The Agent Keys' tap is now ack, jump, pane:chat.
Why: The owner asked that switching to a chat leave the pointer on it, so pushing the stick up scrolls the chat without a push right first. The Claude app scrolls only what is under the pointer.
Consequence: A tap moves the pointer when it is off the chat. It stays when it is on the chat already, when the user moved it since the press, and for a session in a terminal. A config with its own agentKeys press keeps it; the owner's got pane:chat added by hand.
Rejected: Moving the pointer inside jump itself (no way to turn it off). Picking the largest pane as the chat (a wide web page would win).
By: claude

## D-041 (2026-11-22): The socket gets its mode from chmod, not umask

Decision: SocketServer binds daemon.sock, then sets it to 0600 with chmod. It no longer changes the umask around bind.
Why: umask belongs to the whole process. Tests run in parallel in one process, and a folder another test made while the socket was being bound came out 0600, with no execute bit, so nothing could be written into it. ClaudeSettingsTests and PluginTests failed now and then with permission denied, here and on CI for PR 4.
Consequence: Between bind and chmod the socket has the usual mode for a moment, but it sits in the bridge's folder, which is 0700, so no other user can reach it. The test suite no longer fails at random.
Rejected: Rerunning CI until it passed (the race stays). Running the settings tests one at a time (hides the cause).
By: claude

## D-042 (2026-11-22): GitHub hides the owner's email; the push block stays off

Decision: On the owner's GitHub account "Keep my email addresses private" is on since 2026-11-22, and "Block command line pushes that expose my email" is off.
Why: With privacy on, a pull request merged on GitHub is authored with the noreply address. Before, GitHub's own merge of a pull request carried the owner's personal address. The push block came on with it and refused every push whose newest commit has that address, which is every personal repo on the owner's Mac. The owner turned the block off the same hour.
Consequence: The owner's GitHub profile shows no email. Pull requests on the public repo may be merged on GitHub. Nothing on GitHub's side stops the private history from being pushed to the public repo. The pre-push guard in the owner's working folder does that, and a fresh clone of the public repo has no private history to push.
Rejected: Both off: a merge on GitHub would show the personal address. Both on, with the personal git settings switched to the noreply address: it changes the identity of every personal repo for a risk the folder's guard already covers.
By: owner

## D-043 (2026-11-23): On Orca's layer an Agent Key holds one agent tab, put there by hand

Decision: On Orca's layer a key holds one agent tab, which for the owner is a chat. Only the owner puts a tab on a key: a hold on an empty key takes the agent in the workspace on screen, or the panel in Orca assigns it. A hold on a taken key frees it. Nothing else frees a key.
Why: The owner wants to choose what the six keys show in Orca, and keys that never change by themselves. A chat keeps its ID across /clear, so a key can hold the tab.
Consequence: Orca's layer does not follow sessions the way Claude's layer does. What is on each key is saved and survives a restart of the bridge and of Orca. A key can hold a tab that is closed (D-045).
Rejected: A key per worktree. Keys that follow the newest or busiest agents, as on Claude's layer.
By: owner

## D-044 (2026-11-23): With several agents in the workspace on screen, a held key flashes and the panel picks

Decision: When the workspace on screen has one agent, a hold on an empty key takes it. When it has several, the key flashes, the panel in Orca opens, and the owner picks the agent there.
Why: Orca tells a plugin which workspace is on screen, not which tab inside it (read from the plugin typings of Orca 1.4.271, not tried). A guess could put the wrong agent on a key.
Consequence: The several-agents case needs the mouse. On 2026-11-23 the owner's Orca had one agent in three workspaces, so it is the rare case.
Rejected: Stepping through the workspace's agents with the dial: exact and no mouse, about half a day more to build. Taking the agent last sent a message: a guess, and Orca does not report prompts a person types.
By: owner

## D-045 (2026-11-23): A closed tab's key goes dim, and a tap reopens the conversation

Decision: When the agent tab on a key closes, the key keeps it and goes dim. A tap reopens that conversation in a new tab in the same workspace, and the key holds the new tab. No message is sent.
Why: The key must not free itself (D-043). A dim key that reopens its conversation is a bookmark, not a dead key.
Consequence: Not proven for chats: Orca's plugin method that resumes a session is documented as opening a terminal. Check it on a signed-in chat before building on it.
Rejected: A dim key whose tap does nothing.
By: owner

## D-046 (2026-11-23): Orca's layer is built for Orca's chat, not for terminal agents

Decision: On Orca's layer the controls do in Orca's chat what they do in the Claude desktop app: Approve presses the chat's allow button, Decline presses deny, the dial steps question cards, the stick scrolls, and the wide key is hold-to-talk.
Why: The owner works in the Claude desktop app and in Orca's chat, and uses no terminal agents. The first draft of this layer copied the terminal behavior (Return, Esc, slash commands) and was wrong.
Consequence: A chat is not a terminal: Orca lists it as kind chat with a state and a fixed ID, and Orca's commands that jump to or type into a terminal do not reach it. The jump brings the chat's workspace forward and then picks the tab by its name on screen. The chat's permission prompt has not been seen yet.
Rejected: Terminal behavior on Orca's layer.
By: owner

## D-047 (2026-11-23): Layers are isolated: a layer's controls work only in that layer's app

Decision: On Orca's layer Approve, Decline, the dial, the stick and the wide key act only while Orca is in front. On Claude's layer they act only in the Claude app, and do nothing in Orca. A tap on an Agent Key still brings its app to the front. In apps that are neither, the pad's general actions are the same on both layers.
Why: The owner asked for layer isolation: the layer says which app the pad is for.
Consequence: This changes Claude's layer: today its controls act on whatever app is in front. With Orca in front on Claude's layer they will do nothing. The stick still scrolls a web page on either layer.
Rejected: Controls that always act on the app in front, with the layer changing only whose agents the keys show. Claude recommended it as less to remember, and the owner turned it down.
By: owner

## D-048 (2026-11-23): Orca's control settings live in the MicroBridge window and in the Orca panel

Decision: What each control does in Orca can be changed in the MicroBridge window, where Orca is one more app, and in the panel in Orca. The panel also shows the six keys and assigns agents to them.
Why: The owner chose both when asked to pick one.
Consequence: The config file stays the one place the settings are stored, and both screens read and write it through the bridge. Two screens must be kept in step.
Rejected: The window only, which is less to build. The panel only.
By: owner

## D-049 (2026-11-23): Orca is tried in a sandbox copy, not in the owner's working Orca

Decision: Orca work is tried against a second copy of Orca, started headless in Orca's own test mode with a throwaway data folder and a throwaway home folder. The owner's working Orca is touched only at a moment the owner picks.
Why: The owner asked for an instance apart from the one they work in. A plain second copy would share the home folder, where Orca keeps hooks in Claude's settings file.
Consequence: It starts with ORCA_E2E_USER_DATA_DIR, HOME set to the home folder inside it, and ORCA_E2E_HEADLESS=1; in this mode Orca refuses to start unless the home is the throwaway one. On 2026-11-23 the owner's Claude settings, ~/.orca, the orca command, the LaunchAgents and the Orca app were identical before and after. The sandbox has no Claude sign-in, so it shows no real permission prompt. With a window it stops on a macOS keychain dialog, so it runs headless only. It can still read the real home folder.
Rejected: A plain second copy of Orca. Signing in to Claude inside the sandbox: it meets the keychain dialog.
By: claude

## D-050 (2026-11-23): The bridge's own layers and their apps live in one setting, layerApps

Decision: A new setting, layerApps, maps a layer number to the apps it is for: app groups or bundle ids. Layer 1 is always the bridge's and starts as ["claude", "terminal"]. Any other layer listed there is one the bridge drives itself: the pad has its keys there, the bridge holds the pad and acts on them, and that layer has its own six Agent Keys. Orca's layer is {"2": ["com.stablyai.orca"]}. A layer the file leaves out keeps its apps, a layer cannot also be in layers, and an app belongs to one layer.
Why: D-047 needs to know which app each layer is for, and a layer the bridge drives for Orca is not a layer that passes the pad to an app, which is what layers means. One setting answers both: which layers are the bridge's, and whose they are.
Consequence: With only layer 1 listed, which is the default, nothing changes for anyone. On a second layer the six keys no longer show Claude's sessions, and a press there does not act on them. Until Orca's agents are built those keys hold nothing and stay dark. The window has no control for the setting yet.
Rejected: A group name as a value in layers, next to bundle ids: one setting would mean two things, pass the pad on or keep it. A switch per app (orcaLayer: 2): it would need a new setting for the next app.
By: claude

## D-051 (2026-11-23): Isolation stops every control but the Agent Keys, and only in another layer's app

Decision: While the pad is on one of the bridge's own layers, a key, the dial or the stick does nothing when the app in front belongs to another of those layers. That covers every action bound to the control, also lock, open and sh. An Agent Key is never stopped. An app on no layer, or nothing in front, gets the control's usual action on every layer. Terminals belong to Claude's layer.
Why: This is how D-047 reads in code. The owner said a layer's controls do nothing in the other layer's app, and nothing is simplest to predict. An Agent Key brings its own app forward, so stopping it would leave no way across from the pad. The terminal bindings are all Claude Code's, so a terminal is Claude's.
Consequence: On layer 1 with Orca in front, the dial's hold no longer opens the settings file and a key bound to lock does not lock. The log says each press that was stopped and why. The stick's push-to-scroll stops the same way.
Rejected: Letting actions that are not about the app in front (lock, open, sh) through in another layer's app: two kinds of control to remember, and D-047 says nothing.
By: claude

## D-052 (2026-11-23): With a second layer of its own the bridge reads the layer four times a second

Decision: While layerApps names a layer besides the first, the bridge asks the pad for its layer four times a second for as long as the pad is connected, as it already does with layerKeys while ChatGPT is open.
Why: The pad says nothing when a tap changes its layer, and the layer now decides whose six keys show and where the controls act. Read once a second, the first press after a tap would often go by the old layer.
Consequence: A tap takes up to a quarter second to count. The pad answers four small requests a second all day; over USB that showed no cost with layerKeys. Bluetooth is untried.
Rejected: Reading once a second: a press in the first second after a tap goes by the wrong layer. Reading on each press: the answer takes longer than the press.
By: claude

## D-053 (2026-11-23): A session of an Orca chat belongs to Orca's layer and is known by Orca's session ID

Decision: The Claude Code hook treats a session as an Orca chat when its environment has ORCA_AGENT_SESSION_ID and no ORCA_TERMINAL_HANDLE. It reports that session under Orca's session ID, for Orca's layer. Such a session never takes or waits for a key on Claude's layer.
Why: Tried in the owner's Orca on 2026-11-23: every chat fired the bridge's hook, and one took a key from a real Claude session. The ID in the chat's environment is the one orca agent list shows, and a chat keeps it across /clear, which is what a key on Orca's layer holds (D-043).
Consequence: Orca's layer gets working, needs-you and done from the same hook as Claude's layer, at once and without an Orca plugin or polling. The end of the session tells the bridge the tab closed. Until step 3 is built, Orca chats still take Claude's keys. Other agents in Orca's chat (Codex and the rest) report nothing this way.
Rejected: Reading the state word in the tab's name: only tabs on screen have one. Polling orca agent list for the state: slower, and a second source to keep in step with the hook.
By: claude

## D-054 (2026-11-23): A dim key ignores taps, and a hold frees it

Decision: When the chat on a key of Orca's layer is closed, the key keeps it and goes dim. A tap on a dim key does nothing. A hold frees the key, as on any taken key. This replaces the tap of D-045; the rest of D-045 stands.
Why: Orca has no way to reopen a closed chat as a chat. Tried on 2026-11-23 in the owner's Orca: the command line, the new-tab menu, the search and the menu bar offer none, and the plugin method agent.resume opens a terminal with the Claude command or refuses.
Consequence: A dim key only says that its chat was closed. To use the key again the owner holds it to free it and puts another chat on it. Nothing is started or opened by a tap on it.
Rejected: A tap that opens a new chat in the same workspace and puts it on the key: Claude recommended it, and the owner turned it down. Continuing the old conversation in a terminal: the owner uses no terminal agents (D-046).
By: owner

## D-055 (2026-11-23): The three-layer profile stays saved but not active until the Orca build is installed

Decision: Work Louder Input holds the profile "Three layers" (Claude, Orca, ChatGPT). The pad's active profile stays "One tap" until the build that knows Orca's layer is installed and the config names layer 3 as ChatGPT's. Then the profile, the build and the config change together.
Why: The installed build knows two layers. With three on the pad, the way back from ChatGPT to Claude would take two taps, and layer 3 would belong to no app. The owner does not want a second tap.
Consequence: Step 3's test on the pad starts with three changes at once: install the build, change the config, and set "Three layers" active in Input while MicroBridge is stopped. Until then the pad works as before. That a tap reaches layer 3 is still unseen.
Rejected: Leaving "Three layers" active now: it would prove the third layer sooner, but it changes the owner's daily tap before anything uses the new layer.
By: claude

## D-056 (2026-11-23): A hold on an empty key takes the chat whose tab shows in Orca

Decision: On Orca's layer a hold on an empty key reads the tabs of Orca's window and Orca's list of Claude chats, and takes the chat whose tab is the one showing, matched by title. With another kind of tab showing it takes the only Claude chat among those tabs. When that does not single out one chat (several chats and none showing, two chats side by side in a split view, two chats with one title, a chat already on a key) the key flashes red twice and the log says why. This refines D-044: the key flashes only when the window does not say which chat is meant.
Why: D-044 assumed Orca cannot say which tab is on screen. Its command line cannot, but its window can: the selected tab has its own class, seen in the owner's Orca on 2026-11-23. Most holds are made while looking at the chat, so most need no panel.
Consequence: A hold needs Accessibility and Orca's command line, and takes about a third of a second. Tabs carry no ID, so the match is by title: a chat renamed between the two readings is missed once, and two chats with one title cannot be told apart. The panel of step 4 still picks in the unclear cases.
Rejected: Flashing whenever a workspace has more than one agent, as D-044 said: it would send the owner to the panel for the common case. Taking the chat that reported last: it is often not the one on screen.
By: claude

## D-057 (2026-11-23): A chat's key goes dim only when Orca says its tab is closed

Decision: When a chat's Claude process ends (the hook's SessionEnd, or the process found dead), the bridge asks Orca a moment later whether the chat still has a tab. Only with no tab does its key go dim. With a tab the key stays lit and idle. A tap on a dim key asks Orca once more: if the tab is open again the key lights and the tap counts, otherwise the tap does nothing, as D-054 says.
Why: A process ending is not the tab closing. Orca keeps a chat's tab while its process is gone, and after a restart of Orca the tab is back before the chat says anything. Dimming on the process alone would dim keys of chats that are still open, and D-054 would then make those keys dead to taps.
Consequence: A closed tab dims its key about a second later, after one call to Orca's command line. If Orca cannot be asked, the chat counts as closed until it reports again or a tap finds it open. A key can show idle for a chat that sleeps.
Rejected: Dimming as soon as the process ends: wrong for a sleeping chat. Never dimming until a tap fails: the owner asked for the dim key as the sign that a chat was closed (D-045, D-054).
By: claude

## D-058 (2026-11-23): The hook sends nothing for /clear in a chat, and nothing from a Claude Code started inside a chat

Decision: For a session with Orca's chat ID in its environment, the hook sends no end when SessionEnd gives the reason clear, and sends nothing at all when the Claude Code it runs under was itself started by another Claude Code.
Why: D-053 names a chat by Orca's ID, which it keeps across /clear: an end there would dim a key whose chat is open. A command that a chat's session runs (claude -p, a nested agent) inherits the chat's ID in its environment, and its reports would light, clear or end the chat's key.
Consequence: Whether a Claude Code is nested is read from its ancestors: more than one Claude Code among them. Outside Orca both cases report as before.
Rejected: Telling the chat's own process apart by its process ID: the daemon would have to know the chat's first process, and a chat gets a new one after a restart.
By: claude

## D-059 (2026-11-23): On Orca's layer the hold is built in, and a tap shows the chat by workspace and tab title

Decision: On Orca's layer a hold on an Agent Key always takes a chat or frees the key, whatever agentKeys.hold says, and there is no double tap. A tap runs agentKeys.press with the key's chat: ack clears what it finished, jump shows it, pane:chat is skipped. To show a chat the bridge asks Orca where it is open, brings Orca forward, runs orca worktree activate for the chat's workspace, then presses the tab with the chat's title in Orca's window, looking for it for up to 3 seconds.
Why: The keys are filled by hand (D-043), so the hold cannot be left to a setting that means forget on Claude's layer. Orca's command line can bring a workspace forward and cannot select a tab; the tab press was proven in the owner's Orca in step 2, and the activate call in the sandbox copy on 2026-11-24 (UTC): it put the named workspace on screen, did nothing when it already was, and failed cleanly for an unknown one.
Consequence: A jump takes about half a second and needs Accessibility. A split view is read across all its tab strips. With two tabs of one title the first is pressed. A folder workspace cannot be activated from the command line: the tab is still pressed when its workspace is the one on screen.
Rejected: Making the hold configurable per layer: one more setting for a gesture that has one meaning there. Selecting the tab by its position: tabs move.
By: claude

## D-060 (2026-11-23): Orca is in the built-in config as an app group, with Approve and Decline, and on no layer

Decision: The built-in config has the app group orca (com.stablyai.orca), and APPR and REJ have an orca entry that presses Allow and Deny on a chat's permission card. Orca gets a layer only when the owner's file names it under layerApps. The daemon's socket takes orca.take, orca.free and orca.show for a key of Orca's layer, and micro orca prints what the bridge sees of Orca.
Why: A layer needs the pad's keys on it, which only the owner can set up, so no default can give Orca one. The group and the two buttons are safe everywhere: they do nothing until Orca is in front. The socket commands are what the panel of step 4 will call, and they let the keys be tried without a finger on the pad.
Consequence: Every command now lists a third place, In Orca, in the MicroBridge window. A config file that sets APPR or REJ itself replaces the whole command and needs the orca entries added by hand. The keys are saved in orca-keys.json with Orca's IDs and states only.
Rejected: A key fallback such as Return for Approve in Orca: with no card on screen it would send the message being typed.
By: claude

## D-061 (2026-11-23): The README is a front page, and the manual lives in docs/

Decision: The README opens with the pad's picture, the lights, the controls and the install commands. Long material is folded into details sections or moved to docs/ word for word: the ChatGPT sections are in docs/chatgpt.md. Nothing is removed, and the heading the website links to stays in the README with a short version under it.
Why: The owner said the README looked like a word dump. The first screen is where a visitor finds out what the project does and how to install it. The long sections serve people who already use it.
Consequence: New long material goes to docs/, with a short version and a link in the README. A change to a moved section is made in docs/chatgpt.md. This was decided and built in the website's session (pull request 6, merged on main as e462d71) and is logged here so the numbers stay in one order.
Rejected: Removing the long material from the repository.
By: claude

## D-062 (2026-11-23): The bridge's Orca commands always go to this machine's Orca

Decision: When the bridge runs Orca's command line it removes ORCA_ENVIRONMENT and ORCA_PAIRING_CODE from the environment, so the command talks to the Orca on this Mac, wherever the bridge was started from.
Why: The bridge reads the tabs of this Mac's Orca window and hears the hook of chats on this Mac. A shell that points Orca's command at another machine would make the bridge list that machine's chats and press tabs here that belong to none of them.
Consequence: Chats on a paired Orca on another machine cannot be put on keys. A bridge on that machine has to do it there.
Rejected: Following the shell's Orca environment: the list of chats and the window would then be from two machines.
By: claude

## D-063 (2026-11-23): The socket lists Orca's chats, and a key remembers its chat's title in memory only

Decision: The daemon's socket takes orca.chats and answers with Orca's open Claude chats (session ID, title, status, workspace). The daemon keeps the title of each chat that is on a key in memory and gives it in the state answer; orca.chats refreshes it. Titles are not written to orca-keys.json and not to the log.
Why: The window and the panel need a list to choose a chat from, and a key whose chat is closed can only be named by a title the bridge kept, because Orca no longer lists that chat. D-060 keeps Orca's IDs and states only on file, and that stays true.
Consequence: After the bridge restarts, the key of a closed chat shows the start of its ID until it is freed. The keys of open chats get their titles back with the next orca.chats. Anyone who can use the socket (the owner's account) can read the titles.
Rejected: Keeping titles in orca-keys.json: it would put what Orca's window shows on disk, against D-060. Asking Orca from the window itself: the window would then need Orca's command line and a second copy of the bridge's rules.
By: claude

## D-064 (2026-11-23): The window gives Orca layer 2 with one switch, and ChatGPT's layer moves to 3

Decision: The Behavior screen has a switch 'Orca's chats have a layer of their own'. On, it writes layerApps.2 = [orca] and moves a ChatGPT entry from layers.2 to layers.3. Off, it removes Orca's layer and moves ChatGPT back to layer 2. The ChatGPT switch takes the first layer from 2 that the bridge does not drive. The Pad screen draws the six keys of the layer the pad is on, and lists Orca's keys with Show, Free and a menu that puts a chat on an empty key.
Why: A layer is the bridge's own or another app's, not both (the config check refuses the mix), so the old ChatGPT switch, which always wrote layers.2, would clash with Orca's layer. The owner asked for layers kept apart: Claude on 1, Orca on 2, ChatGPT on 3.
Consequence: The window writes only layer 2 for Orca. A file that gives layer 2 to other apps by hand is left alone and the window says so. The pad's profile in Work Louder Input still has to have that many layers, which only the owner can set there.
Rejected: Letting the owner pick any layer number in the window: more to explain, and the file still allows it by hand.
By: claude

## D-065 (2026-11-23): The bridge changes a command in the config file for the panel in Orca, by the window's own rule

Decision: The daemon's socket takes commands (what each command does in one app group, with the controls that run it) and command.set (set what a command does on one trigger in one app group). command.set changes the config file with ConfigFile.setCommand, the same function the MicroBridge window now calls, checks the result with Config.parse, keeps the file from before as config.json.before-app once, writes it and reloads. It refuses an unknown command, an action the bridge does not know, a command that runs a command, and a file that is not JSON. The names of commands and controls moved from the window's code into MicroKit so both screens use one list.
Why: D-048 puts Orca's control settings in two screens with the config file as the one store, read and written through the bridge. A panel in Orca cannot read files, and its worker should not carry a second copy of the file's rules. One function for both screens keeps them in step.
Consequence: The bridge now writes the config file, where it only read it before: for commands only, and only when asked over its socket, which is open to the owner's account alone. The panel sets what a command does in Orca; every other setting stays in the window and the file.
Rejected: A general config.set by path over the socket: more than the panel needs, and it would let any setting be written without the window's checks. The plugin's worker editing the file itself: a second copy of the rules, in another language.
By: claude

## D-066 (2026-11-23): The panel in Orca is a plugin in this repository whose worker asks the bridge over its socket

Decision: The panel is an Orca plugin in orca-plugin/ (id microbridge, execution trusted-worker, no Orca capability). Its panel draws the six keys and the commands; its worker, a Node process, sends one JSON line to the daemon's Unix socket for each thing the panel asks: state, orca.chats, orca.take, orca.free, orca.show, commands, command.set. While a panel is open the worker asks the bridge every 1.5 seconds and tells the panel when something changed. The plugin stores nothing and logs no chat title. Orca's generated typings (.orca/) stay out of the repository. scripts/test-plugin runs Orca's validate, test and check on it.
Why: A panel in Orca can reach only its own worker, and a worker runs with the owner's account, so the worker is the one part that can reach the bridge. The bridge already holds the keys and checks every config change, so the plugin needs no state and no copy of the rules. Keeping it in this repository keeps the socket protocol and its one other user in one place.
Consequence: The plugin needs MicroBridge running on the same Mac. Loading it asks the owner to approve a worker that runs code with their account. It cannot open itself when a key flashes: Orca gives a worker no way to show its panel, so the unclear hold of D-044 still flashes the key and the owner opens the panel. It has been tested with Orca's plugin tools and not yet inside a running Orca.
Rejected: An HTML panel that talks to the socket itself: a panel has no network, socket or file access. A worker that reads Orca's own agent list to fill the keys: the bridge's list comes from the same Orca and a second list could disagree. A separate repository for the plugin: two places to change for one protocol.
By: claude
