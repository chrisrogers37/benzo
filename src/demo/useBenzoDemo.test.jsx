// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, renderHook, screen } from '@testing-library/react'
import NativeAppDemo from '../landing/NativeAppDemo'
import { benzoDemoReducer as reduce, canSleep, initialDemoState, maximumSleepTickGap, useBenzoDemo } from './useBenzoDemo'

afterEach(cleanup)
const arm = (state = initialDemoState(), minutes = 5, now = 0) => reduce(state, { type: 'scheduleSleep', minutes, now })
const tick = (state, now, generation = state.sleepTimer?.generation) => reduce(state, { type: 'sleepTimerTick', now, generation })
const captured = state => ({ originals: state.originals, ownedValues: state.ownedValues, currentValues: state.currentValues, settings: state.settings, capturedAt: state.capturedAt })

function fakeTime() {
  let now = 0, nextID = 0
  const pending = new Map()
  const clock = { now: () => now }
  const scheduler = {
    setTimeout: vi.fn((callback, delay) => { const id = ++nextID; pending.set(id, { callback, delay }); return id }),
    clearTimeout: vi.fn(id => pending.delete(id)),
  }
  return {
    clock, scheduler, pending,
    next: (elapsed = 1000) => {
      const [id, { callback }] = pending.entries().next().value
      pending.delete(id)
      now += elapsed
      act(callback)
    },
  }
}

function Demo({ time }) {
  const [state, dispatch] = useBenzoDemo(time)
  return <NativeAppDemo state={state} dispatch={dispatch} />
}
const click = name => fireEvent.click(screen.getByRole('button', { name, exact: true }))

describe('sleep observations in the active demo', () => {
  it('owns reads only during Diagnostics and leaves power admission unchanged', async () => {
    vi.useFakeTimers()
    const value = { processes: [], kernelSummary: 'No kernel assertions reported', kernelDetails: [], sleepPreventers: [] }
    const read = vi.fn(async () => ({ status: 'success', value }))
    const { result, unmount } = renderHook(() => useBenzoDemo({ assertionRead: read }))
    const before = captured(result.current[0])
    expect(read).not.toHaveBeenCalled()
    await act(async () => result.current[1]({ type: 'diagnostics' }))
    expect(read).toHaveBeenCalledTimes(1)
    expect(result.current[0].sleepAssertions.status).toBe('success')
    expect(canSleep(result.current[0])).toBe(true)
    expect(captured(result.current[0])).toEqual(before)
    await act(async () => vi.advanceTimersByTimeAsync(5000))
    expect(read).toHaveBeenCalledTimes(2)
    await act(async () => result.current[1]({ type: 'back' }))
    await act(async () => vi.advanceTimersByTimeAsync(10000))
    expect(read).toHaveBeenCalledTimes(2)
    expect(result.current[0].sleepAssertions.snapshot).toBeNull()
    await act(async () => result.current[1]({ type: 'diagnostics' }))
    expect(read).toHaveBeenCalledTimes(3)
    await act(async () => result.current[1]({ type: 'quit' }))
    await act(async () => vi.advanceTimersByTimeAsync(10000))
    expect(read).toHaveBeenCalledTimes(3)
    expect(result.current[0].running).toBe(false)
    unmount()
    vi.useRealTimers()
  })

  it('renders the live section and its refresh control inside the keyboard scroll region', async () => {
    render(<Demo />)
    await act(async () => click('Diagnostics'))
    const heading = screen.getByRole('heading', { name: 'Keeping Your Mac Awake' })
    expect(heading.closest('[role="region"]').getAttribute('tabindex')).toBe('0')
    expect(screen.getByText('Playing audio')).toBeTruthy()
    expect(screen.getByText('Backing up files')).toBeTruthy()
    await act(async () => click('Refresh sleep activity'))
    click('Back')
    expect(screen.queryByRole('heading', { name: 'Keeping Your Mac Awake' })).toBeNull()
  })
})

