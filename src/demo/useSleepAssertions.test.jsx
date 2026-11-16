// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, cleanup, renderHook } from '@testing-library/react'
import { assertionRefreshInterval, useSleepAssertions } from './useSleepAssertions'

const value = label => ({ processes: [{ pid: 83, processName: label, friendlyName: label, assertions: [
  { id: '12', kind: 'idle', type: 'PreventUserIdleSystemSleep', description: 'Exporting a recording' },
] }], kernelSummary: 'No kernel assertions reported', kernelDetails: [], sleepPreventers: [] })
const success = label => ({ status: 'success', value: value(label) })
const deferred = () => {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}
const settle = async () => { await act(async () => { await Promise.resolve() }) }
const advance = async milliseconds => { await act(async () => { vi.advanceTimersByTime(milliseconds) }) }

beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-11-16T12:00:00Z'))
  Object.defineProperty(document, 'hidden', { configurable: true, value: false })
})
afterEach(() => {
  cleanup()
  vi.useRealTimers()
  delete document.hidden
})

describe('visible assertion observations', () => {
  it('reads only while enabled and waits five seconds after each result', async () => {
    const read = vi.fn().mockResolvedValue(success('Recorder'))
    const { result, rerender } = renderHook(({ enabled }) => useSleepAssertions({ enabled, read }), { initialProps: { enabled: false } })
    await advance(20_000)
    expect(read).not.toHaveBeenCalled()
    expect(result.current.status).toBe('idle')
    rerender({ enabled: true })
    await settle()
    expect(result.current.snapshot.value).toEqual(value('Recorder'))
    expect(result.current.snapshot.updatedAt.toISOString()).toBe('2026-11-16T12:00:20.000Z')
    await advance(assertionRefreshInterval - 1)
    expect(read).toHaveBeenCalledTimes(1)
    await advance(1)
    expect(read).toHaveBeenCalledTimes(2)
    rerender({ enabled: false })
    await advance(20_000)
    expect(read).toHaveBeenCalledTimes(2)
    expect(result.current.snapshot).toBeNull()
    expect(result.current.status).toBe('idle')
  })

  it('does not overlap slow reads, manual refreshes, or rapid close and reopen', async () => {
    const first = deferred(), second = deferred()
    const read = vi.fn().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise)
    const { result, rerender } = renderHook(({ enabled }) => useSleepAssertions({ enabled, read }), { initialProps: { enabled: true } })
    expect(result.current.status).toBe('loading')
    await advance(30_000)
    act(() => { result.current.refresh(); result.current.refresh() })
    expect(read).toHaveBeenCalledTimes(1)
    const oldSignal = read.mock.calls[0][0].signal
    rerender({ enabled: false })
    expect(oldSignal.aborted).toBe(true)
    rerender({ enabled: true })
    expect(read).toHaveBeenCalledTimes(1)
    await act(async () => first.resolve(success('Old visit')))
    expect(read).toHaveBeenCalledTimes(2)
    expect(result.current.snapshot).toBeNull()
    await act(async () => second.resolve(success('Current visit')))
    expect(result.current.snapshot.value.processes[0].processName).toBe('Current visit')
  })

  it.each(['failed', 'unsupported', 'malformed', 'incomplete'])('preserves an earlier observation as stale after a %s read, then recovers to successful empty', async error => {
    const empty = { processes: [], kernelSummary: 'No kernel assertions reported', kernelDetails: [], sleepPreventers: [] }
    const read = vi.fn().mockResolvedValueOnce(success('Archive Utility')).mockResolvedValueOnce({ status: 'failure', error }).mockResolvedValueOnce({ status: 'success', value: empty })
    const { result } = renderHook(() => useSleepAssertions({ enabled: true, read }))
    await settle()
    const first = result.current.snapshot
    await advance(assertionRefreshInterval)
    expect(result.current.status).toBe('failure')
    expect(result.current.error).toBe(error)
    expect(result.current.snapshot).toBe(first)
    act(() => result.current.refresh())
    expect(result.current.status).toBe('loading')
    expect(result.current.snapshot).toBe(first)
    await settle()
    expect(result.current.status).toBe('success')
    expect(result.current.error).toBeNull()
    expect(result.current.snapshot.value).toEqual(empty)
  })

  it('does not turn a first failed or thrown read into an empty successful observation', async () => {
    const read = vi.fn().mockRejectedValueOnce(new Error('reader unavailable')).mockResolvedValueOnce({ status: 'failure', error: 'unsupported' })
    const { result } = renderHook(() => useSleepAssertions({ enabled: true, read }))
    await settle()
    expect(result.current).toMatchObject({ status: 'failure', snapshot: null, error: 'failed' })
    await advance(assertionRefreshInterval)
    expect(result.current).toMatchObject({ status: 'failure', snapshot: null, error: 'unsupported' })
  })

  it('keeps failure provenance while retrying a stale observation until a new read succeeds', async () => {
    const retry = deferred()
    const read = vi.fn().mockResolvedValueOnce(success('Media app')).mockResolvedValueOnce({ status: 'failure', error: 'incomplete' }).mockReturnValueOnce(retry.promise)
    const { result } = renderHook(() => useSleepAssertions({ enabled: true, read }))
    await settle()
    const first = result.current.snapshot
    await advance(assertionRefreshInterval)
    expect(result.current.error).toBe('incomplete')
    await advance(assertionRefreshInterval)
    expect(result.current).toMatchObject({ status: 'loading', error: 'incomplete' })
    expect(result.current.snapshot).toBe(first)
    await advance(30_000)
    expect(result.current.error).toBe('incomplete')
    expect(read).toHaveBeenCalledTimes(3)
    await act(async () => retry.resolve(success('New observation')))
    expect(result.current).toMatchObject({ status: 'success', error: null })
    expect(result.current.snapshot.value.processes[0].processName).toBe('New observation')
  })

  it('latches an unsettled read for the app session, retains stale data, and prevents manual or reopen retries', async () => {
    const read = vi.fn().mockResolvedValueOnce(success('Recording app')).mockResolvedValueOnce({ status: 'failure', error: 'unsettled' })
    const { result, rerender } = renderHook(({ enabled }) => useSleepAssertions({ enabled, read }), { initialProps: { enabled: true } })
    await settle()
    const first = result.current.snapshot
    await advance(assertionRefreshInterval)
    expect(result.current).toMatchObject({ status: 'failure', error: 'unsettled', pollingPaused: true })
    expect(result.current.snapshot).toBe(first)
    act(() => result.current.refresh())
    await advance(30_000)
    expect(read).toHaveBeenCalledTimes(2)
    expect(vi.getTimerCount()).toBe(0)
    rerender({ enabled: false })
    expect(result.current).toMatchObject({ status: 'failure', snapshot: null, error: 'unsettled', pollingPaused: true })
    rerender({ enabled: true })
    act(() => result.current.refresh())
    await advance(30_000)
    expect(read).toHaveBeenCalledTimes(2)
    expect(result.current.snapshot).toBeNull()
    expect(result.current.pollingPaused).toBe(true)
  })

  it.each([false, true])('latches a canceled prior-visit unsettled result before restarting (reopened: %s)', async reopenBeforeResult => {
    const pending = deferred()
    const read = vi.fn().mockReturnValue(pending.promise)
    const { result, rerender } = renderHook(({ enabled }) => useSleepAssertions({ enabled, read }), { initialProps: { enabled: true } })
    const signal = read.mock.calls[0][0].signal
    rerender({ enabled: false })
    expect(signal.aborted).toBe(true)
    if (reopenBeforeResult) rerender({ enabled: true })
    await act(async () => pending.resolve({ status: 'failure', error: 'unsettled' }))
    expect(result.current).toMatchObject({ status: 'failure', snapshot: null, error: 'unsettled', pollingPaused: true })
    if (!reopenBeforeResult) rerender({ enabled: true })
    act(() => result.current.refresh())
    await advance(30_000)
    expect(read).toHaveBeenCalledTimes(1)
    expect(vi.getTimerCount()).toBe(0)
  })

  it('keeps the pause across reader changes and browser visibility changes', async () => {
    const unsettledRead = vi.fn().mockResolvedValue({ status: 'failure', error: 'unsettled' })
    const replacementRead = vi.fn().mockResolvedValue(success('Replacement'))
    const { result, rerender } = renderHook(({ read }) => useSleepAssertions({ enabled: true, read }), { initialProps: { read: unsettledRead } })
    await settle()
    rerender({ read: replacementRead })
    act(() => window.dispatchEvent(new Event('pagehide')))
    act(() => window.dispatchEvent(new Event('pageshow')))
    act(() => result.current.refresh())
    await advance(30_000)
    expect(result.current.pollingPaused).toBe(true)
    expect(replacementRead).not.toHaveBeenCalled()
  })

  it('pauses for pagehide and document visibility, then reads a fresh visit', async () => {
    const read = vi.fn().mockResolvedValue(success('Notes'))
    const { result } = renderHook(() => useSleepAssertions({ enabled: true, read }))
    await settle()
    act(() => window.dispatchEvent(new Event('pagehide')))
    expect(result.current.snapshot).toBeNull()
    await advance(20_000)
    expect(read).toHaveBeenCalledTimes(1)
    act(() => window.dispatchEvent(new Event('pageshow')))
    await settle()
    expect(read).toHaveBeenCalledTimes(2)
    act(() => {
      Object.defineProperty(document, 'hidden', { configurable: true, value: true })
      document.dispatchEvent(new Event('visibilitychange'))
    })
    await advance(20_000)
    expect(read).toHaveBeenCalledTimes(2)
    act(() => {
      Object.defineProperty(document, 'hidden', { configurable: true, value: false })
      document.dispatchEvent(new Event('visibilitychange'))
    })
    await settle()
    expect(read).toHaveBeenCalledTimes(3)
  })

  it('aborts on unmount and does not schedule from a late result', async () => {
    const pending = deferred()
    const read = vi.fn().mockReturnValue(pending.promise)
    const { unmount } = renderHook(() => useSleepAssertions({ enabled: true, read }))
    const signal = read.mock.calls[0][0].signal
    unmount()
    expect(signal.aborted).toBe(true)
    await act(async () => pending.resolve(success('Late')))
    await advance(20_000)
    expect(read).toHaveBeenCalledTimes(1)
    expect(vi.getTimerCount()).toBe(0)
  })

  it('isolates independent instances and their datasets', async () => {
    const readA = vi.fn().mockResolvedValue(success('Exporter'))
    const readB = vi.fn().mockResolvedValue(success('Meeting app'))
    const first = renderHook(() => useSleepAssertions({ enabled: true, read: readA }))
    const second = renderHook(() => useSleepAssertions({ enabled: true, read: readB }))
    await settle()
    expect(first.result.current.snapshot.value.processes[0].processName).toBe('Exporter')
    expect(second.result.current.snapshot.value.processes[0].processName).toBe('Meeting app')
    first.unmount()
    await advance(assertionRefreshInterval)
    expect(readA).toHaveBeenCalledTimes(1)
    expect(readB).toHaveBeenCalledTimes(2)
  })
})
