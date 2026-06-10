import { useState, useEffect, useRef } from "react";
 
const WORKER_BASE_URL = "https://verify.attention.email"; // ← replace with your worker URL

// ── status pill ───────────────────────────────────────────────────────────────
function StatusPill({ status, onClick }) {
  const map = {
    idle:     { bg: "#F1F5F9", color: "#64748B", dot: "#94A3B8", label: "Check verification" },
    loading:  { bg: "#F1F5F9", color: "#94A3B8", dot: "#CBD5E1", label: "Checking…"          },
    verified: { bg: "#DCFCE7", color: "#15803D", dot: "#22C55E", label: "Verified"            },
    pending:  { bg: "#FEF9C3", color: "#A16207", dot: "#EAB308", label: "Send verification"   },
    unknown:  { bg: "#FEF9C3", color: "#A16207", dot: "#EAB308", label: "Send verification"   },
    sending:  { bg: "#EEF2FF", color: "#4338CA", dot: "#818CF8", label: "Sending…"            },
    sent:     { bg: "#DCFCE7", color: "#15803D", dot: "#22C55E", label: "Email sent"          },
    error:    { bg: "#FEE2E2", color: "#B91C1C", dot: "#EF4444", label: "Try again"           },
    blocked:  { bg: "#FEE2E2", color: "#B91C1C", dot: "#EF4444", label: "Blocked"             },
  };
  const s = map[status] ?? map.idle;

  const isDisabled = status === "loading" || status === "verified"
                  || status === "sending" || status === "sent" || status === "blocked";

  return (
    <button
      onClick={onClick}
      disabled={isDisabled}
      title={
        status === "verified" ? "This address is verified"
      : status === "blocked"  ? "This address has blocked verification emails"
      : status === "sent"     ? "Check your inbox"
      : undefined
      }
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        padding: "4px 10px 4px 8px",
        borderRadius: 999,
        border: "none",
        background: s.bg,
        color: s.color,
        fontSize: 12,
        fontWeight: 600,
        fontFamily: "inherit",
        cursor: isDisabled ? "default" : "pointer",
        transition: "opacity .15s",
        userSelect: "none",
      }}
    >
      <span style={{
        width: 7, height: 7,
        borderRadius: "50%",
        background: s.dot,
        flexShrink: 0,
        ...((status === "loading" || status === "sending") && {
          animation: "ae-pulse 1.2s ease-in-out infinite",
        }),
      }} />
      {s.label}
    </button>
  );
}

// ── main component ────────────────────────────────────────────────────────────
export default function EmailVerificationBadge({ email }) {
  // phase: idle → loading → (verified | unverified | blocked | error)
  //        unverified → sending → (sent | error)
  const [phase, setPhase]       = useState("idle");
  const [errorMsg, setErrorMsg] = useState(null);
  const prevEmailRef            = useRef(email);

  // Reset to idle whenever the email prop changes
  useEffect(() => {
    if (prevEmailRef.current !== email) {
      prevEmailRef.current = email;
      setPhase("idle");
      setErrorMsg(null);
    }
  }, [email]);

  const isValidEmail = (addr) =>
    typeof addr === "string" &&
    /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(addr.trim());

  const handleClick = async () => {
    if (phase === "idle" || phase === "error") {
      if (!isValidEmail(email)) {
        setPhase("error");
        setErrorMsg("Please enter a valid email address.");
        return;
      }
      // Step 1: check status
      setPhase("loading");
      setErrorMsg(null);
      try {
        const res  = await fetch(`${WORKER_BASE_URL}/status?email=${encodeURIComponent(email)}`);
        const data = await res.json();

        if (data.status === "verified") {
          setPhase("verified");
        } else if (data.status === "blocked") {
          setPhase("blocked");
        } else {
          // pending or unknown → ready to send
          setPhase("unknown");
        }
      } catch {
        setPhase("error");
        setErrorMsg("Could not reach verification service.");
      }
      return;
    }

    if (phase === "unknown" || phase === "pending") {
      // Step 2: send verification email
      setPhase("sending");
      setErrorMsg(null);
      try {
        const res  = await fetch(`${WORKER_BASE_URL}/send-verification`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email }),
        });
        const data = await res.json();

        if (res.ok) {
          setPhase("sent");
        } else {
          setPhase("error");
          setErrorMsg(data.error ?? "Something went wrong.");
        }
      } catch {
        setPhase("error");
        setErrorMsg("Could not reach verification service.");
      }
    }
  };

  return (
    <>
      <style>{`
        @keyframes ae-pulse {
          0%, 100% { opacity: 1; }
          50%       { opacity: .3; }
        }
      `}</style>

      <div style={{ display: "inline-flex", flexDirection: "column", gap: 4, alignItems: "flex-start" }}>
        <StatusPill status={phase} onClick={handleClick} />

        <span style={{
          fontSize: 11,
          paddingLeft: 4,
          color: phase === "error" || phase === "blocked" ? "#B91C1C"
               : phase === "verified" || phase === "sent" ? "#15803D"
               : "#94A3B8",
        }}>
          {phase === "idle"     && "Click to check if this email is verified."}
          {phase === "loading"  && "Checking verification status…"}
          {phase === "unknown"  && "Not verified yet — click to send a verification email."}
          {phase === "pending"  && "A verification email was sent. Click to resend."}
          {phase === "sending"  && "Sending verification email…"}
          {phase === "sent"     && "Check your inbox and click the link to verify."}
          {phase === "verified" && "This email address has been verified."}
          {phase === "blocked"  && "This address has blocked verification emails."}
          {phase === "error"    && (errorMsg ?? "Something went wrong.")}
        </span>
      </div>
    </>
  );
}