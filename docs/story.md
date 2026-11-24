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

## 12. The stick finds the chat

Decisions: D-039, D-040

The stick scrolls whatever is under the pointer. With a web page open beside the chat, I scrolled the page, pushed left to get back to the chat, and the pointer did not move. I was stuck in the page. And every time I switched sessions with an Agent Key, I had to push right before the stick would scroll the chat.

Claude read the log and asked the window what it holds. The side pane reported its web page three times: two hidden browser tabs had kept the sizes the pane had before I made it narrower. A push left went to a wider copy, and its middle was still inside the page. Every push landed on the same spot.

Turning point: one rule fixed the first layout and missed the next. Copies with the same edges now count as one, but after I resized again a copy shared no edge. So a move must leave the pane the pointer is in, or it is no move.

For switching, a tap now puts the pointer on the chat once the session shows. The chat is the pane right above the message box. Finding the box took a second try, because it sits inside a small element that scrolls, and the walk stopped at those.

Turned down: asking for the element under each pane's middle, slower and unproven in this app. Making the jump itself move the pointer, which could not be turned off.

Cost: a tap moves the pointer, and a config with its own Agent Key line has to add pane:chat by hand. Mine did.

Still open: the 3 second wait for a slow session to show has not run out yet.

## 13. The first hours in public

Decisions: D-041, D-042

The repo had been public for less than an hour when its first pull request went red. One test of 276 failed with "permission denied", in a folder the test had made a moment before. The same failure had shown up twice on my Mac that day, about once in fourteen full runs. Claude had filed it as an issue with the cause unknown.

Claude suspected the file mask. It is one setting the whole process shares, and it decides the permissions of new files and folders. Claude tested thirteen system calls, found nothing, and reported that our code never touched the mask. That was wrong. A second Claude session, working on the stick in the same folder, had already found it: the socket code set the mask for an instant while it bound the socket. A folder another thread made in that instant came out unwritable. Claude's search had read the folder with that session's fix already sitting in it, so the call looked absent. The fix is small: bind, then give the socket its mode with chmod. A probe showed the difference: 16,558 of 40,000 folders unwritable before, none after.

The same hour I had Claude make GitHub hide my email. GitHub's own merge of a pull request had put my personal address on the merge commit, and the privacy switch stops that. GitHub switched on its push block along with it, and the block refused pushes from every other repo of mine. I asked whether there was a reason for any of this. For the block there was none, so it went off again.

Turning point: the red run on GitHub's own machine. Until then the failure could have been my Mac or Claude's shell.

Cost: my GitHub profile shows no email now. Nothing on GitHub's side keeps the private history out of the public repo. A guard in my working folder does that.

## 14. Orca, talked through first

Decisions: D-043 to D-049

I wanted Orca on the pad, but not the way Claude is. In Claude the keys follow my sessions by themselves. In Orca I want to put each agent on a key myself, and I want it to stay there until I take it off. So before any code we talked it through, one question at a time.

A key holds one agent tab. I put it there with a hold on the pad or from a panel in Orca, and only I can free it. If the workspace I am looking at has several agents, the key flashes and I pick in the panel, because Orca cannot say which tab I am looking at. If I close a tab, its key goes dim, and a tap brings the conversation back.

Turning point: Claude first designed the controls for agents in a terminal, because the one agent open in my Orca that day ran in one. I do not use terminals. I use the Claude desktop app and Orca's chat, so the controls in Orca's chat do what they do in the Claude app. I also turned down Claude's advice on layers. I want them isolated: on Orca's layer the controls work in Orca, on Claude's layer in the Claude app, and other apps get the same general actions on both. The settings go in both places, the MicroBridge window and the Orca panel.

Cost: this is a bigger build than one more app in a list, and Claude's layer changes too. Nothing is proven on a real Orca chat yet. The permission prompt is unseen, and reopening a closed chat is untested. To look without touching the Orca I work in, Claude started a second copy in Orca's own test mode with a throwaway home. It runs without a window. It has no Claude sign-in, and with a window it stopped on a keychain dialog, so the real prompt will be checked in my own Orca when I say so.

## 15. Two layers that stay apart

Decisions: D-050 to D-055

I asked for layers that stay apart: Claude on one, Orca on another. To build that, the bridge first had to know which apps belong to which layer. That is one new setting, layerApps. Layer 1 is Claude's and the terminals'. Any other layer named there is one the bridge drives itself, with six Agent Keys of its own. Orca's layer is layer 2.

Then the rule I asked for. While the pad is on one of these layers, a key, the dial or the stick does nothing when the app in front belongs to the other layer. An Agent Key is never stopped, because it brings its own app forward and is the way across from the pad. An app on no layer gets its usual action on both layers. The pad says nothing when a tap changes its layer, so the bridge now asks it four times a second.

Turning point: Claude tried the hook in my own Orca and found that every Orca chat already fired it. One chat took a key from a real Claude session. So a chat is now known by Orca's own ID, which is in the chat's environment, and it belongs to Orca's layer. It never takes a key on Claude's layer. The same hook now tells Orca's layer working, needs-you and done, with no plugin and no polling.

Turned down: in the talk before, a tap on a dim key was to bring a closed chat back. Claude looked for a way in my Orca: the command line, the new-tab menu, the search, the menu bar and the plugin method. None of them reopens a closed chat as a chat. So I decided that a dim key ignores taps and a hold frees it.

