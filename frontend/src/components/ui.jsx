// components/ui.jsx — shared design system components

export function Logo({ size = 'md' }) {
  const sz = size === 'sm' ? '16px' : size === 'lg' ? 'clamp(20px, 7vw, 32px)' : '22px'

  return (
    <span style={{
      fontFamily: 'var(--font-display)',
      fontSize: sz,
      fontWeight: 800,
      letterSpacing: '-0.02em',
      display: 'inline-flex',
      flexWrap: 'wrap',
      justifyContent: 'center',
      lineHeight: 1.1,
    }}>
      <span style={{ color: 'var(--accent)' }}>ATTENTION</span>
      <span style={{ color: 'var(--text)' }}>MARKET</span>
    </span>
  )
}

export function Tag({ children, color = 'var(--text3)', bg }) {
  return (
    <span style={{
      fontFamily: 'var(--font-mono)', fontSize: '11px', letterSpacing: '0.06em',
      textTransform: 'uppercase', padding: '2px 8px', borderRadius: '3px',
      color, background: bg || (color + '22'), border: `1px solid ${color}44`,
      whiteSpace: 'nowrap',
    }}>{children}</span>
  )
}

export function Pill({ label, color }) {
  return <Tag color={color}>{label}</Tag>
}

export function Btn({ children, onClick, variant = 'primary', disabled, style = {} }) {
  const base = {
    border: 'none', borderRadius: 'var(--r)', cursor: disabled ? 'default' : 'pointer',
    fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '14px',
    padding: '10px 20px', transition: 'opacity 0.15s', opacity: disabled ? 0.45 : 1,
    ...style,
  }
  const variants = {
    primary:  { background: 'var(--accent)',  color: 'var(--bg)' },
    ghost:    { background: 'transparent',    color: 'var(--text2)', border: '1px solid var(--border2)' },
    danger:   { background: 'var(--red)',     color: '#fff' },
    outline:  { background: 'transparent',    color: 'var(--accent)', border: '1px solid var(--accent)44' },
  }
  return (
    <button onClick={disabled ? undefined : onClick} style={{ ...base, ...variants[variant] }}>
      {children}
    </button>
  )
}

export function Input({ label, value, onChange, placeholder, type = 'text', mono, style = {} }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
      {label && <label style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>{label}</label>}
      <input
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          background: 'var(--bg2)', border: '1px solid var(--border2)',
          borderRadius: 'var(--r)', padding: '10px 14px', color: 'var(--text)',
          fontFamily: mono ? 'var(--font-mono)' : 'var(--font-body)', fontSize: '14px',
          outline: 'none', width: '100%', ...style,
        }}
      />
    </div>
  )
}

export function Textarea({ label, value, onChange, placeholder, rows = 3 }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
      {label && <label style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase' }}>{label}</label>}
      <textarea
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        rows={rows}
        style={{
          background: 'var(--bg2)', border: '1px solid var(--border2)',
          borderRadius: 'var(--r)', padding: '10px 14px', color: 'var(--text)',
          fontFamily: 'var(--font-body)', fontSize: '14px',
          outline: 'none', width: '100%', resize: 'vertical',
        }}
      />
    </div>
  )
}

export function Card({ children, style = {}, hover }) {
  return (
    <div style={{
      background: 'var(--bg1)', border: '1px solid var(--border)',
      borderRadius: 'var(--r)', ...style,
    }}
    onMouseEnter={hover ? e => { e.currentTarget.style.borderColor = 'var(--border2)' } : undefined}
    onMouseLeave={hover ? e => { e.currentTarget.style.borderColor = 'var(--border)' } : undefined}
    >
      {children}
    </div>
  )
}

export function StatNum({ value, label, accent }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{ fontFamily: 'var(--font-display)', fontSize: '28px', fontWeight: 700, color: accent || 'var(--text)', lineHeight: 1 }}>{value}</div>
      <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '4px', letterSpacing: '0.06em', textTransform: 'uppercase' }}>{label}</div>
    </div>
  )
}

export function Spinner() {
  return (
    <>
      <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
      <div style={{
        width: '18px', height: '18px', border: '2px solid var(--border2)',
        borderTopColor: 'var(--accent)', borderRadius: '50%',
        animation: 'spin 0.7s linear infinite', display: 'inline-block',
      }} />
    </>
  )
}

export function PageWrap({ children, maxWidth = '1100px' }) {
  return (
    <div style={{ maxWidth, margin: '0 auto', padding: '40px 24px 80px' }}>
      {children}
    </div>
  )
}

export function SectionLabel({ children }) {
  return (
    <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '16px' }}>
      {children}
    </div>
  )
}
