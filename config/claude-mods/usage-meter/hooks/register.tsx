import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionMeasureInput, SessionUsage } from 'claude-code'

import type { Snapshot, Window } from '../types'

const PANE = 'usage-meter'
const WARN = 80
const CRITICAL = 95
const THRESHOLDS = [WARN, CRITICAL]
const BAR_WIDTH = 24

const snapshot = atom({ plugin: 'usage-meter', key: 'snapshot' } as const, null)
const warned = atom({ plugin: 'usage-meter', key: 'warned' } as const, {})

const LABELS: Record<string, string> = {
  five_hour: '5h',
  seven_day: '7d',
  spend_limit: 'Spend',
}

const label = (kind: string) => LABELS[kind] ?? kind

const toSnapshot = (u: SessionUsage | SessionMeasureInput): Snapshot => ({
  windows: u.rateLimits.map(w => ({ kind: w.kind, percentUsed: w.percentUsed, resetsAt: w.resetsAt })),
  costUsd: u.cost?.usd,
  contextPercent: u.context.percent,
})

const usd = (n: number) => `$${n < 10 ? n.toFixed(2) : n.toFixed(1)}`

export const statusText = (s: Snapshot): string | undefined => {
  const parts = s.windows.map(w => `${label(w.kind)} ${Math.round(w.percentUsed)}%`)
  if (s.costUsd !== undefined) parts.push(usd(s.costUsd))
  return parts.length ? parts.join(' · ') : undefined
}

export const until = (resetsAt: string | undefined, now: number): string | undefined => {
  const at = resetsAt ? Date.parse(resetsAt) : NaN
  if (Number.isNaN(at)) return undefined
  const minutes = Math.max(0, Math.round((at - now) / 60000))
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes % 60}m`
  return `${minutes}m`
}

export const bar = (percent: number, width = BAR_WIDTH): string => {
  const filled = Math.min(width, Math.round((Math.min(percent, 100) / 100) * width))
  return '█'.repeat(filled) + '░'.repeat(width - filled)
}

const colorOf = (percent: number) =>
  percent >= CRITICAL ? 'error' : percent >= WARN ? 'warning' : 'success'

const levelOf = (percent: number) => THRESHOLDS.filter(t => percent >= t).pop() ?? 0

const apply = async ($: EngineInterface, s: Snapshot) => {
  await update($, snapshot, () => s)
  $.ui.status(statusText(s))

  const seen = await read($, warned)
  const next: Record<string, number> = { ...seen }
  for (const w of s.windows) {
    const level = levelOf(w.percentUsed)
    if (level > (seen[w.kind] ?? 0)) {
      const resets = until(w.resetsAt, await $.clock.now())
      $.ui.toast(
        `${label(w.kind)} limit at ${Math.round(w.percentUsed)}%${resets ? `, resets in ${resets}` : ''}`,
        { timeoutMs: 8000 },
      )
    }
    // A drop below the last warned level means the window reset: warn again next time.
    next[w.kind] = level
  }
  await update($, warned, () => next)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'usage-meter',
      description: 'Show rate-limit windows and session cost in a pane',
    })
    const result = await next(e)
    await apply($, toSnapshot(await $.session.usage()))
    return result
  })

  on('session.measure', async ($, e, next) => {
    await apply($, toSnapshot(e))
    return next(e)
  })

  on('command.run', { command: 'usage-meter' }, async $ => {
    await apply($, toSnapshot(await $.session.usage()))
    await $.ui.open({ id: PANE, title: 'Usage' })
    return { text: 'Usage pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const s = await read($, snapshot)
    const now = await $.clock.now()
    const width = Math.max(8, Math.min(BAR_WIDTH, (e.props.bodyColumns ?? 40) - 16))

    if (!s) return <Text dimColor>No usage reading yet.</Text>

    return (
      <Box flexDirection="column">
        {s.windows.length === 0 && (
          <Text dimColor>No rate-limit windows (not on a subscription, or no response yet).</Text>
        )}
        {s.windows.map((w: Window) => {
          const resets = until(w.resetsAt, now)
          return (
            <Box key={w.kind} flexDirection="column">
              <Text>
                <Text bold>{label(w.kind).padEnd(5)}</Text>
                <Text color={colorOf(w.percentUsed)}>{bar(w.percentUsed, width)}</Text>
                <Text> {Math.round(w.percentUsed)}%</Text>
              </Text>
              {resets && <Text dimColor>{'     '}resets in {resets}</Text>}
            </Box>
          )
        })}
        {s.contextPercent !== undefined && (
          <Text>
            <Text bold>{'Ctx'.padEnd(5)}</Text>
            <Text color={colorOf(s.contextPercent)}>{bar(s.contextPercent, width)}</Text>
            <Text> {Math.round(s.contextPercent)}%</Text>
          </Text>
        )}
        {s.costUsd !== undefined && (
          <Text>
            <Text bold>{'Cost'.padEnd(5)}</Text>
            <Text>{usd(s.costUsd)} this session</Text>
          </Text>
        )}
      </Box>
    )
  })
}
