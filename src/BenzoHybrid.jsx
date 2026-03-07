import { useState } from "react";

const GITHUB_URL = "https://github.com/chrisrogers37/benzo";
const RELEASES_URL = "https://github.com/chrisrogers37/benzo/releases";

const BenzoHybrid = () => {
  const [isActive, setIsActive] = useState(true);
  const [showDropdown, setShowDropdown] = useState(true);
  const [settings, setSettings] = useState({
    hibernateMode: true,
    disablePowerNap: true,
    disableTcpKeepAlive: false,
    disableProximityWake: true,
    disableUsbWake: true,
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
        overflow: "hidden",
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
        <div style={{ display: "flex", gap: 24, fontSize: 13, color: "#aaa" }}>
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
          padding: "72px 48px 36px",
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
            fontSize: "clamp(40px, 5.5vw, 68px)",
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
            margin: "0 auto 52px",
            fontWeight: 400,
          }}
        >
          Close the lid with your dock plugged in. No fan. No battery drain.
          No warm laptop in your bag. Benzo forces true hibernation — even
          with USB devices connected.
        </p>
      </section>

      {/* Menubar Mockup */}
      <section
        style={{
          maxWidth: 388,
          margin: "0 auto 72px",
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
          <span style={{ fontSize: 11, color: "#c0c0c0" }}>Wi-Fi</span>
          <span style={{ fontSize: 11, color: "#c0c0c0" }}>9:41 AM</span>
          <div
            onClick={() => setShowDropdown(!showDropdown)}
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
                    style={{ fontSize: 13, fontWeight: 600, marginBottom: 2 }}
                  >
                    Deep Sleep Mode
                  </div>
                  <div style={{ fontSize: 11, color: "#bbb" }}>
                    {isActive
                      ? `${activeCount} protection${activeCount !== 1 ? "s" : ""} active`
                      : "USB ports will drain battery"}
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

            {/* Individual Settings */}
            {isActive && (
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
                    key: "disableTcpKeepAlive",
                    label: "Disable TCP Keep-Alive",
                    desc: "No network wake — disables Find My",
                  },
                  {
                    key: "disableProximityWake",
                    label: "Disable Proximity Wake",
                    desc: "iPhone/Watch won't wake Mac",
                  },
                  {
                    key: "disableUsbWake",
                    label: "Disable USB Wake",
                    desc: "Only power button wakes Mac",
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
                      (e.currentTarget.style.background = settings[item.key]
                        ? "rgba(212,116,156,0.03)"
                        : "rgba(0,0,0,0.02)")
                    }
                    onMouseLeave={(e) =>
                      (e.currentTarget.style.background = "transparent")
                    }
                  >
                    <div>
                      <div style={{ fontSize: 12.5, fontWeight: 500 }}>
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
                        background: settings[item.key] ? pink : "transparent",
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
              <span style={{ fontSize: 10, color: "#d0d0d0" }}>v0.1.0</span>
              <div style={{ display: "flex", gap: 14 }}>
                <span
                  style={{
                    fontSize: 10,
                    color: "#bbb",
                    cursor: "pointer",
                  }}
                >
                  Revert to Defaults
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
          </div>
        )}
      </section>

      {/* Feature Grid */}
      <section
        style={{
          maxWidth: 760,
          margin: "0 auto 72px",
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
              body: "CalDigit, OWC, Anker — leave it all plugged in. Benzo cuts power when the lid closes.",
            },
            {
              title: "One-click revert",
              body: "Saves your original pmset values before changing anything. Toggle off to restore defaults.",
            },
            {
              title: "No more warm bags",
              body: "Kills Power Nap, TCP keep-alive, proximity wake, and USB wake. Your Mac goes cold.",
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
          margin: "0 auto 72px",
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
          margin: "0 auto 72px",
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
