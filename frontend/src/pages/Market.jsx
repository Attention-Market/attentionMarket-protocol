import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { fetchRegistry, fetchAllVaults, CATEGORIES, mistToSui } from '../lib/sui.js'
import SellerCard from '../components/SellerCard.jsx'
import { Logo, Spinner, Tag, StatNum, PageWrap } from '../components/ui.jsx'

export default function Market() {
  const [vaults, setVaults]     = useState([])
  const [registry, setRegistry] = useState(null)
  const [loading, setLoading]   = useState(true)
  const [category, setCategory] = useState(null)
  const [sort, setSort]         = useState('price_asc')
  const nav = useNavigate()

  useEffect(() => { load() }, [])

  async function load() {
    setLoading(true)
    try {
      const reg = await fetchRegistry()
      setRegistry(reg)
      const all = await fetchAllVaults(reg.vault_ids)
      setVaults(all)
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  const filtered = vaults
    .filter(v => category === null || v.category === category)
    .sort((a, b) => {
      if (sort === 'price_asc')  return a.lowestBid - b.lowestBid
      if (sort === 'price_desc') return b.lowestBid - a.lowestBid
      if (sort === 'slots')      return b.slotsAvailable - a.slotsAvailable
      if (sort === 'bids')       return b.totalBids - a.totalBids
      return 0
    })

  return (
    <div style={{ overflowX: 'hidden' }}>  {/* ← clamp any stray overflow */}

      {/* Hero */}
      <div style={{
        borderBottom: '1px solid var(--border)',
        background: 'radial-gradient(ellipse 80% 60% at 50% -10%, #1a2208 0%, var(--bg) 65%)',
        padding: '48px 16px 40px',   // ← tighter horizontal padding on all sizes
        textAlign: 'center',
        boxSizing: 'border-box',
        width: '100%',
      }}>
        <Logo size="lg" />
        <p style={{
          fontFamily: 'var(--font-body)',
          fontSize: 'clamp(14px, 4vw, 18px)',  // ← scales down on narrow screens
          color: 'var(--text2)',
          maxWidth: '520px',
          margin: '16px auto 0',
          lineHeight: '1.7',
          padding: '0 8px',                    // ← breathing room near edges
        }}>
          Bid for the attention of people who matter to you.
          Winners get their email delivered. Directly.
        </p>
        <div style={{
          display: 'flex',
          justifyContent: 'center',
          gap: 'clamp(16px, 6vw, 32px)',       // ← gap compresses on narrow screens
          marginTop: '40px',
          flexWrap: 'wrap',
          padding: '0 8px',
        }}>
          <StatNum value={registry?.total_sellers ?? '—'} label="Sellers" accent="var(--accent)" />
          <StatNum value={registry?.total_bids ?? '—'}   label="Total bids" />
          <StatNum value={vaults.filter(v => v.slotsAvailable > 0).length || '—'} label="Open now" accent="var(--teal)" />
        </div>
      </div>

      <PageWrap>
        {/* Filters */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          marginBottom: '24px',
          gap: '12px',
          flexWrap: 'wrap',
        }}>
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            <button onClick={() => setCategory(null)} style={filterBtn(category === null)}>All</button>
            {CATEGORIES.map(c => (
              <button key={c.id} onClick={() => setCategory(c.id)} style={filterBtn(category === c.id)}>
                {c.emoji} {c.label}
              </button>
            ))}
          </div>

          <select
            value={sort}
            onChange={e => setSort(e.target.value)}
            style={{
              background: 'var(--bg2)', border: '1px solid var(--border2)',
              borderRadius: 'var(--r)', padding: '8px 12px', color: 'var(--text)',
              fontFamily: 'var(--font-mono)', fontSize: '12px', cursor: 'pointer', outline: 'none',
            }}
          >
            <option value="price_asc">Price: low to high</option>
            <option value="price_desc">Price: high to low</option>
            <option value="slots">Most slots open</option>
            <option value="bids">Most popular</option>
          </select>
        </div>

        {/* Grid */}
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: '80px 0' }}>
            <Spinner />
          </div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '80px 0' }}>
            <div style={{ fontSize: '40px', marginBottom: '16px' }}>📭</div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 600, marginBottom: '8px' }}>
              {vaults.length === 0 ? 'No sellers yet' : 'No results'}
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)', marginBottom: '24px' }}>
              {vaults.length === 0 ? 'Be the first to list your attention' : 'Try a different category or sort'}
            </div>
            {vaults.length === 0 && (
              <button
                onClick={() => nav('/register')}
                style={{
                  background: 'var(--accent)', color: 'var(--bg)', border: 'none',
                  borderRadius: 'var(--r)', padding: '12px 28px',
                  fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '15px', cursor: 'pointer',
                }}
              >List my attention →</button>
            )}
          </div>
        ) : (
          <div style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(min(300px, 100%), 1fr))', // ← key fix: min() prevents overflow
            gap: '16px',
          }}>
            {filtered.map(v => (
              <div key={v.id} onClick={() => nav(`/profile/${v.id}`)} style={{ cursor: 'pointer' }}>
                <SellerCard vault={v} />
              </div>
            ))}
          </div>
        )}

        {/* CTA */}
        {!loading && vaults.length > 0 && (
          <div style={{
            marginTop: '56px', padding: '32px 24px',  // ← horizontal padding reduced
            background: 'var(--bg1)', border: '1px solid var(--border)', borderRadius: 'var(--r)',
            textAlign: 'center',
            boxSizing: 'border-box',
          }}>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 'clamp(16px, 5vw, 20px)', fontWeight: 700, marginBottom: '8px' }}>
              Want people to reach you on your terms?
            </div>
            <p style={{ fontFamily: 'var(--font-body)', color: 'var(--text2)', marginBottom: '20px', fontSize: '14px' }}>
              List your attention. Set your price. Keep your inbox private.
            </p>
            <button
              onClick={() => nav('/register')}
              style={{
                background: 'var(--accent)', color: 'var(--bg)', border: 'none',
                borderRadius: 'var(--r)', padding: '12px 28px',
                fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '15px', cursor: 'pointer',
              }}
            >Sell your attention →</button>
          </div>
        )}
      </PageWrap>
    </div>
  )
}

function filterBtn(active) {
  return {
    background: active ? 'var(--accent)' : 'var(--bg2)',
    color: active ? 'var(--bg)' : 'var(--text2)',
    border: `1px solid ${active ? 'var(--accent)' : 'var(--border2)'}`,
    borderRadius: '20px', padding: '5px 14px',
    fontFamily: 'var(--font-mono)', fontSize: '12px', cursor: 'pointer',
    transition: 'all 0.15s', whiteSpace: 'nowrap',
  }
}