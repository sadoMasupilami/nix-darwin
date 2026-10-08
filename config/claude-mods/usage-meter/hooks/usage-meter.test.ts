import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

import { bar, statusText, until } from './register'

const READING = {
  context: { window: 200000, tokens: 50000, percent: 25 },
  rateLimits: [
    { kind: 'five_hour', percentUsed: 42.5, resetsAt: '2026-10-07T18:00:00Z' },
    { kind: 'seven_day', percentUsed: 12 },
  ],
  cost: { usd: 1.234 },
}

describe('formatting', () => {
  test('status line names each window and the cost', async () => {
    const text = statusText({
      windows: READING.rateLimits,
      costUsd: READING.cost.usd,
      contextPercent: 25,
    })
    expect(text).toBe('5h 43% · 7d 12% · $1.23')
  })

  test('no windows and no cost clears the status line', async () => {
    expect(statusText({ windows: [] })).toBe(undefined)
  })

  test('reset time reads as hours and minutes', async () => {
    const now = Date.parse('2026-10-07T15:46:00Z')
    expect(until('2026-10-07T18:00:00Z', now)).toBe('2h 14m')
    expect(until('2026-10-09T18:00:00Z', now)).toBe('2d 2h')
    expect(until(undefined, now)).toBe(undefined)
  })

  test('bar fills proportionally and caps at 100', async () => {
    expect(bar(50, 10)).toBe('█████░░░░░')
    expect(bar(130, 4)).toBe('████')
  })
})

// Stands in for the engine beneath the plugin: a clock, the measure echo,
// and the status line and toasts, recorded.
const engine = (on: On) => {
  const statuses: (string | undefined)[] = []
  const toasts: string[] = []
  mock.clock(on, { now: Date.parse('2026-10-07T15:46:00Z') })
  on('session.measure', ($, e) => ({ changed: e.changed }))
  on('ui.status', ($, e) => (statuses.push(e.text), { value: undefined }))
  on('ui.toast', ($, e) => (toasts.push(e.text), { value: undefined }))
  return { statuses, toasts }
}

describe('session.measure', () => {
  test('sets the status line and toasts once when a window passes 80%', async ($, on) => {
    const { statuses, toasts } = engine(on)

    const hot = { ...READING, rateLimits: [{ kind: 'five_hour', percentUsed: 85 }] }
    await $.session.measure({ ...hot, changed: ['rateLimits'] })
    await $.session.measure({ ...hot, changed: ['rateLimits'] })

    expect(statuses.at(-1)).toBe('5h 85% · $1.23')
    expect(toasts).toEqual(['5h limit at 85%'])

    await $.session.measure({
      ...hot,
      rateLimits: [{ kind: 'five_hour', percentUsed: 96 }],
      changed: ['rateLimits'],
    })
    expect(toasts.length).toBe(2)
  })

  test('the pane draws a bar per window and the cost', async ($, on) => {
    engine(on)
    await $.session.measure({ ...READING, changed: ['rateLimits', 'cost', 'context'] })

    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({
        plugin: 'usage-meter',
        surface,
        component: 'Pane',
        requestId: 'usage-meter',
        props: {
          title: 'Usage',
          isFocused: false,
          bodyColumns: 60,
          placement: 'dock',
          scroll: { offset: 0, bodyRows: 10 },
          view: {},
        },
      })
      expect(await ui.find({ text: /43%/ })).toBeTruthy()
      expect(await ui.find({ text: /\$1\.23 this session/ })).toBeTruthy()
    }
  })
})
