// Presentation contract copied from the current Swift source, not execution policy.
// Owners: Views/*.swift, Models/SleepSetting.swift, Theme/BenzoTheme.swift.
// Native claims must change there first, then here. See README.md for parity limits.
export const settingOptions = [
  { key: 'hibernateMode', label: 'Hibernate Mode', desc: 'Set hibernation mode 25, standby 0 and autopoweroff 0', defaultEnabled: false, available: false, unavailableReason: 'Unavailable: AC Power does not report hibernatemode, autopoweroff.', commands: [['hibernatemode', '25'], ['standby', '0'], ['autopoweroff', '0']] },
  { key: 'disablePowerNap', label: 'Disable Power Nap', desc: 'Set Power Nap to 0', defaultEnabled: true, available: true, commands: [['powernap', '0']] },
  { key: 'disableProximityWake', label: 'Disable Proximity Wake', desc: 'Set proximity wake to 0', defaultEnabled: false, available: false, unavailableReason: 'Unavailable: AC Power does not report proximitywake.', commands: [['proximitywake', '0']] },
  { key: 'disableNetworkWake', label: 'Disable Network Wake', desc: 'Set Wake-on-LAN to 0', defaultEnabled: true, available: true, commands: [['womp', '0']] },
  { key: 'disableTcpKeepAlive', label: 'Disable TCP Keep-Alive', desc: 'Set TCP keep-alive to 0; may affect Find My', defaultEnabled: false, available: true, commands: [['tcpkeepalive', '0']] },
]

