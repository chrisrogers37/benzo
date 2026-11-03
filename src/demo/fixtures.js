// Compatibility exports for the original comparison route. New presentation data
// belongs to the design module; only the legacy verification result is frozen.
import { brandColors } from '../design/tokens'
import { exampleReadings, settingOptions } from '../design/appPresentation'
export const { pink, pinkSoft, pinkGlow, pinkBorder } = brandColors
export const SLEEP_SESSIONS = exampleReadings.sleepSessions
export const USB_DEVICES = exampleReadings.usbDevices
// Historical mockup only; the active demo has no sleep timer.
export const SLEEP_TIMER_MINUTES = [5, 15, 30, 60]
export const SETTING_OPTIONS = settingOptions

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
