import { useEffect, useReducer } from 'react'
import { appPresentation, settingOptions } from '../design/appPresentation'
import { siteCopy } from '../design/siteCopy'

// Browser simulation only. No device APIs, permission requests or OS actions.
// The showcase starts active/expanded; First launch starts inactive/collapsed.
const defaults = () => ({
  running: true, open: true, view: 'main', active: true, options: true,
  settings: Object.fromEntries(settingOptions.map(({ key, defaultEnabled }) => [key, defaultEnabled])),
  login: false, backup: true, picker: false, deadline: null, remaining: null,
  sleeping: false, error: null, notice: '',
})

function reducer(state, action) {
  switch (action.type) {
    case 'reset': return defaults()
    case 'firstLaunch': return { ...defaults(), active: false, options: false, backup: false, view: 'setup' }
    case 'setup': return { ...state, view: 'main', notice: siteCopy.demo.notices.setup }
    case 'pill': return state.open
      ? { ...state, open: false }
      : { ...state, open: true, view: state.view === 'setup' ? 'setup' : action.alt ? 'diagnostics' : 'main', picker: false }
    case 'diagnostics': return { ...state, running: true, open: true, view: state.view === 'setup' ? 'setup' : 'diagnostics', picker: false, notice: '' }
    case 'back': return { ...state, view: 'main', picker: false }
    case 'active': return { ...state, active: !state.active, backup: true, error: null, notice: siteCopy.demo.notices.settings }
    case 'options': return { ...state, options: !state.options }
    case 'setting': return { ...state, settings: { ...state.settings, [action.key]: !state.settings[action.key] } }
    case 'login': return { ...state, login: !state.login, notice: siteCopy.demo.notices.login }
    case 'picker': return { ...state, picker: !state.picker }
    case 'timer': return { ...state, picker: false, remaining: action.minutes * 60, deadline: action.now + action.minutes * 60000, notice: siteCopy.demo.notices.timer }
    case 'tick': {
      if (!state.deadline) return state
      const milliseconds = state.deadline - action.now
      return milliseconds <= 0
        ? { ...state, deadline: null, remaining: null, sleeping: true, active: true, backup: true, error: null, notice: siteCopy.demo.notices.expired }
        : { ...state, remaining: Math.floor(milliseconds / 1000) }
    }
    case 'cancel': return { ...state, deadline: null, remaining: null, notice: siteCopy.demo.notices.canceled }
    case 'sleep': return { ...state, sleeping: true, active: true, backup: true, error: null, notice: siteCopy.demo.notices.sleep }
    case 'sleepFinished': return { ...state, sleeping: false }
    case 'restore': return state.backup
      ? { ...state, active: false, error: null, notice: siteCopy.demo.notices.restored }
      : { ...state, error: appPresentation.footer.noBackup, notice: '' }
    case 'quit': return { ...state, running: false, open: false, sleeping: false, deadline: null, remaining: null, notice: siteCopy.demo.notices.quit }
    default: return state
  }
}


export function useBenzoDemo() {
  const [state, dispatch] = useReducer(reducer, undefined, defaults)
  useEffect(() => {
    if (!state.deadline) return
    const interval = setInterval(() => dispatch({ type: 'tick', now: Date.now() }), 1000)
    return () => clearInterval(interval)
  }, [state.deadline])
  useEffect(() => {
    if (!state.sleeping) return
    const timeout = setTimeout(() => dispatch({ type: 'sleepFinished' }), appPresentation.sleep.requestDelayMs)
    return () => clearTimeout(timeout)
  }, [state.sleeping])
  return [state, dispatch]
}
