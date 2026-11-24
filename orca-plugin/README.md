# MicroBridge panel for Orca

A panel in [Orca](https://github.com/stablyai/orca)'s right sidebar for the keys of Orca's layer
on a Codex Micro. It works with the MicroBridge app from this repository. Unofficial: not made
by Work Louder, OpenAI, Anthropic or Orca's authors.

What it shows:

- **Orca's keys.** The six Agent Keys of Orca's layer and the Claude chat each one holds, with
  the chat's title and what it is doing. "Show" brings a chat on screen, as a tap on its key
  does. "Free" lets the chat go, as a hold on a taken key does. An empty key has a menu: put
  the chat on screen on it, or pick one of Orca's open Claude chats.
- **What the controls do in Orca.** Each command on the pad (Approve, Decline and so on) with
  what it does while Orca is in front, one action per line. "Save" writes it to MicroBridge's
  config file through the bridge, which checks it first. The MicroBridge app has the full
  editor (Commands, "In Orca").

It needs MicroBridge running, and a layer for Orca in its config
([docs/configuration.md](../docs/configuration.md#orcas-layer)).

## How it is built

```text
src/panel.tsx    the panel: draws what the worker says, sends what you press
src/worker.ts    the worker: a Node process that asks the MicroBridge daemon
src/bridge.ts    one JSON line out and one back, over the daemon's Unix socket
src/protocol.ts  the requests between panel and worker, typed once
```

A panel in Orca can reach nothing but its own worker, so the worker does the asking. The plugin
keeps nothing: the keys live in the bridge and the settings in the bridge's config file. Chat
titles pass through to the panel and are never logged.

Orca runs a worker as `trusted-worker`: its own Node process with your account's access. This
one opens one thing, the bridge's socket in `~/Library/Application Support/micro-bridge/`. It
asks for no Orca capability.

## Load it

```sh
orca plugin dev load /path/to/micro-bridge/orca-plugin
```

The first run prints what the plugin may do and a fingerprint, and loads nothing. Run it again
with `--approve <fingerprint>` to load it, then open the panel:

```sh
orca plugin open local.microbridge --panel pad
```

`orca plugin dev unload local.microbridge` removes it.

## Test it

```sh
scripts/test-plugin        # from the repository's root
```

That runs `orca plugin validate`, `orca plugin test` (11 tests: the worker against a stand-in
for the daemon, the panel against a stand-in for the worker) and `orca plugin check`, with
`MICROBRIDGE_SOCKET` pointing where nothing listens, so the running bridge is left alone.
`orca plugin types .` writes Orca's typings to `.orca/`, which stays out of the repository.

Seen with Orca 1.4.271. Loaded into a running Orca on 2026-11-24: the worker reached the
bridge's socket and answered with the pad's state, the chats and the commands, and Orca drew
the panel with the six keys. The panel's buttons and its Save have not been pressed in a
running Orca yet; they pass their tests against a stand-in.
