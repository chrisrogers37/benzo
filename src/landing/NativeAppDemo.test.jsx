// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import NativeAppDemo from './NativeAppDemo'
import { useBenzoDemo } from '../demo/useBenzoDemo'

function Demo() {
  const [state, dispatch] = useBenzoDemo()
  return <NativeAppDemo state={state} dispatch={dispatch} />
}

const click = (name) => fireEvent.click(screen.getByRole('button', { name, exact: true }))
const advance = (ms) => act(() => vi.advanceTimersByTime(ms))

beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-26T12:00:00Z')) })
afterEach(() => { cleanup(); vi.useRealTimers() })

describe('source-matched browser simulation', () => {
  it('keeps first-launch setup ahead of diagnostics until permission is simulated', () => {
    render(<Demo />)
    click('First launch')
    click('View diagnostics')
    expect(screen.getByRole('button', { name: 'Grant Permission' })).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Back', exact: true })).toBeNull()
    click('Benzo menu')
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.getByRole('button', { name: 'Grant Permission' })).toBeTruthy()
    click('Grant Permission')
    click('View diagnostics')
    expect(screen.getByRole('button', { name: 'Back', exact: true })).toBeTruthy()
  })

  it.each([5, 15, 30, 60])('counts down the selected %i-minute duration and cancels it', minutes => {
    render(<Demo />)
    click('Set sleep timer')
    click(`${minutes}m`)
    expect(screen.getByRole('button', { name: `Sleeping in ${minutes}:00` })).toBeTruthy()
    advance(1000)
    expect(screen.getByRole('button', { name: `Sleeping in ${minutes - 1}:59` })).toBeTruthy()
    click(`Sleeping in ${minutes - 1}:59`)
    advance(minutes * 60000)
    expect(screen.getByRole('button', { name: 'Sleep Now' })).toBeTruthy()
    expect(screen.getByRole('status').textContent).toBe('Demo timer canceled.')
  })

  it('shows Sleeping... at expiry and never acts outside the simulation', () => {
    render(<Demo />)
    click('Set sleep timer'); click('5m')
    advance(300000)
    expect(screen.getByRole('button', { name: 'Sleeping...' }).disabled).toBe(true)
    expect(screen.getByRole('status').textContent).toContain('No processes were stopped')
    advance(500)
    expect(screen.getByRole('button', { name: 'Sleep Now' })).toBeTruthy()
  })

  it('does not fire early when a timer tick lands within the final second', () => {
    render(<Demo />)
    click('Set sleep timer'); click('5m')
    vi.setSystemTime(new Date('2026-10-26T12:04:58.500Z'))
    advance(1000)
    expect(screen.getByRole('button', { name: 'Sleeping in 0:00' })).toBeTruthy()
    expect(screen.queryByText('Sleeping...')).toBeNull()
    advance(1000)
    expect(screen.getByRole('button', { name: 'Sleeping...' }).disabled).toBe(true)
  })

  it('activates and shows the native sleeping state immediately for Sleep Now', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('Sleep Now')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('true')
    expect(screen.getByRole('button', { name: 'Sleeping...' }).disabled).toBe(true)
    expect(screen.queryByText(/^Sleeping in/)).toBeNull()
    advance(500)
    expect(screen.getByRole('button', { name: 'Sleep Now' })).toBeTruthy()
  })

  it('keeps Options editable while off and preserves choices through restore', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    expect(screen.getByRole('button', { name: 'Options' })).toBeTruthy()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }))
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('Restore System Defaults')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('false')
    expect(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }).getAttribute('aria-checked')).toBe('true')
    click('Options')
    expect(screen.queryByRole('checkbox')).toBeNull()
    click('Options')
    expect(screen.getByRole('checkbox', { name: 'Hibernate Mode' })).toBeTruthy()
  })

  it('simulates first setup and the native no-backup restore error', () => {
    render(<Demo />)
    click('First launch')
    expect(screen.getByText('Welcome to Benzo')).toBeTruthy()
    click('Grant Permission')
    expect(screen.getByRole('status').textContent).toContain('No permission was requested')
    expect(screen.getByRole('button', { name: 'Options' }).getAttribute('aria-expanded')).toBe('false')
    click('Restore System Defaults')
    expect(screen.getByRole('alert').textContent).toBe('Nothing to revert — activate Benzo first.')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('Restore System Defaults')
    expect(screen.queryByRole('alert')).toBeNull()
  })

  it('matches native Option-click semantics and offers a touch-accessible diagnostic path', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.queryByRole('switch', { name: 'Deep Sleep' })).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Benzo menu' }), { altKey: true })
    expect(screen.getByText('Diagnostics')).toBeTruthy()
    expect(screen.getByText('All settings verified')).toBeTruthy()
    click('Back')
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
    click('View diagnostics')
    click('Benzo menu'); click('Benzo menu')
    expect(screen.queryByText('Diagnostics')).toBeNull()
    expect(screen.getByRole('switch', { name: 'Deep Sleep' })).toBeTruthy()
  })

  it('compares diagnostic readings only against active, enabled settings', () => {
    render(<Demo />)
    click('View diagnostics')
    expect(screen.getByText('All settings verified')).toBeTruthy()
    click('Back')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }))
    click('View diagnostics')
    expect(screen.getByText('1 setting drifted')).toBeTruthy()
    expect(screen.getByText('(expected 0)')).toBeTruthy()
    click('Back')
    fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))
    click('View diagnostics')
    expect(screen.getByText('All settings verified')).toBeTruthy()
    expect(screen.queryByText('(expected 0)')).toBeNull()
  })

  it('quits and resets without leaving an active countdown or login preference', () => {
    render(<Demo />)
    fireEvent.click(screen.getByRole('switch', { name: 'Launch at Login' }))
    expect(screen.getByRole('status').textContent).toContain('only in this demo')
    click('Set sleep timer'); click('5m'); click('Quit')
    expect(screen.queryByRole('button', { name: 'Benzo menu' })).toBeNull()
    fireEvent.click(screen.getAllByRole('button', { name: /Restart demo/ })[0])
    advance(300000)
    expect(screen.getByRole('button', { name: 'Sleep Now' })).toBeTruthy()
    expect(screen.getByRole('switch', { name: 'Launch at Login' }).getAttribute('aria-checked')).toBe('false')
  })
})
