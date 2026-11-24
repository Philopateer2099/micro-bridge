// The MicroBridge panel in Orca's right sidebar: the six keys of Orca's layer, the chats they
// hold, and what the pad's controls do in Orca. No build step: Orca compiles this when it loads.
// It asks the worker (src/worker.ts) for everything; the worker asks the bridge.
import {
  atom,
  Badge,
  Box,
  Button,
  Callout,
  Collapsible,
  Field,
  Heading,
  plugin,
  read,
  Row,
  Select,
  set,
  Spinner,
  Stack,
  Text,
  Textarea,
  update,
  type PanelContext
} from 'orca'
import type { Chat, CommandRow, Key, PadState } from './protocol'

type Tone = 'neutral' | 'accent' | 'success' | 'warning' | 'danger'

/** What the bridge last said; null until it answers. */
const state = atom<PadState | null>(null)
/** Why the last change was not made. */
const notice = atom<string | null>(null)
/** What the commands do in Orca; null until the section is opened. */
const commands = atom<CommandRow[] | null>(null)
const commandsProblem = atom<string | null>(null)
/** Text typed for a command and not saved yet, by command name. */
const drafts = atom<Record<string, string>>({})

/** The value of the choice "the chat on screen in Orca". No session ID has a space in it. */
const ON_SCREEN = 'on screen'

const STATUS: Record<string, { label: string; tone: Tone }> = {
  working: { label: 'Working', tone: 'accent' },
  'needs-you': { label: 'Needs you', tone: 'warning' },
  done: { label: 'Done, not read', tone: 'success' },
  failed: { label: 'Failed', tone: 'danger' },
  idle: { label: 'Idle', tone: 'neutral' }
}

/** Actions as the text field shows them: one per line, with \n for an Enter inside an action. */
export function shown(actions: readonly string[]): string {
  return actions.map((action) => action.replace(/\\/g, '\\\\').replace(/\n/g, '\\n')).join('\n')
}

/** The actions typed in the text field. An empty line is no action. */
export function typed(text: string): string[] {
  return text
    .split('\n')
    .filter((line) => line.trim() !== '')
    .map((line) => line.replace(/\\(\\|n)/g, (_, escaped: string) => (escaped === 'n' ? '\n' : '\\')))
}

async function refresh(): Promise<void> {
  set(state, await plugin.request('pad.state'))
}

async function loadCommands(): Promise<void> {
  const answer = await plugin.request('pad.commands')
  set(commands, answer.commands)
  set(commandsProblem, answer.problem ?? null)
}

function said(done: { ok: boolean; error?: string }): void {
  set(notice, done.ok ? null : (done.error ?? 'The bridge did not do it.'))
}

async function take(slot: number, choice: string): Promise<void> {
  said(await plugin.request('pad.take', choice === ON_SCREEN ? { slot } : { slot, session: choice }))
}

async function free(slot: number): Promise<void> {
  said(await plugin.request('pad.free', { slot }))
}

async function show(slot: number): Promise<void> {
  said(await plugin.request('pad.show', { slot }))
}

async function saveCommand(name: string, actions: string[]): Promise<void> {
  const done = await plugin.request('pad.setCommand', { name, actions })
  said(done)
  if (!done.ok) return
  update(drafts, (now) => {
    const next = { ...now }
    delete next[name]
    return next
  })
  await loadCommands()
}

/** Runs once before the first render. What it returns runs when the panel closes. */
export function setup(ctx: PanelContext): () => void {
  ctx.subscriptions.push(plugin.on('pad.changed', (next) => set(state, next)))
  void refresh()
  // The worker watches the bridge for a minute after it was last asked, so ask while open.
  const timers = globalThis as {
    setInterval?: (run: () => void, ms: number) => unknown
    clearInterval?: (timer: unknown) => void
  }
  const timer = timers.setInterval?.(() => {
    if (read(ctx.visible)) void refresh()
  }, 20_000)
  return () => {
    if (timer !== undefined) timers.clearInterval?.(timer)
  }
}

function titleOf(key: Key, chats: readonly Chat[]): string {
  return chats.find((chat) => chat.session === key.session)?.title ?? key.title ?? 'Chat ' + key.session.slice(0, 8)
}

function takenKey(key: Key, chats: readonly Chat[]) {
  const status = STATUS[key.status] ?? STATUS.idle
  return (
    <Box key={'key-' + key.slot} border radius="md" padding="sm" direction="column" gap="xs">
      <Row justify="between" gap="sm">
        <Text weight="medium" truncate>
          {titleOf(key, chats)}
        </Text>
        {key.closed ? <Badge tone="neutral">Closed in Orca</Badge> : <Badge tone={status.tone}>{status.label}</Badge>}
      </Row>
      <Row justify="between" gap="sm">
        <Text muted size="xs">
          Key {key.slot + 1}
        </Text>
        <Row gap="xs">
          <Button size="xs" variant="outline" disabled={key.closed} tooltip="Bring this chat on screen" onPress={() => show(key.slot)}>
            Show {key.slot + 1}
          </Button>
          <Button size="xs" variant="ghost" tooltip="The key lets its chat go" onPress={() => free(key.slot)}>
            Free {key.slot + 1}
          </Button>
        </Row>
      </Row>
    </Box>
  )
}

