// `orca plugin test .` runs this in Node with the runtime and checks Orca uses. The host's
// `requests` stand in for src/worker.ts, so no bridge is needed.
import { assert, mockHost, mount, test } from 'orca/testing'
import * as panel from './panel'
import { shown, typed } from './panel'
import type { PadState } from './protocol'

const KEYS: PadState = {
  running: true,
  connected: true,
  layer: 2,
  orca: {
    layer: 2,
    keys: [
      { slot: 0, session: 'chat-one', status: 'working', closed: false, title: 'An old title' },
      { slot: 1, session: 'chat-two', status: 'needs-you', closed: false },
      { slot: 3, session: 'chat-four', status: 'idle', closed: true, title: 'Review the login flow' }
    ]
  },
  chats: [
    { session: 'chat-one', title: 'Fix the checkout total', status: 'working' },
    { session: 'chat-two', title: 'Write the release notes', status: 'needs-you' },
    { session: 'chat-five', title: 'Plan the search page', status: 'idle' }
  ]
}

test('shows the six keys and frees, shows and takes', async () => {
  const calls: unknown[] = []
  const host = mockHost({
    requests: {
      'pad.state': () => KEYS,
      'pad.free': (input) => (calls.push(['free', input]), { ok: true }),
      'pad.show': (input) => (calls.push(['show', input]), { ok: true }),
      'pad.take': (input) => (calls.push(['take', input]), { ok: true })
    }
  })
  const view = await mount(panel, { host })
  // An open chat is called what Orca calls it now, a closed one what the bridge kept.
  assert.ok(view.find({ text: 'Fix the checkout total' }))
  assert.ok(view.find({ text: 'Write the release notes' }))
  assert.ok(view.find({ text: 'Review the login flow' }))
  assert.ok(view.find({ text: 'Closed in Orca' }))
  assert.ok(view.find({ text: 'Pad connected' }))
  assert.ok(view.find({ text: /The pad is on it now/ }))
  assert.equal(view.findAll({ text: /empty$/ }).length, 3)

  await view.press({ text: 'Free 1' })
  await view.press({ text: 'Show 2' })
  await view.select({ label: 'Put a chat on key 3' }, 'chat-five')
  await view.select({ label: 'Put a chat on key 5' }, 'on screen')
  assert.deepEqual(calls, [
    ['free', { slot: 0 }],
    ['show', { slot: 1 }],
    ['take', { slot: 2, session: 'chat-five' }],
    ['take', { slot: 4 }]
  ])

  // The worker posts what the keys hold after a change.
  await view.post('pad.changed', { ...KEYS, layer: 1, orca: { layer: 2, keys: [] } })
  assert.equal(view.find({ text: 'Fix the checkout total' }), null)
  assert.equal(view.findAll({ text: /empty$/ }).length, 6)
  assert.ok(view.find({ text: /The pad is on layer 1 now/ }))
  assert.deepEqual(view.errors, [])
  assert.deepEqual(view.warnings, [])
  assert.deepEqual(view.refusals, [])
  await view.unmount()
})

test('says why the bridge did not do it', async () => {
  const host = mockHost({
    requests: {
      'pad.state': () => KEYS,
      'pad.take': () => ({ ok: false, error: 'the window does not say which chat is meant' })
    }
  })
  const view = await mount(panel, { host })
  await view.select({ label: 'Put a chat on key 6' }, 'on screen')
  assert.equal(view.find({ label: 'Not done' })?.text, 'Not done the window does not say which chat is meant')
  await view.unmount()
})

test('says when the bridge is not running or Orca has no layer', async () => {
  let answer: PadState = { running: false, problem: 'MicroBridge is not running.', connected: false, orca: null, chats: [] }
  const host = mockHost({ requests: { 'pad.state': () => answer } })
  const view = await mount(panel, { host })
  assert.ok(view.find({ text: 'Not running' }))
  assert.match(view.find({ label: 'The bridge is not answering' })?.text ?? '', /MicroBridge is not running\. Open the MicroBridge app/)
  assert.equal(view.find({ text: "Orca's keys" }), null)

  answer = { running: true, connected: false, orca: null, chats: [] }
  await view.press({ text: 'Refresh' })
  assert.ok(view.find({ text: 'No pad' }))
  assert.ok(view.find({ label: 'Orca has no layer yet' }))
  assert.equal(view.find({ label: 'The bridge is not answering' }), null)
  assert.deepEqual(view.errors, [])
  await view.unmount()
})

test('changes what a command does in Orca', async () => {
  const saved: unknown[] = []
  let own = ['click:native-chat-appearance/=Allow']
  const host = mockHost({
    requests: {
      'pad.state': () => KEYS,
      'pad.commands': () => ({
        commands: [
          { name: 'APPR', title: 'Approve', controls: ['Key 8'], here: own.length > 0 ? { press: own } : {}, elsewhere: { press: ['key:return'] } },
          { name: 'MIC', title: 'Mic', controls: ['Wide key'], here: { press: ['key:cmd+d'], release: ['key:cmd+d'] }, elsewhere: {} }
        ]
      }),
      'pad.setCommand': (input) => {
        saved.push(input)
        own = input.actions
        return { ok: true }
      }
    }
  })
  const view = await mount(panel, { host })
  await view.toggle({ type: 'Collapsible' })
  assert.equal(view.valueOf({ label: 'What Approve does in Orca' }), 'click:native-chat-appearance/=Allow')
  // A command with a press and a release is shown and not changed here.
  assert.equal(view.find({ label: 'What Mic does in Orca' }), null)

  await view.type({ label: 'What Approve does in Orca' }, 'click:native-chat-appearance/=Allow\nkey:return', { replace: true })
  await view.press({ text: 'Save Approve' })
  assert.deepEqual(saved, [{ name: 'APPR', actions: ['click:native-chat-appearance/=Allow', 'key:return'] }])
  assert.equal(view.valueOf({ label: 'What Approve does in Orca' }), 'click:native-chat-appearance/=Allow\nkey:return')

  await view.press({ text: 'Remove' })
  assert.deepEqual(saved[1], { name: 'APPR', actions: [] })
  assert.ok(view.find({ text: /does what it does everywhere else: key:return/ }))
  assert.deepEqual(view.errors, [])
  await view.unmount()
})

test('an Enter inside an action is written as \\n', () => {
  const actions = ['text:/fast\n', 'key:return', 'text:a\\b ']
  assert.equal(shown(actions), 'text:/fast\\n\nkey:return\ntext:a\\\\b ')
  assert.deepEqual(typed(shown(actions)), actions)
  assert.deepEqual(typed('key:return\n\n   \nkey:escape'), ['key:return', 'key:escape'])
  assert.deepEqual(typed(''), [])
})
