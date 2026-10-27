// Shared web design primitives. Native reproduction values stay separate so a
// marketing typography change cannot silently alter the app's source-based UI.
export const brandColors = Object.freeze({
  pink: '#d4749c',
  pinkSoft: 'rgba(212,116,156,0.08)',
  pinkGlow: '0 0 20px rgba(212,116,156,0.2)',
  pinkBorder: 'rgba(212,116,156,0.15)',
})

export const designTokens = Object.freeze({
  color: {
    paper: '#f8f6f2', ink: '#262923', muted: '#5e6259', line: '#dedfd6',
    pink: brandColors.pink, rose: '#9b3e65', roseHover: '#803052',
    inkHover: '#40443b', white: '#ffffff', review: '#ede9e5',
    neutralSurface: '#e9e9e2', softPink: '#f0d5e0',
    finalPink: '#efdbe3', finalPinkBorder: '#e5cbd5',
    section: '#eeeee6', sectionBorder: '#e3e3d9',
    controlBorder: '#a9ac9c', menu: '#fbfaf6', menuBorder: '#dadbcf',
    pillLight: '#f3c4d7', pillDark: '#a84870', pillBorder: '#8a3056',
    neutralPillLight: '#dcdfd5', neutralPillDark: '#62685c',
  },
  type: {
    sans: "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    mono: "'SFMono-Regular', Menlo, Consolas, monospace",
    body: '16px', secondary: '14px', heading: '34px', subheading: '20px',
    hero: 'clamp(48px, 4.2vw, 60px)', heroMobile: 'clamp(36px, 10.1vw, 48px)',
    bodyLeading: '1.65', headingLeading: '1.18', heroLeading: '1.12',
    headingTracking: '-.025em', heroTracking: '-.03em',
  },
  space: { 1: '4px', 2: '8px', 3: '12px', 4: '16px', 5: '20px', 6: '24px', 7: '28px', 8: '32px', 9: '36px', 10: '40px', 12: '48px', 14: '56px', 16: '64px', 20: '80px' },
  radius: { small: '4px', control: '6px', panel: '10px', pill: '100px' },
  motion: { short: '150ms', normal: '200ms', easing: 'ease' },
  layout: { page: '1160px', copy: '490px', demo: '320px', control: '44px', cta: '50px' },
  // These values follow the existing native demo's current SwiftUI reference.
  // Improving its contrast or dimensions requires a native/parity decision.
  native: {
    ink: '#1a1a1a', muted: '#999', faint: '#ccc', description: '#c0c0c0',
    version: '#d0d0d0', toggleOff: '#ddd', loginOff: '#dedede', blue: '#007aff',
    green: '#28cd41', red: '#ff3b30', redMuted: '#ff3b30b3', hoverText: '#555',
    menubar: '#ffffffd9', menubarBorder: '#e6e1dd', whiteSoft: '#ffffffe6',
    whiteLine: '#ffffff38', whiteFaint: '#ffffff55', blackFaint: '#00000005',
    blackLine: '#00000008', blackPressed: '#00000009', blackOutline: '#00000014',
    blackShadow: '#00000025', thumbShadow: '#0000001f',
    pinkHover: '#d4749c08', pinkShadow: '#d4749c4d', pinkShadowSoft: '#d4749c26',
    pinkShadowStrong: '#d4749c59', pinkCheckboxGlow: '#d4749c40',
    base: '12px', tiny: '9px', small: '10px', caption: '10.5px', secondary: '11px',
    setting: '12.5px', title: '13px', setupTitle: '15px',
    toggleWidth: '44px', toggleHeight: '26px', toggleThumb: '20px',
    popoverRadius: '10px', sidePadding: '20px', diagnosticPadding: '16px',
    diagnosticHeight: '400px',
  },
})

const commonVariables = Object.freeze({
  ...Object.fromEntries(Object.entries(designTokens.color).map(([name, value]) => [`--${name.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`)}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.type).map(([name, value]) => [`--type-${name.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`)}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.space).map(([name, value]) => [`--space-${name}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.radius).map(([name, value]) => [`--radius-${name}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.motion).map(([name, value]) => [`--motion-${name}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.layout).map(([name, value]) => [`--layout-${name}`, value])),
  ...Object.fromEntries(Object.entries(designTokens.native).map(([name, value]) => [`--native-${name.replace(/[A-Z]/g, c => `-${c.toLowerCase()}`)}`, value])),
})

// One effective demo state drives every page-level accent. Native app controls
// use the stable --pink/native tokens because their own states follow SwiftUI.
export function designVariables(active = true) {
  const c = designTokens.color
  return {
    ...commonVariables,
    '--rose': active ? c.rose : c.ink,
    '--accent-hover': active ? c.roseHover : c.inkHover,
    '--brand-surface': active ? c.softPink : c.neutralSurface,
    '--final-surface': active ? c.finalPink : c.neutralSurface,
    '--final-border': active ? c.finalPinkBorder : c.line,
    '--pill-light': active ? c.pillLight : c.neutralPillLight,
    '--pill-dark': active ? c.pillDark : c.neutralPillDark,
    '--pill-border': active ? c.pillBorder : c.ink,
    '--glow-opacity': active ? 1 : 0,
  }
}
