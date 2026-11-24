// The plugin's worker: a Node process that asks the MicroBridge daemon on behalf of the panel.
// It keeps nothing: the keys live in the bridge and the settings in the bridge's config file.
// Chat titles pass through to the panel and are never logged.
import type { OrcaWorkerApi } from 'orca/worker'
import { ask, reason, type Answer } from './bridge'
import type { Chat, CommandRow, Done, Key, PadState } from './protocol'

const WATCH_EVERY_MS = 1500
/** How long the worker keeps watching the bridge after a panel last asked. */
const WATCH_FOR_MS = 60_000

let timer: ReturnType<typeof setInterval> | undefined
let askedAt = 0
let posted = ''
let chats: Chat[] = []
let reading = false

const text = (value: unknown): string | undefined => (typeof value === 'string' ? value : undefined)

function stopped(problem: string): PadState {
  return { running: false, problem, connected: false, orca: null, chats: [] }
}

/** The bridge's answer to "state", as the panel wants it. */
export function padState(answer: Answer, open: Chat[]): PadState {
  const orca = answer.orca && typeof answer.orca.layer === 'number' ? answer.orca : null
  const keys: Key[] = []
  for (const item of Array.isArray(orca?.keys) ? orca.keys : []) {
    if (typeof item?.slot !== 'number' || typeof item?.session !== 'string') continue
    const key: Key = { slot: item.slot, session: item.session, status: text(item.status) ?? 'idle', closed: item.closed === true }
    if (typeof item.title === 'string') key.title = item.title
    keys.push(key)
  }
  const state: PadState = {
    running: true,
    connected: answer.connected === true,
    orca: orca ? { layer: orca.layer, keys } : null,
    chats: orca ? open : []
  }
  if (typeof answer.layer === 'number') state.layer = answer.layer
  return state
}

/** Asks the bridge what the keys hold, and with `withChats` which chats are open in Orca. */
async function read(withChats: boolean): Promise<PadState> {
  try {
    const answer = await ask({ op: 'state' })
    if (answer.ok !== true) return stopped(text(answer.error) ?? 'The bridge refused.')
    if (withChats && answer.orca) {
      // The bridge asks Orca's command line, which takes a moment.
      const list = await ask({ op: 'orca.chats' }, 8000)
      if (list.ok === true && Array.isArray(list.chats)) {
        chats = list.chats
          .filter((chat: Answer) => typeof chat?.session === 'string' && typeof chat?.title === 'string')
          .map((chat: Answer) => ({ session: chat.session, title: chat.title, status: text(chat.status) ?? 'idle' }))
      }
    }
    return padState(answer, chats)
  } catch (error) {
    return stopped(reason(error))
  }
}

function lists(value: unknown): Record<string, string[]> {
  const out: Record<string, string[]> = {}
  if (!value || typeof value !== 'object') return out
  for (const [trigger, actions] of Object.entries(value as Record<string, unknown>)) {
    if (Array.isArray(actions)) out[trigger] = actions.filter((action): action is string => typeof action === 'string')
  }
  return out
}

export default function activate(orca: OrcaWorkerApi): void {
  const post = (state: PadState): void => {
    const now = JSON.stringify(state)
    if (now === posted) return
    posted = now
    orca.panels.post('pad.changed', state)
  }

  // While a panel is open it asks again every 20 seconds, which keeps this going.
  const watch = (): void => {
    askedAt = Date.now()
    if (timer) return
    timer = setInterval(() => {
      if (Date.now() - askedAt > WATCH_FOR_MS) {
        clearInterval(timer)
        timer = undefined
        return
      }
      if (reading) return
      reading = true
      void read(false)
        .then(post)
        .finally(() => {
          reading = false
        })
    }, WATCH_EVERY_MS)
    timer.unref?.()
  }

  /** Sends one change to the bridge, then tells every open panel what the keys hold now. */
  const change = async (request: Record<string, unknown>, timeoutMs = 10_000): Promise<Done> => {
    watch()
    let done: Done
    try {
      const answer = await ask(request, timeoutMs)
      done = answer.ok === true ? { ok: true } : { ok: false, error: text(answer.error) ?? 'The bridge refused.' }
    } catch (error) {
      done = { ok: false, error: reason(error) }
    }
    post(await read(true))
    return done
  }

  orca.panels.handle('pad.state', async () => {
    watch()
    const state = await read(true)
    posted = JSON.stringify(state)
    return state
  })
  orca.panels.handle('pad.take', ({ slot, session }) => change(session ? { op: 'orca.take', slot, session } : { op: 'orca.take', slot }))
  orca.panels.handle('pad.free', ({ slot }) => change({ op: 'orca.free', slot }))
  orca.panels.handle('pad.show', ({ slot }) => change({ op: 'orca.show', slot }))

  orca.panels.handle('pad.commands', async () => {
    try {
      const answer = await ask({ op: 'commands', target: 'orca' })
      if (answer.ok !== true || !Array.isArray(answer.commands)) {
        return { commands: [], problem: text(answer.error) ?? 'The bridge refused.' }
      }
      const commands: CommandRow[] = answer.commands
        .filter((row: Answer) => typeof row?.name === 'string')
        .map((row: Answer) => ({
          name: row.name,
          title: text(row.title) ?? row.name,
          controls: Array.isArray(row.controls) ? row.controls.filter((item: unknown) => typeof item === 'string') : [],
          here: lists(row.here),
          elsewhere: lists(row.elsewhere)
        }))
      return { commands }
    } catch (error) {
      return { commands: [], problem: reason(error) }
    }
  })

  orca.panels.handle('pad.setCommand', async ({ name, actions }) => {
    try {
      const answer = await ask({ op: 'command.set', name, target: 'orca', actions })
      return answer.ok === true ? { ok: true } : { ok: false, error: text(answer.error) ?? 'The bridge refused.' }
    } catch (error) {
      return { ok: false, error: reason(error) }
    }
  })
}

/** Orca calls this when the plugin stops. */
export function deactivate(): void {
  if (timer) clearInterval(timer)
  timer = undefined
  askedAt = 0
  posted = ''
  chats = []
  reading = false
}
