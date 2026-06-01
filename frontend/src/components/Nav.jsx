import { Link, useLocation } from 'react-router-dom'
import { ConnectButton, useCurrentAccount } from '@mysten/dapp-kit'
import { Logo } from './ui.jsx'

export default function Nav() {
  const loc = useLocation()
  const account = useCurrentAccount()

  const link = (to, label) => (
    <Link to={to} style={{
      fontFamily: 'var(--font-mono)', fontSize: '12px', letterSpacing: '0.06em',
      textTransform: 'uppercase', color: loc.pathname === to ? 'var(--accent)' : 'var(--text2)',
      transition: 'color 0.15s', padding: '4px 0',
      borderBottom: loc.pathname === to ? '1px solid var(--accent)' : '1px solid transparent',
    }}>{label}</Link>
  )

  return (
    <nav style={{
      borderBottom: '1px solid var(--border)',
      background: 'var(--bg)',
      position: 'sticky', top: 0, zIndex: 100,
    }}>
      <div style={{
        maxWidth: '1100px', margin: '0 auto', padding: '0 24px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        height: '56px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '32px' }}>
          <Link to="/"><Logo size="sm" /></Link>
          <div style={{ display: 'flex', gap: '24px' }}>
            {link('/', 'Market')}
            {link('/register', 'Sell')}
            {account && link('/dashboard', 'Dashboard')}
          </div>
        </div>
        <ConnectButton />
      </div>
    </nav>
  )
}
