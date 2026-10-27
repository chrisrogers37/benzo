// Presentation contract copied from the current Swift source, not execution policy.
// Owners: Views/*.swift, Models/SleepSetting.swift, Theme/BenzoTheme.swift.
// Native claims must change there first, then here. See README.md for parity limits.
export const settingOptions = [
  { key: 'hibernateMode', label: 'Hibernate Mode', desc: 'Full power-off, USB ports disabled', defaultEnabled: true, commands: [['hibernatemode', '25'], ['standby', '0'], ['autopoweroff', '0']] },
  { key: 'disablePowerNap', label: 'Disable Power Nap', desc: 'No background syncing during sleep', defaultEnabled: true, commands: [['powernap', '0']] },
  { key: 'disableProximityWake', label: 'Disable Proximity Wake', desc: "iPhone/Watch won't wake Mac", defaultEnabled: true, commands: [['proximitywake', '0']] },
  { key: 'disableNetworkWake', label: 'Disable Network Wake', desc: 'No Wake-on-LAN from network devices', defaultEnabled: true, commands: [['womp', '0']] },
  { key: 'disableTcpKeepAlive', label: 'Disable TCP Keep-Alive', desc: 'No network wake — disables Find My', defaultEnabled: false, commands: [['tcpkeepalive', '0']] },
]

export const appPresentation = {
  version: 'v0.3.0',
  menu: { name: 'Benzo menu', hint: 'Click to open or close. Option-click when closed for diagnostics.', finder: 'Finder', wifi: 'Wi-Fi', time: '9:41 AM' },
  master: { name: 'Deep Sleep', on: 'Deep Sleep is On', off: 'Deep Sleep is Off', activeDescription: 'Sedated. Your Mac can rest.', inactiveDescription: 'Your Mac is awake.' },
  sleep: { action: 'Sleep Now', sleeping: 'Sleeping...', countdown: 'Sleeping in', openTimer: 'Set sleep timer', closeTimer: 'Close timer', minutes: [5, 15, 30, 60], requestDelayMs: 500 },
  options: 'Options',
  blockers: { singular: '1 app may prevent sleep:', exampleName: 'caffeinate' },
  footer: { login: 'Launch at Login', restore: 'Restore System Defaults', quit: 'Quit', noBackup: 'Nothing to revert — activate Benzo first.' },
  setup: { name: 'Benzo setup', title: 'Welcome to Benzo', description: "Benzo needs one-time permission to modify your Mac's sleep settings.", action: 'Grant Permission', note: ['This creates a system rule so Benzo', 'can adjust sleep settings without', 'repeatedly asking for your password.'] },
  mainName: 'Benzo sleep controls',
  diagnostics: { name: 'Benzo diagnostics', title: 'Diagnostics', back: 'Back', sessions: 'Recent Sleep Sessions', wakeReason: 'Last Wake Reason', usb: 'Connected USB Devices', settings: 'Settings Verification', verified: 'All settings verified', expected: 'expected', missing: 'N/A', drifted: count => `${count} setting${count === 1 ? '' : 's'} drifted` },
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