describe('sleep admission and countdown reducer', () => {
  it.each([5, 15, 30, 60])('arms the %i minute preset without applying settings or changing originals', minutes => {
    const before = initialDemoState()
    const state = arm(before, minutes, 1234)
    expect(state.sleepTimer.deadline).toBe(1234 + minutes * 60_000)
    expect(state.sleepTimer.remainingSeconds).toBe(minutes * 60)
    expect(captured(state)).toEqual(captured(before))
    expect(state.operation).toBeNull()
    expect(state.sleepRequestInFlight).toBe(false)
  })

  it.each([
    { phase: 'off' }, { phase: 'checking' }, { phase: 'applying' }, { phase: 'restoring' }, { phase: 'recoveryRequired' },
    { hasSession: false }, { helperReadiness: 'notInstalled' }, { isPerformingHelperSetup: true }, { sleepCapability: false },
    { operation: 'uncertain' }, { quitPending: true }, { conflict: { key: 'powernap' } }, { legacyUnknown: true },
    { running: false }, { view: 'setup' }, { sleepRequestInFlight: true },
  ])('rejects immediate and timed actions directly for %j', overrides => {
    const state = { ...initialDemoState(), ...overrides }
    expect(canSleep(state)).toBe(false)
    for (const action of [{ type: 'sleep' }, { type: 'scheduleSleep', minutes: 5, now: 0 }]) {
      const blocked = reduce(state, action)
      expect(blocked.sleepTimer).toBeNull()
      expect(blocked.sleepRequestInFlight).toBe(state.sleepRequestInFlight)
      expect(blocked.sleepGeneration).toBe(state.sleepGeneration)
      expect(captured(blocked)).toEqual(captured(state))
    }
  })

  it.each([0, -1, 1, 4, 6, 120, '5', NaN, Infinity])('refuses invalid preset %s', minutes => {
    const before = initialDemoState()
    expect(arm(before, minutes)).toBe(before)
  })

  it('uses the elapsed deadline and sends exactly once at expiry', () => {
    const before = initialDemoState()
    let state = arm(before)
    state = tick(state, 1700)
    expect(state.sleepTimer.remainingSeconds).toBe(299)
    state = tick(state, 3100)
    expect(state.sleepTimer.remainingSeconds).toBe(297)
    for (let now = 4100; now < 300_000; now += 1000) state = tick(state, now)
    const generation = state.sleepTimer.generation
    state = tick(state, 300_000)
    expect(state.sleepRequestInFlight).toBe(true)
    expect(state.sleepTimer).toBeNull()
    expect(state.sleepMessage).toBe('Requesting Sleep…')
    expect(captured(state)).toEqual(captured(before))
    expect(tick(state, 300_100, generation)).toBe(state)
    expect(reduce(state, { type: 'sleep' }).sleepRequestGeneration).toBe(state.sleepRequestGeneration)
  })

  it.each(['cancelScheduledSleep', 'active', 'restore', 'quit', 'setup', 'checking', 'conflict', 'operationFailed', 'legacyUnknown', 'systemSleep', 'systemWake'])('cancels on %s and ignores an already queued tick', type => {
    const armed = arm()
    const state = reduce(armed, { type })
    expect(state.sleepTimer).toBeNull()
    expect(tick(state, 300_000, armed.sleepTimer.generation)).toBe(state)
    expect(state.sleepRequestInFlight).toBe(false)
  })

  it.each([
    { type: 'helperReadinessChanged', readiness: 'connectionUnavailable' },
    { type: 'sleepCapabilityChanged', available: false },
  ])('cancels on lost eligibility: %j', action => {
    const state = reduce(arm(), action)
    expect(state.sleepTimer).toBeNull()
    expect(state.sleepRequestInFlight).toBe(false)
  })

  it('rechecks eligibility on every tick even if state changed between callbacks', () => {
    const state = tick({ ...arm(), isPerformingHelperSetup: true }, 1000)
    expect(state.sleepTimer).toBeNull()
    expect(state.sleepRequestInFlight).toBe(false)
  })

  it.each([maximumSleepTickGap + 1, 300_001, -1])('cancels an interrupted or backward clock (%s ms) without dispatching', now => {
    const state = tick(arm(), now)
    expect(state.sleepTimer).toBeNull()
    expect(state.sleepMessage).toBe('Sleep timer canceled after an interruption.')
    expect(state.sleepRequestInFlight).toBe(false)
  })

  it('rearming and reset invalidate stale ticks and stale request completions', () => {
    const first = arm()
    const second = arm(first, 15, 500)
    expect(tick(second, 300_000, first.sleepTimer.generation)).toBe(second)
    const reset = arm(reduce(second, { type: 'reset' }))
    expect(tick(reset, 900_500, second.sleepTimer.generation)).toBe(reset)
    const pending = reduce(reset, { type: 'sleep' })
    const replacement = reduce(reduce(pending, { type: 'reset' }), { type: 'sleep' })
    expect(reduce(replacement, { type: 'sleepRequestSettled', generation: pending.sleepRequestGeneration })).toBe(replacement)
    const launch = reduce(first, { type: 'firstLaunch' })
    expect(tick(launch, 300_000, first.sleepTimer.generation)).toBe(launch)
  })

  it('keeps sent requests pending through cancellation and blocks settings work until settled', () => {
    const pending = reduce(arm(), { type: 'sleep' })
    for (const type of ['cancelScheduledSleep', 'systemSleep', 'systemWake']) {
      expect(reduce(pending, { type })).toBe(pending)
    }
    for (const type of ['active', 'restore', 'retry', 'restoreRecordedOriginal', 'keepCurrent', 'quitAnyway', 'setup', 'replaceHelper', 'removeHelper']) {
      const blocked = reduce(pending, { type })
      expect(blocked.sleepRequestInFlight).toBe(true)
      expect(blocked.phase).toBe('activeVerified')
      expect(blocked.operation).toBeNull()
      expect(captured(blocked)).toEqual(captured(pending))
      expect(blocked.error).toContain('Wait for the sleep request')
    }
    const queued = reduce(pending, { type: 'quit' })
    expect(queued.quitPending).toBe(true)
    expect(queued.phase).toBe('activeVerified')
    const finished = reduce(queued, { type: 'sleepRequestSettled', generation: queued.sleepRequestGeneration })
    expect(finished.sleepMessage).toBe('Sleep request sent.')
    expect(finished.sleepRequestInFlight).toBe(false)
    expect(finished.phase).toBe('restoring')
    const closed = reduce(finished, { type: 'restoreSucceeded' })
    expect(closed.running).toBe(false)
    expect(closed.currentValues).toEqual(closed.originals)
  })

  it('preserves recovery and missing access if a pending quit settles', () => {
    const pending = reduce(initialDemoState(), { type: 'sleep' })
    for (const action of [{ type: 'conflict' }, { type: 'helperReadinessChanged', readiness: 'connectionUnavailable' }]) {
      let state = reduce(reduce(pending, action), { type: 'quit' })
      state = reduce(state, { type: 'sleepRequestSettled', generation: state.sleepRequestGeneration })
      expect(state.running).toBe(true)
      expect(state.operation).toBeNull()
      expect(state.hasSession).toBe(true)
      expect(state.error).toBeTruthy()
    }
  })

  it('keeps old-tool apply and restore working, requiring an explicit Off update for sleep', () => {
    let state = { ...initialDemoState(false), sleepCapability: false }
    state = reduce(reduce(state, { type: 'active' }), { type: 'applySucceeded' })
    expect(state.phase).toBe('activeVerified')
    expect(canSleep(state)).toBe(false)
    expect(reduce(state, { type: 'replaceHelper' })).toBe(state)
    state = reduce(reduce(state, { type: 'restore' }), { type: 'restoreSucceeded' })
    expect(state.phase).toBe('off')
    state = reduce(state, { type: 'replaceHelper' })
    expect(state.sleepCapability).toBe(true)
    state = reduce(reduce(state, { type: 'active' }), { type: 'applySucceeded' })
    expect(canSleep(state)).toBe(true)
  })
})

