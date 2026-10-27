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
  },
  metadata: {
    canonical: 'https://benzo.work/',
    title: 'Benzo: Sleep controls for your Mac',
    description: 'Adjust your Mac’s sleep settings and check which apps may be keeping it awake. A menu bar utility for MacBook setups with docks, displays, and audio gear.',
  },
  navigation: { why: 'Why Benzo', setup: 'Getting started', download: 'Get Benzo', home: 'Benzo home', skip: 'Skip to content' },
  download: {
    primary: 'Get Benzo for Mac',
    details: 'Free · macOS 13+ · Administrator setup required',
    destination: 'Download from GitHub Releases.',
    shortNote: 'Free for Mac · Opens GitHub Releases',
  },
  hero: {
    context: 'The anti-Amphetamine for Mac',
    headline: ['Done for the day.', 'Mac still awake?'],
    lead: 'Benzo gives you sleep controls in the menu bar, plus a view of the apps that may be keeping your Mac awake.',
    description: 'Choose your settings, finish your work, then click Sleep Now.',
    secondary: 'See how it works',
  },
  story: {
    headline: ['The screen is off.', 'The Mac might not be.'],
    paragraphs: [
      'Docks, external displays, audio gear, and background apps can keep your Mac awake or wake it after you put it to sleep. Your Mac may keep using power long after you’ve finished working.',
      'Check Benzo before leaving your desk to see your sleep settings and any blockers macOS reports.',
    ],
    source: 'Apple’s guide to unexpected wake-ups',
  },
  featuresLabel: 'What Benzo does',
  features: [
    { title: 'Choose your sleep settings', body: 'Adjust sleep and wake options. Use Sleep Now when you’re ready, or set a timer.' },
    { title: 'Check sleep blockers', body: 'See the apps macOS reports as sleep blockers, along with recent sleep sessions and wake reasons.' },
    { title: 'A pill in your menu bar', body: 'Click the pill to open Benzo. Adjust your settings, then close the panel when you’re done.' },
  ],
  gettingStarted: {
    title: 'Install Benzo',
    introduction: 'Benzo lives in the menu bar at the top of your screen.',
    steps: [
      { title: 'Get the Mac app', body: 'Download the DMG from GitHub Releases, open it, then drag Benzo into Applications.', link: 'View releases', destination: 'releases' },
      { title: 'Look for the pill', body: 'Open Benzo from Applications, then click the pill in your menu bar. There’s no separate app window.', illustration: 'menubar' },
      { title: 'Review your settings', body: 'Follow the administrator setup prompt, then review the sleep options. Finish recordings and exports before using Sleep Now.', link: 'Read before installing', destination: '#before-install' },
    ],
  },
  trust: {
    title: 'Before you install',
    introduction: 'Benzo changes your Mac’s sleep settings and needs administrator access to set up.',
    source: 'View source on GitHub',
    questions: [
      { question: 'Will it work with my Mac and dock?', answer: 'The app requires macOS Ventura 13 or later. Sleep behavior depends on your Mac, macOS version, dock, and other equipment. Benzo can’t promise zero battery drain, USB ports with no power, or compatibility with every studio setup.' },
      { question: 'Why does Benzo need administrator access?', answer: 'Changing sleep settings requires administrator access. Setup adds a permission rule that lets administrator accounts run specific macOS power commands. The rule stays installed after you quit and isn’t limited to Benzo.', link: 'Read the setup documentation', destination: 'setup' },
      { question: 'Will macOS let me open it?', answer: 'The current release documentation says the app isn’t notarized by Apple, so macOS may block it from opening. Read the release instructions before continuing.', link: 'View release instructions', destination: 'releases' },
      { question: 'Does quitting restore my settings?', answer: 'Benzo tries to restore your saved settings when you quit, but this can fail. Deleting the app doesn’t undo changes either. Read the recovery and removal guidance before uninstalling, and keep the settings backup if something goes wrong.', link: 'Get help on GitHub', destination: 'help' },
      { question: 'Can I leave my audio interface connected?', answer: 'Check the instructions for your interface and driver. Some manufacturers recommend disconnecting before sleep or shutting down after a session. Finish recordings and exports first; Benzo can’t guarantee that your devices will reconnect correctly.' },
    ],
  },
  final: { title: 'Get Benzo for your Mac', description: 'Download the app and review the release notes on GitHub.' },
  footer: { tagline: 'Built because I wanted my Mac to sleep when I do.', source: 'Source', help: 'Help & feedback', contact: 'Contact' },
  demo: {
    name: 'Interactive Benzo app demonstration', navigation: 'Demo navigation', title: 'Interactive demo',
    firstLaunch: 'First launch', reset: 'Reset demo', restart: 'Restart demo', closed: 'Demo closed.',
    diagnostics: 'View diagnostics',
    hint: 'Try the switch, timer, and Options. This demo won’t change your Mac’s settings.',
    disclosure: 'About this demo',
    disclosureBody: 'The controls follow the current app. Diagnostic readings are made-up examples. This page can’t put your Mac to sleep or show macOS permission prompts. On a real Mac, sleep, USB power, and restoring settings depend on your setup; the labels in the app don’t guarantee those results.',
    resultsLabel: 'Example diagnostic results', cancelTimer: 'Cancel sleep timer',
    notices: {
      setup: 'Setup simulated. No permission was requested or installed.',
      settings: 'Sleep settings changed only in this demo.', login: 'Login preference changed only in this demo.',
      timer: 'The demo timer is running. This countdown won’t put your Mac to sleep.',
      expired: 'The demo timer finished. No processes were stopped or sleep commands sent.',
      canceled: 'Demo timer canceled.', sleep: 'Sleep requested in the demo. Your Mac is unchanged.',
      restored: 'The demo’s example settings were restored. Your Mac’s settings haven’t changed.',
      quit: 'Demo closed. Use Restart demo to explore again.',
    },
  },
}
