// Static content rendered by the landing-page menubar demo.

// The pink that creeps in when sedation is active
export const pink = "#d4749c";
export const pinkSoft = "rgba(212,116,156,0.08)";
export const pinkGlow = "0 0 20px rgba(212,116,156,0.2)";
export const pinkBorder = "rgba(212,116,156,0.15)";

export const SLEEP_SESSIONS = [
  {
    sleep: "Mar 8, 11:30 PM",
    wake: "7:15 AM",
    dur: "7h 45m",
    bat: "85% → 83%",
    delta: "-2%",
  },
  {
    sleep: "Mar 7, 10:45 PM",
    wake: "6:30 AM",
    dur: "7h 45m",
    bat: "92% → 91%",
    delta: "-1%",
  },
  {
    sleep: "Mar 6, 11:15 PM",
    wake: "7:00 AM",
    dur: "7h 45m",
    bat: "78% → 78%",
    delta: "0%",
  },
];

export const USB_DEVICES = [
  { name: "CalDigit TS4", power: "500" },
  { name: "Apple Keyboard", power: "100" },
];

export const SETTINGS_VERIFICATION = [
  {
    key: "hibernatemode",
    val: "25",
    ok: true,
  },
  { key: "standby", val: "0", ok: true },
  { key: "autopoweroff", val: "0", ok: true },
  { key: "powernap", val: "0", ok: true },
  {
    key: "tcpkeepalive",
    val: "1",
    expected: "0",
    ok: false,
  },
  { key: "proximitywake", val: "0", ok: true },
  { key: "womp", val: "0", ok: true },
];

export const SLEEP_TIMER_MINUTES = [5, 15, 30, 60];

export const SETTING_OPTIONS = [
  {
    key: "hibernateMode",
    label: "Hibernate Mode",
    desc: "Full power-off, USB ports disabled",
  },
  {
    key: "disablePowerNap",
    label: "Disable Power Nap",
    desc: "No background syncing during sleep",
  },
  {
    key: "disableProximityWake",
    label: "Disable Proximity Wake",
    desc: "iPhone/Watch won't wake Mac",
  },
  {
    key: "disableNetworkWake",
    label: "Disable Network Wake",
    desc: "No Wake-on-LAN from network devices",
  },
  {
    key: "disableTcpKeepAlive",
    label: "Disable TCP Keep-Alive",
    desc: "No network wake — disables Find My",
  },
];