Cost: a tap that changes the layer takes up to a quarter second to count, and the pad answers four small requests a second all day. On Claude's layer with Orca in front, the dial's hold and a key bound to lock do nothing now. The pad's three-layer profile had to wait in Work Louder Input, saved and not active, until the build that knows Orca's layer was installed, so that the profile, the build and the config changed together.

## 16. Chats on keys, by hand

Decisions: D-056 to D-060

With the layer in place, the keys of Orca's layer had to be filled, shown and freed by hand.

A hold on an empty key takes the chat I am looking at. We had assumed Orca cannot say which tab is on screen. Its command line cannot, but its window can. So the bridge reads the tabs of Orca's window and matches the one showing to Orca's list of chats, by title. When that does not single out one chat, the key flashes red twice and I pick in the panel. A hold on a taken key frees it. On this layer the hold always means that, whatever my settings say, and there is no double tap. A tap shows the chat: the bridge asks Orca where it is open, brings Orca forward, activates the workspace and presses the tab with the chat's title.

Turning point: a chat's process ending is not its tab closing. Orca keeps the tab while the process is gone, and after Orca restarts the tab is back before the chat says anything. Dimming on the process alone would have dimmed the keys of chats that are still open, and a dim key ignores taps. So when a process ends the bridge asks Orca a moment later whether the tab is still there, and only a closed tab dims its key. For the same reason the hook sends nothing when I type /clear in a chat, and nothing from a Claude Code that a chat started itself. Both carry the chat's ID and would have dimmed or changed its key.

Orca also went into the built-in config as an app group. Approve and Decline press Allow and Deny on a chat's permission card. Orca gets a layer only when my own file names one, because only I can put the pad's keys on a layer.

Turned down: Return as a fallback for Approve in Orca. With no card on screen it would send the message I was typing.

Cost: a hold and a jump need Accessibility and Orca's command line, and take a third to half a second. Tabs carry no ID, so the match is by title, and two chats with one title cannot be told apart. The keys are saved with Orca's IDs and states only.

Still open: all of this was tried on my real Orca through the bridge's socket, and it works there. From the pad's own keys it is not tried yet.

## 17. A front page, a window and a panel

Decisions: D-061 to D-066

Three things that people look at changed: the README, the MicroBridge window, and a new panel inside Orca.

I said the README looked like a word dump. It is a front page now: the pad's picture, the lights, the controls and the install commands. The long parts moved to docs/ word for word. Nothing was removed.

The window got Orca. One switch on the Behavior screen gives Orca's chats layer 2 and moves ChatGPT to layer 3, because a layer is the bridge's own or another app's, not both. The Pad screen draws the six keys of the layer the pad is on. It lists Orca's keys with Show, Free and a menu that puts a chat on an empty key. For that menu the bridge now answers with Orca's open chats, and it remembers the title of each chat that is on a key.

The panel is an Orca plugin that lives in this repository. A panel in Orca can reach only its own worker, and the worker runs with my account. So the worker asks the bridge over its socket for everything: the keys, the chats, and what the controls do in Orca. The plugin stores nothing. The bridge's own Orca commands always go to the Orca on this Mac, because the window it reads and the chats it hears from are on this Mac.

Turning point: the panel can change what a command does in Orca, and the config file is the one store for that. So the bridge now writes the config file, where it only read it before. It does that with the same function the window uses, so the two screens follow one rule. Claude also first wrote the chat titles into the keys file. That went against an earlier decision, which keeps only Orca's IDs and states on disk, so the titles came out again. They stay in memory and out of the log.

Turned down: a command over the socket that sets any setting. The worker editing the config file itself. A separate repository for the plugin.

Cost: the bridge writes the config file for commands only, and only when asked over its socket. Loading the plugin asks me to approve a worker that runs code with my account. Chats on an Orca on another machine cannot be put on keys. After the bridge restarts, the key of a closed chat shows the start of its ID in place of its title.

Still open: the panel passes Orca's own plugin tools, but it has never run inside a running Orca. The second copy of Orca that Claude tests in hung at start that night, because the Mac was short of memory. The new window has not been tried against the running bridge, because nothing was installed that night. The pad's own keys were untried that night. The morning after, Claude installed the build at my word, and on the pad the tap to Orca's layer, the hold that takes a chat and the tap on its key worked. Then I approved the panel's worker, and the panel showed that key in my own Orca.

## 18. The list that stopped Approve

Decisions: D-067

I set a test chat in Orca to ask for approval, got the card, and pressed the ✓ key on the pad. Nothing happened. I pressed it four times.

The bridge had the answer in its log on every press. My settings file has a list of the apps the bridge may type and click in. Orca came off that list on November 13, when I wanted no Orca tie at all. When Claude set up Orca's layer in my file, it did not put Orca back. So the bridge found the command for the Allow button and stopped itself.

Turning point: the night before, Claude had pressed Allow through the command line, which skips this check. That test passed, and the pad's own path was never run on a card. One line in my file fixed my Mac, with my yes.

Turned down: letting an app with a layer be typed in without being on the list. The list would stop being the one place that says where the bridge types.

Cost: two settings still have to agree. Now the tools keep them in step. The window's Orca switch adds Orca to the list. The bridge's log and the config check warn when a layer's app is missing from it. The window shows that as the next step, with a button that adds the app.

Still open: Approve pressing Allow from the pad, with the corrected file, is not seen yet.
