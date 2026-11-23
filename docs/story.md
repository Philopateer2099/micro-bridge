# Story

The decisions in decisions.md, retold for people as chapters, one problem each. Newest last. decisions.md is the record: agents read and cite it, not this file.

## 1. Never save half a command

Decisions: D-001 to D-004

The bridge reads its config file within a second of any change. That is great for trying things, and risky for a settings window. If the window saved on every keystroke, a half-typed shell command would sit on a live key. `sh:rm` is a valid action long before you finish typing what comes after it.

So nothing you type is saved until you press Return or Save. Choices that need no typing, like picking a command from a menu, save at once. Three smaller rules came from the same worry, that the file could end up meaning something you did not intend. A key with its own actions is always written as a full set of triggers. An app with no actions left falls back to "Everywhere else". And a command cannot be deleted while a key still runs it.

Cost: One more click for every typed change. A draft is lost if the window quits.

## 2. The drawing looked wrong

Decisions: D-005 to D-008

The first drawing of the pad had the dial on the wrong side, the stick in the wrong corner and a dark body. I said it looked wrong. Claude redrew it from OpenAI's public help page and shop photos: a white plate with the controls in their real order, and a test that pins that order.

The same day I opened the Codex app's own Micro settings page and asked for the window to follow it. That page draws a flat diagram, not the hardware. So the window switched to the diagram, and the white pad moved to the app icon and the website, where it tells a visitor which device this is.

Turning point: D-007 replaced the look of D-005 within hours. The order of the controls survived. The white plate did not.

Two rules about color came out of this. The window's chrome is grey, because the pad's five status colors carry meaning, and a blue selection next to a blue "working" key reads like a sixth status. And a key is changed in a dialog with a Save button, because one stray click should not rebind a key.

Cost: Every new screen takes its colors from one theme file. A new use of the accent color needs a reason of its own.

## 3. A locked Mac keeps the keyboard to itself

Decisions: D-009 to D-012

The Codex page has a switch that turns the pad's lights off when the Mac locks, so the bridge got one too. It listened for the lock notice from macOS and turned the lights off.

Then I tested it. From the moment the Mac locked, macOS refused every write to the pad, and the refusals started before the lock notice arrived. The pad's light channel is part of its keyboard interface, and a locked Mac keeps keyboards to itself. On top of that, the bridge read each refusal as a lost pad and reopened it every second.

Turning point: D-010 took the switch out. Now the bridge keeps the pad open when macOS refuses, leaves the lights alone, and tries again every 2 seconds.

The way back in was timing. If the lights have to be off before the lock starts, the bridge has to see the lock coming. First came a LOCK command on the pad: lights off, wait for the pad to confirm, then lock. But I lock with ⌃⌘Q, not with a pad key. So the bridge now catches exactly ⌃⌘Q, turns the lights off, and sends the shortcut again with a mark it lets through, 2.5 seconds later at most. If no lock follows within 5 seconds, it stops catching the shortcut and shows a notification.

Turned down: A root helper that writes to the pad while the Mac is locked. It would get around a macOS protection, and this project does not do that.

Cost: Touch ID and the Apple menu still lock with the lights on. While the setting is on, the bridge sees every key press, and reads only the key code, the modifiers and its own mark.

## 4. Claude scrolls only what is under the pointer

Decisions: D-013 to D-015

The stick should scroll the chat. The first tries sent scroll events straight to the Claude app: with the window's number, in lines, in pixels, with gesture phases. The chat did not move. A scroll posted at the system level did scroll it, but dragged the pointer along. Only a scroll at the pointer's own position worked without moving it.

So the stick scrolls whatever is under the pointer, faster the farther it is pushed. That made the pointer part of the interface, so stick left and right now move the pointer to the next pane, with a real mouse move so hover states stay right. Decline changed too. I read Approve and Decline as the next-step box's first and second buttons, so Decline now picks the second choice instead of closing the box.

Cost: The pointer has to be over the chat to scroll it. A box with two choices can no longer be closed from the pad.

