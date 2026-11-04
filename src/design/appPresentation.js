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
  version: 'v0.3.0',
  menu: { name: 'Benzo menu', hint: 'Click to open or close. Option-click when closed for diagnostics.', finder: 'Finder', wifi: 'Wi-Fi', time: '9:41 AM' },
  master: { name: 'Deep Sleep', on: 'Deep Sleep is On', off: 'Deep Sleep is Off', activeDescription: 'Selected settings are applied and verified.', inactiveDescription: 'Selected settings are off. Captured originals are preserved.' },
  sleep: { action: 'Sleep Now', unavailable: 'Sleep Now is unavailable for this manual apply-and-restore workflow.' },
  recovery: {
    titles: { checking: 'Checking Settings', off: 'Settings Are Off', applying: 'Applying Settings', activeVerified: 'Settings Applied', restoring: 'Restoring Settings', recoveryRequired: 'Recovery Required' },
    messages: { checking: 'Reading settings and recovery evidence.', off: 'No unresolved Benzo settings session.', applying: 'Applying your frozen selection and checking each value.', activeVerified: 'Selected settings were read back successfully. Physical sleep behavior is not verified.', restoring: 'Restoring captured pre-Benzo settings and checking each value.', recoveryRequired: 'Recovery requires review. Existing evidence is preserved.' },
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
  footer: { login: 'Launch at Login', restore: 'System Defaults', restoreHelp: 'System Defaults restores captured pre-Benzo settings.', quit: 'Quit', noBackup: 'Nothing to restore — apply a selected setting first.' },
  setup: {
    name: 'Benzo permission status', title: 'Permission status', action: 'Refresh status', back: 'Back',
    observations: {
      noLegacyRule: 'No legacy permission rule found',
      legacyRulePresent: 'Legacy permission rule found; authorization is unverified',
      unknown: 'Permission status could not be determined',
    },
    note: ['This only checks for a legacy rule.', 'It does not verify authorization', 'or change permissions.'],
  },
  mainName: 'Benzo sleep controls',
  diagnostics: {
    name: 'Benzo diagnostics', title: 'Diagnostics', back: 'Back',
    sessions: 'Recent Sleep Sessions', wakeReason: 'Last Wake Reason', usb: 'Connected USB Devices', settings: 'Current Settings',
    loading: 'Loading...', sleepFailure: 'Could not read sleep history', sleepEmpty: 'No sleep sessions reported',
    usbFailure: 'Could not read USB devices', usbEmpty: 'No USB devices reported', settingsFailure: 'Could not read settings',
    missing: 'Not reported', unknown: 'Unknown', summary: 'Reported by pmset. Changes are not verified.',
  },
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
