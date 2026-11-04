import { useEffect, useReducer } from 'react'
import { appPresentation, exampleReadings, settingOptions } from '../design/appPresentation'
import { siteCopy } from '../design/siteCopy'

// Browser simulation only. No device APIs, permission requests or OS actions.
// The showcase starts active/expanded; First launch starts inactive/collapsed.
const defaults = () => ({
  running: true, open: true, view: 'main', permissionDestination: 'main', active: true, options: true,
  settings: Object.fromEntries(settingOptions.map(({ key, defaultEnabled }) => [key, defaultEnabled])),
  login: false, backup: true, update: { status: 'idle' }, error: null, notice: '', permissionObservation: 'legacyRulePresent',
  // Independent fictional read results, never derived from activity or choices.
  sleepData: { status: 'success', value: { sessions: exampleReadings.sleepSessions, lastWakeReason: exampleReadings.wakeReason } },
  usbDevices: { status: 'success', value: exampleReadings.usbDevices },
  observedSettings: { status: 'success', value: settingOptions.flatMap(({ commands }) => commands.map(([key]) => ({ key, actualValue: exampleReadings.values[key] }))) },
})

function reducer(state, action) {
  switch (action.type) {
    case 'reset': return defaults()
    case 'firstLaunch': return { ...defaults(), active: false, options: false, backup: false, view: 'setup', permissionObservation: 'noLegacyRule' }
    case 'refreshPermission': return { ...state, notice: siteCopy.demo.notices.permission }
    case 'pill': return state.open
      ? { ...state, open: false, update: state.update.status === 'checking' ? { status: 'idle' } : state.update }
      : { ...state, open: true, view: state.view === 'setup' ? 'setup' : action.alt ? 'diagnostics' : 'main', permissionDestination: action.alt ? 'diagnostics' : 'main' }
    case 'diagnostics': return { ...state, update: state.update.status === 'checking' ? { status: 'idle' } : state.update, running: true, open: true, view: state.view === 'setup' ? 'setup' : 'diagnostics', permissionDestination: 'diagnostics', notice: '' }
    case 'back': return { ...state, view: state.view === 'setup' ? state.permissionDestination : 'main' }
    case 'active': return { ...state, active: !state.active, backup: true, error: null, notice: siteCopy.demo.notices.settings }
    case 'options': return { ...state, options: !state.options }
    case 'setting': return state.active || state.backup
      ? { ...state, error: appPresentation.selectionBlocked }
      : { ...state, settings: { ...state.settings, [action.key]: !state.settings[action.key] } }
    case 'login': return { ...state, login: !state.login, notice: siteCopy.demo.notices.login }
    case 'sleep': return { ...state, error: appPresentation.sleep.unavailable }
    case 'restore': return state.backup
      ? { ...state, active: false, error: null, notice: siteCopy.demo.notices.restored }
      : { ...state, error: appPresentation.footer.noBackup, notice: '' }
    case 'quit': return { ...state, update: { status: 'idle' }, running: false, open: false, notice: siteCopy.demo.notices.quit }
    case 'checkUpdates': return state.update.status === 'checking' || !state.open || state.view !== 'main' || !state.running
      ? state : { ...state, update: { status: 'checking' }, notice: '' }
    case 'updatesChecked': return state.update.status !== 'checking'
      ? state : { ...state, update: { status: 'current', version: '0.3.0' } }
    case 'viewRelease': return { ...state, notice: appPresentation.updates.demoNotice }
    default: return state
  }
}

export function useBenzoDemo() {
  const [state, dispatch] = useReducer(reducer, undefined, defaults)
  useEffect(() => {
    if (state.update.status !== 'checking') return
    // A deterministic simulated response, never a network check or an install.
    const timer = setTimeout(() => dispatch({ type: 'updatesChecked' }), 400)
    return () => clearTimeout(timer)
  }, [state.update])
  return [state, dispatch]
}
