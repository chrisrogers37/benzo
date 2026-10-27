import { Fragment, useId, useState } from 'react'
import { appPresentation as app, exampleReadings, settingOptions, siteCopy, AppSymbol, MenuPill } from '../design'

const copy = siteCopy.demo

function Diagnostics({ onBack, active, settings }) {
  // DiagnosticService compares the example readings with active, enabled settings.
  const readings = exampleReadings.values
  const verification = settingOptions.flatMap(({ key: setting, commands }) => commands.map(([key, target]) => {
    const val = readings[key] ?? app.diagnostics.missing
    const expected = active && settings[setting] ? target : val
    return { key, val, expected, ok: val === expected }
  }))
  const drifted = verification.filter(row => !row.ok).length
  return <>
    <div className="bn-diagnostic-header"><button onClick={onBack}><AppSymbol name="back" size={10} />{app.diagnostics.back}</button><strong>{app.diagnostics.title}</strong><span aria-hidden="true" /></div>
    <div className="bn-diagnostic-scroll" role="region" aria-label={copy.resultsLabel} tabIndex={0}>
      <div className="bn-panel"><h3>{app.diagnostics.sessions}</h3>{exampleReadings.sleepSessions.map(s => <div className="bn-session" key={s.sleep}><div>{s.sleep}<span className="bn-faint"> → </span>{s.wake}</div><div><span>{s.dur}</span><span className={`bn-mono${s.delta === '0%' ? ' bn-green' : ''}`}>{s.bat} ({s.delta})</span></div></div>)}</div>
      <div className="bn-panel"><h3>{app.diagnostics.wakeReason}</h3><div className="bn-wake"><AppSymbol name="laptop" size={16} /><span>{exampleReadings.wakeReason}</span></div></div>
      <div className="bn-panel"><h3>{app.diagnostics.usb}</h3>{exampleReadings.usbDevices.map(d => <div className="bn-usb" key={d.name}><span>{d.name}</span><span className="bn-mono">{d.power} mA</span></div>)}</div>
      <div className="bn-panel"><h3>{app.diagnostics.settings}</h3>{verification.map(s => <div className="bn-verification" key={s.key}><span className={`bn-result ${s.ok ? 'bn-success' : 'bn-failure'}`}><AppSymbol name={s.ok ? 'check' : 'x'} size={7} /></span><span className="bn-mono">{s.key}</span><span className={`bn-mono bn-value${s.ok ? '' : ' bn-red'}`}>{s.val}</span>{!s.ok && <small>({app.diagnostics.expected} {s.expected})</small>}</div>)}<div className={`bn-verification-summary${drifted ? ' bn-red' : ' bn-green'}`}>{drifted ? app.diagnostics.drifted(drifted) : app.diagnostics.verified}</div></div>
    </div>
  </>
}

function Setup({ onSetup }) {
  return <div className="bn-setup"><span className="bn-setup-pill" aria-hidden="true">💊</span><h3>{app.setup.title}</h3><p>{app.setup.description}</p><button onClick={onSetup}>{app.setup.action}</button><p className="bn-setup-note">{app.setup.note.map((line, index) => <Fragment key={line}>{index > 0 && <br />}{line}</Fragment>)}</p></div>
}

