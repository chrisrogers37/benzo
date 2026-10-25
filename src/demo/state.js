// Shared state for the landing-page menubar demo. BenzoHybrid owns it via
// useReducer so marketing chrome (orbs, header, CTA, diagnostics hint) can
// react to the same state the mockup renders.

export const initialDemoState = {
  isActive: true,
  showDropdown: true,
  showOptions: true,
  showDiagnostics: false,
  sleepButtonState: "default", // "default" | "picker" | "countdown"
  settings: {
    hibernateMode: true,
    disablePowerNap: true,
    disableTcpKeepAlive: false,
    disableProximityWake: true,
    disableNetworkWake: true,
  },
};

export function demoReducer(state, action) {
  switch (action.type) {
    case "toggleActive":
      return { ...state, isActive: !state.isActive };
    // Plain click on the menubar pill
    case "toggleDropdown":
      return {
        ...state,
        showDiagnostics: false,
        showDropdown: !state.showDropdown,
      };
    // ⌥-click on the pill, or the diagnostics hint below the mockup
    case "toggleDiagnostics":
      return {
        ...state,
        showDiagnostics: !state.showDiagnostics,
        showDropdown: true,
      };
    case "closeDiagnostics":
      return { ...state, showDiagnostics: false };
    case "toggleOptions":
      return { ...state, showOptions: !state.showOptions };
    case "toggleSetting":
      return {
        ...state,
        settings: {
          ...state.settings,
          [action.key]: !state.settings[action.key],
        },
      };
    case "sleepNow":
      return state.sleepButtonState === "default"
        ? { ...state, sleepButtonState: "countdown" }
        : state;
    case "startTimer":
      return { ...state, sleepButtonState: "countdown" };
    case "cancelCountdown":
      return { ...state, sleepButtonState: "default" };
    case "toggleTimerPicker":
      return {
        ...state,
        sleepButtonState:
          state.sleepButtonState === "picker" ? "default" : "picker",
      };
    default:
      return state;
  }
}
