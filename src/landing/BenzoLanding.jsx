import NativeAppDemo from './NativeAppDemo'
import { useBenzoDemo } from '../demo/useBenzoDemo'
import { siteCopy as copy, appPresentation, designVariables, Icon, Pill, MenuPill, DownloadLink, Brand } from '../design'

function ContentLink({ destination, children, ...props }) {
  const href = copy.links[destination] ?? destination
  const external = href.startsWith('https://')
  return <a href={href} {...(external ? { target: '_blank', rel: 'noreferrer' } : {})} {...props}>{children}</a>
}

export default function BenzoLanding() {
  const [demo, dispatch] = useBenzoDemo()
  const active = demo.active && demo.running

  return <div className="benzo-site" style={designVariables(active)} data-benzo-active={active}>
    <a className="bz-skip" href="#main">{copy.navigation.skip}</a>
    <header className="bz-header bz-width">
      <Brand homeLabel={copy.navigation.home} />
      <nav aria-label="Main navigation"><a href="#why-benzo">{copy.navigation.why}</a><a href="#getting-started">{copy.navigation.setup}</a><ContentLink className="bz-nav-download" destination="releases">{copy.navigation.download} <Icon name="arrow" size={15} /></ContentLink></nav>
    </header>

    <main id="main">
      <section className="bz-hero bz-width" aria-labelledby="hero-title">
        <div className="bz-hero-copy">
          <div className="bz-eyebrow">{copy.hero.context}</div>
          <h1 id="hero-title">{copy.hero.headline[0]}<br /><span>{copy.hero.headline[1]}</span></h1>
          <p className="bz-lead">{copy.hero.lead}</p>
          <p className="bz-hero-description">{copy.hero.description}</p>
          <div className="bz-hero-actions">
            <DownloadLink />
            <p className="bz-download-note">{copy.download.details}<br /><span>{copy.download.destination}</span></p>
            <a className="bz-text-link" href="#why-benzo">{copy.hero.secondary} <span aria-hidden="true">↓</span></a>
          </div>
        </div>
        <div className="bz-hero-visual"><div className="bz-orbit" aria-hidden="true"><span>z</span><span>z</span><span>z</span></div><NativeAppDemo state={demo} dispatch={dispatch} /></div>
      </section>

      <section id="why-benzo" className="bz-story bz-width" aria-labelledby="story-title">
        <div className="bz-story-heading"><h2 id="story-title">{copy.story.headline[0]}<br />{copy.story.headline[1]}</h2></div>
        <div className="bz-story-body">{copy.story.paragraphs.map(text => <p key={text}>{text}</p>)}<ContentLink destination="appleSleep" className="bz-source-link">{copy.story.source} <Icon name="external" size={13} /></ContentLink></div>
      </section>

      <section className="bz-capabilities bz-width" aria-label={copy.featuresLabel}>{copy.features.map(item => <article key={item.title}><h3>{item.title}</h3><p>{item.body}</p></article>)}</section>

      <section id="getting-started" className="bz-start" aria-labelledby="start-title"><div className="bz-width">
        <div className="bz-section-heading"><h2 id="start-title">{copy.gettingStarted.title}</h2><p>{copy.gettingStarted.introduction}</p></div>
        <ol className="bz-steps">{copy.gettingStarted.steps.map((step, index) => <li key={step.title}>
          <span className="bz-step-number" aria-hidden="true">{index + 1}</span><h3>{step.title}</h3><p>{step.body}</p>
          {step.link && <ContentLink destination={step.destination}>{step.link} <Icon name="arrow" size={15} /></ContentLink>}
          {step.illustration === 'menubar' && <span className="bz-mini-menu"><MenuPill active={active} /><span>{appPresentation.menu.wifi}</span><span>{appPresentation.menu.time}</span></span>}
        </li>)}</ol>
      </div></section>

      <section id="before-install" className="bz-trust bz-width" aria-labelledby="trust-title">
        <div><h2 id="trust-title">{copy.trust.title}</h2><p>{copy.trust.introduction}</p><ContentLink className="bz-text-link" destination="repository">{copy.trust.source} <Icon name="external" size={14} /></ContentLink></div>
        <div className="bz-faqs">{copy.trust.questions.map(item => <details key={item.question}><summary>{item.question}<Icon name="chevron" size={16} /></summary><div className="bz-answer">{item.answer}{item.link && <> <ContentLink destination={item.destination}>{item.link} <Icon name="external" size={12} /></ContentLink></>}</div></details>)}</div>
      </section>

      <section className="bz-final bz-width" aria-labelledby="final-title"><div className="bz-final-pill"><Pill /></div><div><h2 id="final-title">{copy.final.title}</h2><p>{copy.final.description}</p></div><div><DownloadLink /><span className="bz-final-note">{copy.download.shortNote}</span></div></section>
    </main>

    <footer className="bz-footer bz-width"><Brand /><p>{copy.footer.tagline}</p><div><ContentLink destination="repository">{copy.footer.source}</ContentLink><ContentLink destination="help">{copy.footer.help} <Icon name="external" size={12} /></ContentLink><ContentLink destination="contact">{copy.footer.contact}</ContentLink></div></footer>
  </div>
}
