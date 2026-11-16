# Diagnostics layout and USB readback

Diagnostics uses full-width, leading-aligned sections with a 16-point content
inset, readable system headings and wrapping rows. Current Settings shows readable
names/values alongside raw keys/values. An absent value remains **Not reported**;
unknown numeric values remain visible. “Current values reported by macOS.”
describes readback only, not proof of physical sleep or USB power loss.

USB reads first query `system_profiler -listDataTypes` (10 seconds, 64 KiB).
An advertised `SPUSBHostDataType` is preferred; otherwise an advertised
`SPUSBDataType` selects the legacy reader. Both JSON reads retain the existing
30-second/16-MiB limits. No advertised supported type means unavailable, even
though an unsupported profiler request can return exit zero and an empty array.
The selected report must match the returned format. A failed selected read does
not fall back to another format and mask the failure.

Legacy identity and `bus_power_used` fields describe current requirements.
Host-format vendor/product IDs distinguish devices and hubs from root bus
controllers. `USBKeyHardwareType` alone does not identify a bus: built-in hubs
are devices too. `USBDeviceKeyPowerAllocation` includes its own units and is shown
as **Power allocated**, never measured current draw. Missing power fields are
omitted. Reports and synthetic fixtures retain no serial-number fields.

Injected regressions cover discovery selection, both recursive formats, supported
empty versus unsupported, malformed and partial captures, missing identities,
power semantics and observed-setting presentation. The active web demo mirrors
these states and refreshes simulated settings on Diagnostics entry; historical
unbundled mockups remain unchanged. Its empty sleep history and illustrative USB
rows are simulated examples, not observations of the visitor’s Mac.

## Acceptance still requiring the installed native app

- Compare native empty/loading/failure/populated sections at the 320-point width,
  including many USB devices, long names and the bottom of Current Settings.
- Check Tab/Shift-Tab, arrows, Page Up/Down, Back/Escape, short-screen scrolling and
  VoiceOver headings/rows without losing the existing focus indication.
- Investigate the blue strip below the header in the November 16 native screenshot.
  A clipped native scroll focus ring is a hypothesis, not a confirmed diagnosis.
  This change leaves scroll focusability and keyboard handlers intact.
- Check native USB enumeration on the owner’s hardware after a separately
  authorized install. Physical sleep/wake and USB power behavior remain a separate
  acceptance task; no such result follows from these read-only diagnostics.

This work does not install, launch, quit or replace the native app, change power
access/settings, add a sleep-prevention list, or publish a native release.