export default function NativeAppDemo({ state, dispatch }) {
  const { running, open, view, active, options, settings, login, picker, remaining, sleeping } = state
  const [aboutOpen, setAboutOpen] = useState(false)
  const aboutId = useId()

  const time = remaining === null ? '' : `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')}`

  return <div className="bz-native-demo" aria-label={copy.name}>
    <div className="bn-demo-toolbar" aria-label={copy.navigation}><span>{copy.title}</span><div><button onClick={() => dispatch({ type: 'firstLaunch' })}>{copy.firstLaunch}</button><button onClick={() => dispatch({ type: 'reset' })}>{running ? copy.reset : copy.restart}</button></div></div>
    <div className="bn-stage">
      <div className="bn-menubar"><span>{app.menu.finder}</span><div>{running && <button className="bn-menu-button" aria-label={app.menu.name} aria-expanded={open} title={app.menu.hint} onClick={e => dispatch({ type: 'pill', alt: e.altKey })}><MenuPill active={active} /></button>}<span>{app.menu.wifi}</span><span>{app.menu.time}</span></div></div>
      {running && open && <div className="bn-popover" aria-label={view === 'setup' ? app.setup.name : view === 'diagnostics' ? app.diagnostics.name : app.mainName}>
        {view === 'setup' ? <Setup onSetup={() => dispatch({ type: 'setup' })} /> : view === 'diagnostics' ? <Diagnostics active={active} settings={settings} onBack={() => dispatch({ type: 'back' })} /> : <>
          <div className="bn-master"><div><strong>{active ? app.master.on : app.master.off}</strong><p>{active ? app.master.activeDescription : app.master.inactiveDescription}</p></div><button className={`bn-toggle${active ? ' bn-on' : ''}`} role="switch" aria-label={app.master.name} aria-checked={active} onClick={() => dispatch({ type: 'active' })}><span /></button></div>
          <div className="bn-sleep-wrap"><div className={`bn-sleep-capsule${sleeping ? ' bn-sleeping' : ''}`}>
            {sleeping || remaining !== null ? <button className="bn-status" disabled={sleeping} onClick={() => dispatch({ type: 'cancel' })} title={sleeping ? undefined : copy.cancelTimer}>{sleeping ? <><span className="bn-spinner" />{app.sleep.sleeping}</> : <><AppSymbol name="sleepingMoon" size={11} />{app.sleep.countdown} {time}</>}</button> : <>
              {picker ? <div className="bn-timer-picker">{app.sleep.minutes.map(minutes => <button key={minutes} onClick={() => dispatch({ type: 'timer', minutes, now: Date.now() })}>{minutes}m</button>)}</div> : <button className="bn-sleep-now" onClick={() => dispatch({ type: 'sleep' })}><AppSymbol name="moon" size={11} />{app.sleep.action}</button>}
              <span className="bn-sleep-divider" /><button className="bn-clock" aria-label={picker ? app.sleep.closeTimer : app.sleep.openTimer} title={picker ? app.sleep.closeTimer : app.sleep.openTimer} onClick={() => dispatch({ type: 'picker' })}><AppSymbol name={picker ? 'x' : 'clock'} size={12} /></button>
            </>}
          </div></div>
          {active && <div className="bn-blockers"><div><AppSymbol name="warning" size={9} />{app.blockers.singular}</div><div>{app.blockers.exampleName}</div></div>}
          <div className="bn-options"><button aria-expanded={options} onClick={() => dispatch({ type: 'options' })}><span>{app.options}</span><span className={options ? 'bn-expanded' : ''}><AppSymbol name="chevron" size={9} /></span></button></div>
          {options && <div className="bn-settings">{settingOptions.map(({ key, label, desc }) => <button className="bn-setting" role="checkbox" aria-checked={settings[key]} aria-label={label} key={key} onClick={() => dispatch({ type: 'setting', key })}><span><strong>{label}</strong><small>{desc}</small></span><span className={`bn-checkbox${settings[key] ? ' bn-checked' : ''}`}>{settings[key] && <AppSymbol name="check" size={8} />}</span></button>)}</div>}
          {state.error && <p className="bn-error" role="alert">{state.error}</p>}
          <div className="bn-footer"><div className="bn-login"><span>{app.footer.login}</span><button className={`bn-login-toggle${login ? ' bn-on' : ''}`} role="switch" aria-label={app.footer.login} aria-checked={login} onClick={() => dispatch({ type: 'login' })}><span /></button></div><div className="bn-footer-actions"><span>{app.version}</span><button onClick={() => dispatch({ type: 'restore' })}>{app.footer.restore}</button><button onClick={() => dispatch({ type: 'quit' })}>{app.footer.quit}</button></div></div>
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
