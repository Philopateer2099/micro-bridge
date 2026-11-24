// Talks to the MicroBridge daemon: one JSON object per line over its Unix socket, one line back.
// Only the worker imports this file. A panel can reach nothing but the worker.
import { createConnection } from 'node:net'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { env } from 'node:process'

export type Answer = Record<string, any>

/** Where the daemon listens. MICROBRIDGE_SOCKET names another place, for tests. */
export function socketPath(): string {
  return env.MICROBRIDGE_SOCKET || join(homedir(), 'Library', 'Application Support', 'micro-bridge', 'daemon.sock')
}

/** Why a request failed, in words for the panel. */
export function reason(error: unknown): string {
  const code = (error as { code?: string } | null)?.code
  if (code === 'ENOENT' || code === 'ECONNREFUSED') return 'MicroBridge is not running.'
  return error instanceof Error ? error.message : String(error)
}

/** Sends one request and resolves with the bridge's answer to it. */
export function ask(request: Record<string, unknown>, timeoutMs = 4000): Promise<Answer> {
  return new Promise((resolve, reject) => {
    const socket = createConnection(socketPath())
    let text = ''
    let done = false
    const finish = (error: unknown, answer?: Answer): void => {
      if (done) return
      done = true
      clearTimeout(timer)
      socket.destroy()
      if (answer) resolve(answer)
      else reject(error)
    }
    const timer = setTimeout(() => finish(new Error('The bridge did not answer in time.')), timeoutMs)
    socket.setEncoding('utf8')
    socket.on('connect', () => socket.write(JSON.stringify(request) + '\n'))
    socket.on('data', (chunk: string) => {
      text += chunk
      const end = text.indexOf('\n')
      if (end < 0) return
      try {
        finish(null, JSON.parse(text.slice(0, end)) as Answer)
      } catch {
        finish(new Error('The bridge sent an answer that is not JSON.'))
      }
    })
    socket.on('error', (error: unknown) => finish(error))
    socket.on('close', () => finish(new Error('The bridge closed the connection.')))
  })
}