function emptyKey(slot: number, offKeys: readonly Chat[]) {
  const options = [
    { value: ON_SCREEN, label: 'The chat on screen in Orca' },
    ...offKeys.map((chat) => ({ value: chat.session, label: chat.title }))
  ]
  return (
    <Box key={'key-' + slot} border radius="md" padding="sm" direction="column" gap="xs">
      <Text muted size="xs">
        Key {slot + 1} · empty
      </Text>
      <Select
        label={'Put a chat on key ' + (slot + 1)}
        labelHidden
        placeholder="Put a chat here"
        value=""
        options={options}
        onChange={(choice) => take(slot, choice)}
      />
    </Box>
  )
}

function keysOf(now: PadState) {
  const orca = now.orca
  if (!orca) return null
  const taken = new Set(orca.keys.map((key) => key.session))
  const offKeys = now.chats.filter((chat) => !taken.has(chat.session))
  const where =
    now.layer === undefined ? '' : now.layer === orca.layer ? ' The pad is on it now.' : ' The pad is on layer ' + now.layer + ' now.'
  return (
    <Stack gap="sm">
      <Heading level={3}>Orca's keys</Heading>
      <Text muted size="xs">
        Layer {orca.layer} of the pad.{where}
      </Text>
      {[0, 1, 2, 3, 4, 5].map((slot) => {
        const key = orca.keys.find((held) => held.slot === slot)
        return key ? takenKey(key, now.chats) : emptyKey(slot, offKeys)
      })}
      <Text muted size="xs">
        On the pad: hold an empty key to take the chat on screen, hold a taken key to free it, tap a key to show its chat. A key never
        changes by itself.
      </Text>
    </Stack>
  )
}

function commandRow(row: CommandRow) {
  const own = row.here.press ?? []
  const fallback = row.elsewhere.press ?? []
  const more = Object.keys(row.here).filter((trigger) => trigger !== 'press')
  const label = row.title + (row.controls.length > 0 ? ' · ' + row.controls.join(', ') : '')
  if (more.length > 0) {
    return (
      <Field key={'command-' + row.name} label={label} description="It does more than one thing on a key here. Change it in the MicroBridge app.">
        <Text muted size="xs">
          {shown(own)}
        </Text>
      </Field>
    )
  }
  const saved = shown(own)
  const draft = read(drafts)[row.name] ?? saved
  const description =
    own.length > 0
      ? 'One action per line. \\n at the end of typed text sends it.'
      : fallback.length > 0
        ? 'Nothing of its own in Orca, so it does what it does everywhere else: ' + shown(fallback).replace(/\n/g, ', ')
        : 'It does nothing in Orca yet.'
  return (
    <Field key={'command-' + row.name} label={label} description={description}>
      <Textarea
        label={'What ' + row.title + ' does in Orca'}
        labelHidden
        rows={Math.max(2, draft.split('\n').length)}
        value={draft}
        placeholder="click:native-chat-appearance/=Allow"
        onChange={(next) => update(drafts, (now) => ({ ...now, [row.name]: next }))}
      />
      <Row gap="xs">
        <Button size="xs" disabled={draft === saved} onPress={() => saveCommand(row.name, typed(draft))}>
          Save {row.title}
        </Button>
        <Button size="xs" variant="ghost" disabled={own.length === 0} tooltip="Remove what it does in Orca only" onPress={() => saveCommand(row.name, [])}>
          Remove
        </Button>
      </Row>
    </Field>
  )
}

function controlsOf() {
  const rows = read(commands)
  const problem = read(commandsProblem)
  return (
    <Collapsible
      title="What the controls do in Orca"
      description="Saved in MicroBridge's config file"
      onChange={(open) => {
        if (open) void loadCommands()
      }}
    >
      <Stack gap="md">
        {problem ? <Callout tone="warning">{problem}</Callout> : null}
        {rows === null ? <Spinner label="Asking the bridge" /> : rows.map(commandRow)}
        <Text muted size="xs">
          The MicroBridge app has the full editor, under Commands, "In Orca".
        </Text>
      </Stack>
    </Collapsible>
  )
}

export default function Panel() {
  const now = read(state)
  const problem = read(notice)
  if (now === null) {
    return (
      <Stack gap="md">
        <Heading>MicroBridge</Heading>
        <Spinner label="Asking the bridge" />
      </Stack>
    )
  }
  return (
    <Stack gap="md">
      <Row justify="between" gap="sm">
        <Heading>MicroBridge</Heading>
        <Badge tone={!now.running ? 'danger' : now.connected ? 'success' : 'warning'}>
          {!now.running ? 'Not running' : now.connected ? 'Pad connected' : 'No pad'}
        </Badge>
      </Row>
      {problem ? (
        <Callout tone="warning" title="Not done">
          {problem}
        </Callout>
      ) : null}
      {!now.running ? (
        <Callout tone="danger" title="The bridge is not answering">
          {(now.problem ?? '') + ' Open the MicroBridge app, then press Refresh.'}
        </Callout>
      ) : null}
      {now.running && !now.orca ? (
        <Callout tone="neutral" title="Orca has no layer yet">
          In the MicroBridge app, open Behavior and turn on "Orca's chats have a layer of their own". The pad needs its keys on that
          layer too.
        </Callout>
      ) : null}
      {keysOf(now)}
      {now.orca ? controlsOf() : null}
      <Row>
        <Button variant="ghost" size="xs" icon="refresh" onPress={refresh}>
          Refresh
        </Button>
      </Row>
    </Stack>
  )
}
