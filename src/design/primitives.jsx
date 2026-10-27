import { brandColors } from './tokens'
import { siteCopy } from './siteCopy'

const paths = {
  arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
  download: <path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4" />,
  display: <><rect x="3" y="4" width="18" height="13" rx="2" /><path d="M8 21h8m-4-4v4" /></>,
  audio: <path d="M4 10v4m4-8v12m4-15v18m4-15v12m4-8v4" />,
  plug: <path d="M8 3v5m8-5v5M6 8h12v3a6 6 0 0 1-12 0V8Zm6 9v4" />,
  external: <path d="M14 3h7v7m0-7L10 14M10 3H4a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-6" />,
  moon: <path d="M20 15A8.5 8.5 0 0 1 9 4a8.5 8.5 0 1 0 11 11Z" fill="currentColor" stroke="none" />,
  sleepingMoon: <><path d="M16 15A7 7 0 0 1 7 6a7 7 0 1 0 9 9Z" fill="currentColor" stroke="none" /><path d="M13 6h3l-3 4h3m2-8h4l-4 5h4" strokeWidth="1.2" /></>,
  clock: <><circle cx="12" cy="12" r="9" /><path d="M12 6v6l4 2" /></>,
  x: <path d="m6 6 12 12M18 6 6 18" />,
  check: <path d="m5 12 4 4L19 6" />,
  chevron: <path d="m9 5 7 7-7 7" />,
  back: <path d="m15 5-7 7 7 7" />,
  warning: <><path d="m12 3 10 18H2Z" /><path d="M12 9v5m0 3v.2" /></>,
  laptop: <><rect x="4" y="4" width="16" height="12" rx="1" /><path d="M2 20h20l-2-4H4Z" /></>,
}

export function Icon({ name, size = 20, ...props }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>{paths[name]}</svg>
}

export function AppSymbol({ size = 12, ...props }) {
  return <Icon size={size} strokeWidth="1.8" {...props} />
}

export function Pill({ small = false }) {
  return <span className={`bz-pill${small ? ' bz-pill-small' : ''}`} aria-hidden="true"><span /></span>
}

export function MenuPill({ active }) {
  return <svg width="28" height="22" viewBox="0 0 28 22" aria-hidden="true"><rect x="4" y="5" width="20" height="12" rx="6" fill={active ? brandColors.pink : 'none'} stroke={active ? 'none' : 'currentColor'} strokeWidth="1.3" /><path d="M7 11h14" stroke={active ? '#ffffff99' : 'currentColor'} strokeWidth=".8" /></svg>
}

export function DownloadLink() {
  return <a className="bz-button" href={siteCopy.links.releases} target="_blank" rel="noreferrer"><Icon name="download" size={18} />{siteCopy.download.primary}<Icon name="arrow" size={18} /></a>
}

export function Brand({ homeLabel }) {
  return <a className="bz-brand" href="#main" aria-label={homeLabel}><span className="bz-logo"><Pill small /></span>{siteCopy.brand}<span className="bz-brand-period">.</span></a>
}
