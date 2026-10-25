import { useReducer, useState } from "react";
import BenzoMockup from "./components/BenzoMockup";
import { demoReducer, initialDemoState } from "./demo/state";
import { pink, pinkSoft, pinkGlow, pinkBorder } from "./demo/fixtures";

const GITHUB_URL = "https://github.com/chrisrogers37/benzo";
const RELEASES_URL = "https://github.com/chrisrogers37/benzo/releases";

const BenzoHybrid = () => {
  const [demo, dispatch] = useReducer(demoReducer, initialDemoState);
  const { isActive, showDiagnostics } = demo;
  const [showGatekeeper, setShowGatekeeper] = useState(false);

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
      <BenzoMockup state={demo} dispatch={dispatch} />

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
          onClick={() => dispatch({ type: "toggleDiagnostics" })}
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
