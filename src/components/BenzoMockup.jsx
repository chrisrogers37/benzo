import {
  pink,
  pinkSoft,
  pinkGlow,
  SLEEP_SESSIONS,
  USB_DEVICES,
  SETTINGS_VERIFICATION,
  SLEEP_TIMER_MINUTES,
  SETTING_OPTIONS,
} from "../demo/fixtures";

// The menubar pill and popover demo. Pure view over demo state; every
// interaction is dispatched to the reducer owned by BenzoHybrid.
const BenzoMockup = ({ state, dispatch }) => {
  const {
    isActive,
    showDropdown,
    showOptions,
    showDiagnostics,
    sleepButtonState,
    settings,
  } = state;

  return (
    <section
      style={{
        maxWidth: 388,
        margin: "0 auto 40px",
        padding: "0 20px",
        position: "relative",
        zIndex: 10,
      }}
    >
      {/* Fake menubar */}
      <div
        style={{
          background: "rgba(255,255,255,0.9)",
          backdropFilter: "blur(20px)",
          borderRadius: "12px 12px 0 0",
          padding: "8px 16px",
          display: "flex",
          justifyContent: "flex-end",
          alignItems: "center",
          gap: 14,
          borderBottom: "1px solid rgba(0,0,0,0.06)",
          boxShadow: "0 -1px 0 rgba(0,0,0,0.03)",
        }}
      >
        <div
          onClick={(e) => {
            if (e.altKey) {
              dispatch({ type: "toggleDiagnostics" });
            } else {
              dispatch({ type: "toggleDropdown" });
            }
          }}
          style={{
            cursor: "pointer",
            padding: "2px 8px",
            borderRadius: 4,
            background: showDropdown
              ? isActive
                ? pinkSoft
                : "rgba(0,0,0,0.04)"
              : "transparent",
            fontSize: 12,
            display: "flex",
            alignItems: "center",
            gap: 6,
            transition: "background 0.3s ease",
          }}
        >
          <span>💊</span>
          <span
            style={{
              width: 6,
              height: 6,
              borderRadius: "50%",
              background: isActive ? pink : "#ccc",
              transition: "all 0.4s ease",
              boxShadow: isActive
                ? `0 0 6px rgba(212,116,156,0.4)`
                : "none",
            }}
          />
        </div>
        <span style={{ fontSize: 11, color: "#c0c0c0" }}>Wi-Fi</span>
        <span style={{ fontSize: 11, color: "#c0c0c0" }}>9:41 AM</span>
      </div>

      {/* Dropdown */}
      {showDropdown && (
        <div
          style={{
            background: "rgba(255,255,255,0.98)",
            backdropFilter: "blur(30px)",
            borderRadius: "0 0 12px 12px",
            border: "1px solid rgba(0,0,0,0.07)",
            borderTop: "none",
            overflow: "hidden",
            boxShadow: isActive
              ? "0 24px 80px rgba(212,116,156,0.08), 0 8px 32px rgba(0,0,0,0.06)"
              : "0 24px 80px rgba(0,0,0,0.06)",
            transition: "box-shadow 0.6s ease",
          }}
        >
          {showDiagnostics ? (
            <>
              {/* Diagnostics Header */}
              <div
                style={{
                  padding: "10px 16px",
                  borderBottom: "1px solid rgba(0,0,0,0.05)",
                  display: "flex",
                  alignItems: "center",
                }}
              >
                <span
                  onClick={() => dispatch({ type: "closeDiagnostics" })}
                  style={{
                    fontSize: 11,
                    fontWeight: 500,
                    color: pink,
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    gap: 3,
                  }}
                >
                  <span style={{ fontSize: 9 }}>&#9664;</span> Back
                </span>
                <span
                  style={{
                    flex: 1,
                    textAlign: "center",
                    fontSize: 13,
                    fontWeight: 600,
                  }}
                >
                  Diagnostics
                </span>
                <span style={{ width: 40 }} />
              </div>

              {/* Recent Sleep Sessions */}
              <div style={{ padding: "10px 16px 6px" }}>
                <div
                  style={{
                    fontSize: 9,
                    fontWeight: 700,
                    color: "#ccc",
                    textTransform: "uppercase",
                    letterSpacing: "0.08em",
                    marginBottom: 6,
                  }}
                >
                  Recent Sleep Sessions
                </div>
                {SLEEP_SESSIONS.map((s, i) => (
                  <div
                    key={i}
                    style={{ marginBottom: 6, lineHeight: 1.5 }}
                  >
                    <div style={{ fontSize: 11, fontWeight: 500 }}>
                      {s.sleep}{" "}
                      <span style={{ color: "#ccc" }}>→</span> {s.wake}
                    </div>
                    <div style={{ fontSize: 10, color: "#bbb" }}>
                      {s.dur} ·{" "}
                      <span
                        style={{
                          fontFamily:
                            "'IBM Plex Mono', 'SF Mono', monospace",
                        }}
                      >
                        {s.bat}
                      </span>{" "}
                      <span
                        style={{
                          color:
                            s.delta === "0%"
                              ? "#4caf50"
                              : "#bbb",
                        }}
                      >
                        ({s.delta})
                      </span>
                    </div>
                  </div>
                ))}
              </div>

              <div
                style={{ borderTop: "1px solid rgba(0,0,0,0.04)" }}
              />

              {/* Last Wake Reason */}
              <div style={{ padding: "10px 16px" }}>
                <div
                  style={{
                    fontSize: 9,
                    fontWeight: 700,
                    color: "#ccc",
                    textTransform: "uppercase",
                    letterSpacing: "0.08em",
                    marginBottom: 6,
                  }}
                >
                  Last Wake Reason
                </div>
                <div
                  style={{
                    fontSize: 12,
                    fontWeight: 500,
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                  }}
                >
                  <span style={{ color: pink }}>⏻</span> Lid Opened
                </div>
              </div>

              <div
                style={{ borderTop: "1px solid rgba(0,0,0,0.04)" }}
              />

              {/* Connected USB Devices */}
              <div style={{ padding: "10px 16px" }}>
                <div
                  style={{
                    fontSize: 9,
                    fontWeight: 700,
                    color: "#ccc",
                    textTransform: "uppercase",
                    letterSpacing: "0.08em",
                    marginBottom: 6,
                  }}
                >
                  Connected USB Devices
                </div>
                {USB_DEVICES.map((d, i) => (
                  <div
                    key={i}
                    style={{
                      display: "flex",
                      justifyContent: "space-between",
                      fontSize: 11,
                      padding: "3px 0",
                    }}
                  >
                    <span style={{ fontWeight: 500 }}>{d.name}</span>
                    <span
                      style={{
                        color: "#bbb",
                        fontFamily:
                          "'IBM Plex Mono', 'SF Mono', monospace",
                        fontSize: 10,
                      }}
                    >
                      {d.power} mA
                    </span>
                  </div>
                ))}
              </div>

              <div
                style={{ borderTop: "1px solid rgba(0,0,0,0.04)" }}
              />

              {/* Settings Verification */}
              <div style={{ padding: "10px 16px 6px" }}>
                <div
                  style={{
                    fontSize: 9,
                    fontWeight: 700,
                    color: "#ccc",
                    textTransform: "uppercase",
                    letterSpacing: "0.08em",
                    marginBottom: 6,
                  }}
                >
                  Settings Verification
                </div>
                {SETTINGS_VERIFICATION.map((s, i) => (
                  <div
                    key={i}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 5,
                      fontSize: 11,
                      padding: "2px 0",
                      fontFamily:
                        "'IBM Plex Mono', 'SF Mono', monospace",
                    }}
                  >
                    <span
                      style={{
                        color: s.ok ? "#4caf50" : "#e53935",
                        fontSize: 10,
                      }}
                    >
                      {s.ok ? "✓" : "✗"}
                    </span>
                    <span style={{ color: "#666" }}>{s.key}</span>
                    <span style={{ flex: 1 }} />
                    <span
                      style={{
                        color: s.ok ? "#bbb" : "#e53935",
                      }}
                    >
                      {s.val}
                    </span>
                    {!s.ok && (
                      <span
                        style={{
                          fontSize: 9,
                          color: "rgba(229,57,53,0.6)",
                        }}
                      >
                        (exp {s.expected})
                      </span>
                    )}
                  </div>
                ))}
                <div
                  style={{
                    textAlign: "center",
                    fontSize: 10,
                    fontWeight: 500,
                    color: "#e53935",
                    marginTop: 6,
                    paddingBottom: 4,
                    fontFamily: "inherit",
                  }}
                >
                  1 setting drifted
                </div>
              </div>
            </>
          ) : (
            <>
              {/* Master Toggle */}
              <div
                style={{
                  padding: "16px 20px",
                  borderBottom: "1px solid rgba(0,0,0,0.05)",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                  }}
                >
                  <div>
                    <div
                      style={{
                        fontSize: 13,
                        fontWeight: 600,
                        marginBottom: 2,
                      }}
                    >
                      {isActive
                        ? "Deep Sleep is On"
                        : "Deep Sleep is Off"}
                    </div>
                    <div style={{ fontSize: 11, color: "#bbb" }}>
                      {isActive
                        ? "Sedated. Your Mac can rest."
                        : "Your Mac is awake."}
                    </div>
                  </div>
                  <div
                    onClick={() => dispatch({ type: "toggleActive" })}
                    style={{
                      width: 44,
                      height: 26,
                      borderRadius: 13,
                      background: isActive ? pink : "#ddd",
                      cursor: "pointer",
                      position: "relative",
                      transition: "all 0.3s ease",
                      boxShadow: isActive ? pinkGlow : "none",
                    }}
                  >
                    <div
                      style={{
                        width: 20,
                        height: 20,
                        borderRadius: "50%",
                        background: "#fff",
                        position: "absolute",
                        top: 3,
                        left: isActive ? 21 : 3,
                        transition: "left 0.2s ease",
                        boxShadow: "0 1px 4px rgba(0,0,0,0.12)",
                      }}
                    />
                  </div>
                </div>
              </div>

              {/* Sleep Now button — split capsule: [Sleep Now | timer] */}
              <div style={{ padding: "0 20px 14px" }}>
                <div
                  style={{
                    width: "100%",
                    borderRadius: 100,
                    background: pink,
                    color: "#fff",
                    fontSize: 12,
                    fontWeight: 600,
                    display: "flex",
                    alignItems: "stretch",
                    overflow: "hidden",
                    boxShadow: `0 2px 12px rgba(212,116,156,0.2)`,
                    transition: "all 0.2s ease",
                  }}
                  onMouseEnter={(e) =>
                    (e.currentTarget.style.boxShadow =
                      "0 4px 20px rgba(212,116,156,0.35)")
                  }
                  onMouseLeave={(e) =>
                    (e.currentTarget.style.boxShadow =
                      "0 2px 12px rgba(212,116,156,0.2)")
                  }
                >
                  {sleepButtonState === "countdown" ? (
                    <div
                      onClick={() => dispatch({ type: "cancelCountdown" })}
                      style={{
                        flex: 1,
                        padding: "10px 0",
                        cursor: "pointer",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        gap: 7,
                      }}
                    >
                      <span style={{ fontSize: 11 }}>💤</span>
                      Sleeping in 4:32
                    </div>
                  ) : (
                    <>
                      <div
                        style={{
                          flex: 1,
                          padding: "10px 0",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          gap: 7,
                          cursor:
                            sleepButtonState === "default"
                              ? "pointer"
                              : "default",
                        }}
                        onClick={() => dispatch({ type: "sleepNow" })}
                      >
                        {sleepButtonState === "picker" ? (
                          <span
                            style={{
                              display: "flex",
                              gap: 8,
                              alignItems: "center",
                            }}
                          >
                            {SLEEP_TIMER_MINUTES.map((m) => (
                              <span
                                key={m}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  dispatch({ type: "startTimer" });
                                }}
                                style={{
                                  fontSize: 11,
                                  fontWeight: 600,
                                  color: pink,
                                  background: "rgba(255,255,255,0.9)",
                                  padding: "4px 10px",
                                  borderRadius: 100,
                                  cursor: "pointer",
                                }}
                              >
                                {m}m
                              </span>
                            ))}
                          </span>
                        ) : (
                          <>
                            <span style={{ fontSize: 11 }}>🌙</span>
                            Sleep Now
                          </>
                        )}
                      </div>
                      <div
                        style={{
                          width: 1,
                          background: "rgba(255,255,255,0.22)",
                          margin: "10px 0",
                        }}
                      />
                      <div
                        onClick={() => dispatch({ type: "toggleTimerPicker" })}
                        style={{
                          width: 38,
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          cursor: "pointer",
                          fontSize: 13,
                        }}
                        title={
                          sleepButtonState === "picker"
                            ? "Close timer"
                            : "Set sleep timer"
                        }
                      >
                        {sleepButtonState === "picker" ? "✕" : "⏱"}
                      </div>
                    </>
                  )}
                </div>
              </div>

              {/* Sleep blocker warning */}
              {isActive && (
                <div
                  style={{
                    padding: "0 20px 10px",
                    textAlign: "center",
                  }}
                >
                  <div
                    style={{
                      fontSize: 11,
                      color: "#999",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: 4,
                    }}
                  >
                    <span style={{ fontSize: 9 }}>⚠</span>
                    1 app may prevent sleep:
                  </div>
                  <div style={{ fontSize: 10, color: "#999" }}>
                    caffeinate
                  </div>
                </div>
              )}

              <div
                style={{ borderTop: "1px solid rgba(0,0,0,0.05)" }}
              />

              {/* Options toggle */}
              {isActive && (
                <div
                  onClick={() => dispatch({ type: "toggleOptions" })}
                  style={{
                    padding: "9px 20px",
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    cursor: "pointer",
                    borderBottom: "1px solid rgba(0,0,0,0.04)",
                  }}
                >
                  <span
                    style={{
                      fontSize: 12,
                      fontWeight: 500,
                      color: "#999",
                    }}
                  >
                    Options
                  </span>
                  <span
                    style={{
                      fontSize: 10,
                      color: "#bbb",
                      transform: showOptions
                        ? "rotate(90deg)"
                        : "rotate(0deg)",
                      transition: "transform 0.2s ease",
                    }}
                  >
                    ▶
                  </span>
                </div>
              )}

              {/* Individual Settings */}
              {isActive && showOptions && (
                <div style={{ padding: "4px 0" }}>
                  {SETTING_OPTIONS.map((item) => (
                    <div
                      key={item.key}
                      onClick={() =>
                        dispatch({ type: "toggleSetting", key: item.key })
                      }
                      style={{
                        padding: "9px 20px",
                        display: "flex",
                        justifyContent: "space-between",
                        alignItems: "center",
                        cursor: "pointer",
                        transition: "background 0.15s",
                      }}
                      onMouseEnter={(e) =>
                        (e.currentTarget.style.background =
                          settings[item.key]
                            ? "rgba(212,116,156,0.03)"
                            : "rgba(0,0,0,0.02)")
                      }
                      onMouseLeave={(e) =>
                        (e.currentTarget.style.background =
                          "transparent")
                      }
                    >
                      <div>
                        <div
                          style={{
                            fontSize: 12.5,
                            fontWeight: 500,
                          }}
                        >
                          {item.label}
                        </div>
                        <div
                          style={{
                            fontSize: 10.5,
                            color: "#c0c0c0",
                            marginTop: 1,
                          }}
                        >
                          {item.desc}
                        </div>
                      </div>
                      <div
                        style={{
                          width: 15,
                          height: 15,
                          borderRadius: 3,
                          border: settings[item.key]
                            ? "none"
                            : "1.5px solid #ddd",
                          background: settings[item.key]
                            ? pink
                            : "transparent",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          fontSize: 9,
                          color: "#fff",
                          transition: "all 0.2s ease",
                          flexShrink: 0,
                          boxShadow: settings[item.key]
                            ? "0 0 8px rgba(212,116,156,0.25)"
                            : "none",
                        }}
                      >
                        {settings[item.key] && "✓"}
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {/* Footer */}
              <div
                style={{
                  padding: "10px 20px",
                  borderTop: "1px solid rgba(0,0,0,0.04)",
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                }}
              >
                <span style={{ fontSize: 10, color: "#d0d0d0" }}>
                  v0.3.0
                </span>
                <div style={{ display: "flex", gap: 14 }}>
                  <span
                    style={{
                      fontSize: 10,
                      color: "#bbb",
                      cursor: "pointer",
                    }}
                  >
                    Restore System Defaults
                  </span>
                  <span
                    style={{
                      fontSize: 10,
                      color: "#bbb",
                      cursor: "pointer",
                    }}
                  >
                    Quit
                  </span>
                </div>
              </div>
            </>
          )}
        </div>
      )}
    </section>
  );
};

export default BenzoMockup;
