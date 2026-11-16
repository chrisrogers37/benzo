import { useCallback, useEffect, useRef, useState } from 'react'

export const assertionRefreshInterval = 5000
const emptyObservation = (pollingPaused = false) => ({
  status: pollingPaused ? 'failure' : 'idle', snapshot: null,
  error: pollingPaused ? 'unsettled' : null, pollingPaused,
})
const wallClock = () => new Date()

// Deliberately fictional data: the website cannot inspect the visitor's Mac.
export const exampleSleepAssertions = {
  processes: [
    { pid: 410, processName: 'Music', friendlyName: 'Music', assertions: [
      { id: '0x1001', kind: 'idle', type: 'PreventUserIdleSystemSleep', description: 'Playing audio' },
    ] },
    { pid: 620, processName: 'backupd', friendlyName: 'Time Machine', assertions: [
      { id: '0x1002', kind: 'system', type: 'PreventSystemSleep', description: 'Backing up files' },
    ] },
  ],
  kernelSummary: 'No kernel assertions reported', kernelDetails: [], sleepPreventers: [],
}

export async function readDemoSleepAssertions() {
  return { status: 'success', value: exampleSleepAssertions }
}

/** Own one visible visit. Retain the in-flight slot until even a canceled reader settles. */
export function useSleepAssertions({ enabled, read = readDemoSleepAssertions, now = wallClock } = {}) {
  const [observation, setObservation] = useState(emptyObservation)
  const owner = useRef({ active: false, mounted: false, pollingPaused: false, generation: 0, request: null, timer: null, run: null })

  useEffect(() => {
    const state = owner.current
    state.mounted = true
    let pageHidden = false

    function stop() {
      state.active = false
      state.generation += 1
      clearTimeout(state.timer)
      state.timer = null
      state.request?.controller.abort()
    }

    function run() {
      if (!state.active || state.request || state.pollingPaused) return
      clearTimeout(state.timer)
      state.timer = null
      const request = { controller: new AbortController(), generation: state.generation }
      state.request = request
      // The last failure still qualifies retained data until a new read succeeds.
      setObservation(previous => ({ ...previous, status: 'loading' }))
      void (async () => {
        let result
        try {
          result = await read({ signal: request.controller.signal })
        } catch {
          result = { status: 'failure', error: 'failed' }
        }
        if (state.request !== request) return
        state.request = null
        // A bounded read can return before its child is confirmed stopped.
        // This applies even to a canceled prior visit: never launch a replacement.
        if (result?.status === 'failure' && result.error === 'unsettled') {
          state.pollingPaused = true
          clearTimeout(state.timer)
          state.timer = null
          if (state.mounted) setObservation(previous => ({ ...previous, status: 'failure', error: 'unsettled', pollingPaused: true }))
          return
        }
        if (!state.active || request.generation !== state.generation) {
          // A reopened visit waits here for the old read to release its slot.
          if (state.active) state.run?.()
          return
        }
        if (result?.status === 'success') {
          setObservation({ status: 'success', snapshot: { value: result.value, updatedAt: now() }, error: null, pollingPaused: false })
        } else {
          const error = ['failed', 'unsupported', 'malformed', 'incomplete'].includes(result?.error) ? result.error : 'failed'
          setObservation(previous => ({ ...previous, status: 'failure', error }))
        }
        state.timer = setTimeout(() => state.run?.(), assertionRefreshInterval)
      })()
    }

    function syncVisibility() {
      const active = Boolean(enabled) && !document.hidden && !pageHidden
      if (active === state.active) return
      stop()
      setObservation(active && !state.pollingPaused ? { ...emptyObservation(), status: 'loading' } : emptyObservation(state.pollingPaused))
      state.active = active
      if (active) run()
    }
    const hide = () => { pageHidden = true; syncVisibility() }
    const show = () => { pageHidden = false; syncVisibility() }
    state.run = run
    // A dependency change starts a new visit even if it remains enabled.
    setObservation(emptyObservation(state.pollingPaused))
    syncVisibility()
    window.addEventListener('pagehide', hide)
    window.addEventListener('pageshow', show)
    document.addEventListener('visibilitychange', syncVisibility)
    return () => {
      state.mounted = false
      stop()
      window.removeEventListener('pagehide', hide)
      window.removeEventListener('pageshow', show)
      document.removeEventListener('visibilitychange', syncVisibility)
    }
  }, [enabled, read, now])

  const refresh = useCallback(() => owner.current.run?.(), [])
  return { ...observation, refresh }
}
