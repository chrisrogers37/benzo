import { useCallback, useEffect, useReducer } from 'react'
import { appPresentation, exampleReadings, settingOptions } from '../design/appPresentation'
import { siteCopy } from '../design/siteCopy'

const originals = Object.freeze({ powernap: '1', womp: '1', tcpkeepalive: '1' })
const exampleCapturedAt = 'Nov 4, 2026 at 9:00 AM (example)'
const selectedDefaults = Object.freeze({
  hibernateMode: false, disablePowerNap: true, disableProximityWake: false,
  disableNetworkWake: true, disableTcpKeepAlive: false,
})

const selectedValues = settings => ({
  powernap: settings.disablePowerNap ? '0' : originals.powernap,
  womp: settings.disableNetworkWake ? '0' : originals.womp,
  tcpkeepalive: settings.disableTcpKeepAlive ? '0' : originals.tcpkeepalive,
})

const targetValues = (settings, captured) => ({
  powernap: settings.disablePowerNap ? '0' : captured.powernap,
  womp: settings.disableNetworkWake ? '0' : captured.womp,
  tcpkeepalive: settings.disableTcpKeepAlive ? '0' : captured.tcpkeepalive,
})

const ownedSelectionValues = (settings, captured) => Object.fromEntries(
  Object.entries(targetValues(settings, captured)).filter(([key, value]) => value !== captured[key]),
)

export const initialDemoState = (active = true) => ({
  running: true, open: true, view: 'main',
  phase: active ? 'activeVerified' : 'off', options: true,
  settings: { ...selectedDefaults }, originals,
  hasSession: active, capturedAt: active ? exampleCapturedAt : null,
  ownedValues: active ? ownedSelectionValues(selectedDefaults, originals) : {},
  currentValues: active ? selectedValues(selectedDefaults) : { ...originals },
  login: false, error: null, notice: '', update: { status: 'idle' }, helperReadiness: 'ready', helperSetupError: null, isPerformingHelperSetup: false,
  helperAccountAuthorized: true, helperRemovalConfirmation: false,
  sleepCapability: true, sleepTimer: null, sleepGeneration: 0,
  sleepRequestInFlight: false, sleepRequestGeneration: null, sleepMessage: '',
  operation: null, quitPending: false, resumePhase: null, conflict: null, conflictDeferred: false, conflictResolution: null, legacyUnknown: false,
  sleepData: { status: 'success', value: { sessions: exampleReadings.sleepSessions, lastWakeReason: exampleReadings.wakeReason } },
  usbDevices: { status: 'success', value: exampleReadings.usbDevices },
  observedSettings: { status: 'success', value: settingOptions.flatMap(({ commands }) => commands.map(([key]) => ({ key, actualValue: exampleReadings.values[key] }))) },
})

function publish(state, phase, notice = '') {
  return { ...state, phase, notice, error: null, operation: null, quitPending: false }
}

export const sleepPresets = Object.freeze([5, 15, 30, 60])
// A delayed browser callback cannot establish that a countdown stayed awake.
// Cancel after a suspension instead of sending an overdue simulated request.
export const maximumSleepTickGap = 2000

export function sleepDisabledReason(state) {
  if (state.sleepRequestInFlight) return appPresentation.sleep.pending
  if (!state.running || state.phase !== 'activeVerified' || !state.hasSession) return appPresentation.sleep.requiresActive
  if (state.operation || state.quitPending || state.conflict || state.legacyUnknown) return appPresentation.sleep.requiresResolved
  if (state.helperReadiness !== 'ready' || state.isPerformingHelperSetup || state.view === 'setup') return appPresentation.sleep.requiresReady
  if (!state.sleepCapability) return appPresentation.sleep.requiresUpdate
  return null
}

export const canSleep = state => sleepDisabledReason(state) === null

function cancelTimer(state, message = appPresentation.sleep.cancelled) {
  return state.sleepTimer ? { ...state, sleepTimer: null, sleepGeneration: state.sleepGeneration + 1, sleepMessage: message } : state
}

