import { useEffect, useReducer } from 'react'
import { appPresentation, exampleReadings, settingOptions } from '../design/appPresentation'
import { siteCopy } from '../design/siteCopy'

const originals = Object.freeze({ powernap: '1', womp: '1', tcpkeepalive: '1' })
const selectedDefaults = Object.freeze({
  hibernateMode: false, disablePowerNap: true, disableProximityWake: false,
  disableNetworkWake: true, disableTcpKeepAlive: false,
})

const selectedValues = settings => ({
  powernap: settings.disablePowerNap ? '0' : originals.powernap,
  womp: settings.disableNetworkWake ? '0' : originals.womp,
  tcpkeepalive: settings.disableTcpKeepAlive ? '0' : originals.tcpkeepalive,
})

const ownedSelectionValues = settings => Object.fromEntries(
  Object.entries(selectedValues(settings)).filter(([key, value]) => value !== originals[key]),
)

export const initialDemoState = (active = true) => ({
  running: true, open: true, view: 'main', permissionDestination: 'main',
  phase: active ? 'activeVerified' : 'off', options: true,
  settings: { ...selectedDefaults }, originals,
  hasSession: active,
  ownedValues: active ? ownedSelectionValues(selectedDefaults) : {},
  currentValues: active ? selectedValues(selectedDefaults) : { ...originals },
  login: false, error: null, notice: '', permissionObservation: 'noLegacyRule',
  operation: null, quitPending: false, resumePhase: null, conflict: null, conflictResolution: null, legacyUnknown: false,
  sleepData: { status: 'success', value: { sessions: exampleReadings.sleepSessions, lastWakeReason: exampleReadings.wakeReason } },
  usbDevices: { status: 'success', value: exampleReadings.usbDevices },
  observedSettings: { status: 'success', value: settingOptions.flatMap(({ commands }) => commands.map(([key]) => ({ key, actualValue: exampleReadings.values[key] }))) },
})

function publish(state, phase, notice = '') {
  return { ...state, phase, notice, error: null, operation: null, quitPending: false }
}

