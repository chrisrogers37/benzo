import { Fragment, useId, useState } from 'react'
import { appPresentation as app, settingOptions, siteCopy, AppSymbol, MenuPill } from '../design'

const copy = siteCopy.demo

function ReadStatus({ result, failure }) {
  return <div className="bn-session bn-faint">{result.status === 'failure' ? failure : app.diagnostics.loading}</div>
}

function Diagnostics({ onBack, sleepData, usbDevices, observedSettings }) {
  return <>
    <div className="bn-diagnostic-header"><button onClick={onBack}><AppSymbol name="back" size={10} />{app.diagnostics.back}</button><strong>{app.diagnostics.title}</strong><span aria-hidden="true" /></div>
    <div className="bn-diagnostic-scroll" role="region" aria-label={copy.resultsLabel} tabIndex={0}>
      <div className="bn-panel"><h3>{app.diagnostics.sessions}</h3>
        {sleepData.status !== 'success' ? <ReadStatus result={sleepData} failure={app.diagnostics.sleepFailure} /> : sleepData.value.sessions.length === 0 ? <div className="bn-session bn-faint">{app.diagnostics.sleepEmpty}</div> : sleepData.value.sessions.map(s => <div className="bn-session" key={s.sleep}><div>{s.sleep}{s.wake != null && <><span className="bn-faint"> → </span>{s.wake}</>}</div><div><span>{s.dur}</span>{s.bat && <span className={`bn-mono${s.delta === '0%' ? ' bn-green' : ''}`}>{s.bat}{s.delta && ` (${s.delta})`}</span>}</div></div>)}
      </div>
      <div className="bn-panel"><h3>{app.diagnostics.wakeReason}</h3>
        {sleepData.status !== 'success' ? <ReadStatus result={sleepData} failure={app.diagnostics.sleepFailure} /> : <div className="bn-wake"><AppSymbol name="laptop" size={16} /><span>{sleepData.value.lastWakeReason ?? app.diagnostics.unknown}</span></div>}
      </div>
      <div className="bn-panel"><h3>{app.diagnostics.usb}</h3>
        {usbDevices.status !== 'success' ? <ReadStatus result={usbDevices} failure={app.diagnostics.usbFailure} /> : usbDevices.value.length === 0 ? <div className="bn-session bn-faint">{app.diagnostics.usbEmpty}</div> : usbDevices.value.map(d => <div className="bn-usb" key={d.name}><span>{d.name}</span>{d.power != null && <span className="bn-mono">{d.power} mA</span>}</div>)}
      </div>
      <div className="bn-panel"><h3>{app.diagnostics.settings}</h3>
        {observedSettings.status !== 'success' ? <ReadStatus result={observedSettings} failure={app.diagnostics.settingsFailure} /> : <>{observedSettings.value.map(s => <div className="bn-verification" key={s.key}><span className="bn-mono">{s.key}</span><span className="bn-mono bn-value">{s.actualValue ?? app.diagnostics.missing}</span></div>)}<div className="bn-verification-summary bn-faint">{app.diagnostics.summary}</div></>}
      </div>
    </div>
  </>
}

function Setup({ observation, onRefresh, onBack }) {
  return <div className="bn-setup"><span className="bn-setup-pill" aria-hidden="true">💊</span><h3>{app.setup.title}</h3><p>{app.setup.observations[observation] ?? app.setup.observations.unknown}</p><button onClick={onRefresh}>{app.setup.action}</button><button onClick={onBack}>{app.setup.back}</button><p className="bn-setup-note">{app.setup.note.map((line, index) => <Fragment key={line}>{index > 0 && <br />}{line}</Fragment>)}</p></div>
}

