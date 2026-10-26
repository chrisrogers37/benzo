// @vitest-environment jsdom
import { afterEach, describe, expect, it } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import BenzoHybrid from "../BenzoHybrid";
import { demoReducer, initialDemoState } from "../demo/state";
import { pink } from "../demo/fixtures";

afterEach(cleanup);

// Normalize a CSS value the same way the DOM does for inline styles.
const css = (prop, value) => {
  const el = document.createElement("div");
  el.style[prop] = value;
  return el.style[prop];
};

// The mockup is built from styled divs, so locate controls by the copy a
// visitor sees next to them.
const pill = () =>
  within(screen.getByText("Wi-Fi").parentElement).getByText("💊");
const masterSwitch = () =>
  screen.getByText(/^Deep Sleep is (On|Off)$/).parentElement
    .nextElementSibling;
const hint = () =>
  screen.getByText(/^(⌥-click pill for diagnostics|Viewing diagnostics)$/);
const settingRow = (label) =>
  screen.getByText(label).parentElement.parentElement;
const isChecked = (label) =>
  within(settingRow(label)).queryByText("✓") !== null;

const SETTING_LABELS = {
  "Hibernate Mode": true,
  "Disable Power Nap": true,
  "Disable Proximity Wake": true,
  "Disable Network Wake": true,
  "Disable TCP Keep-Alive": false,
};

const expectMainView = () => {
  expect(screen.getByText(/^Deep Sleep is (On|Off)$/)).toBeTruthy();
  expect(screen.queryByText("Recent Sleep Sessions")).toBeNull();
  expect(hint().textContent).toBe("⌥-click pill for diagnostics");
};

const expectDiagnosticsView = () => {
  expect(screen.getByText("Diagnostics")).toBeTruthy();
  expect(screen.getByText("Recent Sleep Sessions")).toBeTruthy();
  expect(screen.getByText("Lid Opened")).toBeTruthy();
  expect(screen.getByText("CalDigit TS4")).toBeTruthy();
  expect(screen.getByText("1 setting drifted")).toBeTruthy();
  expect(screen.queryByText(/^Deep Sleep is/)).toBeNull();
  expect(hint().textContent).toBe("Viewing diagnostics");
  expect(hint().style.color).toBe(css("color", pink));
};

const expectDropdownClosed = () => {
  expect(screen.queryByText(/^Deep Sleep is/)).toBeNull();
  expect(screen.queryByText("Diagnostics")).toBeNull();
};

describe("demoReducer", () => {
  it("returns new state without mutating the previous state", () => {
    const before = structuredClone(initialDemoState);
    const next = demoReducer(initialDemoState, {
      type: "toggleSetting",
      key: "disableTcpKeepAlive",
    });
    expect(initialDemoState).toEqual(before);
    expect(next.settings.disableTcpKeepAlive).toBe(true);
    expect(next.settings).not.toBe(initialDemoState.settings);
  });


});

