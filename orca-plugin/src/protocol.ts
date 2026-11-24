// The panel <-> worker contract, declared once: src/panel.tsx and src/worker.ts both read it.

/** A key of Orca's layer that holds a chat. `slot` counts from 0. */
export type Key = { slot: number; session: string; status: string; closed: boolean; title?: string }

/** An open Claude chat in Orca, by Orca's session ID. */
export type Chat = { session: string; title: string; status: string }

/** What the bridge says about the pad and Orca's layer. */
export type PadState = {
  /** False when the bridge did not answer; `problem` then says why. */
  running: boolean
  problem?: string
  /** The pad is connected to the bridge. */
  connected: boolean
  /** The layer the pad is on, when the pad says. */
  layer?: number
  /** Null when the config gives Orca no layer. */
  orca: { layer: number; keys: Key[] } | null
  /** Orca's open Claude chats, for a key to take. */
  chats: Chat[]
}

/** A command, the controls that run it, and what it does in Orca and everywhere else, by trigger. */
export type CommandRow = {
  name: string
  title: string
  controls: string[]
  here: Record<string, string[]>
  elsewhere: Record<string, string[]>
}

export type Done = { ok: boolean; error?: string }

declare module 'orca' {
  interface PluginRequests {
    /** Asks the bridge, and keeps the worker watching it for the next minute. */
    'pad.state': { output: PadState }
    /** Puts a chat on an empty key: the one named, or the chat on screen in Orca. */
    'pad.take': { input: { slot: number; session?: string }; output: Done }
    'pad.free': { input: { slot: number }; output: Done }
    /** Brings the key's chat on screen, as a tap on the key does. */
    'pad.show': { input: { slot: number }; output: Done }
    'pad.commands': { output: { commands: CommandRow[]; problem?: string } }
    /** Sets what a command does on a press in Orca. No actions removes Orca's own part. */
    'pad.setCommand': { input: { name: string; actions: string[] }; output: Done }
  }
  interface PluginPanelEvents {
    /** Posted to every open panel when what the bridge says has changed. */
    'pad.changed': PadState
  }
}