export default function NativeAppDemo({ state, dispatch }) {
  const { running, open, view, options, settings, login, phase } = state
  const active = phase === 'activeVerified'
  const busy = ['checking', 'applying', 'restoring'].includes(phase)
  const canToggleMaster = active || (phase === 'off' && settingOptions.some(option => option.available && settings[option.key]))
  const canRestore = Boolean(state.hasSession) && !busy && state.operation !== 'uncertain'
  const [aboutOpen, setAboutOpen] = useState(false)
  const aboutId = useId()

  const sleepUnavailableId = useId()
  const selectionBlockedId = useId()
  const selectionBlocked = phase !== 'off' || state.legacyUnknown

  return <div className="bz-native-demo" aria-label={copy.name}>
    <div className="bn-demo-toolbar" aria-label={copy.navigation}><span>{copy.title}</span><div><button onClick={() => dispatch({ type: 'firstLaunch' })}>{copy.firstLaunch}</button><button onClick={() => dispatch({ type: 'reset' })}>{running ? copy.reset : copy.restart}</button></div></div>
    <div className="bn-stage">
      <div className="bn-menubar"><span>{app.menu.finder}</span><div>{running && <button className="bn-menu-button" aria-label={app.menu.name} aria-expanded={open} title={app.menu.hint} onClick={e => dispatch({ type: 'pill', alt: e.altKey })}><MenuPill active={active} /></button>}<span>{app.menu.wifi}</span><span>{app.menu.time}</span></div></div>
      {running && open && <div className="bn-popover" aria-label={view === 'setup' ? app.setup.name : view === 'diagnostics' ? app.diagnostics.name : app.mainName}>
        {view === 'setup' ? <Setup observation={state.permissionObservation} onRefresh={() => dispatch({ type: 'refreshPermission' })} onBack={() => dispatch({ type: 'back' })} /> : view === 'diagnostics' ? <Diagnostics sleepData={state.sleepData} usbDevices={state.usbDevices} observedSettings={state.observedSettings} onBack={() => dispatch({ type: 'back' })} /> : <>
          <div className="bn-master"><div><strong>{app.recovery.titles[phase] ?? app.recovery.titles.recoveryRequired}</strong><p>{phase === 'recoveryRequired' && state.error ? state.error : app.recovery.messages[phase] ?? app.recovery.messages.recoveryRequired}</p></div><button className={`bn-toggle${active ? ' bn-on' : ''}`} role="switch" aria-label={app.master.name} aria-checked={active} disabled={!canToggleMaster} onClick={() => dispatch({ type: 'active' })}><span /></button></div>
          <div className="bn-sleep-wrap"><div className="bn-sleep-capsule">
            <button className="bn-sleep-now" disabled aria-describedby={sleepUnavailableId}><AppSymbol name="moon" size={11} />{app.sleep.action}</button>
          </div><p className="bn-control-reason" id={sleepUnavailableId}>{app.sleep.unavailable}</p></div>
          <div className="bn-options"><button aria-expanded={options} onClick={() => dispatch({ type: 'options' })}><span>{app.options}</span><span className={options ? 'bn-expanded' : ''}><AppSymbol name="chevron" size={9} /></span></button></div>
          {options && <div className="bn-settings">{selectionBlocked && <p className="bn-control-reason" id={selectionBlockedId}>{app.selectionBlocked}</p>}{settingOptions.map(({ key, label, desc, available, unavailableReason }) => <button className="bn-setting" role="checkbox" aria-checked={settings[key]} aria-label={label} disabled={selectionBlocked || !available} aria-describedby={!available ? `${key}-unavailable` : selectionBlocked ? selectionBlockedId : undefined} key={key} onClick={() => dispatch({ type: 'setting', key })}><span><strong>{label}</strong><small>{desc}</small>{!available && <small id={`${key}-unavailable`} className="bn-control-reason">{unavailableReason}</small>}</span><span className={`bn-checkbox${settings[key] ? ' bn-checked' : ''}`}>{settings[key] && <AppSymbol name="check" size={8} />}</span></button>)}</div>}
          {state.error && <p className="bn-error" role="alert">{state.error}</p>}
          {phase === 'recoveryRequired' && <div className="bn-recovery-actions"><button onClick={() => dispatch({ type: 'retry' })}>Retry</button>{state.conflict && state.operation !== 'uncertain' && <><button onClick={() => dispatch({ type: 'keepCurrent' })}>Keep Current</button><button onClick={() => dispatch({ type: 'restoreRecordedOriginal' })}>Restore Recorded Original Anyway</button><button onClick={() => dispatch({ type: 'deferConflict' })}>Defer</button></>}{state.conflict && <button onClick={() => dispatch({ type: 'refreshRecovery' })}>Refresh Recovery Status</button>}{state.quitPending && <><button onClick={() => dispatch({ type: 'stayOpen' })}>Stay Open</button><button onClick={() => dispatch({ type: 'quitAnyway' })}>Quit Anyway</button></>}</div>}
          {state.legacyUnknown && <p className="bn-control-reason">{app.recovery.legacyHelp}</p>}
          <div className="bn-footer"><div className="bn-login"><span>{app.footer.login}</span><button className={`bn-login-toggle${login ? ' bn-on' : ''}`} role="switch" aria-label={app.footer.login} aria-checked={login} onClick={() => dispatch({ type: 'login' })}><span /></button></div><div className="bn-footer-actions"><span>{app.version}</span><span className="bn-control-reason">{app.footer.restoreHelp}</span><button disabled={!canRestore} onClick={() => dispatch({ type: 'restore' })}>{app.footer.restore}</button><button onClick={() => dispatch({ type: 'quit' })}>{app.footer.quit}</button></div></div>
        </>}
      </div>}
      {!running && <div className="bn-closed">{copy.closed}<button onClick={() => dispatch({ type: 'reset' })}>{copy.restart} <span aria-hidden="true">↗</span></button></div>}
    </div>
    <div className="bn-demo-caption">
      <p>{copy.hint}</p>
      <div className="bn-demo-actions">
        <button onClick={() => dispatch({ type: 'diagnostics' })}>{copy.diagnostics}<AppSymbol name="chevron" size={10} /></button>
        <button aria-expanded={aboutOpen} aria-controls={aboutId} onClick={() => setAboutOpen(open => !open)}>{copy.disclosure}<span className={aboutOpen ? 'bn-expanded' : ''}><AppSymbol name="chevron" size={10} /></span></button>
      </div>
      <p id={aboutId} className="bn-demo-about" hidden={!aboutOpen}>{copy.disclosureBody}</p>
      <p className="bn-demo-notice" role="status" aria-live="polite">{state.notice}</p>
    </div>
  </div>
}
