// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import SleepAssertionsPanel from './SleepAssertionsPanel'

afterEach(cleanup)
const empty = { processes: [], kernelSummary: 'No kernel assertions reported', kernelDetails: [], sleepPreventers: [] }
const observed = value => ({ status: 'success', snapshot: { value, updatedAt: new Date('2026-11-16T12:30:00Z') }, error: null, refresh: vi.fn() })
const process = (pid, kind, description, name = 'Worker') => ({ pid, processName: `worker-${pid}`, friendlyName: name,
  assertions: [{ id: `0x${pid}`, kind, type: kind === 'idle' ? 'PreventUserIdleSystemSleep' : kind === 'system' ? 'PreventSystemSleep' : 'UserIsActive', description }] })

describe('Keeping Your Mac Awake presentation', () => {
  it('separates idle, system, other, and kernel reports without merging friendly-name collisions', () => {
    const value = { ...empty, processes: [process(71, 'idle', 'Finishing an export'), process(72, 'idle', 'Uploading a file'), process(90, 'system', 'Saving a backup', 'Backup'), process(95, 'other', 'Recent keyboard input', 'Window Server')],
      kernelSummary: 'USB kernel assertion reported', kernelDetails: ['owner=USB controller'], sleepPreventers: ['IODisplayWrangler'] }
    render(<SleepAssertionsPanel observation={observed(value)} />)
    expect(screen.getByRole('heading', { name: 'Automatic idle sleep' })).toBeTruthy()
    expect(screen.getByRole('heading', { name: 'System sleep' })).toBeTruthy()
    expect(screen.getAllByText('Worker')).toHaveLength(2)
    expect(screen.getByText('PID 71')).toBeTruthy()
    expect(screen.getByText('PID 72')).toBeTruthy()
    expect(screen.getByText('Finishing an export')).toBeTruthy()
    expect(screen.getByText('Saving a backup')).toBeTruthy()
    expect(screen.getByText('These reports are not classified as preventing system sleep.')).toBeTruthy()
    expect(screen.getByText('Kernel reports are separate from app sleep-prevention assertions.')).toBeTruthy()
    expect(screen.getByText('Automatic idle-sleep prevention does not guarantee that Sleep Now is blocked.')).toBeTruthy()
    expect(screen.queryByRole('button', { name: /quit|kill|stop process/i })).toBeNull()
    expect(screen.getByText('owner=USB controller').closest('details').open).toBe(false)
  })

  it('shows all assertions for a process without implying display activity is an idle blocker', () => {
    const reporter = process(24, 'idle', 'Audio playback')
    reporter.assertions[0].details = ['Timeout will fire in 120 seconds Action=TimeoutActionRelease']
    reporter.assertions.push({ id: '0x25', kind: 'idle', type: 'PreventUserIdleSystemSleep', description: 'Finishing file transfer' })
    reporter.assertions.push({ id: '0x26', kind: 'display', type: 'PreventUserIdleDisplaySleep', description: 'Showing a presentation' })
    render(<SleepAssertionsPanel observation={observed({ ...empty, processes: [reporter] })} />)
    const idleGroup = screen.getByRole('heading', { name: 'Automatic idle sleep' }).parentElement
    expect(within(idleGroup).getByText('Audio playback')).toBeTruthy()
    expect(within(idleGroup).getByText('Finishing file transfer')).toBeTruthy()
    expect(within(idleGroup).queryByText('Showing a presentation')).toBeNull()
    expect(screen.getByRole('heading', { name: 'Display & other activity' })).toBeTruthy()
    expect(within(idleGroup).getAllByText('Assertion details')).toHaveLength(1)
    expect(screen.getByText('Timeout will fire in 120 seconds Action=TimeoutActionRelease').closest('details').open).toBe(false)
  })

  it('uses successful empty wording only after a successful observation', () => {
    const { rerender } = render(<SleepAssertionsPanel observation={{ status: 'loading', snapshot: null, error: null, refresh: vi.fn() }} />)
    expect(screen.getByText('Reading sleep activity…')).toBeTruthy()
    expect(screen.queryByText('No automatic idle-sleep assertions reported.')).toBeNull()
    expect(screen.getByRole('button', { name: 'Refresh sleep activity' }).disabled).toBe(true)
    rerender(<SleepAssertionsPanel observation={observed(empty)} />)
    expect(screen.getByText('No automatic idle-sleep assertions reported.')).toBeTruthy()
    expect(screen.getByText('No system-sleep assertions reported.')).toBeTruthy()
    expect(screen.queryByText(/nothing is preventing sleep/i)).toBeNull()
  })

  it.each([
    ['failed', 'Could not read sleep activity.'],
    ['unsupported', 'This sleep activity format is not supported.'],
    ['malformed', 'The sleep activity read could not be understood.'],
    ['incomplete', 'The sleep activity read was incomplete.'],
  ])('keeps %s failure distinct and labels retained data stale', (error, message) => {
    const observation = observed({ ...empty, processes: [process(301, 'idle', 'Recording a session')] })
    const { rerender } = render(<SleepAssertionsPanel observation={{ ...observation, status: 'failure', snapshot: null, error }} />)
    expect(screen.getByText(message)).toBeTruthy()
    expect(screen.queryByText('No automatic idle-sleep assertions reported.')).toBeNull()
    rerender(<SleepAssertionsPanel observation={{ ...observation, status: 'failure', error }} />)
    expect(screen.getByText(`${message} Last successful observation — stale.`)).toBeTruthy()
    expect(screen.getByText('Recording a session')).toBeTruthy()
    expect(screen.getByText(/Last updated/).querySelector('time').dateTime).toBe('2026-11-16T12:30:00.000Z')
  })

  it('disables refresh and explains the session pause while identifying any retained observation as stale', () => {
    const observation = { ...observed({ ...empty, processes: [process(455, 'idle', 'Rendering an animation')] }), status: 'failure', error: 'unsettled', pollingPaused: true }
    const { rerender } = render(<SleepAssertionsPanel observation={observation} />)
    const reason = 'Live refresh is paused for this app session because the previous read did not stop cleanly.'
    expect(screen.getByText(`${reason} Last successful observation — stale.`)).toBeTruthy()
    expect(screen.getByText('Rendering an animation')).toBeTruthy()
    const refresh = screen.getByRole('button', { name: 'Refresh sleep activity' })
    expect(refresh.disabled).toBe(true)
    fireEvent.click(refresh)
    expect(observation.refresh).not.toHaveBeenCalled()
    expect(screen.queryByText('Updates every 5 seconds while Diagnostics is open.')).toBeNull()
    rerender(<SleepAssertionsPanel observation={{ ...observation, snapshot: null }} />)
    expect(screen.getByText(reason)).toBeTruthy()
    expect(screen.queryByText('No automatic idle-sleep assertions reported.')).toBeNull()
  })

  it('keeps a stale failure label while the next refresh is pending', () => {
    const observation = { ...observed({ ...empty, processes: [process(930, 'idle', 'Uploading a draft')] }), status: 'loading', error: 'failed' }
    render(<SleepAssertionsPanel observation={observation} />)
    expect(screen.getByText('Could not read sleep activity. Last successful observation — stale.')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Refresh sleep activity' }).disabled).toBe(true)
    expect(screen.getByText('Refreshing…')).toBeTruthy()
    expect(screen.getByText('Uploading a draft')).toBeTruthy()
  })

  it('offers a keyboard-native manual refresh without a live region for every polling update', () => {
    const observation = observed(empty)
    const { container } = render(<SleepAssertionsPanel observation={observation} />)
    const refresh = screen.getByRole('button', { name: 'Refresh sleep activity' })
    refresh.focus()
    expect(document.activeElement).toBe(refresh)
    fireEvent.click(refresh)
    expect(observation.refresh).toHaveBeenCalledTimes(1)
    expect(container.querySelector('[aria-live]')).toBeNull()
  })
})