## 5. Getting ready to go public

Decisions: D-016 to D-025

Seven of this chapter's ten decisions are mine. The private history has a personal email on every commit and a real session id in the first one. Rather than rewrite history, the public repo starts from one fresh commit, with my real name and GitHub's noreply address. The private repo stays as the archive.

Downloads wait for an Apple Developer ID, so macOS does not warn people away and keeps their permissions across updates. The license stays MIT. Posts like this one live on my portfolio, not on a second site I would have to keep up. A downloaded app sets itself up through a command or a Claude Code plugin, so the window never writes Claude's settings file, and it starts at login through macOS's own Login Items.

Claude's three calls were about shipping without surprises. Release builds and the test zip use the same hardened runtime, so testing the zip tests what people download. The site's deploy job waits, skipped rather than failing, until I switch Pages on. And CI scans every change for home folder paths, email addresses, session ids and keys. It does not search for my own email, because the script is public and would publish exactly what it guards.

Cost: The public repo has no history before its first commit. The decision log and the development log carry the story instead.

## 6. Sharing the pad with ChatGPT

Decisions: D-026

The pad ships working with ChatGPT, and both apps can talk to it at once. The clean fix would be to take the pad for Claude alone while Claude is in front. macOS refuses that for an ordinary app.

I chose "whoever is in front drives the pad". While ChatGPT is in front, the bridge writes no lights and acts on no key. When another app comes to the front, it repaints at once, and it paints over ChatGPT's light changes at most once a second.

Still open: ChatGPT still hears every key while Claude is in front. What it does with them is not known yet.

## 7. ChatGPT kept listening from the background

Decisions: D-027

Stepping aside while ChatGPT is in front was not enough. ChatGPT still acted on every press while Claude was in front, and it has no setting to stop that. I had asked Claude to fix that part, and it had not said plainly that it couldn't.

Turning point: a one-off test showed that root can take the pad for itself, while my own account cannot. The project had a rule against root helpers. I lifted it for this one program and said build it.

Claude built MicroBridge Helper: a small separate program that runs as root and holds the pad only while ChatGPT is behind another app and the pad is on its first layer. It writes only the five allowed methods, serves only my account and only MicroBridge signed with the same certificate, and lets go the moment MicroBridge hangs up. On the pad, ChatGPT went silent while Claude was in front, and picked the pad back up 3 seconds after it came to the front.

Turned down: running the whole bridge as root, and Apple's helper-install APIs, which need a paid developer team.

Cost: installing takes my password and adding the helper to Input Monitoring by hand, since a root program cannot add itself. A helper started before the switch was on stayed refused until it restarted, so it now restarts itself. The first keystroke after a layer change while held is lost.

## 8. Two taps to pass the pad

Decisions: D-028 to D-032

"Whoever is in front" never worked for ChatGPT. It retries the pad every 10 seconds, and I only brought it forward for a second or two. I asked for a switch on the pad itself: a tap on the touch sensor should say who drives it, so I can hand layers to other apps such as Orca later.

Claude gave layer 2 to ChatGPT. On layer 2 the bridge let go, and on layer 1 it kept the pad. I tried it and called it super buggy, then said layer 2 did not work at all. I asked whether it had been checked properly first. It had not: the daemon had no tests, because it talked to the real pad directly. Claude put the daemon behind a seam so tests could run it on a fake pad. A second model's review then found two real faults: the bridge turned off lights it could never turn back on, and a press during a busy moment went by the old layer.

Turning point: I asked Claude to drive the live test itself. Its first step was to put the Codex keys on layer 2 in Work Louder Input. That step does not exist. The Codex keys live only on layer 1, and Input offers none for other layers. On layer 2 the pad tells nobody anything, so "layer 2 is ChatGPT's" could never have worked. The fake pad had sent keys from every layer, which hid it.