export function benzoDemoReducer(state, action) {
  switch (action.type) {
    case 'reset': return initialDemoState(true)
    case 'firstLaunch': return { ...initialDemoState(false), options: false, view: 'setup', permissionObservation: 'noLegacyRule' }
    case 'refreshPermission': return { ...state, notice: siteCopy.demo.notices.permission }
    case 'pill': return state.open
      ? { ...state, open: false }
      : { ...state, open: true, view: state.view === 'setup' ? 'setup' : action.alt ? 'diagnostics' : 'main', permissionDestination: action.alt ? 'diagnostics' : 'main' }
    case 'diagnostics': return { ...state, running: true, open: true, view: state.view === 'setup' ? 'setup' : 'diagnostics', permissionDestination: 'diagnostics', notice: '' }
    case 'back': return { ...state, view: state.view === 'setup' ? state.permissionDestination : 'main' }
    case 'options': return { ...state, options: !state.options }
    case 'setting':
      if (state.phase !== 'off' || state.legacyUnknown) return { ...state, error: appPresentation.selectionBlocked }
      if (!settingOptions.find(option => option.key === action.key)?.available) return { ...state, error: appPresentation.recovery.unsupported }
      return { ...state, settings: { ...state.settings, [action.key]: !state.settings[action.key] }, error: null }
    case 'active':
      if (state.phase === 'off') {
        if (!Object.values(state.settings).some(Boolean)) return { ...state, error: appPresentation.recovery.emptySelection }
        return { ...state, phase: 'applying', operation: 'apply', hasSession: true, error: null, notice: appPresentation.recovery.titles.applying }
      }
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
      if (state.phase === 'recoveryRequired') return { ...state, error: appPresentation.recovery.refuseWrite }
      return state
    case 'checking': return { ...state, phase: 'checking', resumePhase: state.phase, error: null, notice: appPresentation.recovery.titles.checking }
    case 'checkingSucceeded': {
      if (state.phase !== 'checking') return state
      const nextPhase = state.resumePhase ?? (Object.keys(state.ownedValues).length ? 'activeVerified' : 'off')
      if (!state.quitPending) return { ...state, phase: nextPhase, resumePhase: null, notice: appPresentation.recovery.titles[nextPhase] }
      if (nextPhase === 'activeVerified' || Object.keys(state.ownedValues).length) return { ...state, phase: 'restoring', operation: 'restore', resumePhase: null, error: null, notice: appPresentation.recovery.titles.restoring }
      if (nextPhase === 'recoveryRequired' || state.conflict || state.legacyUnknown) return { ...state, phase: 'recoveryRequired', resumePhase: null, error: appPresentation.recovery.quitPrompt }
      return { ...state, phase: 'off', running: false, open: false, quitPending: false, resumePhase: null, notice: siteCopy.demo.notices.quit }
    }
    case 'applySucceeded':
      if (state.phase !== 'applying') return state
      {
        const applied = { ...state, hasSession: true, ownedValues: ownedSelectionValues(state.settings), currentValues: { ...state.currentValues, ...selectedValues(state.settings) } }
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
        const resolved = { ...state, currentValues, ownedValues, hasSession: Object.keys(ownedValues).length > 0, conflict: null, conflictResolution: null }
        if (restoreConflictOnly && Object.keys(ownedValues).length && !state.quitPending) {
          return { ...resolved, phase: 'recoveryRequired', operation: null, error: appPresentation.recovery.remainingOwned, notice: '' }
        }
        if (restoreConflictOnly && Object.keys(ownedValues).length && state.quitPending) {
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
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', quitPending: true, error: null, notice: appPresentation.recovery.titles.restoring }
      if (['checking', 'applying', 'restoring'].includes(state.phase)) return { ...state, quitPending: true, error: null }
      return { ...state, phase: 'recoveryRequired', quitPending: true, error: appPresentation.recovery.quitPrompt, notice: '' }
    case 'quitAnyway': return { ...state, running: false, open: false, quitPending: false, notice: siteCopy.demo.notices.quitAnyway }
    case 'restore':
      if (state.phase === 'off') return { ...state, error: appPresentation.footer.noBackup, notice: '' }
      if (state.legacyUnknown) return { ...state, error: appPresentation.recovery.legacyHelp }
      if (state.operation === 'uncertain' || state.conflict) return { ...state, error: appPresentation.recovery.refuseWrite }
      if (state.phase === 'activeVerified') return { ...state, phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring }
      if (state.phase === 'recoveryRequired') return { ...state, error: appPresentation.recovery.explicitRestore, phase: 'restoring', operation: 'restore' }
      return state
    case 'conflict': {
      const conflict = action.conflict ?? { key: 'powernap' }
      return { ...state, phase: 'recoveryRequired', conflict, currentValues: { ...state.currentValues, [conflict.key]: conflict.currentValue ?? '2' }, error: appPresentation.recovery.conflict, notice: '' }
    }
    case 'keepCurrent': {
      if (!state.conflict || state.operation === 'uncertain') return state
      const { [state.conflict.key]: _released, ...ownedValues } = state.ownedValues
      const currentValues = { ...state.currentValues, [state.conflict.key]: state.conflict.currentValue ?? state.currentValues[state.conflict.key] }
      const resolved = { ...state, conflict: null, conflictResolution: 'keepCurrent', ownedValues, hasSession: Object.keys(ownedValues).length > 0, currentValues, operation: null }
      return Object.keys(ownedValues).length
        ? { ...resolved, phase: 'recoveryRequired', error: appPresentation.recovery.keptCurrent, notice: '' }
        : publish(resolved, 'off', appPresentation.recovery.keptCurrent)
    }
    case 'restoreRecordedOriginal':
      return state.conflict && state.operation !== 'uncertain' ? { ...state, conflictResolution: 'restoreOriginal', phase: 'restoring', operation: 'restore', error: null, notice: appPresentation.recovery.titles.restoring } : state
    case 'deferConflict': return state.conflict ? { ...state, error: appPresentation.recovery.deferred } : state
    case 'refreshRecovery': return state.operation === 'uncertain'
      ? { ...state, error: appPresentation.recovery.uncertainRetry }
      : { ...state, phase: 'checking', resumePhase: state.phase, error: null, notice: appPresentation.recovery.titles.checking }
    case 'legacyUnknown': return { ...state, phase: 'recoveryRequired', legacyUnknown: true, error: appPresentation.recovery.legacyHelp, notice: '', operation: null }
    case 'login': return { ...state, login: !state.login, notice: siteCopy.demo.notices.login }
    case 'sleep': return { ...state, error: appPresentation.sleep.unavailable }
    default: return state
  }
}

export function useBenzoDemo() {
  const [state, dispatch] = useReducer(benzoDemoReducer, undefined, () => initialDemoState(true))
  useEffect(() => {
    if (state.phase === 'checking') dispatch({ type: 'checkingSucceeded' })
    if (state.phase === 'applying') dispatch({ type: 'applySucceeded' })
    if (state.phase === 'restoring' && ['restore', 'restoreRemaining'].includes(state.operation)) dispatch({ type: 'restoreSucceeded' })
  }, [state.phase, state.operation])
  return [state, dispatch]
}
