// Runs src/worker.ts against a stand-in for the MicroBridge daemon: a Unix socket in a scratch
// folder that answers each request line by its "op". Nothing here reaches the real bridge.
import { mkdtempSync, rmSync } from 'node:fs'
import { createServer, type Server } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { env } from 'node:process'
import { afterEach, assert, beforeEach, mountWorker, test } from 'orca/testing'
import * as main from './worker'

type Request = Record<string, any>

let server: Server
let folder = ''
let asked: Request[] = []
let answers: Record<string, (request: Request) => unknown> = {}

const CHATS = {
  ok: true,
  chats: [
    { session: 'chat-one', title: 'Fix the build', status: 'working', worktree: 'repo::/code/app' },
    { session: 'chat-five', title: 'Plan the search page', status: 'idle', worktree: 'repo::/code/app' }
  ]
}

function state(keys: unknown[]): unknown {
  return { ok: true, connected: true, layer: 2, slots: [], sessions: [], orca: { layer: 2, slots: [], keys } }
}

beforeEach(async () => {
  folder = mkdtempSync(join(tmpdir(), 'mb-'))
  env.MICROBRIDGE_SOCKET = join(folder, 'daemon.sock')
  asked = []
  answers = {}
  server = createServer((socket) => {
    let text = ''
    socket.setEncoding('utf8')
    socket.on('data', (chunk: string) => {
      text += chunk
      const end = text.indexOf('\n')
      if (end < 0) return
      const request = JSON.parse(text.slice(0, end)) as Request
      asked.push(request)
      socket.end(JSON.stringify(answers[request.op]?.(request) ?? { ok: false, error: 'unknown op' }) + '\n')
    })
  })
  await new Promise<void>((resolve) => server.listen(env.MICROBRIDGE_SOCKET, resolve))
})

afterEach(async () => {
  await new Promise((resolve) => server.close(resolve))
  rmSync(folder, { recursive: true, force: true })
})

test('reads the keys and the open chats from the bridge', async () => {
  answers = {
    state: () =>
      state([
        { slot: 1, session: 'chat-one', status: 'working', title: 'Fix the build' },
        { slot: 3, session: 'chat-four', status: 'idle', closed: true }
      ]),
    'orca.chats': () => CHATS
  }
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.state'), {
    running: true,
    connected: true,
    layer: 2,
    orca: {
      layer: 2,
      keys: [
        { slot: 1, session: 'chat-one', status: 'working', closed: false, title: 'Fix the build' },
        { slot: 3, session: 'chat-four', status: 'idle', closed: true }
      ]
    },
    chats: [
      { session: 'chat-one', title: 'Fix the build', status: 'working' },
      { session: 'chat-five', title: 'Plan the search page', status: 'idle' }
    ]
  })
  assert.deepEqual(asked, [{ op: 'state' }, { op: 'orca.chats' }])
  // A chat's title is in no log line.
  assert.deepEqual(worker.logs, [])
  assert.deepEqual(worker.refusals, [])
  await worker.deactivate()
})

test('with no layer for Orca it does not ask for chats', async () => {
  answers = { state: () => ({ ok: true, connected: false }) }
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.state'), { running: true, connected: false, orca: null, chats: [] })
  assert.deepEqual(asked, [{ op: 'state' }])
  await worker.deactivate()
})

test('puts a chat on a key, frees it and shows it, and tells open panels', async () => {
  let keys: unknown[] = []
  answers = {
    state: () => state(keys),
    'orca.chats': () => CHATS,
    'orca.take': (request) => {
      keys = [{ slot: request.slot, session: request.session ?? 'chat-one', status: 'idle', title: 'Plan the search page' }]
      return { ok: true }
    },
    'orca.free': () => {
      keys = []
      return { ok: true }
    },
    'orca.show': () => ({ ok: true })
  }
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.take', { slot: 4, session: 'chat-five' }), { ok: true })
  assert.deepEqual(asked[0], { op: 'orca.take', slot: 4, session: 'chat-five' })
  assert.equal(worker.posts.length, 1)
  assert.equal(worker.posts[0].event, 'pad.changed')
  assert.deepEqual((worker.posts[0].payload as { orca: { keys: unknown[] } }).orca.keys, [
    { slot: 4, session: 'chat-five', status: 'idle', closed: false, title: 'Plan the search page' }
  ])

  // With no chat named, the bridge takes the chat on screen.
  await worker.request('pad.free', { slot: 4 })
  await worker.request('pad.take', { slot: 0 })
  await worker.request('pad.show', { slot: 0 })
  assert.deepEqual(
    asked.filter((request) => String(request.op).startsWith('orca.') && request.op !== 'orca.chats'),
    [
      { op: 'orca.take', slot: 4, session: 'chat-five' },
      { op: 'orca.free', slot: 4 },
      { op: 'orca.take', slot: 0 },
      { op: 'orca.show', slot: 0 }
    ]
  )
  await worker.deactivate()
})

test('passes on why the bridge refused', async () => {
  answers = {
    state: () => state([]),
    'orca.chats': () => CHATS,
    'orca.take': () => ({ ok: false, error: 'key 1 holds a chat already: free it first' })
  }
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.take', { slot: 0 }), { ok: false, error: 'key 1 holds a chat already: free it first' })
  await worker.deactivate()
})

test('says when the bridge is not running', async () => {
  env.MICROBRIDGE_SOCKET = join(folder, 'nothing-here.sock')
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.state'), {
    running: false,
    problem: 'MicroBridge is not running.',
    connected: false,
    orca: null,
    chats: []
  })
  assert.deepEqual(await worker.request('pad.free', { slot: 2 }), { ok: false, error: 'MicroBridge is not running.' })
  assert.deepEqual(await worker.request('pad.commands'), { commands: [], problem: 'MicroBridge is not running.' })
  await worker.deactivate()
})

test('lists what the commands do in Orca and changes one', async () => {
  answers = {
    commands: () => ({
      ok: true,
      commands: [
        {
          name: 'APPR',
          title: 'Approve',
          controls: ['Key 8'],
          here: { press: ['click:native-chat-appearance/=Allow'] },
          elsewhere: { press: ['key:return'] }
        }
      ]
    }),
    'command.set': (request) => (request.actions.length > 0 ? { ok: true } : { ok: false, error: 'not saved: a reason' })
  }
  const worker = await mountWorker(main)
  assert.deepEqual(await worker.request('pad.commands'), {
    commands: [
      {
        name: 'APPR',
        title: 'Approve',
        controls: ['Key 8'],
        here: { press: ['click:native-chat-appearance/=Allow'] },
        elsewhere: { press: ['key:return'] }
      }
    ]
  })
  assert.deepEqual(await worker.request('pad.setCommand', { name: 'APPR', actions: ['key:return'] }), { ok: true })
  assert.deepEqual(asked[1], { op: 'command.set', name: 'APPR', target: 'orca', actions: ['key:return'] })
  assert.deepEqual(await worker.request('pad.setCommand', { name: 'APPR', actions: [] }), { ok: false, error: 'not saved: a reason' })
  await worker.deactivate()
})