export const appPresentation = {
  version: 'v0.5.0',
  menu: { name: 'Benzo menu', hint: 'Click to open or close. Option-click when closed for diagnostics.', finder: 'Finder', wifi: 'Wi-Fi', time: '9:41 AM' },
  master: { apply: 'Apply selected settings', restore: 'Restore captured settings' },
  sleep: {
    action: 'Sleep Now', timer: 'Sleep timer', cancel: 'Cancel sleep timer',
    requesting: 'Requesting Sleep…', sent: 'Sleep request sent.',
    pending: 'Wait for the sleep request to finish before changing settings.',
    requiresActive: 'Apply your selected settings before requesting sleep.',
    requiresResolved: 'Resolve the current operation or recovery before requesting sleep.',
    requiresReady: 'Power access must be ready before requesting sleep.',
    requiresUpdate: 'Update power access to enable Sleep Now and its timer.',
    cancelled: 'Sleep timer canceled.', interrupted: 'Sleep timer canceled after an interruption.',
    help: 'Send a sleep request using your applied settings', timerHelp: 'Choose a sleep countdown',
  },
  recovery: {
    titles: { checking: 'Checking Settings', off: 'Settings Are Off', applying: 'Applying Settings', activeVerified: 'Settings Applied', restoring: 'Restoring Settings', recoveryRequired: 'Recovery Required' },
    messages: { checking: 'Checking your settings.', off: 'Benzo is off.', applying: 'Applying your selected settings.', activeVerified: 'Your selected settings are applied.', restoring: 'Restoring your previous settings.', recoveryRequired: 'Recovery requires review. Existing evidence is preserved.' },
    evidence: { captured: 'Captured', simulatedProfile: 'AC Power (simulated Mac Mini)', original: 'Recorded original:', current: 'Observed now:', lastVerified: 'Last verified Benzo value:', none: 'none', race: 'Other tools can change settings after this observation.' },
    unsupported: 'This setting is unavailable because the target does not report every required key.',
    emptySelection: 'Select at least one available setting before applying.',
    failed: 'The operation could not be verified. Captured originals and your selection are preserved.',
    refuseWrite: 'A previous request may still be running. Retry can inspect state only; settings writes remain blocked in this boot.',
    uncertainRetry: 'The earlier request may still be running. Retry only checks current values; no new write is allowed in this boot.',
    conflict: 'A setting changed outside this session. Choose how to resolve it or defer; recovery remains required.',
    keptCurrent: 'This conflicting setting was kept by explicit choice. Other Benzo-owned settings still require restoration.',
    remainingOwned: 'The conflicting setting was restored. Other Benzo-owned settings remain; restore them or review recovery before continuing.',
    deferred: 'Recovery remains required until this conflict is resolved.',
    explicitRestore: 'Restoring the recorded original requires explicit confirmation.',
    legacyHelp: 'Legacy or unknown recovery evidence needs administrator-assisted recovery and retirement. Preserve ~/Library/Application Support/Benzo/original-pmset.json and /private/etc/sudoers.d/benzo. This app cannot substantiate their profile ownership or mark them restored.',
    quitPrompt: 'Restore could not be verified. Retry, stay open, or quit anyway while preserving recovery evidence.',
  },
  options: 'Options',
  selectionBlocked: 'Resolve the current session or recovery before changing settings.',
  footer: { login: 'Launch at Login', restore: 'Restore Settings', restoreHelp: 'Restore captured pre-Benzo settings. This does not reset macOS to Apple defaults.', quit: 'Quit', noBackup: 'Nothing to restore — apply a selected setting first.' },
  updates: {
    check: 'Check for Updates…', checking: 'Checking…', release: 'View Release', releases: 'View Releases',
    current: version => `You're on the latest published release (${version}).`,
    available: version => `Benzo ${version} is available.`,
    ahead: 'No newer stable release found.', offline: "Couldn't check for updates. Try again.",
    unavailable: 'Update check unavailable. Try later.', unknownVersion: "Couldn't compare this build. View Releases.",
    compatibility: "Compatibility isn't verified here. Review release requirements.",
    recovery: 'Resolve any recovery before replacing Benzo.',
    demoNotice: "Demo only — this would open Benzo's releases in your browser. No update was downloaded.",
  },
  setup: {
    name: 'Benzo power access setup', entry: 'Manage Power Access', refresh: 'Check Again', back: 'Back', done: 'Done',
    manage: 'Advanced',
    writeBlocked: 'Power access is needed to change settings. Open Power Access to complete setup.',
    recoveryBlocked: 'Settings may still be changed. Power access is needed to restore them. Your recovery record is retained.',
    replacementBlocked: 'Turn Benzo off and resolve any recovery before updating power access. If this copy cannot restore settings, use the previous Benzo release.',
    inProgress: 'Finish power access setup before changing settings or quitting Benzo.',
    remove: 'Remove Power Access', removeTitle: 'Remove Benzo’s power access?', cancel: 'Cancel',
    removalBlocked: 'Turn Benzo off and resolve any recovery before removing power access.',
    removalConfirmation: 'This removes Benzo’s power tool and permission to run it. Setup will be needed to change settings again. Your account and recovery records are retained.',
    states: {
      checking: { title: 'Checking Power Access', message: 'Checking this account’s access to power settings.' },
      notInstalled: { title: 'Set Up Power Access', message: 'One administrator approval lets this Mac account apply and restore Benzo’s supported power settings and request sleep. These actions affect everyone using this Mac.', action: 'Set Up Power Access', event: 'registerHelper' },
      requiresApproval: { title: 'Set Up Power Access', message: 'One administrator approval lets this Mac account apply and restore Benzo’s supported power settings and request sleep. These actions affect everyone using this Mac.', action: 'Set Up Power Access', event: 'registerHelper' },
      needsOwnerAuthorization: { title: 'Set Up Power Access', message: 'One administrator approval lets this Mac account apply and restore Benzo’s supported power settings and request sleep. These actions affect everyone using this Mac.', action: 'Set Up Power Access', event: 'authorizeCurrentAccount' },
      ready: { title: 'Benzo Is Ready', message: 'Power access is set up for this Mac account.', action: 'Repair / Update Power Access', event: 'replaceHelper' },
      differentAccount: { title: 'Benzo Is Set Up for Another Account', message: 'Use the Mac account that completed setup. This account cannot change settings through Benzo.' },
      connectionUnavailable: { title: 'Power Access Is Unavailable', message: 'Benzo couldn’t verify power access. Check again, or repair access after restoring any active settings.', action: 'Repair / Update Power Access', event: 'replaceHelper' },
      incompatible: { title: 'Update Power Access', message: 'The installed power tool needs an update. Restore any active settings before updating power access.', action: 'Repair / Update Power Access', event: 'replaceHelper' },
      signingUnavailable: { title: 'Setup Is Unavailable in This Build', message: 'This copy of Benzo is missing a usable power tool. Install a complete Benzo app, then try setup again.' },
      executionUncertain: { title: 'Power Settings Need Recovery', message: 'An earlier settings change has not finished safely. Your recovery record is preserved. Check recovery before making further changes.' },
    },
  },
  mainName: 'Benzo sleep controls',
  diagnostics: {
    name: 'Benzo diagnostics', title: 'Diagnostics', back: 'Back',
    sessions: 'Recent Sleep Sessions', wakeReason: 'Last Wake Reason', usb: 'Connected USB Devices', settings: 'Current Settings',
    loading: 'Loading...', sleepFailure: 'Could not read sleep history', sleepEmpty: 'No sleep sessions reported',
    usbFailure: 'Could not read USB devices', usbEmpty: 'No USB devices reported', settingsFailure: 'Could not read settings',
    usbErrors: { unsupportedFormat: 'USB reporting is unavailable on this Mac', malformedFormat: 'Could not interpret the USB report', incompleteCapture: 'The USB report was incomplete' },
    usbPowerNote: 'Reported requirements or allocations, not measured power use.',
    missing: 'Not reported', unknown: 'Unknown', summary: 'Current values reported by macOS.',
  },
}

