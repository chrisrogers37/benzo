import { useReducer } from 'react'
import { appPresentation, settingOptions } from '../design/appPresentation'
import { siteCopy } from '../design/siteCopy'

// Browser simulation only. No device APIs, permission requests or OS actions.
// The showcase starts active/expanded; First launch starts inactive/collapsed.
const defaults = () => ({
  running: true, open: true, view: 'main', active: true, options: true,
  settings: Object.fromEntries(settingOptions.map(({ key, defaultEnabled }) => [key, defaultEnabled])),
  login: false, backup: true, error: null, notice: '',
})

function reducer(state, action) {
  switch (action.type) {
    case 'reset': return defaults()
    case 'firstLaunch': return { ...defaults(), active: false, options: false, backup: false, view: 'setup' }
    case 'setup': return { ...state, view: 'main', notice: siteCopy.demo.notices.setup }
    case 'pill': return state.open
      ? { ...state, open: false }
      : { ...state, open: true, view: state.view === 'setup' ? 'setup' : action.alt ? 'diagnostics' : 'main' }
    case 'diagnostics': return { ...state, running: true, open: true, view: state.view === 'setup' ? 'setup' : 'diagnostics', notice: '' }
    case 'back': return { ...state, view: 'main' }
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
    case 'quit': return { ...state, running: false, open: false, notice: siteCopy.demo.notices.quit }
    default: return state
  }
}

export function useBenzoDemo() {
  return useReducer(reducer, undefined, defaults)
}
