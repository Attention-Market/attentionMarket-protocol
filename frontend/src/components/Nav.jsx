import { Link, useLocation } from 'react-router-dom'
import { ConnectButton, useCurrentAccount } from '@mysten/dapp-kit'
import { Logo } from './ui.jsx'
import { useState } from 'react'

export default function Nav() {
  const loc = useLocation()
  const account = useCurrentAccount()
  const [menuOpen, setMenuOpen] = useState(false)

  const links = [
    { to: '/', label: 'Market' },
    { to: '/register', label: 'Sell' },
    ...(account ? [{ to: '/dashboard', label: 'Dashboard' }] : []),
    ...(account ? [{ to: '/receipts', label: 'Receipts' }] : []),
  ]

  const linkStyle = (to) => ({
    fontFamily: 'var(--font-mono)',
    fontSize: '12px',
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: loc.pathname === to ? 'var(--accent)' : 'var(--text2)',
    transition: 'color 0.15s',
    padding: '4px 0',
    borderBottom: loc.pathname === to ? '1px solid var(--accent)' : '1px solid transparent',
  })

  const mobileLinkStyle = (to) => ({
    fontFamily: 'var(--font-mono)',
    fontSize: '13px',
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: loc.pathname === to ? 'var(--accent)' : 'var(--text2)',
    padding: '14px 0',
    borderBottom: '1px solid var(--border)',
    display: 'block',
    transition: 'color 0.15s',
  })

  return (
    <nav style={{
      borderBottom: menuOpen ? 'none' : '1px solid var(--border)',
      background: 'var(--bg)',
      position: 'sticky',
      top: 0,
      zIndex: 100,
    }}>
      <div style={{
        maxWidth: '1100px',
        margin: '0 auto',
        padding: '0 24px',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        height: '56px',
      }}>
    

        {/* Desktop links */}
        <div style={{
          display: 'flex',
          gap: '24px',
          alignItems: 'center',
        }} className="nav-desktop-links">
          {links.map(({ to, label }) => (
            <Link key={to} to={to} style={linkStyle(to)}>{label}</Link>
          ))}
        </div>

        {/* Right side: ConnectButton + hamburger */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <ConnectButton />
          {/* Hamburger — mobile only */}
          <button
            onClick={() => setMenuOpen(o => !o)}
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            style={{
              display: 'none',
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '4px',
              color: 'var(--text2)',
            }}
            className="nav-hamburger"
          >
            {menuOpen
              ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
              : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="3" y1="7" x2="21" y2="7"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="17" x2="21" y2="17"/></svg>
            }
          </button>
        </div>
      </div>

      {/* Mobile dropdown */}
      {menuOpen && (
        <div
          className="nav-mobile-menu"
          style={{
            display: 'none',
            padding: '0 24px 8px',
            background: 'var(--bg)',
            borderBottom: '1px solid var(--border)',
          }}
        >
          {links.map(({ to, label }) => (
            <Link
              key={to}
              to={to}
              style={mobileLinkStyle(to)}
              onClick={() => setMenuOpen(false)}
            >
              {label}
            </Link>
          ))}
        </div>
      )}

      <style>{`
        @media (max-width: 640px) {
          .nav-desktop-links { display: none !important; }
          .nav-hamburger { display: flex !important; }
          .nav-mobile-menu { display: block !important; }
        }
      `}</style>
    </nav>
  )
}