// Mirror ObservedSetting presentation, retaining unknown/missing values verbatim.
export function presentObservedSetting({ key, actualValue }) {
  const names = { hibernatemode: 'Hibernation mode', standby: 'Standby', autopoweroff: 'Automatic power-off', powernap: 'Power Nap', proximitywake: 'Proximity wake', womp: 'Wake for network access', tcpkeepalive: 'TCP keep-alive' }
  let value = actualValue ?? appPresentation.diagnostics.missing
  if (actualValue != null) {
    if (key === 'hibernatemode') value = ({ 0: 'Standard sleep', 3: 'Safe sleep', 25: 'Hibernate' })[actualValue] ?? `Mode ${actualValue}`
    else if (Object.hasOwn(names, key)) value = ({ 0: 'Off', 1: 'On' })[actualValue] ?? actualValue
  }
  return { name: names[key] ?? key, value, rawDetail: actualValue == null ? key : `${key} = ${actualValue}` }
}

export function usbPowerDetail(power) {
  if (!power) return null
  if (power.kind === 'requiredCurrent') return `Current required: ${power.value} mA`
  if (power.kind === 'allocatedPower') return `Power allocated: ${power.value}`
  return null
}

// Active demo fixtures are separate from the frozen historical mockup below.
export const diagnosticReadings = {
  sleep: { sessions: [], lastWakeReason: null },
  usbDevices: [
    { name: 'USB audio interface', power: { kind: 'allocatedPower', value: '2.5 W (500 mA)' } },
    { name: 'USB keyboard', power: { kind: 'requiredCurrent', value: '100' } },
    { name: 'USB hub' },
  ],
}

export const exampleReadings = {
  wakeReason: 'Lid Opened',
  sleepSessions: [
    { sleep: 'Mar 8, 11:30 PM', wake: '7:15 AM', dur: '7h 45m', bat: '85% → 83%', delta: '-2%' },
    { sleep: 'Mar 7, 10:45 PM', wake: '6:30 AM', dur: '7h 45m', bat: '92% → 91%', delta: '-1%' },
    { sleep: 'Mar 6, 11:15 PM', wake: '7:00 AM', dur: '7h 45m', bat: '78% → 78%', delta: '0%' },
  ],
  usbDevices: [{ name: 'CalDigit TS4', power: '500' }, { name: 'Apple Keyboard', power: '100' }],
  values: { hibernatemode: '25', standby: '0', autopoweroff: '0', powernap: '0', proximitywake: '0', womp: '0', tcpkeepalive: '1' },
}