I picked two taps instead. Both apps use layer 1's keys. A tap to layer 2 and a tap back hands the pad to ChatGPT, and the same two taps take it back. A notification says who has it. On the real pad it worked: ChatGPT got the pad and moved between ten conversations on my key presses while the bridge stayed quiet. Then the bridge took the pad back and held it within a second.

Turned down: a second profile for ChatGPT, which would have meant writing to the pad. Forgetting who has the pad when the cable drops.

Cost: a visit shorter than a second goes unseen, so I wait for the notification. After the pad sits on layer 2 for more than 10 seconds, a press within a second of the tap back can reach both apps. Opening Work Louder Input most likely updated my pad's firmware from 0.6.1 to 0.6.3 without asking.

Still open: a third app such as Orca on a third layer. It is thought through, not tried.

## 9. Send takes the suggestion

Decisions: D-033

I wanted Send on the pad to do what Tab then Return does by hand. With nothing typed, it should take the grey suggestion in the Claude app's message box and send it.

Claude looked for the suggestion's text in the app's accessibility tree first. Seven presses on the pad found nothing. The app keeps that text to itself. The only sign of a suggestion is that the box's hint goes away, and the hint also goes away without one.

Turning point: MicroBridge stopped trying to read the suggestion. When the box is empty and shows no hint, it presses Tab and checks what Tab did. If the box filled, Return sends it. If Tab moved the focus out of the box, it moves back and stops the press. If Tab typed blank space, it takes it out. On the pad it worked: my "Done, check it" was a suggestion the pad sent.

Turned down: sending the hint text, since a new session's hint would go out as a prompt. Doing it in terminals, since the bridge cannot see a terminal's prompt and Tab there completes file names. I chose the Claude app only.

Cost: a config with its own Send key keeps it and gets no suggestion step. The log keeps lengths, never the suggestion's text.

Still open: the two safety steps, Tab leaving the box and Tab typing blank space, have not happened on a real box yet.

## 10. One tap instead of two

Decisions: D-034, D-035

The two taps worked and I did not like them. Tap, wait for a notification, tap again. I wanted one tap, so I asked Claude whether the touch sensor itself could be changed.

It could not. The sensor has no setting. No command from the Mac sets the layer. A tap does not even send an event. The rule that a tap goes to the next layer is in the pad's firmware, and I was not going to patch firmware.

Turning point: What a tap lands on could be changed. Work Louder Input shows no Codex keys for a second layer, but it imports a profile file that has them. Claude exported my profile, copied layer 1's keys to layer 2 in a copy, and imported the copy as a second profile. The pad sent the same key messages from layer 2. So the layer itself can say who drives: ChatGPT on layer 2, MicroBridge on layer 1.

I tried it on the pad. One tap worked both ways.

Cost: Going to ChatGPT takes 8 to 10 seconds. MicroBridge shuts ChatGPT out while I am on my own layer, and ChatGPT only tries the pad again every 10 seconds. Coming back takes a quarter second.

Turned down: A rebuild that never shuts ChatGPT out, with plain keyboard keys on my layer. About half a day of work, and the stick would probably lose its speed control. I barely use ChatGPT now, so the wait stays.

Still open: Orca on layer 2, with ChatGPT moved to layer 3.

## 11. Going public

Decisions: D-036 to D-038

The bridge worked on my desk and I wanted people to see it. The plan said to wait: first a signed download from Apple, then the posts. I did not want to wait days on a membership check. So LinkedIn and Reddit moved forward, and the posts say to build from source.

Then the repo itself. The private history has my email on every commit, so the public repo starts from one clean commit, as planned. It needed a name. Every link in the README, the plugin and the site already pointed at micro-bridge. So the public repo took that name and the private one became micro-bridge-private. The commit carries the name on my GitHub profile and GitHub's noreply address.

Turning point: the clean copy passed the scan for private data, and git's hash said its files were the same as main's. After that the push was a small step.

Cost: an old address now leads to the public repo, so the private history must never be pushed there. The first visitors have to build it themselves. A test failed at random twice that day and Claude could not find why in ten minutes. It is filed as an issue, not hidden.
