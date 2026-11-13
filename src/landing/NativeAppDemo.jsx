import { useEffect, useId, useRef, useState } from 'react'
import { appPresentation as app, settingOptions, siteCopy, AppSymbol, MenuPill } from '../design'

const copy = siteCopy.demo

function ReadStatus({ result, failure }) {
  return <div className="bn-session bn-faint">{result.status === 'failure' ? failure : app.diagnostics.loading}</div>
}

function Diagnostics({ onBack, backRef, sleepData, usbDevices, observedSettings }) {
  return <>
    <div className="bn-diagnostic-header"><button ref={backRef} onClick={onBack}><AppSymbol name="back" size={10} />{app.diagnostics.back}</button><h3>{app.diagnostics.title}</h3><span aria-hidden="true" /></div>
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

function Setup({ readiness, error, recoveryMessage, canReplaceHelper, canRemoveHelper, removalConfirmation, setupBusy, actionRef, onBack, dispatch }) {
  const status = app.setup.states[readiness] ?? app.setup.states.connectionUnavailable
  const primaryDisabled = setupBusy || (readiness === 'incompatible' && !canReplaceHelper)
  const removalTitleId = useId()
  const removalReasonId = useId()
  const cancelRef = useRef(null)
  const removeRef = useRef(null)
  const wasConfirmingRemoval = useRef(false)
  useEffect(() => {
    if (removalConfirmation) cancelRef.current?.focus()
    else if (wasConfirmingRemoval.current) removeRef.current?.focus()
    wasConfirmingRemoval.current = removalConfirmation
  }, [removalConfirmation])
  if (removalConfirmation) return <div className="bn-setup" role="alertdialog" aria-labelledby={removalTitleId} aria-describedby={removalReasonId}>
    <h3 id={removalTitleId}>{app.setup.removeTitle}</h3><p id={removalReasonId}>{app.setup.removalConfirmation}</p>
    <button disabled={!canRemoveHelper} onClick={() => dispatch({ type: 'removeHelper' })}>{app.setup.remove}</button>
    <button ref={cancelRef} onClick={() => dispatch({ type: 'cancelRemoveHelper' })}>{app.setup.cancel}</button>
  </div>
  return <div className="bn-setup">
    <span className="bn-setup-pill" aria-hidden="true">💊</span><h3>{status.title}</h3><p>{status.message}</p>
    {recoveryMessage && <p>{recoveryMessage}</p>}
    {error && <p className="bn-error" role="alert">{error}</p>}
    {readiness === 'incompatible' && !canReplaceHelper && !setupBusy && <p>{app.setup.replacementBlocked}</p>}
    {status.action && <button ref={!primaryDisabled ? actionRef : undefined} disabled={primaryDisabled} onClick={() => dispatch({ type: status.event })}>{status.action}</button>}
    {['ready', 'incompatible'].includes(readiness) && <>
      {!canRemoveHelper && !setupBusy && <p>{app.setup.removalBlocked}</p>}
      <button ref={removeRef} disabled={!canRemoveHelper} onClick={() => dispatch({ type: 'requestRemoveHelper' })}>{app.setup.remove}</button>
    </>}
    <button ref={(!status.action || primaryDisabled) && readiness !== 'ready' && !setupBusy ? actionRef : undefined} disabled={setupBusy} onClick={() => dispatch({ type: 'refreshHelper' })}>{app.setup.refresh}</button>
    <button ref={readiness === 'ready' || setupBusy ? actionRef : undefined} onClick={onBack}>{readiness === 'ready' ? app.setup.done : app.setup.back}</button>
    <p className="bn-setup-note">{app.setup.note}</p>
  </div>
}

function UpdateCheck({ update = { status: 'idle' }, dispatch }) {
  const checking = update.status === 'checking'
  const available = update.status === 'available'
  const message = ['current', 'available'].includes(update.status)
    ? app.updates[update.status](update.version) : app.updates[update.status]
  return <>
    <div className="bn-update-row"><span>{app.version}</span><button disabled={checking} onClick={() => dispatch({ type: 'checkUpdates' })}>{checking ? app.updates.checking : app.updates.check}</button></div>
    <div className="bn-update-result" aria-live="polite" aria-atomic="true">
      {checking && <p>{app.updates.checking}</p>}
      {!checking && message && <>
        <p>{message}</p>
        {available && <><p>{app.updates.compatibility}</p><p>{app.updates.recovery}</p></>}
        <button onClick={() => dispatch({ type: 'viewRelease' })}>{available ? app.updates.release : app.updates.releases}</button>
      </>}
    </div>
  </>
}

export default function NativeAppDemo({ state, dispatch }) {
  const { running, open, view, options, settings, login, phase } = state
  const statusTitle = app.recovery.titles[phase] ?? app.recovery.titles.recoveryRequired
  const statusMessage = phase === 'recoveryRequired' && state.error
    ? state.error
    : app.recovery.messages[phase] ?? app.recovery.messages.recoveryRequired
  const active = phase === 'activeVerified'
  const busy = ['checking', 'applying', 'restoring'].includes(phase)
  const helperReady = state.helperReadiness === 'ready' && !state.isPerformingHelperSetup
  const helperStatus = app.setup.states[state.helperReadiness] ?? app.setup.states.connectionUnavailable
  const canToggleMaster = helperReady && (active || (phase === 'off' && settingOptions.some(option => option.available && settings[option.key])))
  const canRestore = helperReady && Boolean(state.hasSession) && !busy && state.operation !== 'uncertain' && !state.conflict
  const canReplaceHelper = state.helperReadiness === 'incompatible' && phase === 'off' && !state.hasSession && state.operation !== 'uncertain' && !state.isPerformingHelperSetup
  const canRemoveHelper = ['ready', 'incompatible'].includes(state.helperReadiness) && phase === 'off' && !state.hasSession && state.operation !== 'uncertain' && !state.isPerformingHelperSetup
  const conflictSetting = state.conflict && settingOptions.find(option => option.commands.some(([key]) => key === state.conflict.key))
  const [aboutOpen, setAboutOpen] = useState(false)
  const aboutId = useId()

  const sleepUnavailableId = useId()
  const selectionBlockedId = useId()
  const descriptionId = useId()
  const selectionBlocked = phase !== 'off' || state.legacyUnknown
  const menuRef = useRef(null)
  const diagnosticsRef = useRef(null)
  const externalDiagnosticsRef = useRef(null)
  const diagnosticBackRef = useRef(null)
  const setupRef = useRef(null)
  const setupActionRef = useRef(null)
  const diagnosticOrigin = useRef('menu')
  const returningFromDiagnostics = useRef(false)
  const returningFromSetup = useRef(false)

  useEffect(() => {
    if (!running || !open) return
    if (view === 'diagnostics') diagnosticBackRef.current?.focus()
    else if (view === 'setup' && !state.helperRemovalConfirmation) setupActionRef.current?.focus()
    else if (view === 'main' && returningFromDiagnostics.current) {
      returningFromDiagnostics.current = false
      const origin = { menu: menuRef, internal: diagnosticsRef, external: externalDiagnosticsRef }
      origin[diagnosticOrigin.current].current?.focus()
    } else if (view === 'main' && returningFromSetup.current) {
      returningFromSetup.current = false
      setupRef.current?.focus()
    }
  }, [running, open, view])
  useEffect(() => {
    if (running && open && view === 'setup' && !state.helperRemovalConfirmation) setupActionRef.current?.focus()
  }, [state.helperReadiness])

  const openDiagnostics = origin => {
    diagnosticOrigin.current = origin
    dispatch({ type: 'diagnostics' })
    diagnosticBackRef.current?.focus()
  }
  const backFromDiagnostics = () => {
    returningFromDiagnostics.current = true
    dispatch({ type: 'back' })
  }
  const backFromSetup = () => {
    returningFromSetup.current = true
    dispatch({ type: 'back' })
  }

  return <div className="bz-native-demo" aria-label={copy.name}>
    <div className="bn-demo-toolbar" aria-label={copy.navigation}><span>{copy.title}</span><div><button onClick={() => dispatch({ type: 'firstLaunch' })}>{copy.firstLaunch}</button><button onClick={() => dispatch({ type: 'reset' })}>{running ? copy.reset : copy.restart}</button></div></div>
    <div className="bn-stage">
      <div className="bn-menubar"><span>{app.menu.finder}</span><div>{running && <button ref={menuRef} className="bn-menu-button" aria-label={app.menu.name} aria-description={`Benzo: ${statusTitle}. ${statusMessage}`} aria-expanded={open} title={`${statusTitle}. ${statusMessage}`} onClick={e => { if (!open && e.altKey) diagnosticOrigin.current = 'menu'; dispatch({ type: 'pill', alt: e.altKey }) }}><MenuPill active={active} status={phase} /></button>}<span>{app.menu.wifi}</span><span>{app.menu.time}</span></div></div>
      {running && open && <div className="bn-popover" aria-label={view === 'setup' ? app.setup.name : view === 'diagnostics' ? app.diagnostics.name : app.mainName} onKeyDown={event => {
        if (event.key === 'Escape') {
          event.stopPropagation()
          if (state.helperRemovalConfirmation) dispatch({ type: 'cancelRemoveHelper' })
          else { dispatch({ type: 'pill' }); menuRef.current?.focus() }
        }
      }}>
        <div className={view === 'diagnostics' ? undefined : 'bn-popover-scroll'} role={view === 'diagnostics' ? undefined : 'region'} aria-label={view === 'diagnostics' ? undefined : 'Benzo controls'} tabIndex={view === 'diagnostics' ? undefined : 0}>
        {view === 'setup' ? <Setup readiness={state.helperReadiness} error={state.helperSetupError} recoveryMessage={state.hasSession ? (helperReady ? statusMessage : app.setup.recoveryBlocked) : null} canReplaceHelper={canReplaceHelper} canRemoveHelper={canRemoveHelper} removalConfirmation={state.helperRemovalConfirmation} setupBusy={state.isPerformingHelperSetup} actionRef={setupActionRef} onBack={backFromSetup} dispatch={dispatch} /> : view === 'diagnostics' ? <Diagnostics backRef={diagnosticBackRef} sleepData={state.sleepData} usbDevices={state.usbDevices} observedSettings={state.observedSettings} onBack={backFromDiagnostics} /> : <>
          <div className="bn-master"><div><strong>{statusTitle}</strong><p>{statusMessage}</p></div><button className={`bn-toggle${active ? ' bn-on' : ''}`} role="switch" aria-label={active ? app.master.restore : app.master.apply} aria-checked={active} disabled={!canToggleMaster} onClick={() => dispatch({ type: 'active' })}><span /></button></div>
          {!helperReady && <div className="bn-helper-status"><strong>{helperStatus.title}</strong><p className="bn-control-reason">{state.hasSession ? app.setup.recoveryBlocked : helperStatus.message}</p></div>}
          <div className="bn-helper-entry"><button ref={setupRef} onClick={() => dispatch({ type: 'setup' })}>{app.setup.entry}</button></div>
          <div className="bn-sleep-wrap"><div className="bn-sleep-capsule">
            <button className="bn-sleep-now" disabled aria-describedby={sleepUnavailableId}><AppSymbol name="moon" size={11} />{app.sleep.action}</button>
          </div><p className="bn-control-reason" id={sleepUnavailableId}>{app.sleep.unavailable}</p></div>
          <div className="bn-options"><button aria-expanded={options} onClick={() => dispatch({ type: 'options' })}><span>{app.options}</span><span className={options ? 'bn-expanded' : ''}><AppSymbol name="chevron" size={9} /></span></button></div>
          {options && <div className="bn-settings">{selectionBlocked && <p className="bn-control-reason" id={selectionBlockedId}>{app.selectionBlocked}</p>}{settingOptions.map(({ key, label, desc, available, unavailableReason }) => <button className="bn-setting" role="checkbox" aria-checked={settings[key]} aria-label={label} disabled={selectionBlocked || !available} aria-describedby={`${descriptionId}-${key}${!available ? ` ${descriptionId}-${key}-unavailable` : ''}${selectionBlocked ? ` ${selectionBlockedId}` : ''}`} key={key} onClick={() => dispatch({ type: 'setting', key })}><span><strong>{label}</strong><small id={`${descriptionId}-${key}`}>{desc}</small>{!available && <small id={`${descriptionId}-${key}-unavailable`} className="bn-control-reason">{unavailableReason}</small>}</span><span aria-hidden="true" className={`bn-checkbox${settings[key] ? ' bn-checked' : ''}`}>{settings[key] && <AppSymbol name="check" size={8} />}</span></button>)}</div>}
          <div className="bn-diagnostics-entry"><button ref={diagnosticsRef} onClick={() => openDiagnostics('internal')}>{app.diagnostics.title}</button></div>
          {state.error && <p className="bn-error" role="alert">{state.error}</p>}
          {(phase === 'recoveryRequired' || (state.quitPending && !busy)) && <>
            {state.capturedAt && <p className="bn-control-reason">{app.recovery.evidence.captured} {state.capturedAt}</p>}
            {state.conflict && (state.conflictDeferred
              ? <div className="bn-recovery-conflict"><span>Conflict deferred; recovery evidence is retained.</span><button onClick={() => dispatch({ type: 'reviewConflict' })}>Review</button></div>
              : <div className="bn-recovery-conflict" role="group" aria-label="Recovery conflict details">
                <strong>{conflictSetting?.label ?? state.conflict.key} · {app.recovery.evidence.simulatedProfile}</strong>
                <p>{app.recovery.evidence.original} {state.originals[state.conflict.key] ?? app.diagnostics.missing}. {app.recovery.evidence.current} {state.conflict.currentValue ?? app.diagnostics.missing}.</p>
                <p>{app.recovery.evidence.lastVerified} {state.conflict.lastVerified ?? app.recovery.evidence.none}. {app.recovery.evidence.race}</p>
                <div className="bn-recovery-actions"><button disabled={state.conflict.currentValue === null || state.operation === 'uncertain'} onClick={() => dispatch({ type: 'keepCurrent' })}>Keep Current</button><button disabled={!helperReady || state.conflict.currentValue === null || state.operation === 'uncertain'} onClick={() => dispatch({ type: 'restoreRecordedOriginal' })}>Restore Recorded Original Anyway</button><button onClick={() => dispatch({ type: 'deferConflict' })}>Defer</button></div>
              </div>)}
            <div className="bn-recovery-actions">{state.quitPending && <button disabled={!helperReady} onClick={() => dispatch({ type: 'retry' })}>Retry</button>}{!state.quitPending && <button onClick={() => dispatch({ type: 'refreshRecovery' })}>Refresh Recovery Status</button>}{state.quitPending && <><button onClick={() => dispatch({ type: 'stayOpen' })}>Stay Open</button><button onClick={() => dispatch({ type: 'quitAnyway' })}>Quit Anyway</button></>}</div>
          </>}
          {state.legacyUnknown && <p className="bn-control-reason">{app.recovery.legacyHelp}</p>}
          <div className="bn-footer"><div className="bn-login"><span>{app.footer.login}</span><button className={`bn-login-toggle${login ? ' bn-on' : ''}`} role="switch" aria-label={app.footer.login} aria-checked={login} onClick={() => dispatch({ type: 'login' })}><span /></button></div><UpdateCheck update={state.update} dispatch={dispatch} /><p className="bn-restore-help bn-control-reason">{app.footer.restoreHelp}</p><div className="bn-footer-actions"><button disabled={!canRestore} onClick={() => dispatch({ type: 'restore' })}>{app.footer.restore}</button><button onClick={() => dispatch({ type: 'quit' })}>{app.footer.quit}</button></div></div>
        </>}
        </div>
      </div>}
      {!running && <div className="bn-closed">{copy.closed}<button onClick={() => dispatch({ type: 'reset' })}>{copy.restart} <span aria-hidden="true">↗</span></button></div>}
    </div>
    <div className="bn-demo-caption">
      <p>{copy.hint}</p>
      <div className="bn-demo-actions">
        {state.helperReadiness === 'requiresApproval' && state.helperSettingsOpened && <button onClick={() => dispatch({ type: 'helperApprovalGranted' })}>Simulate macOS Approval</button>}
        <button ref={externalDiagnosticsRef} onClick={() => openDiagnostics('external')}>{copy.diagnostics}<AppSymbol name="chevron" size={10} /></button>
        <button aria-expanded={aboutOpen} aria-controls={aboutId} onClick={() => setAboutOpen(open => !open)}>{copy.disclosure}<span className={aboutOpen ? 'bn-expanded' : ''}><AppSymbol name="chevron" size={10} /></span></button>
      </div>
      <p id={aboutId} className="bn-demo-about" hidden={!aboutOpen}>{copy.disclosureBody}</p>
      <p className="bn-demo-notice" role="status" aria-live="polite">{state.notice}</p>
    </div>
  </div>
}
