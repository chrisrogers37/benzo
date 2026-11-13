// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, renderHook, screen, within } from '@testing-library/react'
import NativeAppDemo from './NativeAppDemo'
import { benzoDemoReducer, initialDemoState, useBenzoDemo } from '../demo/useBenzoDemo'

function Demo() {
  const [state, dispatch] = useBenzoDemo()
  return <NativeAppDemo state={state} dispatch={dispatch} />
}

const click = (name) => fireEvent.click(screen.getByRole('button', { name, exact: true }))
function completeSetup() {
  click('Helper Setup')
  click('Set Up')
  click('Open System Settings')
  click('Simulate macOS Approval')
  click('Authorize This Account')
  click('Done')
}
const panel = name => screen.getByRole('heading', { name, exact: true }).parentElement
const success = value => ({ status: 'success', value })
const diagnosticFixture = overrides => ({
  running: true, open: true, view: 'diagnostics', active: false,
  sleepData: success({ sessions: [], lastWakeReason: null }),
  usbDevices: success([]),
  observedSettings: success([{ key: 'hibernatemode', actualValue: '25' }, { key: 'womp', actualValue: null }]),
  ...overrides,
})
afterEach(() => { cleanup(); vi.useRealTimers() })

describe('source-matched browser simulation', () => {
  it('keeps originals immutable, freezes choices during apply, and unlocks only after verified restore', () => {
    const original = initialDemoState(false)
    let state = benzoDemoReducer(original, { type: 'setting', key: 'disableTcpKeepAlive' })
    state = benzoDemoReducer(state, { type: 'active' })
    expect(state.phase).toBe('applying')
    expect(benzoDemoReducer(state, { type: 'setting', key: 'disablePowerNap' }).settings).toEqual(state.settings)
    state = benzoDemoReducer(state, { type: 'applySucceeded' })
    expect(state.phase).toBe('activeVerified')
    expect(state.originals).not.toBe(original.originals)
    expect(state.originals).toEqual(original.originals)
    expect(state.currentValues.tcpkeepalive).toBe('0')
    state = benzoDemoReducer(state, { type: 'restore' })
    expect(state.phase).toBe('restoring')
    const capturedSettings = state.settings
    const capturedOriginals = state.originals
    state = benzoDemoReducer(state, { type: 'operationFailed', message: 'Restore did not verify.' })
    expect(state.phase).toBe('recoveryRequired')
    expect(state.settings).toBe(capturedSettings)
    expect(state.originals).toBe(capturedOriginals)
    state = benzoDemoReducer(state, { type: 'retry' })
    expect(state.phase).toBe('restoring')
    state = benzoDemoReducer(state, { type: 'restoreSucceeded' })
    expect(state.phase).toBe('off')
    expect(state.currentValues).toEqual(state.originals)
    expect(state.settings.disableTcpKeepAlive).toBe(true)
  })

  it('returns an all-no-op apply directly to Off without retaining a session', () => {
    let state = { ...initialDemoState(false), currentValues: { powernap: '0', womp: '0', tcpkeepalive: '1' } }
    state = benzoDemoReducer(state, { type: 'active' })
    state = benzoDemoReducer(state, { type: 'applySucceeded' })
    expect(state.phase).toBe('off')
    expect(state.hasSession).toBe(false)
    expect(state.ownedValues).toEqual({})
    expect(state.capturedAt).toBeNull()
  })

  it('refuses unsupported settings and preserves originals and selection after uncertain failure', () => {
    const off = initialDemoState(false)
    expect(benzoDemoReducer(off, { type: 'setting', key: 'hibernateMode' }).settings).toEqual(off.settings)
    expect(benzoDemoReducer(off, { type: 'setting', key: 'disableProximityWake' }).settings).toEqual(off.settings)
    let state = benzoDemoReducer(off, { type: 'active' })
    state = benzoDemoReducer(state, { type: 'operationFailed', uncertain: true })
    const selection = state.settings
    const captured = state.originals
    state = benzoDemoReducer(state, { type: 'retry' })
    expect(state.phase).toBe('recoveryRequired')
    expect(state.error).toContain('no new write is allowed')
    expect(state.settings).toBe(selection)
    expect(state.originals).toBe(captured)
    const midWrite = benzoDemoReducer(off, { type: 'active' })
    const quit = benzoDemoReducer(midWrite, { type: 'quit' })
    expect(quit.phase).toBe('applying')
    expect(quit.quitPending).toBe(true)
    const applied = benzoDemoReducer(quit, { type: 'applySucceeded' })
    expect(applied.phase).toBe('restoring')
    expect(applied.quitPending).toBe(true)
    expect(benzoDemoReducer(applied, { type: 'restoreSucceeded' }).running).toBe(false)
  })

  it('requires explicit conflict resolution and leaves legacy evidence requiring administrator help', () => {
    let state = benzoDemoReducer(initialDemoState(true), { type: 'conflict' })
    expect(state.phase).toBe('recoveryRequired')
    state = benzoDemoReducer(state, { type: 'deferConflict' })
    expect(state.phase).toBe('recoveryRequired')
    state = benzoDemoReducer(state, { type: 'keepCurrent' })
    expect(state.phase).toBe('recoveryRequired')
    expect(state.ownedValues).toEqual({ womp: '0' })
    expect(state.currentValues.powernap).toBe('0')
    state = benzoDemoReducer(state, { type: 'retry' })
    state = benzoDemoReducer(state, { type: 'restoreSucceeded' })
    expect(state.phase).toBe('off')
    expect(state.currentValues.powernap).toBe('0')
    expect(state.currentValues.womp).toBe('1')
    expect(state.currentValues.tcpkeepalive).toBe('1')

    let restoreConflict = benzoDemoReducer(initialDemoState(true), { type: 'conflict', conflict: { key: 'powernap', currentValue: '0', lastVerified: null } })
    restoreConflict = benzoDemoReducer(restoreConflict, { type: 'restoreRecordedOriginal' })
    restoreConflict = benzoDemoReducer(restoreConflict, { type: 'restoreSucceeded' })
    expect(restoreConflict.phase).toBe('recoveryRequired')
    expect(restoreConflict.currentValues.powernap).toBe('1')
    expect(restoreConflict.currentValues.womp).toBe('0')
    expect(restoreConflict.currentValues.tcpkeepalive).toBe('1')
    expect(restoreConflict.ownedValues).toEqual({ womp: '0' })
    restoreConflict = benzoDemoReducer(restoreConflict, { type: 'restore' })
    restoreConflict = benzoDemoReducer(restoreConflict, { type: 'restoreSucceeded' })
    expect(restoreConflict.currentValues.womp).toBe('1')

    state = benzoDemoReducer({ ...initialDemoState(true), phase: 'recoveryRequired' }, { type: 'operationFailed', message: 'Restore failed.' })
    const ownedBeforeRefresh = state.ownedValues
    const currentBeforeRefresh = state.currentValues
    state = benzoDemoReducer(state, { type: 'refreshRecovery' })
    expect(state.phase).toBe('checking')
    state = benzoDemoReducer(state, { type: 'checkingSucceeded' })
    expect(state.phase).toBe('recoveryRequired')
    expect(state.ownedValues).toBe(ownedBeforeRefresh)
    expect(state.currentValues).toBe(currentBeforeRefresh)

    const conflictAtQuit = benzoDemoReducer({ ...initialDemoState(true), phase: 'recoveryRequired', conflict: { key: 'powernap', currentValue: '0' } }, { type: 'quit' })
    const checkingQuit = benzoDemoReducer(conflictAtQuit, { type: 'checking' })
    const refreshedQuit = benzoDemoReducer(checkingQuit, { type: 'checkingSucceeded' })
    expect(refreshedQuit.phase).toBe('recoveryRequired')
    expect(refreshedQuit.running).toBe(true)
    expect(refreshedQuit.ownedValues).toBe(conflictAtQuit.ownedValues)

    state = benzoDemoReducer(state, { type: 'conflict', conflict: { key: 'powernap', currentValue: 0 } })
    state = benzoDemoReducer(state, { type: 'keepCurrent' })
    state = benzoDemoReducer(state, { type: 'retry' })
    state = benzoDemoReducer(state, { type: 'restoreSucceeded' })
    expect(state.phase).toBe('off')
    state = benzoDemoReducer(state, { type: 'active' })
    expect(state.originals.powernap).toBe('0')
    state = benzoDemoReducer(state, { type: 'applySucceeded' })
    expect(state.ownedValues).toEqual({ womp: '0' })

    state = benzoDemoReducer(state, { type: 'legacyUnknown' })
    const preserved = state.originals
    state = benzoDemoReducer(state, { type: 'retry' })
    expect(state.phase).toBe('recoveryRequired')
    expect(state.originals).toBe(preserved)
    expect(state.error).toContain('administrator')
  })

  it('offers stay open and explicit quit anyway when restoration cannot be verified', () => {
    let state = benzoDemoReducer(initialDemoState(true), { type: 'quit' })
    state = benzoDemoReducer(state, { type: 'operationFailed', message: 'Restore failed.' })
    expect(state.quitPending).toBe(true)
    state = benzoDemoReducer(state, { type: 'stayOpen' })
    expect(state.running).toBe(true)
    state = benzoDemoReducer({ ...state, quitPending: true }, { type: 'quitAnyway' })
    expect(state.running).toBe(false)
    expect(state.originals).toBe(initialDemoState(true).originals)
  })

  it('offers Retry, Stay Open, and Quit Anyway after a known failed quit restore', () => {
    const dispatch = vi.fn()
    const state = { ...initialDemoState(true), phase: 'recoveryRequired', quitPending: true, error: 'Restore failed.' }
    render(<NativeAppDemo state={state} dispatch={dispatch} />)
    for (const name of ['Retry', 'Stay Open', 'Quit Anyway']) expect(screen.getByRole('button', { name, exact: true })).toBeTruthy()
  })

  it('exposes busy and recovery status from the menu bar while the popover is closed', () => {
    const dispatch = vi.fn()
    const { rerender } = render(<NativeAppDemo state={{ ...initialDemoState(true), open: false, phase: 'applying' }} dispatch={dispatch} />)
    let menu = screen.getByRole('button', { name: 'Benzo menu' })
    expect(menu.getAttribute('aria-description')).toContain('Benzo: Applying Settings.')
    expect(menu.title).toContain('Applying your frozen selection')
    expect(menu.querySelector('[data-status="busy"]')).toBeTruthy()
    expect(screen.queryByRole('switch', { name: 'Deep Sleep' })).toBeNull()

    rerender(<NativeAppDemo state={{ ...initialDemoState(true), open: false, phase: 'recoveryRequired', error: 'Restore failed.' }} dispatch={dispatch} />)
    menu = screen.getByRole('button', { name: 'Benzo menu' })
    expect(menu.getAttribute('aria-description')).toContain('Benzo: Recovery Required.')
    expect(menu.title).toContain('Restore failed.')
    expect(menu.querySelector('[data-status="recovery"]')).toBeTruthy()
    expect(screen.queryByRole('switch', { name: 'Deep Sleep' })).toBeNull()
  })

  it('disables the master without an available Off selection and disables restore without a session', () => {
    const emptySelection = { ...initialDemoState(false), settings: Object.fromEntries(Object.keys(initialDemoState(false).settings).map(key => [key, false])) }
    const { rerender } = render(<NativeAppDemo state={emptySelection} dispatch={vi.fn()} />)
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'System Defaults' }).disabled).toBe(true)

    rerender(<NativeAppDemo state={{ ...emptySelection, phase: 'recoveryRequired', legacyUnknown: true }} dispatch={vi.fn()} />)
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'System Defaults' }).disabled).toBe(true)
    expect(screen.getByText('Legacy or unknown recovery evidence needs administrator-assisted recovery and retirement. Preserve ~/Library/Application Support/Benzo/original-pmset.json and /private/etc/sudoers.d/benzo. This app cannot substantiate their profile ownership or mark them restored.')).toBeTruthy()
  })

  it('renders native recovery conflict evidence and requires conflict resolution before System Defaults', () => {
    let state = benzoDemoReducer(initialDemoState(true), { type: 'conflict' })
    const dispatch = vi.fn()
    const { rerender } = render(<NativeAppDemo state={state} dispatch={dispatch} />)
    expect(screen.getByText('Captured Nov 4, 2026 at 9:00 AM (example)')).toBeTruthy()
    expect(screen.getByText('Disable Power Nap · AC Power (simulated Mac Mini)')).toBeTruthy()
    expect(screen.getByText('Recorded original: 1. Observed now: 0.')).toBeTruthy()
    expect(screen.getByText('Last verified Benzo value: none. Other tools can change settings after this observation.')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'System Defaults' }).disabled).toBe(true)
    expect(screen.queryByRole('button', { name: 'Retry' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Refresh Recovery Status' }))
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'refreshRecovery' })

    state = benzoDemoReducer(state, { type: 'deferConflict' })
    rerender(<NativeAppDemo state={state} dispatch={dispatch} />)
    expect(screen.getByText('Conflict deferred; recovery evidence is retained.')).toBeTruthy()
    expect(screen.queryByText('Recorded original: 1. Observed now: 0.')).toBeNull()
    expect(screen.queryByRole('button', { name: 'Keep Current' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Review' }))
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'reviewConflict' })

    const unavailable = benzoDemoReducer(initialDemoState(true), { type: 'conflict', conflict: { key: 'powernap', currentValue: '3' } })
    rerender(<NativeAppDemo state={unavailable} dispatch={dispatch} />)
    expect(screen.getByText('Recorded original: 1. Observed now: Not reported.')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Keep Current' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Restore Recorded Original Anyway' }).disabled).toBe(true)
  })

  it('uses read-only Refresh Recovery Status in ordinary recovery', () => {
    const dispatch = vi.fn()
    render(<NativeAppDemo state={{ ...initialDemoState(true), phase: 'recoveryRequired', error: 'Restore failed.' }} dispatch={dispatch} />)
    fireEvent.click(screen.getByRole('button', { name: 'Refresh Recovery Status' }))
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'refreshRecovery' })
    expect(screen.queryByRole('button', { name: 'Retry' })).toBeNull()
  })

  it('allows restore for an active no-op session even when it owns no changed cells', () => {
    const noOpSession = { ...initialDemoState(true), ownedValues: {}, hasSession: true }
    render(<NativeAppDemo state={noOpSession} dispatch={vi.fn()} />)
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(false)
    expect(screen.getByRole('button', { name: 'System Defaults' }).disabled).toBe(false)
  })

  it('starts in main with setup available and keeps diagnostics reachable before setup', () => {
    render(<Demo />)
    click('First launch')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Helper Setup' })).toBeTruthy()
    expect(screen.queryByText('Permission status')).toBeNull()
    click('View diagnostics')
    expect(screen.getByText('Diagnostics')).toBeTruthy()
    click('Benzo menu')
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.getByText('Diagnostics')).toBeTruthy()
    click('Back')
    click('Helper Setup')
    click('Check Again')
    expect(screen.getByText('Set Up Benzo')).toBeTruthy()
    expect(screen.getByRole('status').textContent).toContain('No permission was requested or changed')
  })

  it('opens main after normally reopening setup even if diagnostics was previously requested', () => {
    render(<Demo />)
    click('First launch')
    click('View diagnostics')
    click('Benzo menu'); click('Benzo menu')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
    expect(screen.queryByText('Diagnostics')).toBeNull()
  })

  it('disables Sleep Now with an explanation and omits timer and blocker controls', () => {
    render(<Demo />)
    const sleepButton = screen.getByRole('button', { name: 'Sleep Now' })
    expect(sleepButton.disabled).toBe(true)
    expect(document.getElementById(sleepButton.getAttribute('aria-describedby')).textContent).toBe('Sleep Now is unavailable for this manual apply-and-restore workflow.')
    expect(screen.queryByRole('button', { name: /timer/i })).toBeNull()
    expect(screen.queryByText('caffeinate')).toBeNull()
    expect(screen.queryByText(/app may prevent sleep/)).toBeNull()
    click('First launch')
    click('Sleep Now')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('false')
    expect(screen.getByRole('button', { name: 'Sleep Now' }).disabled).toBe(true)
  })

  it.each([
    ['active', []],
    ['before activation', ['firstLaunch', 'back']],
    ['after Restore', ['restore']],
  ])('refuses direct sleep actions %s without changing state or queuing work', (_label, actions) => {
    vi.useFakeTimers()
    const { result } = renderHook(useBenzoDemo)
    for (const type of actions) act(() => result.current[1]({ type }))
    const before = result.current[0]
    act(() => result.current[1]({ type: 'sleep' }))
    expect(result.current[0]).toEqual({ ...before, error: 'Sleep Now is unavailable for this manual apply-and-restore workflow.' })
    expect(vi.getTimerCount()).toBe(0)
    act(() => vi.advanceTimersByTime(3600000))
    expect(result.current[0]).toEqual({ ...before, error: 'Sleep Now is unavailable for this manual apply-and-restore workflow.' })
  })

  it('allows only reported target choices while Off and unlocks after captured restore', () => {
    render(<Demo />)
    const initialSetting = screen.getByRole('checkbox', { name: 'Hibernate Mode' })
    expect(initialSetting.disabled).toBe(true)
    expect(document.getElementById(initialSetting.getAttribute('aria-describedby')).textContent).toBe('Unavailable: AC Power does not report hibernatemode, autopoweroff.')
    click('First launch'); completeSetup(); click('Options')
    const setting = screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' })
    expect(setting.disabled).toBe(false)
    expect(screen.queryByText('Resolve the current session or recovery before changing settings.')).toBeNull()
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    expect(setting.disabled).toBe(true)
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    click('System Defaults')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('false')
    expect(setting.disabled).toBe(false)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('false')
    expect(screen.getByRole('status').textContent).toContain('editable again')
    click('Options')
    expect(screen.queryByRole('checkbox')).toBeNull()
    click('Options')
    expect(screen.getByRole('checkbox', { name: 'Hibernate Mode' }).disabled).toBe(true)
  })

  it.each([
    ['active', []],
  ])('refuses direct setting actions %s and preserves the backup', (_label, actions) => {
    const { result } = renderHook(useBenzoDemo)
    for (const type of actions) act(() => result.current[1]({ type }))
    const before = result.current[0]
    expect(before.phase).not.toBe('off')
    act(() => result.current[1]({ type: 'setting', key: 'disableTcpKeepAlive' }))
    expect(result.current[0]).toEqual({ ...before, error: 'Resolve the current session or recovery before changing settings.' })
  })

  it('requires distinct simulated OS approval and account authorization before enabling writes', () => {
    render(<Demo />)
    click('First launch')
    click('Helper Setup')
    click('Set Up')
    expect(screen.getByText('Approve Benzo in System Settings')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Authorize This Account' })).toBeNull()
    click('Open System Settings')
    click('Check Again')
    expect(screen.getByText('Approve Benzo in System Settings')).toBeTruthy()
    click('Simulate macOS Approval')
    expect(screen.getByRole('button', { name: 'Authorize This Account' })).toBeTruthy()
    click('Back')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(true)
    click('Helper Setup')
    click('Authorize This Account')
    expect(screen.getByText('Benzo Is Ready')).toBeTruthy()
    click('Done')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(false)
    expect(screen.getByRole('button', { name: 'System Defaults' }).disabled).toBe(true)
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it.each([
    ['differentAccount', 'Benzo Is Set Up for Another Account'],
    ['connectionUnavailable', 'Benzo’s Helper Is Unavailable'],
    ['incompatible', 'Benzo Needs a Matching Helper'],
    ['signingUnavailable', 'Setup Is Unavailable in This Build'],
    ['executionUncertain', 'Helper Recovery Required'],
  ])('renders %s without offering unsupported enable actions', (helperReadiness, text) => {
    const dispatch = vi.fn()
    render(<NativeAppDemo state={{ ...initialDemoState(false), view: 'setup', helperReadiness }} dispatch={dispatch} />)
    expect(screen.getByText(text)).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Set Up', exact: true })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Authorize This Account' })).toBeNull()
    click('Check Again')
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'refreshHelper' })
    click('Back')
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'back' })
  })

  it('keeps refresh and Back independent of settings, recovery evidence, and active state', () => {
    const { result } = renderHook(useBenzoDemo)
    act(() => result.current[1]({ type: 'firstLaunch' }))
    const before = result.current[0]
    act(() => result.current[1]({ type: 'refreshHelper' }))
    expect(result.current[0]).toEqual({ ...before, notice: 'Setup status refresh simulated. No permission was requested or changed.' })
    const refreshed = result.current[0]
    act(() => result.current[1]({ type: 'back' }))
    expect(result.current[0]).toEqual({ ...refreshed, view: 'main' })
    const returned = result.current[0]
    act(() => result.current[1]({ type: 'setup' }))
    expect(result.current[0]).toEqual({ ...returned, view: 'setup' })
  })

  it('offers explicit helper replacement only for an incompatible helper while Off', () => {
    const before = { ...initialDemoState(false), helperReadiness: 'incompatible', view: 'setup' }
    const refreshed = benzoDemoReducer(before, { type: 'refreshHelper' })
    expect(refreshed.helperReadiness).toBe('incompatible')
    const dispatch = vi.fn()
    render(<NativeAppDemo state={refreshed} dispatch={dispatch} />)
    const replace = screen.getByRole('button', { name: 'Replace Helper' })
    expect(replace.disabled).toBe(false)
    expect(screen.queryByText('Restore or resolve the current settings session before replacing Benzo’s helper. If needed, use the previous Benzo release to restore settings.')).toBeNull()
    fireEvent.click(replace)
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'replaceHelper' })
    const replaced = benzoDemoReducer(refreshed, { type: 'replaceHelper' })
    expect(replaced.helperReadiness).toBe('ready')
    expect(replaced.currentValues).toBe(before.currentValues)
    expect(replaced.originals).toBe(before.originals)
    expect(replaced.hasSession).toBe(false)
  })

  it.each([
    { phase: 'activeVerified', hasSession: true },
    { phase: 'recoveryRequired', hasSession: true },
    { phase: 'recoveryRequired', hasSession: false, legacyUnknown: true },
    { phase: 'off', hasSession: true },
    { phase: 'off', operation: 'uncertain' },
    { phase: 'applying' },
  ])('blocks helper replacement and retains evidence for %j', overrides => {
    const state = { ...initialDemoState(false), helperReadiness: 'incompatible', view: 'setup', ...overrides }
    const dispatch = vi.fn()
    render(<NativeAppDemo state={state} dispatch={dispatch} />)
    expect(screen.getByRole('button', { name: 'Replace Helper' }).disabled).toBe(true)
    expect(screen.getByText('Restore or resolve the current settings session before replacing Benzo’s helper. If needed, use the previous Benzo release to restore settings.')).toBeTruthy()
    expect(benzoDemoReducer(state, { type: 'replaceHelper' })).toBe(state)
  })

  it('disables duplicate replacement while setup is busy', () => {
    const state = { ...initialDemoState(false), helperReadiness: 'incompatible', view: 'setup', isPerformingHelperSetup: true }
    render(<NativeAppDemo state={state} dispatch={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Replace Helper' }).disabled).toBe(true)
    expect(benzoDemoReducer(state, { type: 'replaceHelper' })).toBe(state)
  })

  it('blocks writes and ordinary quit during setup even if a concurrent status check reports ready', () => {
    const state = { ...initialDemoState(false), helperReadiness: 'ready', isPerformingHelperSetup: true }
    render(<NativeAppDemo state={state} dispatch={vi.fn()} />)
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).disabled).toBe(true)
    for (const type of ['active', 'restore', 'retry', 'restoreRecordedOriginal', 'quit']) {
      const blocked = benzoDemoReducer(state, { type })
      expect(blocked).toEqual({ ...state, error: 'Finish helper setup before changing settings or quitting Benzo.' })
    }
  })

  it.each(['notInstalled', 'requiresApproval', 'needsOwnerAuthorization', 'ready', 'differentAccount', 'connectionUnavailable', 'signingUnavailable', 'executionUncertain'])('never offers or performs replacement for %s', helperReadiness => {
    const state = { ...initialDemoState(false), helperReadiness, view: 'setup' }
    render(<NativeAppDemo state={state} dispatch={vi.fn()} />)
    expect(screen.queryByRole('button', { name: 'Replace Helper' })).toBeNull()
    expect(benzoDemoReducer(state, { type: 'replaceHelper' })).toBe(state)
  })

  it('matches native Option-click semantics and offers a touch-accessible diagnostic path', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.queryByRole('switch', { name: 'Deep Sleep' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.getByText('Diagnostics')).toBeTruthy()
    expect(screen.getByText('Reported by pmset. Changes are not verified.')).toBeTruthy()
    click('Back')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
    click('View diagnostics')
    click('Benzo menu'); click('Benzo menu')
    expect(screen.queryByText('Diagnostics')).toBeNull()
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
  })

  it.each(['notInstalled', 'requiresApproval', 'needsOwnerAuthorization', 'differentAccount', 'connectionUnavailable', 'incompatible', 'signingUnavailable', 'executionUncertain'])('blocks writes with %s without erasing session evidence', helperReadiness => {
    const active = { ...initialDemoState(true), helperReadiness }
    for (const type of ['active', 'restore', 'retry', 'restoreRecordedOriginal']) {
      const blocked = benzoDemoReducer(active, { type })
      expect(blocked.phase).toBe('activeVerified')
      expect(blocked.ownedValues).toBe(active.ownedValues)
      expect(blocked.originals).toBe(active.originals)
      expect(blocked.currentValues).toBe(active.currentValues)
      expect(blocked.hasSession).toBe(true)
    }
    const quitting = benzoDemoReducer(active, { type: 'quit' })
    expect(quitting.quitPending).toBe(true)
    expect(quitting.running).toBe(true)
    expect(quitting.phase).toBe('activeVerified')
    render(<NativeAppDemo state={quitting} dispatch={vi.fn()} />)
    expect(screen.getByRole('button', { name: 'Retry' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Stay Open' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Quit Anyway' })).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Helper Setup' })).toBeTruthy()
    const quitAnyway = benzoDemoReducer(quitting, { type: 'quitAnyway' })
    expect(quitAnyway.running).toBe(false)
    expect(quitAnyway.originals).toBe(active.originals)
    expect(quitAnyway.ownedValues).toBe(active.ownedValues)
  })

  it('keeps conflict evidence and read-only recovery controls reachable without helper access', () => {
    const state = { ...benzoDemoReducer(initialDemoState(true), { type: 'conflict' }), helperReadiness: 'differentAccount' }
    render(<NativeAppDemo state={state} dispatch={vi.fn()} />)
    expect(screen.getByText('Recorded original: 1. Observed now: 0.')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Restore Recorded Original Anyway' }).disabled).toBe(true)
    expect(screen.getByRole('button', { name: 'Refresh Recovery Status' }).disabled).toBe(false)
    expect(screen.getByRole('button', { name: 'Keep Current' }).disabled).toBe(false)
    expect(screen.getByRole('button', { name: 'Defer' }).disabled).toBe(false)
  })

  it.each(['Authorization was cancelled.', 'Authorization was denied.'])('retains setup feedback after a status refresh: %s', message => {
    let state = { ...initialDemoState(false), view: 'setup', helperReadiness: 'needsOwnerAuthorization' }
    state = benzoDemoReducer(state, { type: 'helperSetupFailed', message })
    state = benzoDemoReducer(state, { type: 'refreshHelper' })
    render(<NativeAppDemo state={state} dispatch={vi.fn()} />)
    expect(screen.getByRole('alert').textContent).toBe(message)
    expect(state.helperReadiness).toBe('needsOwnerAuthorization')
  })

  it('does not start a pending quit restore when helper access is lost during an apply', () => {
    let state = benzoDemoReducer(initialDemoState(false), { type: 'active' })
    state = benzoDemoReducer(state, { type: 'quit' })
    state = benzoDemoReducer(state, { type: 'helperReadinessChanged', readiness: 'connectionUnavailable' })
    state = benzoDemoReducer(state, { type: 'applySucceeded' })
    expect(state.phase).toBe('activeVerified')
    expect(state.operation).toBeNull()
    expect(state.quitPending).toBe(true)
    expect(state.hasSession).toBe(true)
    expect(state.running).toBe(true)
  })

  it('keeps observed settings unchanged when activity and preferences change', () => {
    render(<Demo />)
    click('View diagnostics')
    const before = panel('Current Settings').textContent
    expect(before).toContain('tcpkeepalive1')
    expect(screen.queryByText('All settings verified')).toBeNull()
    expect(panel('Current Settings').querySelector('.bn-result, .bn-green, .bn-red, svg')).toBeNull()
    click('Back')
    click('First launch'); completeSetup(); click('Options')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }))
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('View diagnostics')
    expect(panel('Current Settings').textContent).toBe(before)
    expect(screen.queryByText(/drifted|\(expected/)).toBeNull()
    click('Back')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('View diagnostics')
    expect(panel('Current Settings').textContent).toBe(before)
  })

  it('distinguishes supported empty results and missing observations from read failures', () => {
    const { rerender } = render(<NativeAppDemo state={diagnosticFixture()} dispatch={vi.fn()} />)
    expect(screen.getByText('No sleep sessions reported')).toBeTruthy()
    expect(screen.getByText('No USB devices reported')).toBeTruthy()
    expect(screen.getByText('Unknown')).toBeTruthy()
    expect(within(panel('Current Settings')).getByText('Not reported')).toBeTruthy()
    expect(within(panel('Current Settings')).getByText('25')).toBeTruthy()
    expect(screen.queryByText(/Could not read/)).toBeNull()

    const failure = { status: 'failure' }
    rerender(<NativeAppDemo state={diagnosticFixture({ sleepData: failure, usbDevices: failure, observedSettings: failure })} dispatch={vi.fn()} />)
    expect(screen.getAllByText('Could not read sleep history')).toHaveLength(2)
    expect(screen.getByText('Could not read USB devices')).toBeTruthy()
    expect(screen.getByText('Could not read settings')).toBeTruthy()
    expect(screen.queryByText('No sleep sessions reported')).toBeNull()
    expect(screen.queryByText('No USB devices reported')).toBeNull()
    expect(screen.queryByText('Unknown')).toBeNull()
    expect(screen.queryByText('25')).toBeNull()
    expect(screen.queryByText('Reported by pmset. Changes are not verified.')).toBeNull()
  })

  it.each(['idle', 'loading'])('shows %s without treating old payloads as current', status => {
    const stale = diagnosticFixture({
      sleepData: success({ sessions: [{ sleep: 'Old sleep', wake: 'Old wake', dur: '1h' }], lastWakeReason: 'Old reason' }),
      usbDevices: success([{ name: 'Old device', power: '100' }]),
    })
    render(<NativeAppDemo state={{ ...stale, sleepData: { ...stale.sleepData, status }, usbDevices: { ...stale.usbDevices, status }, observedSettings: { ...stale.observedSettings, status } }} dispatch={vi.fn()} />)
    expect(screen.getAllByText('Loading...')).toHaveLength(4)
    expect(screen.queryByText(/Old/)).toBeNull()
    expect(screen.queryByText('hibernatemode')).toBeNull()
    expect(screen.queryByText(/No .* reported|Could not read/)).toBeNull()
  })

  it('keeps independent fresh results when another dataset fails or is still loading', () => {
    render(<NativeAppDemo state={diagnosticFixture({
      sleepData: { status: 'failure' },
      usbDevices: success([{ name: 'Example keyboard', power: '100' }]),
      observedSettings: { status: 'loading' },
    })} dispatch={vi.fn()} />)
    expect(screen.getAllByText('Could not read sleep history')).toHaveLength(2)
    expect(screen.getByText('Example keyboard')).toBeTruthy()
    expect(within(panel('Current Settings')).getByText('Loading...')).toBeTruthy()
    expect(screen.queryByText('Could not read USB devices')).toBeNull()
  })

  it('renders a supported session without inventing missing battery or wake-reason values', () => {
    render(<NativeAppDemo state={diagnosticFixture({
      sleepData: success({ sessions: [{ sleep: 'Nov 2, 11:30 PM', wake: '7:15 AM', dur: '7h 45m' }], lastWakeReason: null }),
    })} dispatch={vi.fn()} />)
    expect(within(panel('Recent Sleep Sessions')).getByText('7h 45m')).toBeTruthy()
    expect(panel('Recent Sleep Sessions').textContent).not.toContain('%')
    expect(screen.getByText('Unknown')).toBeTruthy()
  })

  it('omits unavailable wake and USB power details while retaining reported zero power', () => {
    render(<NativeAppDemo state={diagnosticFixture({
      sleepData: success({ sessions: [{ sleep: 'Nov 2, 11:30 PM', dur: 'In progress' }], lastWakeReason: null }),
      usbDevices: success([{ name: 'Unknown power device' }, { name: 'Zero power device', power: 0 }]),
    })} dispatch={vi.fn()} />)
    expect(panel('Recent Sleep Sessions').textContent).not.toContain('→')
    expect(within(panel('Recent Sleep Sessions')).getByText('In progress')).toBeTruthy()
    expect(screen.getByText('Unknown power device').parentElement.textContent).toBe('Unknown power device')
    expect(screen.getByText('Zero power device').parentElement.textContent).toBe('Zero power device0 mA')
  })

  it('quits and resets the login preference', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('switch', { name: 'Launch at Login' }))
    expect(screen.getByRole('status').textContent).toContain('only in this demo')
    click('Quit')
    expect(screen.queryByRole('button', { name: 'Benzo menu' })).toBeNull()
    fireEvent.click(screen.getAllByRole('button', { name: /Restart demo/ })[0])
    expect(screen.getByRole('button', { name: 'Sleep Now' }).disabled).toBe(true)
    expect(screen.getByRole('switch', { name: 'Launch at Login' }).getAttribute('aria-checked')).toBe('false')
  })
})
