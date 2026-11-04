// Marketing copy and public destinations. Native UI strings live in appPresentation.
const repository = 'https://github.com/chrisrogers37/benzo'

export const siteCopy = {
  brand: 'benzo',
  links: {
    repository,
    releases: `${repository}/releases`,
    help: `${repository}/issues`,
    contact: 'mailto:contact@benzo.work',
    setup: `${repository}#readme`,
    appleSleep: 'https://support.apple.com/guide/mac-help/if-your-mac-sleeps-or-wakes-unexpectedly-mchlp2995/mac',
    privacy: `${repository}/blob/main/PRIVACY.md`,
  },
  metadata: {
    canonical: 'https://benzo.work/',
    title: 'Benzo: Sleep controls for your Mac',
    description: 'Explore Benzo’s menu bar sleep settings and example diagnostics. Review release notes and recovery limitations before installing.',
  },
  navigation: { why: 'Why Benzo', setup: 'Getting started', download: 'Get Benzo', home: 'Benzo home', skip: 'Skip to content' },
  download: {
    primary: 'Get Benzo for Mac',
    details: 'Free · macOS 13+ · Administrator setup required',
    destination: 'Downloads are existing releases; the demo previews unreleased changes.',
    shortNote: 'Free for Mac · Opens GitHub Releases',
  },
  hero: {
    context: 'The anti-Amphetamine for Mac',
    headline: ['Done for the day.', 'Mac still awake?'],
    lead: 'Benzo brings sleep settings and diagnostics into your menu bar.',
    description: 'Recovery controls are being updated. Explore the unreleased changes below and review the limitations before installing.',
    secondary: 'See how it works',
  },
  story: {
    headline: ['The screen is off.', 'The Mac might not be.'],
    paragraphs: [
      'Docks, external displays, audio gear, and background apps can keep your Mac awake or wake it after you put it to sleep. Your Mac may keep using power long after you’ve finished working.',
      'Benzo brings sleep settings, recent sleep sessions, and wake reasons into one menu bar panel.',
    ],
    source: 'Apple’s guide to unexpected wake-ups',
  },
  featuresLabel: 'What Benzo does',
  features: [
    { title: 'Review your sleep settings', body: 'The unreleased update locks choices during an active session or when recovery evidence remains. Sleep Now is unavailable while recovery controls are being updated.' },
    { title: 'Explore diagnostics', body: 'Review recent sleep sessions, wake reasons, and reported settings. The demo uses made-up readings.' },
    { title: 'A pill in your menu bar', body: 'Click the pill to open Benzo, review the options, then close the panel when you’re done.' },
  ],
  gettingStarted: {
    title: 'Install Benzo',
    introduction: 'Benzo lives in the menu bar at the top of your screen.',
    steps: [
      { title: 'Get the Mac app', body: 'Download the DMG from GitHub Releases, open it, then drag Benzo into Applications.', link: 'View releases', destination: 'releases' },
      { title: 'Look for the pill', body: 'Open Benzo from Applications, then click the pill in your menu bar. There’s no separate app window.', illustration: 'menubar' },
      { title: 'Review the limitations', body: 'Read the release notes and recovery guidance before setup. The download may differ from this unreleased demo.', link: 'Read before installing', destination: '#before-install' },
    ],
  },
  trust: {
    title: 'Before you install',
    introduction: 'Benzo changes your Mac’s sleep settings and needs administrator access to set up. The containment changes shown here are unreleased; existing downloads retain known recovery limitations.',
    source: 'View source on GitHub',
    questions: [
      { question: 'Will it work with my Mac and dock?', answer: 'The app requires macOS Ventura 13 or later. Sleep behavior depends on your Mac, macOS version, dock, and other equipment. Benzo can’t promise zero battery drain, USB ports with no power, or compatibility with every studio setup.' },
      { question: 'Why does Benzo need administrator access?', answer: 'Changing sleep settings requires administrator access. Existing downloads install a permission rule that stays after quitting and isn’t limited to Benzo. The unreleased source only observes whether a legacy rule is present; it does not install one or verify authorization.', link: 'Read the setup documentation', destination: 'setup' },
      { question: 'Will macOS let me open it?', answer: 'The current release documentation says the app isn’t notarized by Apple, so macOS may block it from opening. Read the release instructions before continuing.', link: 'View release instructions', destination: 'releases' },
      { question: 'Does quitting restore my settings?', answer: 'Benzo tries to restore your saved settings when you quit, but this can fail. Deleting the app doesn’t undo changes either. Read the recovery and removal guidance before uninstalling, and keep the settings backup if something goes wrong.', link: 'Get help on GitHub', destination: 'help' },
      { question: 'Can I leave my audio interface connected?', answer: 'Check the instructions for your interface and driver. Some manufacturers recommend disconnecting before sleep or shutting down after a session. Finish recordings and exports first; Benzo can’t guarantee that your devices will reconnect correctly.' },
      { question: 'What data does Benzo collect?', answer: 'This demo uses made-up readings and keeps its state in this page; it cannot read your Mac. The reviewed native source keeps preferences and saved settings locally, with no analytics or diagnostics upload code. Vercel receives website requests, and external links use other services. The privacy notes describe the reviewed source separately from the older download.', link: 'Read the privacy notes', destination: 'privacy' },
    ],
  },
  final: { title: 'Get Benzo for your Mac', description: 'Download the app and review the release notes on GitHub.' },
  footer: { tagline: 'Built because I wanted my Mac to sleep when I do.', source: 'Source', help: 'Help & feedback', contact: 'Contact', privacy: 'Privacy' },
  demo: {
    name: 'Interactive Benzo app demonstration', navigation: 'Demo navigation', title: 'Interactive demo',
    firstLaunch: 'First launch', reset: 'Reset demo', restart: 'Restart demo', closed: 'Demo closed.',
    diagnostics: 'View diagnostics',
    hint: 'Preview unreleased changes with the switch and Options. Use First launch to try settings before activation. This demo won’t change your Mac’s settings.',
    disclosure: 'About this demo',
    disclosureBody: 'The controls follow unreleased source changes, not the downloadable app. Permission status only observes legacy rule evidence; it does not grant access. Sleep Now is disabled, and settings stay locked while active or while a backup remains, including after Restore. Diagnostic readings are made-up examples. This page can’t put your Mac to sleep or show macOS permission prompts. On a real Mac, sleep, USB power, and restoring settings depend on your setup; the labels in the app don’t guarantee those results.',
    resultsLabel: 'Example diagnostic results',
    notices: {
      permission: 'Status refresh simulated. No permission was requested or changed.',
      settings: 'Sleep settings changed only in this demo.', login: 'Login preference changed only in this demo.',
      restored: 'Restore simulated. The backup remains, so settings stay locked. Your Mac’s settings haven’t changed.',
      quit: 'Demo closed. Use Restart demo to explore again.',
    },
  },
}
