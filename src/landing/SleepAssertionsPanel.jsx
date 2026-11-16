import { useId } from 'react'
import { appPresentation } from '../design/appPresentation'
import '../design/sleep-assertions.css'


function ProcessGroup({ title, empty, processes, kinds, copy, explanation }) {
  const groups = processes.map(process => ({ ...process, assertions: process.assertions.filter(assertion => kinds.includes(assertion.kind)) }))
    .filter(process => process.assertions.length > 0)
  if (groups.length === 0 && !empty) return null
  return <div className="bn-assertion-group">
    <h4>{title}</h4>
    {explanation && <p className="bn-assertion-note">{explanation}</p>}
    {groups.length === 0 ? <p className="bn-assertion-note">{empty}</p> : <ul>
      {groups.map(process => <li key={`${process.pid}:${process.processName}`}>
        <div className="bn-assertion-process"><strong>{process.friendlyName || process.processName}</strong><span>PID {process.pid}</span></div>
        {process.assertions.map(assertion => <p className="bn-assertion-description" key={assertion.id}>{assertion.description || assertion.type}</p>)}
        <details><summary>{copy.details}</summary><ul>{process.assertions.map(assertion => <li key={assertion.id}>
          <span>{process.processName}</span><br /><span className="bn-mono">{assertion.type} · {assertion.id}</span>
          {assertion.details?.map((detail, index) => <div key={index}>{detail}</div>)}
        </li>)}</ul></details>
      </li>)}
    </ul>}
  </div>
}

export default function SleepAssertionsPanel({ observation = { status: 'idle', snapshot: null, error: null }, copy = appPresentation.diagnostics.assertions }) {
  const titleId = useId()
  const { status, snapshot, error, refresh, pollingPaused = false } = observation
  const value = snapshot?.value
  const loading = status === 'loading'
  return <section className="bn-panel bn-assertions" aria-labelledby={titleId}>
    <div className="bn-assertion-heading"><h3 id={titleId}>{copy.title}</h3>
      <button onClick={refresh} disabled={loading || status === 'idle' || pollingPaused} aria-label="Refresh sleep activity">{loading ? copy.refreshing : copy.refresh}</button>
    </div>
    <div className="bn-assertion-body">
      {!pollingPaused && <p className="bn-assertion-note">{copy.cadence}</p>}
      {snapshot && <p className="bn-assertion-note">{copy.lastUpdated} <time dateTime={snapshot.updatedAt.toISOString()}>{snapshot.updatedAt.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })}</time></p>}
      {!snapshot && status !== 'failure' && <p className="bn-assertion-note">{loading ? copy.loading : copy.idle}</p>}
      {error && <p className="bn-assertion-failure">{copy.failure[error] ?? copy.failure.failed}{snapshot && <> {copy.stale}</>}</p>}
      {value && <>
        <ProcessGroup title={copy.idleTitle} empty={copy.idleEmpty} processes={value.processes} kinds={['idle']} copy={copy} />
        <ProcessGroup title={copy.systemTitle} empty={copy.systemEmpty} processes={value.processes} kinds={['system']} copy={copy} />
        <ProcessGroup title={copy.otherTitle} explanation={copy.otherExplanation} processes={value.processes} kinds={['display', 'other']} copy={copy} />
        <div className="bn-assertion-group"><h4>{copy.kernelTitle}</h4><p className="bn-assertion-note">{value.kernelSummary}</p>
          <p className="bn-assertion-note">{copy.kernelExplanation}</p>
          {(value.kernelDetails.length > 0 || value.sleepPreventers.length > 0) && <details><summary>{copy.kernelDetails}</summary>
            <ul>{[...value.kernelDetails, ...value.sleepPreventers].map((detail, index) => <li key={index}>{detail}</li>)}</ul>
          </details>}
        </div>
      </>}
      <p className="bn-assertion-note bn-assertion-explanation">{copy.explanation}</p>
    </div>
  </section>
}
