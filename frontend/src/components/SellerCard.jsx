import { useNavigate } from 'react-router-dom'
import { Card, Tag } from './ui.jsx'
import { categoryById, mistToSui } from '../lib/sui.js'

export default function SellerCard({ vault }) {
  const nav  = useNavigate()
  const cat  = categoryById(vault.category)
  const full = vault.slotsAvailable === 0

  return (
    <Card
      hover
      style={{ padding: '24px', cursor: 'pointer', transition: 'border-color 0.15s' }}
      onClick={() => nav(`/profile/${vault.id}`)}
    >
      {/* Header row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '14px' }}>
        {/* Avatar placeholder — initials */}
        <div style={{
          width: '44px', height: '44px', borderRadius: '50%',
          background: `hsl(${vault.name.charCodeAt(0) * 7 % 360}, 40%, 22%)`,
          border: '1px solid var(--border2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '16px', color: 'var(--text)',
        }}>
          {vault.name.slice(0, 2).toUpperCase()}
        </div>
        <Tag color={full ? 'var(--red)' : 'var(--teal)'}>
          {full ? 'Full' : `${vault.slotsAvailable} open`}
        </Tag>
      </div>

      {/* Name + category */}
      <div style={{ fontFamily: 'var(--font-display)', fontSize: '17px', fontWeight: 700, marginBottom: '4px' }}>
        {vault.name}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', marginBottom: '10px' }}>
        <span style={{ fontSize: '13px' }}>{cat.emoji}</span>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', textTransform: 'uppercase', letterSpacing: '0.06em' }}>{cat.label}</span>
        {vault.socialHandle && (
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)' }}>
            · @{vault.socialHandle}
          </span>
        )}
      </div>

      {/* Bio */}
      <p style={{
        fontFamily: 'var(--font-body)', fontSize: '13px', color: 'var(--text2)',
        lineHeight: '1.6', marginBottom: '18px',
        display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
      }}>
        {vault.bio}
      </p>

      {/* Price row */}
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', paddingTop: '14px', borderTop: '1px solid var(--border)' }}>
        <div>
          <span style={{ fontFamily: 'var(--font-display)', fontSize: '22px', fontWeight: 800, color: 'var(--accent)' }}>
            {mistToSui(vault.lowestBid)}
          </span>
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', marginLeft: '5px' }}>SUI</span>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '2px' }}>
            {full ? 'min to outbid' : 'opening bid'}
          </div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)' }}>
            {vault.totalBids} bids total
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)' }}>
            {vault.slotsPerEpoch} slots / epoch
          </div>
        </div>
      </div>
    </Card>
  )
}
