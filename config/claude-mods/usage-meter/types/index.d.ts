export type Window = { kind: string; percentUsed: number; resetsAt?: string }

export type Snapshot = {
  windows: Window[]
  costUsd?: number
  contextPercent?: number
}

declare module 'claude-code' {
  interface PluginState {
    'usage-meter': {
      snapshot: Snapshot | null
      // Highest warning threshold already toasted, per window kind.
      warned: Record<string, number>
    }
  }
}
