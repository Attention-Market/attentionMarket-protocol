import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { sha256 } from 'js-sha256'
import { fetchVault, categoryById, mistToSui, suiToMist, PACKAGE_ID, REGISTRY_ID } from '../lib/sui.js'
import { Card, Btn, Input, Tag, Spinner, PageWrap, SectionLabel, StatNum } from '../components/ui.jsx'

function hexToBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  }
  return Array.from(bytes)
}

function SlotRow({ slot, index }) {
  const empty = slot.bidder === '0x0000000000000000000000000000000000000000000000000000000000000000'
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: '12px', padding: '12px 16px',
      background: 'var(--bg2)', borderRadius: 'var(--r)',
      borderLeft: `3px solid ${empty ? 'var(--border2)' : 'var(--amber)'}`,
    }}>
      <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', width: '20px' }}>
        #{index + 1}
      </div>
      <div style={{ flex: 1 }}>
        {empty
          ? <span style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>open slot</span>
          : <span style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)' }}>{slot.bidder.slice(0, 10)}…</span>
        }
      </div>
      <div style={{ fontFamily: 'var(--font-display)', fontSize: '14px', fontWeight: 700, color: empty ? 'var(--text3)' : 'var(--amber)' }}>
        {empty ? '—' : `${mistToSui(slot.amount)} SUI`}
      </div>
      <Tag color={empty ? 'var(--text3)' : 'var(--amber)'}>{empty ? 'open' : 'bid placed'}</Tag>
    </div>
  )
}

function BidSuccessPanel({ txDigest }) {
  const nav = useNavigate()
  return (
    <div style={{ padding: '4px 0', textAlign: 'center' }}>
      <div style={{ fontSize: '36px', marginBottom: '12px' }}>🎯</div>
      <div style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '18px', color: 'var(--teal)', marginBottom: '8px' }}>
        Bid placed!
      </div>
      <p style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', lineHeight: '1.8', marginBottom: '24px', maxWidth: '360px', margin: '0 auto 24px' }}>
        You're in the running. When the seller closes this epoch, a receipt will
        appear in your wallet and on your receipts page — that's when you can
        generate your delivery token.
      </p>
      <a
        href={`https://suiscan.xyz/testnet/tx/${txDigest}`}
        target="_blank" rel="noopener noreferrer"
        style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', borderBottom: '1px solid var(--text3)44', display: 'inline-block', marginBottom: '24px' }}
      >View transaction →</a>
      <div>
        <Btn onClick={() => nav('/receipts')} style={{ width: '100%', padding: '12px' }}>
          Go to my receipts →
        </Btn>
      </div>
    </div>
  )
}