describe("landing page demo", () => {
  it("renders the initial active, open, options-expanded state", () => {
    render(<BenzoHybrid />);

    expect(screen.getByText("Deep Sleep is On")).toBeTruthy();
    expect(screen.getByText("Sedated. Your Mac can rest.")).toBeTruthy();
    expect(screen.getByText("Sleep Now")).toBeTruthy();
    expect(screen.getByText("1 app may prevent sleep:")).toBeTruthy();
    expect(screen.getByText("Options")).toBeTruthy();
    for (const [label, checked] of Object.entries(SETTING_LABELS)) {
      expect(isChecked(label)).toBe(checked);
    }
    expectMainView();
    expect(
      screen.getByRole("link", { name: "Download" }).style.color,
    ).toBe(css("color", pink));
  });

  it("toggling Deep Sleep off hides options and recolors the marketing wrapper", () => {
    const { container } = render(<BenzoHybrid />);
    const orb = container.firstChild.firstChild;
    const activeOrb = orb.style.background;

    fireEvent.click(masterSwitch());

    expect(screen.getByText("Deep Sleep is Off")).toBeTruthy();
    expect(screen.getByText("Your Mac is awake.")).toBeTruthy();
    expect(screen.getByText("Sleep Now")).toBeTruthy();
    expect(screen.queryByText("1 app may prevent sleep:")).toBeNull();
    expect(screen.queryByText("Options")).toBeNull();
    expect(screen.queryByText("Hibernate Mode")).toBeNull();

    expect(orb.style.background).toBe(css("background", "none"));
    expect(orb.style.background).not.toBe(activeOrb);
    expect(
      screen.getByRole("link", { name: "Download" }).style.color,
    ).toBe(css("color", "#1a1a1a"));
    expect(
      screen.getByRole("button", { name: "Download Benzo" }).style.background,
    ).toBe(css("background", "#1a1a1a"));

    fireEvent.click(masterSwitch());

    expect(screen.getByText("Deep Sleep is On")).toBeTruthy();
    expect(orb.style.background).toBe(activeOrb);
    expect(
      screen.getByRole("button", { name: "Download Benzo" }).style.background,
    ).toBe(css("background", pink));
  });

  it("setting rows toggle independently and survive a Deep Sleep off/on cycle", () => {
    render(<BenzoHybrid />);

    fireEvent.click(screen.getByText("Disable TCP Keep-Alive"));
    fireEvent.click(screen.getByText("Hibernate Mode"));

    expect(isChecked("Disable TCP Keep-Alive")).toBe(true);
    expect(isChecked("Hibernate Mode")).toBe(false);
    expect(isChecked("Disable Power Nap")).toBe(true);

    fireEvent.click(masterSwitch());
    fireEvent.click(masterSwitch());

    expect(isChecked("Disable TCP Keep-Alive")).toBe(true);
    expect(isChecked("Hibernate Mode")).toBe(false);
  });

  it("the Options row collapses and expands the settings list", () => {
    render(<BenzoHybrid />);

    fireEvent.click(screen.getByText("Options"));
    expect(screen.queryByText("Hibernate Mode")).toBeNull();

    fireEvent.click(screen.getByText("Options"));
    expect(screen.getByText("Hibernate Mode")).toBeTruthy();
  });

  it("a plain pill click closes and reopens the dropdown", () => {
    render(<BenzoHybrid />);

    fireEvent.click(pill());
    expectDropdownClosed();

    fireEvent.click(pill());
    expectMainView();
  });

  describe("diagnostics", () => {
    const openers = {
      "⌥-click on the pill": () => fireEvent.click(pill(), { altKey: true }),
      "the hint below the mockup": () => fireEvent.click(hint()),
    };

    for (const [name, open] of Object.entries(openers)) {
      it(`${name} toggles diagnostics while keeping the dropdown open`, () => {
        render(<BenzoHybrid />);

        open();
        expectDiagnosticsView();

        open();
        expectMainView();
      });

      it(`${name} opens the dropdown straight into diagnostics when closed`, () => {
        render(<BenzoHybrid />);
        fireEvent.click(pill());
        expectDropdownClosed();

        open();
        expectDiagnosticsView();
      });
    }

    it("the hint and ⌥-click share one diagnostics state", () => {
      render(<BenzoHybrid />);

      fireEvent.click(pill(), { altKey: true });
      expectDiagnosticsView();

      fireEvent.click(hint());
      expectMainView();
    });

    it("Back returns to the main view", () => {
      render(<BenzoHybrid />);
      fireEvent.click(hint());

      fireEvent.click(screen.getByText("Back"));
      expectMainView();
    });

    it("a plain pill click from diagnostics closes the dropdown and resets diagnostics", () => {
      render(<BenzoHybrid />);
      fireEvent.click(hint());

      fireEvent.click(pill());
      expectDropdownClosed();
      expect(hint().textContent).toBe("⌥-click pill for diagnostics");

      fireEvent.click(pill());
      expectMainView();
    });
  });

  it("keeps the Gatekeeper tray independent of shared demo state", () => {
    render(<BenzoHybrid />);
    const toggle = screen.getByText('macOS says "unidentified developer"?');
    const tray = toggle.nextElementSibling;
    expect(tray.style.maxHeight).toBe("0px");

    fireEvent.click(toggle);
    expect(tray.style.maxHeight).toBe("200px");
    fireEvent.click(hint());
    expectDiagnosticsView();
    expect(tray.style.maxHeight).toBe("200px");

    fireEvent.click(toggle);
    expect(tray.style.maxHeight).toBe("0px");
    expectDiagnosticsView();
  });

  // P1 verifies the existing mock interaction only. Actual elapsed time and
  // selected-duration behavior are implemented and tested with P5.
  describe("Sleep Now button", () => {
    it("starts and cancels the mock countdown", () => {
      render(<BenzoHybrid />);

      fireEvent.click(screen.getByText("Sleep Now"));
      expect(screen.getByText(/^Sleeping in /)).toBeTruthy();
      expect(screen.queryByTitle("Set sleep timer")).toBeNull();

      fireEvent.click(screen.getByText(/^Sleeping in /));
      expect(screen.getByText("Sleep Now")).toBeTruthy();
    });

    it("the timer picker offers presets that start the countdown", () => {
      render(<BenzoHybrid />);

      fireEvent.click(screen.getByTitle("Set sleep timer"));
      for (const preset of ["5m", "15m", "30m", "60m"]) {
        expect(screen.getByText(preset)).toBeTruthy();
      }
      expect(screen.queryByText("Sleep Now")).toBeNull();

      // Clicking the picker row between presets does nothing
      fireEvent.click(screen.getByText("5m").parentElement);
      expect(screen.getByText("15m")).toBeTruthy();

      fireEvent.click(screen.getByText("30m"));
      expect(screen.getByText(/^Sleeping in /)).toBeTruthy();
      expect(screen.queryByText("30m")).toBeNull();
    });

    it("the timer picker closes back to Sleep Now", () => {
      render(<BenzoHybrid />);

      fireEvent.click(screen.getByTitle("Set sleep timer"));
      fireEvent.click(screen.getByTitle("Close timer"));

      expect(screen.getByText("Sleep Now")).toBeTruthy();
      expect(screen.queryByText("5m")).toBeNull();
    });
  });
});
