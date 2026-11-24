# ChatGPT and MicroBridge

ChatGPT and MicroBridge use the same pad. This page covers keeping ChatGPT off the keys while
you work in Claude Code, and handing the pad to ChatGPT and back with the touch sensor.

## Keeping ChatGPT out

ChatGPT acts on the pad's keys even while another app is in front, and it has no setting
against that. Only a program running as root can keep the pad from it. MicroBridge Helper is
that program, and it is optional. With it, while ChatGPT runs behind another app, MicroBridge
holds the pad and ChatGPT hears nothing. With ChatGPT in front, the pad is shared again, and
ChatGPT picks it back up within seconds.

```sh
sudo scripts/helper install   # asks for your password; from a download:
                              # sudo /Applications/MicroBridge.app/Contents/Resources/helper install
```

Then open System Settings > Privacy & Security > Input Monitoring, press +, and add
`/Library/PrivilegedHelperTools/MicroBridge Helper.app`. macOS does not let a root program add
itself to that list. The bridge moves over to the helper within half a minute; its log says
"through MicroBridge Helper". `scripts/helper status` shows whether it runs, and
`sudo scripts/helper remove` takes it all out again.

What it does and does not do:

- It opens only the Codex Micro, and only while MicroBridge is connected to it. When
  MicroBridge quits, the pad is shared again at once.
- It writes only the five methods listed under [Safety and privacy](../README.md#safety-and-privacy). It checks each request and
  rebuilds it before writing it.
- It serves only your account, and only a program signed as MicroBridge with the same
  certificate as the helper.
- It holds the pad only on its first layer. On other layers the pad types like a keyboard, and
  a held keyboard types nothing. If the pad sends keyboard or mouse input while held, the pad
  is shared at once and that first input is lost.
- It makes no network connections. Its log, `/Library/Logs/micro-bridge-helper.log`, says when
  MicroBridge connected and when the pad was held or shared, never what was pressed.

## Passing the pad to ChatGPT

Both apps use the same keys. The Codex keys exist only on the pad's layer 1, and Work Louder
Input offers none for other layers, so out of the box no layer can be ChatGPT's. Two taps on
the pad's touch sensor (its bottom-left edge) pass the pad instead. Turn on "Two taps pass the
pad to ChatGPT" on the window's Behavior tab, or set `"layers": {"2": "com.openai.codex"}`.

1. Tap the touch sensor. The pad goes to layer 2.
2. Wait about a second for the notification "ChatGPT has the pad".
3. Tap again. The pad is back on layer 1, and its keys are ChatGPT's.

The same two taps give the pad back to MicroBridge.

- Until the first visit MicroBridge keeps the pad, also while ChatGPT is in front. With the
  helper, ChatGPT hears nothing; without it, ChatGPT hears the keys too.
- While ChatGPT has the pad, MicroBridge lights nothing and acts on no key, whatever app is in
  front. It turns its six Agent Key lights off as it lets go and leaves the ring and the key
  backlight as they are. After a hold, ChatGPT can take up to 10 s to open the pad again.
- ChatGPT gets the pad only while it is open. Quitting it gives the pad back, and so does a
  restart of MicroBridge. A pad that sleeps or loses its cable changes nothing.
- The pad does not say when its layer changes, so MicroBridge reads it once a second. A visit
  shorter than that goes unseen: stay on layer 2 until the notification comes. With
  `layerWarning` off there is no notification, and the log has the same lines.

### One tap instead of two

The second tap is needed only because layer 2 has no Codex keys. Work Louder Input does not
offer them for a second layer, but it imports a profile file that has them. With such a profile
one tap is enough: on layer 2 ChatGPT has the pad, on layer 1 MicroBridge.

1. Stop MicroBridge: `launchctl bootout gui/$(id -u)/local.micro-bridge`. Input cannot write to
   a pad that MicroBridge Helper holds.
2. In Work Louder Input, export your profile. It saves `<name>-profile.json`. Keep that file
   as your backup.
3. In a copy of the file, give the second entry of `profile.layers` the same `layout` as the
   first, and give `profile.name` a new name.
4. In Input, import the copy. It arrives as a second profile. Select it. Your old profile
   stays as it was.
5. Start MicroBridge again (`scripts/install`, or log out and in) and turn on "Layer 2 has the
   pad's keys too" on the window's Behavior tab, or set `"layerKeys": true`.

- The layer the pad is on says who has it, also right after MicroBridge starts. The app in
  front does not matter.
- While ChatGPT is closed, MicroBridge acts on layer 2's keys too.
- MicroBridge reads the layer four times a second while ChatGPT is open, so a tap takes a
  quarter of a second to count. After a tap to layer 2, ChatGPT can take up to 10 s to open
  the pad again.
- To undo it, select your old profile in Input, delete the new one, and turn the setting off.