function requestSleep(state) {
  if (!canSleep(state)) return { ...state, error: sleepDisabledReason(state) }
  const generation = state.sleepGeneration + 1
  return { ...state, sleepTimer: null, sleepGeneration: generation, sleepRequestGeneration: generation,
    sleepRequestInFlight: true, sleepMessage: appPresentation.sleep.requesting, error: null, notice: siteCopy.demo.notices.sleep }
}

export function benzoDemoReducer(state, action) {
  if (['active', 'restore', 'quit', 'quitAnyway', 'setup', 'checking', 'refreshRecovery', 'operationFailed', 'conflict', 'legacyUnknown', 'systemSleep', 'systemWake'].includes(action.type)) state = cancelTimer(state)
  const next = reduceDemo(state, action)
  return next.sleepTimer && !canSleep(next) ? cancelTimer(next) : next
}

function reduceDemo(state, action) {
  if (state.sleepRequestInFlight) {
    if (action.type === 'quit') return { ...state, quitPending: true, update: { status: 'idle' } }
    if (['active', 'restore', 'retry', 'restoreRecordedOriginal', 'keepCurrent', 'quitAnyway', 'setting', 'setup', 'registerHelper', 'authorizeCurrentAccount', 'replaceHelper', 'requestRemoveHelper', 'removeHelper'].includes(action.type)) {
      return { ...state, error: appPresentation.sleep.pending }
    }
  }
  if (action.type === 'quit') state = { ...state, update: { status: 'idle' } }
  if (['active', 'restore', 'retry', 'restoreRecordedOriginal', 'quit'].includes(action.type) && state.isPerformingHelperSetup) {
    return { ...state, error: appPresentation.setup.inProgress }
  }
  if (['active', 'restore', 'retry', 'restoreRecordedOriginal'].includes(action.type) && state.helperReadiness !== 'ready') {
    return { ...state, error: state.hasSession ? appPresentation.setup.recoveryBlocked : appPresentation.setup.writeBlocked }
  }
  switch (action.type) {
    case 'reset': return { ...initialDemoState(true), sleepGeneration: state.sleepGeneration + 1 }
    case 'firstLaunch': return { ...initialDemoState(false), sleepGeneration: state.sleepGeneration + 1, options: false, helperReadiness: 'notInstalled', helperAccountAuthorized: false }
    case 'setup': return { ...state, update: { status: 'idle' }, view: 'setup' }
    case 'refreshHelper': return { ...state, notice: 'Setup status refresh simulated. No permission was requested or changed.' }
    case 'registerHelper': return ['notInstalled', 'requiresApproval'].includes(state.helperReadiness) && !state.isPerformingHelperSetup
      ? { ...state, helperReadiness: 'ready', sleepCapability: true, helperAccountAuthorized: true, helperSetupError: null, notice: 'One administrator approval simulated for this Mac account. No permission was requested or changed.' } : state
    case 'authorizeCurrentAccount': return state.helperReadiness === 'needsOwnerAuthorization' && !state.isPerformingHelperSetup
      ? { ...state, helperReadiness: 'ready', sleepCapability: true, helperAccountAuthorized: true, helperSetupError: null, notice: 'One administrator approval simulated for this Mac account. No permission was requested or changed.' } : state
    case 'replaceHelper': return ['ready', 'incompatible', 'connectionUnavailable'].includes(state.helperReadiness) && state.phase === 'off' && !state.hasSession && state.operation !== 'uncertain' && !state.isPerformingHelperSetup
      ? { ...state, helperReadiness: 'ready', sleepCapability: true, helperSetupError: null, notice: 'Power access repair simulated. No power tool or permission was changed.' } : state
    case 'requestRemoveHelper': return ['ready', 'incompatible'].includes(state.helperReadiness) && state.phase === 'off' && !state.hasSession && state.operation !== 'uncertain' && !state.isPerformingHelperSetup
      ? { ...state, helperRemovalConfirmation: true } : state
    case 'cancelRemoveHelper': return { ...state, helperRemovalConfirmation: false }
    case 'removeHelper': return state.helperRemovalConfirmation && ['ready', 'incompatible'].includes(state.helperReadiness) && state.phase === 'off' && !state.hasSession && state.operation !== 'uncertain' && !state.isPerformingHelperSetup
      ? { ...state, helperReadiness: 'notInstalled', helperRemovalConfirmation: false, helperSetupError: null, notice: 'Power access removal simulated. Account and recovery records were retained. No power tool or permission was changed.' } : state
    case 'helperReadinessChanged': return Object.hasOwn(appPresentation.setup.states, action.readiness)
      ? { ...state, helperReadiness: action.readiness } : state
    case 'helperSetupFailed': return { ...state, helperSetupError: action.message }
    case 'pill': return state.open
      ? { ...state, open: false, update: { status: 'idle' }, helperRemovalConfirmation: false }
      : { ...state, open: true, view: action.alt ? 'diagnostics' : 'main' }
    case 'diagnostics': return { ...state, update: { status: 'idle' }, helperRemovalConfirmation: false, running: true, open: true, view: 'diagnostics', notice: '' }
    case 'back': return { ...state, helperRemovalConfirmation: false, view: 'main' }
    case 'options': return { ...state, options: !state.options }
    case 'setting':
      if (state.phase !== 'off' || state.legacyUnknown) return { ...state, error: appPresentation.selectionBlocked }
      if (!settingOptions.find(option => option.key === action.key)?.available) return { ...state, error: appPresentation.recovery.unsupported }
      return { ...state, settings: { ...state.settings, [action.key]: !state.settings[action.key] }, error: null }
    case 'active':
      if (state.phase === 'off') {
        if (!Object.values(state.settings).some(Boolean)) return { ...state, error: appPresentation.recovery.emptySelection }
        return { ...state, phase: 'applying', operation: 'apply', hasSession: true, originals: Object.freeze({ ...state.currentValues }), capturedAt: exampleCapturedAt, error: null, notice: appPresentation.recovery.titles.applying }
      }
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
      if (state.phase === 'recoveryRequired') return { ...state, error: appPresentation.recovery.refuseWrite }
      return state
    case 'checking': return { ...state, phase: 'checking', resumePhase: state.phase, error: null, notice: appPresentation.recovery.titles.checking }
    case 'checkingSucceeded': {
      if (state.phase !== 'checking') return state
      const nextPhase = state.resumePhase ?? (Object.keys(state.ownedValues).length ? 'activeVerified' : 'off')
      if (!state.quitPending) return { ...state, phase: nextPhase, resumePhase: null, conflictDeferred: false, notice: appPresentation.recovery.titles[nextPhase] }
      if (nextPhase === 'recoveryRequired' || state.conflict || state.legacyUnknown) return { ...state, phase: 'recoveryRequired', resumePhase: null, error: appPresentation.recovery.quitPrompt }
      if (nextPhase === 'activeVerified' || Object.keys(state.ownedValues).length) return state.helperReadiness === 'ready'
        ? { ...state, phase: 'restoring', operation: 'restore', resumePhase: null, error: null, notice: appPresentation.recovery.titles.restoring }
        : { ...state, phase: nextPhase, operation: null, resumePhase: null, error: appPresentation.setup.recoveryBlocked, notice: '' }
      return { ...state, phase: 'off', running: false, open: false, quitPending: false, resumePhase: null, notice: siteCopy.demo.notices.quit }
    }
    case 'applySucceeded':
      if (state.phase !== 'applying') return state
      {
        const ownedValues = ownedSelectionValues(state.settings, state.originals)
        const applied = { ...state, hasSession: Object.keys(ownedValues).length > 0, ownedValues, currentValues: { ...state.currentValues, ...targetValues(state.settings, state.originals) } }
        if (!Object.keys(ownedValues).length) {
          return state.quitPending
            ? { ...applied, phase: 'off', capturedAt: null, running: false, open: false, quitPending: false, operation: null, notice: siteCopy.demo.notices.quit }
            : { ...applied, phase: 'off', capturedAt: null, quitPending: false, operation: null, notice: siteCopy.demo.notices.noChanges }
        }
        if (state.quitPending && state.helperReadiness !== 'ready') return { ...applied, phase: 'activeVerified', operation: null, error: appPresentation.setup.recoveryBlocked, notice: '' }
        return state.quitPending
          ? { ...applied, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
          : publish(applied, 'activeVerified', siteCopy.demo.notices.applied)
      }
    case 'restoreSucceeded':
      if (state.phase !== 'restoring') return state
      {
        const restoreConflictOnly = state.conflictResolution === 'restoreOriginal' && state.conflict
        const restoredKeys = restoreConflictOnly ? new Set([state.conflict.key]) : new Set(Object.keys(state.ownedValues))
        const currentValues = { ...state.currentValues }
        for (const key of restoredKeys) currentValues[key] = state.originals[key]
        const ownedValues = { ...state.ownedValues }
        for (const key of restoredKeys) delete ownedValues[key]
        const hasSession = Object.keys(ownedValues).length > 0
        const resolved = { ...state, currentValues, ownedValues, hasSession, capturedAt: hasSession ? state.capturedAt : null, conflict: null, conflictDeferred: false, conflictResolution: null }
        if (restoreConflictOnly && Object.keys(ownedValues).length && !state.quitPending) {
          return { ...resolved, phase: 'recoveryRequired', operation: null, error: appPresentation.recovery.remainingOwned, notice: '' }
        }
        if (restoreConflictOnly && Object.keys(ownedValues).length && state.quitPending) {
          if (state.helperReadiness !== 'ready') return { ...resolved, phase: 'recoveryRequired', operation: null, error: appPresentation.setup.recoveryBlocked, notice: '' }
          return { ...resolved, phase: 'restoring', operation: 'restoreRemaining', error: null, notice: appPresentation.recovery.titles.restoring }
        }
      return state.quitPending
        ? { ...publish(resolved, 'off', siteCopy.demo.notices.restored), running: false, open: false, notice: siteCopy.demo.notices.quit }
        : publish(resolved, 'off', siteCopy.demo.notices.restored)
      }
    case 'operationFailed':
      return { ...state, phase: 'recoveryRequired', operation: action.uncertain ? 'uncertain' : null,
        error: action.message ?? appPresentation.recovery.failed, notice: '', quitPending: state.quitPending }
    case 'retry':
      if (state.operation === 'uncertain') return { ...state, phase: 'recoveryRequired', error: appPresentation.recovery.uncertainRetry, notice: '' }
      if (state.phase === 'recoveryRequired' && state.legacyUnknown) return { ...state, error: appPresentation.recovery.legacyHelp }
      if (state.conflict) return { ...state, error: appPresentation.recovery.deferred }
      return { ...state, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
    case 'stayOpen': return { ...state, quitPending: false, running: true, error: null }
    case 'quit':
      if (state.phase === 'off') return { ...state, running: false, open: false, notice: siteCopy.demo.notices.quit }
      if (state.hasSession && state.helperReadiness !== 'ready' && !['checking', 'applying', 'restoring'].includes(state.phase)) return { ...state, quitPending: true, error: appPresentation.setup.recoveryBlocked, notice: '' }
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', quitPending: true, error: null, notice: appPresentation.recovery.titles.restoring }
      if (['checking', 'applying', 'restoring'].includes(state.phase)) return { ...state, quitPending: true, error: null }
      return { ...state, phase: 'recoveryRequired', quitPending: true, error: appPresentation.recovery.quitPrompt, notice: '' }
    case 'quitAnyway': return { ...state, update: { status: 'idle' }, running: false, open: false, quitPending: false, notice: siteCopy.demo.notices.quitAnyway }
    case 'restore':
      if (state.phase === 'off') return { ...state, error: appPresentation.footer.noBackup, notice: '' }
      if (state.legacyUnknown) return { ...state, error: appPresentation.recovery.legacyHelp }
      if (state.operation === 'uncertain' || state.conflict) return { ...state, error: appPresentation.recovery.refuseWrite }
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
      if (state.phase === 'recoveryRequired') return { ...state, error: appPresentation.recovery.explicitRestore, phase: 'restoring', operation: 'restore' }
      return state
    case 'conflict': {
      const proposed = action.conflict ?? { key: 'powernap', currentValue: '0', lastVerified: null }
      const key = Object.hasOwn(originals, proposed.key) ? proposed.key : 'powernap'
      const currentValue = ['0', '1', 0, 1].includes(proposed.currentValue) ? String(proposed.currentValue) : null
      const conflict = { ...proposed, key, currentValue, lastVerified: proposed.lastVerified ?? null }
      return { ...state, phase: 'recoveryRequired', conflict, conflictDeferred: false, currentValues: { ...state.currentValues, [conflict.key]: conflict.currentValue }, error: appPresentation.recovery.conflict, notice: '' }
    }
    case 'keepCurrent': {
      if (!state.conflict || state.conflict.currentValue === null || state.operation === 'uncertain') return state
      const { [state.conflict.key]: _released, ...ownedValues } = state.ownedValues
      const currentValues = { ...state.currentValues, [state.conflict.key]: state.conflict.currentValue ?? null }
      const hasSession = Object.keys(ownedValues).length > 0
      const resolved = { ...state, conflict: null, conflictDeferred: false, conflictResolution: 'keepCurrent', ownedValues, hasSession, capturedAt: hasSession ? state.capturedAt : null, currentValues, operation: null }
      return Object.keys(ownedValues).length
        ? { ...resolved, phase: 'recoveryRequired', error: appPresentation.recovery.keptCurrent, notice: '' }
        : publish(resolved, 'off', appPresentation.recovery.keptCurrent)
    }
    case 'restoreRecordedOriginal':
      return state.conflict && state.conflict.currentValue !== null && state.operation !== 'uncertain' ? { ...state, conflictResolution: 'restoreOriginal', phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring } : state
    case 'deferConflict': return state.conflict ? { ...state, conflictDeferred: true, error: appPresentation.recovery.deferred } : state
    case 'reviewConflict': return state.conflict ? { ...state, conflictDeferred: false, error: appPresentation.recovery.conflict } : state
    case 'refreshRecovery': return state.operation === 'uncertain'
      ? { ...state, error: appPresentation.recovery.uncertainRetry }
      : { ...state, phase: 'checking', resumePhase: state.phase, conflictDeferred: false, error: null, notice: appPresentation.recovery.titles.checking }
    case 'legacyUnknown': return { ...state, phase: 'recoveryRequired', legacyUnknown: true, error: appPresentation.recovery.legacyHelp, notice: '', operation: null }
    case 'login': return { ...state, login: !state.login, notice: siteCopy.demo.notices.login }
    case 'sleepCapabilityChanged': return { ...state, sleepCapability: action.available === true }
    case 'sleep': return requestSleep(state)
    case 'scheduleSleep': {
      if (!canSleep(state)) return { ...state, error: sleepDisabledReason(state) }
      if (!sleepPresets.includes(action.minutes) || !Number.isFinite(action.now)) return state
      const generation = state.sleepGeneration + 1
      return { ...state, sleepGeneration: generation, sleepMessage: '', error: null,
        sleepTimer: { generation, deadline: action.now + action.minutes * 60_000, lastTick: action.now, remainingSeconds: action.minutes * 60 } }
    }
    case 'cancelScheduledSleep': return cancelTimer(state)
    case 'systemSleep':
    case 'systemWake': return state
    case 'sleepTimerTick': {
      const timer = state.sleepTimer
      if (!timer || action.generation !== timer.generation) return state
      if (!canSleep(state)) return cancelTimer(state)
      if (!Number.isFinite(action.now) || action.now < timer.lastTick || action.now - timer.lastTick > maximumSleepTickGap) return cancelTimer(state, appPresentation.sleep.interrupted)
      const remainingSeconds = Math.max(0, Math.ceil((timer.deadline - action.now) / 1000))
      return remainingSeconds === 0 ? requestSleep(state) : { ...state, sleepTimer: { ...timer, lastTick: action.now, remainingSeconds } }
    }
    case 'sleepRequestSettled': {
      if (!state.sleepRequestInFlight || action.generation !== state.sleepRequestGeneration) return state
      const settled = { ...state, sleepRequestInFlight: false, sleepRequestGeneration: null, error: null, sleepMessage: appPresentation.sleep.sent }
      return state.quitPending ? benzoDemoReducer(settled, { type: 'quit' }) : settled
    }
    case 'checkUpdates': return state.update?.status === 'checking' || !state.open || state.view !== 'main' || !state.running
      ? state : { ...state, update: { status: 'checking' }, notice: '' }
    case 'updatesChecked': return state.update?.status !== 'checking' || !state.open || state.view !== 'main' || !state.running
      ? state : { ...state, update: { status: 'ahead' } }
    case 'viewRelease': return !state.open || state.view !== 'main' || !state.running || !state.update || ['idle', 'checking'].includes(state.update.status)
      ? state : { ...state, notice: appPresentation.updates.demoNotice }
    default: return state
  }
}

const browserClock = { now: () => Date.now() }
const browserScheduler = { setTimeout: (callback, delay) => setTimeout(callback, delay), clearTimeout: timer => clearTimeout(timer) }

export function useBenzoDemo({ clock = browserClock, scheduler = browserScheduler } = {}) {
  const [state, reduce] = useReducer(benzoDemoReducer, undefined, () => initialDemoState(true))
  const dispatch = useCallback(action => reduce(action.type === 'scheduleSleep' ? { ...action, now: clock.now() } : action), [clock])
  useEffect(() => {
    if (state.phase === 'checking') dispatch({ type: 'checkingSucceeded' })
    if (state.phase === 'applying') dispatch({ type: 'applySucceeded' })
    if (state.phase === 'restoring' && ['restore', 'restoreRemaining'].includes(state.operation)) dispatch({ type: 'restoreSucceeded' })
  }, [state.phase, state.operation])
  useEffect(() => {
    if (state.update.status !== 'checking') return
    // Deterministic presentation only: no GitHub request, download, or installer.
    const timer = setTimeout(() => dispatch({ type: 'updatesChecked' }), 400)
    return () => clearTimeout(timer)
  }, [state.update])
  useEffect(() => {
    if (!state.sleepTimer) return
    const generation = state.sleepTimer.generation
    const timer = scheduler.setTimeout(() => reduce({ type: 'sleepTimerTick', generation, now: clock.now() }), 1000)
    return () => scheduler.clearTimeout(timer)
  }, [state.sleepTimer, clock, scheduler])
  useEffect(() => {
    if (!state.sleepRequestInFlight) return
    const generation = state.sleepRequestGeneration
    // Simulation only. The browser never requests system sleep or changes power settings.
    const timer = scheduler.setTimeout(() => reduce({ type: 'sleepRequestSettled', generation }), 400)
    return () => scheduler.clearTimeout(timer)
  }, [state.sleepRequestInFlight, state.sleepRequestGeneration, scheduler])
  useEffect(() => {
    const suspend = () => reduce({ type: 'systemSleep' })
    const resume = () => reduce({ type: 'systemWake' })
    const visibility = () => { if (document.visibilityState === 'hidden') suspend() }
    window.addEventListener('pagehide', suspend)
    window.addEventListener('pageshow', resume)
    document.addEventListener('visibilitychange', visibility)
    return () => {
      window.removeEventListener('pagehide', suspend)
      window.removeEventListener('pageshow', resume)
      document.removeEventListener('visibilitychange', visibility)
    }
  }, [])
  return [state, dispatch]
}