export default function Profile() {
  const { vaultId }  = useParams()
  const nav          = useNavigate()
  const account      = useCurrentAccount()
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction()

  const [vault, setVault]         = useState(null)
  const [loading, setLoading]     = useState(true)
  const [bidEmail, setBidEmail]   = useState('')
  const [bidAmount, setBidAmount] = useState('')
  const [step, setStep]           = useState('idle') // idle | bidding | placed | error
  const [txDigest, setTxDigest]   = useState('')
  const [errMsg, setErrMsg]       = useState('')

  useEffect(() => { load() }, [vaultId])

  async function load() {
    setLoading(true)
    try { setVault(await fetchVault(vaultId)) }
    catch (e) { console.error(e) }
    finally { setLoading(false) }
  }

  async function placeBid() {
    if (!account || !vault || !bidEmail || !bidAmount) return
    setStep('bidding')
    setErrMsg('')
    try {
      const emailHash      = sha256(bidEmail.toLowerCase().trim())
      const pid            = sha256(`${emailHash}:${vaultId}`)
      const pidBytes       = hexToBytes(pid)
      const emailHashBytes = hexToBytes(emailHash)

      const tx   = new Transaction()
      const coin = tx.splitCoins(tx.gas, [suiToMist(bidAmount)])
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::bid`,
        arguments: [
          tx.object(REGISTRY_ID),
          tx.object(vaultId),
          tx.pure.vector('u8', pidBytes),
          tx.pure.vector('u8', emailHashBytes),
          coin,
        ],
      })

      const res = await signAndExecute({ transaction: tx, options: { showEffects: true } })
      setTxDigest(res.digest)
      setStep('placed')
      setTimeout(load, 2000)
    } catch (e) {
      setErrMsg(e.message || 'Transaction failed')
      setStep('error')
    }
  }

  if (loading) return <PageWrap><div style={{ display: 'flex', justifyContent: 'center', padding: '80px' }}><Spinner /></div></PageWrap>
  if (!vault)  return <PageWrap><div style={{ textAlign: 'center', padding: '80px' }}><div style={{ fontFamily: 'var(--font-display)', fontSize: '20px' }}>Vault not found</div></div></PageWrap>

  const cat      = categoryById(vault.category)
  const full     = vault.slotsAvailable === 0
  const minBid   = mistToSui(vault.lowestBid)
  const bidValid = bidEmail.includes('@') && (parseFloat(bidAmount) || 0) >= parseFloat(minBid)

  return (
    <PageWrap maxWidth="800px">
      <button
        onClick={() => nav('/')}
        style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)', background: 'none', border: 'none', cursor: 'pointer', marginBottom: '28px' }}
      >← Back to market</button>

      {/* Profile header */}
      <div style={{ display: 'flex', gap: '20px', alignItems: 'flex-start', marginBottom: '32px' }}>
        <div style={{
          width: '64px', height: '64px', borderRadius: '50%', flexShrink: 0,
          background: `hsl(${vault.name.charCodeAt(0) * 7 % 360}, 40%, 22%)`,
          border: '2px solid var(--border2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '24px',
        }}>
          {vault.name.slice(0, 2).toUpperCase()}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '26px', fontWeight: 800, marginBottom: '6px' }}>{vault.name}</div>
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center', flexWrap: 'wrap' }}>
            <Tag color={full ? 'var(--red)' : 'var(--teal)'}>{full ? 'All slots full' : `${vault.slotsAvailable} of ${vault.slotsPerEpoch} open`}</Tag>
            <Tag>{cat.emoji} {cat.label}</Tag>
            {vault.socialHandle && <Tag color="var(--text2)">@{vault.socialHandle}</Tag>}
          </div>
        </div>
      </div>

      {/* Bio */}
      <Card style={{ padding: '20px', marginBottom: '24px' }}>
        <SectionLabel>About</SectionLabel>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '15px', color: 'var(--text2)', lineHeight: '1.7' }}>{vault.bio}</p>
      </Card>

      {/* Stats */}
      <div style={{ display: 'flex', gap: '12px', marginBottom: '24px', flexWrap: 'wrap' }}>
        {[
          { value: `${mistToSui(vault.floorBid)} SUI`, label: 'Floor bid' },
          { value: `${mistToSui(vault.lowestBid)} SUI`, label: full ? 'Min to outbid' : 'Opening bid', accent: 'var(--accent)' },
          { value: vault.slotsPerEpoch, label: 'Slots / epoch' },
          { value: vault.totalBids, label: 'Total bids' },
        ].map(s => (
          <Card key={s.label} style={{ padding: '16px 20px', flex: 1, minWidth: '120px', textAlign: 'center' }}>
            <StatNum {...s} />
          </Card>
        ))}
      </div>

      {/* Slots */}
      <div style={{ marginBottom: '32px' }}>
        <SectionLabel>Current epoch slots</SectionLabel>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
          {vault.slots.map((slot, i) => <SlotRow key={i} slot={slot} index={i} />)}
        </div>
        {full && (
          <div style={{
            marginTop: '10px', padding: '10px 14px',
            background: 'color-mix(in srgb, var(--amber) 8%, transparent)',
            border: '1px solid color-mix(in srgb, var(--amber) 25%, transparent)',
            borderRadius: 'var(--r)',
            fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.7',
          }}>
            All slots are taken. You can still outbid the lowest holder ({mistToSui(vault.lowestBid)} SUI) — they'll be refunded immediately and you take their slot.
          </div>
        )}
      </div>

      {/* Bid panel */}
      <Card style={{ padding: '28px' }}>
        <SectionLabel>{step === 'placed' ? 'Bid confirmed' : 'Place a bid'}</SectionLabel>

        {step === 'placed' ? (
          <BidSuccessPanel txDigest={txDigest} />
        ) : (
          <>
            <p style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', marginBottom: '20px', lineHeight: '1.7' }}>
              Win a slot and {vault.name} will receive your email.
              Minimum bid: <strong style={{ color: 'var(--accent)' }}>{minBid} SUI</strong>.
              {full && ' All slots full — outbid the lowest holder to take their slot.'}
            </p>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div>
                <Input
                  label="Your email address"
                  value={bidEmail}
                  onChange={setBidEmail}
                  placeholder="you@example.com"
                  type="email"
                />
                <div style={{
                  display: 'flex', alignItems: 'flex-start', gap: '7px',
                  marginTop: '8px', padding: '8px 12px',
                  background: 'color-mix(in srgb, var(--teal) 8%, transparent)',
                  border: '1px solid color-mix(in srgb, var(--teal) 25%, transparent)',
                  borderRadius: 'var(--r)',
                }}>
                  <span style={{ fontSize: '13px', flexShrink: 0, marginTop: '1px' }}>🔒</span>
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.7' }}>
                    Hashed with SHA-256 before submission —{' '}
                    <strong style={{ color: 'var(--teal)' }}>never stored on-chain in plaintext.</strong>
                  </span>
                </div>
              </div>

              <Input
                label={`Bid amount (min ${minBid} SUI)`}
                value={bidAmount}
                onChange={setBidAmount}
                placeholder={minBid}
                mono
              />
            </div>

            {step === 'error' && (
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', marginTop: '14px', wordBreak: 'break-word' }}>{errMsg}</div>
            )}

            <div style={{ marginTop: '20px' }}>
              {!account
                ? <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>Connect your wallet to bid</div>
                : <Btn onClick={placeBid} disabled={!bidValid || step === 'bidding'} style={{ width: '100%', padding: '13px' }}>
                    {step === 'bidding' ? 'Confirm in wallet…' : `Bid ${bidAmount || '—'} SUI →`}
                  </Btn>
              }
            </div>

            <p style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '14px', lineHeight: '1.6' }}>
              Receipts are issued when the seller closes the epoch. If outbid, your SUI is refunded immediately.
            </p>
          </>
        )}
      </Card>
    </PageWrap>
  )
}