describe('sleep simulation and accessible controls', () => {
  it.each([5, 15, 30, 60])('selects %i minutes, closes the picker, retains on panel close, and cancels accessibly', minutes => {
    const time = fakeTime()
    render(<Demo time={time} />)
    click('Sleep timer')
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Sleep in 5 minutes' }))
    click(`Sleep in ${minutes} minutes`)
    expect(screen.queryByRole('group', { name: 'Sleep timer duration' })).toBeNull()
    const cancel = screen.getByRole('button', { name: 'Cancel sleep timer' })
    expect(document.activeElement).toBe(cancel)
    expect(cancel.getAttribute('aria-description')).toBe(`${minutes}:00 remaining`)
    click('Benzo menu')
    time.next(1700)
    click('Benzo menu')
    expect(screen.getByRole('button', { name: 'Cancel sleep timer' }).getAttribute('aria-description')).toBe(`${minutes - 1}:59 remaining`)
    click('Cancel sleep timer')
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Sleep Now' }))
    expect(time.pending.size).toBe(0)
  })

  it('closes only the timer picker on Escape and restores focus', () => {
    render(<Demo time={fakeTime()} />)
    click('Sleep timer')
    fireEvent.keyDown(document.activeElement, { key: 'Escape' })
    expect(screen.queryByRole('group', { name: 'Sleep timer duration' })).toBeNull()
    expect(document.activeElement).toBe(screen.getByRole('button', { name: 'Sleep timer' }))
    expect(screen.getByRole('button', { name: 'Sleep Now' })).toBeTruthy()
  })

  it.each(['immediate', 'timer'])('shares the pending and result path for %s sleep without mutating settings', mode => {
    const time = fakeTime()
    const { result } = renderHook(() => useBenzoDemo(time))
    const before = result.current[0]
    act(() => result.current[1](mode === 'immediate' ? { type: 'sleep' } : { type: 'scheduleSleep', minutes: 5 }))
    if (mode === 'timer') for (let second = 0; second < 300; second++) time.next()
    expect(result.current[0].sleepRequestInFlight).toBe(true)
    expect(result.current[0].sleepMessage).toBe('Requesting Sleep…')
    expect(time.pending.size).toBe(1)
    time.next(400)
    expect(result.current[0].sleepMessage).toBe('Sleep request sent.')
    expect(result.current[0].sleepRequestInFlight).toBe(false)
    expect(captured(result.current[0])).toEqual(captured(before))
    expect(time.pending.size).toBe(0)
  })

  it('keeps a queued quit waiting while rendering the sent-request state honestly', () => {
    const time = fakeTime()
    render(<Demo time={time} />)
    click('Sleep Now')
    expect(screen.getByRole('button', { name: 'Requesting Sleep…' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Sleep timer' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Restore Settings' }).disabled).toBe(true)
    expect(screen.getByRole('switch', { name: 'Restore captured settings' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Manage Power Access' }).disabled).toBe(true)
    click('Quit')
    expect(screen.getByRole('button', { name: 'Requesting Sleep…' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Quit Anyway' })).toBeNull()
    time.next(400)
    expect(screen.getByText('Demo closed.')).toBeTruthy()
  })

  it('uses injected clock elapsed time to cancel a resumed callback and ignores it after reset/rearm', () => {
    const time = fakeTime()
    const { result } = renderHook(() => useBenzoDemo(time))
    act(() => result.current[1]({ type: 'scheduleSleep', minutes: 5 }))
    const oldCallback = [...time.pending.values()][0].callback
    time.next(300_001)
    expect(result.current[0].sleepTimer).toBeNull()
    expect(result.current[0].sleepRequestInFlight).toBe(false)
    act(() => result.current[1]({ type: 'reset' }))
    act(() => result.current[1]({ type: 'scheduleSleep', minutes: 15 }))
    const next = result.current[0]
    act(oldCallback)
    expect(result.current[0]).toBe(next)
  })

  it.each(['pagehide', 'pageshow', 'visibilitychange'])('cancels browser interruption %s without replaying on resume', eventName => {
    const time = fakeTime()
    const { result } = renderHook(() => useBenzoDemo(time))
    act(() => result.current[1]({ type: 'scheduleSleep', minutes: 5 }))
    const visibility = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden')
    try {
      act(() => (eventName === 'visibilitychange' ? document : window).dispatchEvent(new Event(eventName)))
      expect(result.current[0].sleepTimer).toBeNull()
      expect(result.current[0].sleepRequestInFlight).toBe(false)
      expect(time.pending.size).toBe(0)
      act(() => window.dispatchEvent(new Event('pageshow')))
      expect(time.pending.size).toBe(0)
    } finally { visibility.mockRestore() }
  })

  it('shows only the old-tool upgrade hint and exposes explicit update while Off', () => {
    const old = { ...initialDemoState(false), sleepCapability: false }
    const { rerender } = render(<NativeAppDemo state={old} dispatch={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Sleep Now' }).disabled).toBe(true)
    expect(screen.getByRole('switch', { name: 'Apply selected settings' }).disabled).toBe(false)
    expect(screen.getByText('Update power access to enable Sleep Now and its timer.')).toBeTruthy()
    rerender(<NativeAppDemo state={{ ...old, view: 'setup' }} dispatch={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Advanced' }).getAttribute('aria-expanded')).toBe('true')
    expect(screen.getByRole('button', { name: 'Repair / Update Power Access' }).disabled).toBe(false)
  })
})
