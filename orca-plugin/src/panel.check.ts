// `orca plugin check` renders the panel once per scenario, with the real worker behind it. The
// worker asks the MicroBridge daemon, so what check draws is what the bridge says right now:
// the keys when it runs, "not running" when it does not. To check without the bridge, run it
// with MICROBRIDGE_SOCKET set to a path where nothing listens. src/panel.test.tsx covers the
// other states with made-up answers.
import { defineCheck } from 'orca/testing'

export default defineCheck({
  asBridgeSays: {}
})
