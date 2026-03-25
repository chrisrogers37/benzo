import { useState } from "react";

const GITHUB_URL = "https://github.com/chrisrogers37/benzo";
const RELEASES_URL = "https://github.com/chrisrogers37/benzo/releases";

const BenzoHybrid = () => {
  const [isActive, setIsActive] = useState(true);
  const [showDropdown, setShowDropdown] = useState(true);
  const [showOptions, setShowOptions] = useState(true);
  const [showDiagnostics, setShowDiagnostics] = useState(false);
  const [showGatekeeper, setShowGatekeeper] = useState(false);
  const [settings, setSettings] = useState({
    hibernateMode: true,
    disablePowerNap: true,
    disableTcpKeepAlive: false,
    disableProximityWake: true,
    disableNetworkWake: true,
  });

  const toggleSetting = (key) => {
    setSettings((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  const activeCount = Object.values(settings).filter(Boolean).length;

  // The pink that creeps in when sedation is active
  const pink = "#d4749c";
  const pinkSoft = "rgba(212,116,156,0.08)";
  const pinkGlow = "0 0 20px rgba(212,116,156,0.2)";
  const pinkBorder = "rgba(212,116,156,0.15)";

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "#f6f5f3",
        fontFamily:
          "'Instrument Sans', 'SF Pro Display', -apple-system, Helvetica, sans-serif",
        color: "#1a1a1a",
        overflowX: "hidden",
        position: "relative",
      }}
    >
      {/* Subtle pink orb that only appears when active */}
      <div
        style={{
          position: "fixed",
          top: "10%",
          right: "-5%",
          width: "45vw",
          height: "45vw",
          borderRadius: "50%",
          background: isActive
            ? "radial-gradient(circle, rgba(212,116,156,0.06) 0%, rgba(212,116,156,0.02) 40%, transparent 70%)"
            : "none",
          pointerEvents: "none",
          transition: "background 1.2s ease",
          filter: "blur(40px)",
        }}
      />
      <div
        style={{
          position: "fixed",
          bottom: "-20%",
          left: "-10%",
          width: "40vw",
          height: "40vw",
          borderRadius: "50%",
          background: isActive
            ? "radial-gradient(circle, rgba(212,116,156,0.04) 0%, transparent 70%)"
            : "none",
          pointerEvents: "none",
          transition: "background 1.2s ease",
          filter: "blur(60px)",
        }}
      />

      {/* Header */}
      <header
        style={{
          padding: "32px 48px",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <div
            style={{
              width: 30,
              height: 30,
              borderRadius: 7,
              background: isActive ? pink : "#1a1a1a",
              transition: "background 0.6s ease, box-shadow 0.6s ease",
              boxShadow: isActive ? pinkGlow : "none",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 14,
            }}
          >
            💊
          </div>
          <span
            style={{
              fontSize: 16,
              fontWeight: 600,
              letterSpacing: "0.08em",
              textTransform: "uppercase",
            }}
          >
            Benzo
          </span>
        </div>
        <div style={{ display: "flex", gap: 16, fontSize: 13, color: "#aaa" }}>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            style={{ cursor: "pointer", color: "inherit", textDecoration: "none" }}
          >
            GitHub
          </a>
          <a
            href={RELEASES_URL}
            target="_blank"
            rel="noopener noreferrer"
            style={{
              cursor: "pointer",
              color: isActive ? pink : "#1a1a1a",
              fontWeight: 500,
              transition: "color 0.4s ease",
              textDecoration: "none",
            }}
          >
            Download
          </a>
        </div>
      </header>

      {/* Hero */}
      <section
        style={{
          padding: "48px 48px 24px",
          maxWidth: 860,
          margin: "0 auto",
          textAlign: "center",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          style={{
            display: "inline-block",
            padding: "6px 18px",
            borderRadius: 100,
            background: isActive ? pinkSoft : "rgba(0,0,0,0.04)",
            border: `1px solid ${isActive ? pinkBorder : "rgba(0,0,0,0.08)"}`,
            fontSize: 12,
            color: isActive ? pink : "#777",
            marginBottom: 28,
            letterSpacing: "0.04em",
            transition: "all 0.6s ease",
            fontWeight: 500,
          }}
        >
          The anti-Amphetamine for macOS
        </div>

        <h1
          style={{
            fontSize: "clamp(32px, 7vw, 68px)",
            fontWeight: 300,
            lineHeight: 1.06,
            letterSpacing: "-0.025em",
            margin: "0 0 22px",
            color: "#1a1a1a",
          }}
        >
          Prescribing{" "}
          <em
            style={{
              fontStyle: "italic",
              color: isActive ? pink : "#1a1a1a",
              transition: "color 0.6s ease",
            }}
          >
            actual
          </em>{" "}
          sleep
          <br />
          for your Mac.
        </h1>

        <p
          style={{
            fontSize: 16,
            lineHeight: 1.7,
            color: "#999",
            maxWidth: 500,
            margin: "0 auto 40px",
            fontWeight: 400,
          }}
        >
          Leave your dock plugged in. When your Mac sleeps, Benzo forces
          true hibernation — no fan, no heat, no wear and tear on your
          battery.
        </p>
      </section>

      {/* Menubar Mockup */}
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
                setShowDiagnostics(!showDiagnostics);
                setShowDropdown(true);
              } else {
                setShowDiagnostics(false);
                setShowDropdown(!showDropdown);
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
                    onClick={() => setShowDiagnostics(false)}
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
                  {[
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
                  ].map((s, i) => (
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
                  {[
                    { name: "CalDigit TS4", power: "500" },
                    { name: "Apple Keyboard", power: "100" },
                  ].map((d, i) => (
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
                  {[
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
                  ].map((s, i) => (
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
                      onClick={() => setIsActive(!isActive)}
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

                {/* Sleep Now button */}
                <div style={{ padding: "0 20px 14px" }}>
                  <button
                    style={{
                      width: "100%",
                      padding: "10px 0",
                      borderRadius: 100,
                      border: "none",
                      background: pink,
                      color: "#fff",
                      fontSize: 12,
                      fontWeight: 600,
                      fontFamily: "inherit",
                      cursor: "pointer",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      gap: 7,
                      boxShadow: `0 2px 12px rgba(212,116,156,0.2)`,
                      transition: "box-shadow 0.2s ease",
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
                    <span style={{ fontSize: 11 }}>🌙</span>
                    Sleep Now
                  </button>
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
                    onClick={() => setShowOptions(!showOptions)}
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
                    {[
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
                    ].map((item) => (
                      <div
                        key={item.key}
                        onClick={() => toggleSetting(item.key)}
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
                    v0.2.1
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

      {/* Diagnostics hint */}
      <div
        style={{
          textAlign: "center",
          margin: "0 auto 16px",
          position: "relative",
          zIndex: 10,
        }}
      >
        <span
          onClick={() => {
            setShowDiagnostics(!showDiagnostics);
            setShowDropdown(true);
          }}
          style={{
            fontSize: 11,
            color: showDiagnostics ? pink : "#ccc",
            cursor: "pointer",
            transition: "color 0.3s ease",
          }}
        >
          {showDiagnostics ? "Viewing diagnostics" : "⌥-click pill for diagnostics"}
        </span>
      </div>

      {/* Scroll affordance */}
      <div
        style={{
          textAlign: "center",
          margin: "0 auto 32px",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          style={{
            display: "inline-block",
            animation: "gentleBounce 2.4s ease-in-out infinite",
            color: "#ccc",
            fontSize: 18,
          }}
        >
          &#8964;
        </div>
        <style>{`
          @keyframes gentleBounce {
            0%, 100% { transform: translateY(0); opacity: 0.4; }
            50% { transform: translateY(6px); opacity: 0.7; }
          }
        `}</style>
      </div>

      {/* Feature Grid */}
      <section
        style={{
          maxWidth: 760,
          margin: "0 auto 48px",
          padding: "0 48px",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))",
            gap: 12,
          }}
        >
          {[
            {
              title: "Actual zero drain",
              body: "hibernatemode 25 writes RAM to disk and fully powers off. USB ports go dark.",
            },
            {
              title: "Dock-friendly",
              body: "CalDigit, Plugable, OWC, Anker — leave it all plugged in. Benzo kills power once your Mac drifts into hibernation.",
            },
            {
              title: "One-click revert",
              body: "Saves your original pmset values before changing anything. Toggle off to restore defaults.",
            },
            {
              title: "No more warm bags",
              body: "Kills Power Nap, TCP keep-alive, proximity wake, and network wake. Your Mac goes cold.",
            },
            {
              title: "Granular control",
              body: "Pick exactly which protections you want. Keep Find My but kill everything else.",
            },
            {
              title: "Free & open source",
              body: "MIT licensed. Built by someone tired of a hot MacBook in his backpack.",
            },
          ].map((card, i) => (
            <div
              key={i}
              style={{
                background: "#fff",
                border: "1px solid rgba(0,0,0,0.05)",
                borderRadius: 10,
                padding: "20px 18px",
                transition: "border-color 0.3s ease, box-shadow 0.3s ease",
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = pinkBorder;
                e.currentTarget.style.boxShadow =
                  "0 4px 20px rgba(212,116,156,0.06)";
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = "rgba(0,0,0,0.05)";
                e.currentTarget.style.boxShadow = "none";
              }}
            >
              <div
                style={{
                  fontSize: 13,
                  fontWeight: 600,
                  marginBottom: 6,
                  letterSpacing: "-0.01em",
                }}
              >
                {card.title}
              </div>
              <div style={{ fontSize: 12, color: "#aaa", lineHeight: 1.55 }}>
                {card.body}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Under the Hood */}
      <section
        style={{
          maxWidth: 540,
          margin: "0 auto 48px",
          padding: "0 48px",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          style={{
            background: "#fff",
            border: "1px solid rgba(0,0,0,0.06)",
            borderRadius: 10,
            padding: 22,
          }}
        >
          <div
            style={{
              fontSize: 10,
              color: "#ccc",
              textTransform: "uppercase",
              letterSpacing: "0.1em",
              marginBottom: 14,
              fontWeight: 600,
            }}
          >
            Under the hood
          </div>
          <pre
            style={{
              fontFamily: "'IBM Plex Mono', 'SF Mono', monospace",
              fontSize: 12,
              lineHeight: 1.75,
              color: isActive ? pink : "#1a1a1a",
              margin: 0,
              overflow: "auto",
              transition: "color 0.6s ease",
            }}
          >
            {`sudo pmset -a hibernatemode 25
sudo pmset -a powernap 0
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0
sudo pmset -a tcpkeepalive 0
sudo pmset -a proximitywake 0`}
          </pre>
          <div
            style={{
              fontSize: 12,
              color: "#c0c0c0",
              marginTop: 16,
              lineHeight: 1.55,
            }}
          >
            That's it. No mystery. Six terminal commands Apple should have
            put in System Settings years ago.
          </div>
        </div>
      </section>

      {/* Compatibility footer */}
      <section
        style={{
          maxWidth: 540,
          margin: "0 auto 48px",
          padding: "0 48px",
          textAlign: "center",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          style={{
            fontSize: 12,
            color: "#ccc",
            lineHeight: 1.8,
          }}
        >
          Intel MacBook Pro/Air (2015-2020) · Apple Silicon (M1-M4)
          <br />
          macOS Catalina and later · Requires admin privileges
        </div>
      </section>

      {/* CTA */}
      <section
        style={{
          maxWidth: 540,
          margin: "0 auto 48px",
          padding: "0 48px",
          textAlign: "center",
          position: "relative",
          zIndex: 10,
        }}
      >
        <a
          href={RELEASES_URL}
          target="_blank"
          rel="noopener noreferrer"
          style={{ textDecoration: "none" }}
        >
          <button
            style={{
              padding: "14px 40px",
              borderRadius: 8,
              border: "none",
              background: isActive ? pink : "#1a1a1a",
              color: "#fff",
              fontSize: 14,
              fontWeight: 600,
              fontFamily: "inherit",
              letterSpacing: "0.04em",
              cursor: "pointer",
              transition: "all 0.4s ease",
              boxShadow: isActive
                ? "0 4px 24px rgba(212,116,156,0.25)"
                : "none",
            }}
          >
            Download Benzo
          </button>
        </a>
        <div style={{ marginTop: 14 }}>
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            style={{
              fontSize: 11,
              color: "#ccc",
              cursor: "pointer",
              textDecoration: "none",
            }}
          >
            View on GitHub →
          </a>
        </div>
      </section>

      {/* Gatekeeper note */}
      <section
        style={{
          maxWidth: 540,
          margin: "0 auto 48px",
          padding: "0 48px",
          textAlign: "center",
          position: "relative",
          zIndex: 10,
        }}
      >
        <div
          onClick={() => setShowGatekeeper(!showGatekeeper)}
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: 6,
            padding: "7px 24px",
            borderRadius: 100,
            background: showGatekeeper
              ? pinkSoft
              : "rgba(212,116,156,0.04)",
            border: `1px solid ${
              showGatekeeper ? pinkBorder : "rgba(212,116,156,0.08)"
            }`,
            cursor: "pointer",
            transition: "all 0.3s ease",
            fontSize: 11,
            color: showGatekeeper ? pink : "rgba(212,116,156,0.5)",
            fontWeight: 500,
            letterSpacing: "0.02em",
          }}
        >
          <span
            style={{
              fontSize: 9,
              transition: "transform 0.3s ease",
              transform: showGatekeeper ? "rotate(90deg)" : "rotate(0deg)",
            }}
          >
            ▶
          </span>
          macOS says "unidentified developer"?
        </div>

        <div
          style={{
            maxHeight: showGatekeeper ? 200 : 0,
            opacity: showGatekeeper ? 1 : 0,
            overflow: "hidden",
            transition: "max-height 0.4s ease, opacity 0.3s ease, margin 0.4s ease",
            marginTop: showGatekeeper ? 16 : 0,
          }}
        >
          <div
            style={{
              background: "#fff",
              border: `1px solid ${pinkBorder}`,
              borderRadius: 10,
              padding: "16px 20px",
              textAlign: "left",
              fontSize: 12,
              color: "#999",
              lineHeight: 1.7,
            }}
          >
            Benzo isn't notarized yet — macOS Gatekeeper will block it.
            To open it, right-click the app and choose{" "}
            <strong style={{ color: "#666" }}>Open</strong>, or run:
            <pre
              style={{
                fontFamily: "'IBM Plex Mono', 'SF Mono', monospace",
                fontSize: 11,
                color: pink,
                background: pinkSoft,
                borderRadius: 6,
                padding: "8px 12px",
                margin: "10px 0 4px",
                overflowX: "auto",
              }}
            >
              xattr -d com.apple.quarantine /Applications/Benzo.app
            </pre>
            <span style={{ fontSize: 11, color: "#bbb" }}>
              This is standard for open-source Mac apps distributed outside the App Store.
            </span>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer
        style={{
          padding: "32px 48px",
          textAlign: "center",
          position: "relative",
          zIndex: 10,
          borderTop: "1px solid rgba(0,0,0,0.04)",
        }}
      >
        <div style={{ fontSize: 11, color: "#ccc", lineHeight: 1.8 }}>
          MIT License ·{" "}
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: "#bbb", textDecoration: "none" }}
          >
            Source on GitHub
          </a>
        </div>
      </footer>
    </div>
  );
};

export default BenzoHybrid;
