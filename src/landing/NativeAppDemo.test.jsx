// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, renderHook, screen, within } from '@testing-library/react'
import NativeAppDemo from './NativeAppDemo'
import { useBenzoDemo } from '../demo/useBenzoDemo'

function Demo() {
  const [state, dispatch] = useBenzoDemo()
  return <NativeAppDemo state={state} dispatch={dispatch} />
}

const click = (name) => fireEvent.click(screen.getByRole('button', { name, exact: true }))
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
  it('keeps permission status ahead of diagnostics until Back without granting access', () => {
    render(<Demo />)
    click('First launch')
    click('View diagnostics')
    expect(screen.getByRole('button', { name: 'Refresh status' })).toBeTruthy()
    expect(screen.getByText('No legacy permission rule found')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Grant Permission' })).toBeNull()
    click('Benzo menu')
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.getByRole('button', { name: 'Refresh status' })).toBeTruthy()
    click('Refresh status')
    expect(screen.getByText('No legacy permission rule found')).toBeTruthy()
    expect(screen.getByRole('status').textContent).toContain('No permission was requested or changed')
    click('Back')
    expect(screen.getByText('Diagnostics')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Back', exact: true })).toBeTruthy()
  })

  it('opens main after normally reopening permission status even if diagnostics was previously requested', () => {
    render(<Demo />)
    click('First launch')
    click('View diagnostics')
    click('Benzo menu'); click('Benzo menu')
    click('Back')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
    expect(screen.queryByText('Diagnostics')).toBeNull()
  })

  it('disables Sleep Now with an explanation and omits timer and blocker controls', () => {
    render(<Demo />)
    const sleepButton = screen.getByRole('button', { name: 'Sleep Now' })
    expect(sleepButton.disabled).toBe(true)
    expect(document.getElementById(sleepButton.getAttribute('aria-describedby')).textContent).toBe('Sleep Now is unavailable while recovery controls are being updated.')
    expect(screen.queryByRole('button', { name: /timer/i })).toBeNull()
    expect(screen.queryByText('caffeinate')).toBeNull()
    expect(screen.queryByText(/app may prevent sleep/)).toBeNull()
    click('First launch'); click('Back')
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
    expect(result.current[0]).toEqual({ ...before, error: 'Sleep Now is unavailable while recovery controls are being updated.' })
    expect(vi.getTimerCount()).toBe(0)
    act(() => vi.advanceTimersByTime(3600000))
    expect(result.current[0]).toEqual({ ...before, error: 'Sleep Now is unavailable while recovery controls are being updated.' })
  })

  it('allows choices only before activation and keeps them frozen after Off and Restore', () => {
    render(<Demo />)
    const initialSetting = screen.getByRole('checkbox', { name: 'Hibernate Mode' })
    expect(initialSetting.disabled).toBe(true)
    expect(document.getElementById(initialSetting.getAttribute('aria-describedby')).textContent).toBe('Resolve the current session or recovery before changing settings.')
    click('First launch'); click('Back'); click('Options')
    const setting = screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' })
    expect(setting.disabled).toBe(false)
    expect(screen.queryByText('Resolve the current session or recovery before changing settings.')).toBeNull()
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    expect(setting.disabled).toBe(true)
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    expect(setting.disabled).toBe(true)
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    click('Restore System Defaults')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('false')
    expect(setting.disabled).toBe(true)
    fireEvent.click(setting)
    expect(setting.getAttribute('aria-checked')).toBe('true')
    expect(screen.getByRole('status').textContent).toContain('The backup remains')
    click('Options')
    expect(screen.queryByRole('checkbox')).toBeNull()
    click('Options')
    expect(screen.getByRole('checkbox', { name: 'Hibernate Mode' }).disabled).toBe(true)
  })

  it.each([
    ['active', []],
    ['after Off', ['active']],
    ['after Restore', ['restore']],
  ])('refuses direct setting actions %s and preserves the backup', (_label, actions) => {
    const { result } = renderHook(useBenzoDemo)
    for (const type of actions) act(() => result.current[1]({ type }))
    const before = result.current[0]
    expect(before.backup).toBe(true)
    act(() => result.current[1]({ type: 'setting', key: 'disableTcpKeepAlive' }))
    expect(result.current[0]).toEqual({ ...before, error: 'Resolve the current session or recovery before changing settings.' })
  })

  it('leaves permission status without changing activity and preserves the no-backup restore error', () => {
    render(<Demo />)
    click('First launch')
    expect(screen.getByText('Permission status')).toBeTruthy()
    click('Refresh status')
    click('Back')
    expect(screen.getByRole('status').textContent).toContain('No permission was requested')
    expect(screen.getByRole('button', { name: 'Options' }).getAttribute('aria-expanded')).toBe('false')
    click('Restore System Defaults')
    expect(screen.getByRole('alert').textContent).toBe('Nothing to revert — activate Benzo first.')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('Restore System Defaults')
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it.each([
    ['noLegacyRule', 'No legacy permission rule found'],
    ['legacyRulePresent', 'Legacy permission rule found; authorization is unverified'],
    ['unknown', 'Permission status could not be determined'],
  ])('renders %s as evidence only', (permissionObservation, text) => {
    const dispatch = vi.fn()
    render(<NativeAppDemo state={{ running: true, open: true, view: 'setup', permissionObservation }} dispatch={dispatch} />)
    expect(screen.getByText(text)).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Grant Permission' })).toBeNull()
    click('Refresh status')
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'refreshPermission' })
    click('Back')
    expect(dispatch).toHaveBeenLastCalledWith({ type: 'back' })
  })

  it('keeps refresh and Back independent of settings, recovery evidence, and active state', () => {
    const { result } = renderHook(useBenzoDemo)
    act(() => result.current[1]({ type: 'firstLaunch' }))
    const before = result.current[0]
    act(() => result.current[1]({ type: 'refreshPermission' }))
    expect(result.current[0]).toEqual({ ...before, notice: 'Status refresh simulated. No permission was requested or changed.' })
    const refreshed = result.current[0]
    act(() => result.current[1]({ type: 'back' }))
    expect(result.current[0]).toEqual({ ...refreshed, view: 'main' })
    const returned = result.current[0]
    act(() => result.current[1]({ type: 'setup' }))
    expect(result.current[0]).toEqual(returned)
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

  it('keeps observed settings unchanged when activity and preferences change', () => {
    render(<Demo />)
    click('View diagnostics')
    const before = panel('Current Settings').textContent
    expect(before).toContain('tcpkeepalive1')
    expect(screen.queryByText('All settings verified')).toBeNull()
    expect(panel('Current Settings').querySelector('.bn-result, .bn-green, .bn-red, svg')).toBeNull()
    click('Back')
    click('First launch'); click('Back'); click('Options')
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
