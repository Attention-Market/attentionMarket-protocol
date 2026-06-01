import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useCurrentAccount, useSignAndExecuteTransaction, useSignPersonalMessage } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { sha256 } from 'js-sha256'
import { fetchVault, categoryById, mistToSui, suiToMist, PACKAGE_ID, REGISTRY_ID } from '../lib/sui.js'
import { Card, Btn, Input, Tag, Spinner, PageWrap, SectionLabel, StatNum } from '../components/ui.jsx'

// The message the winner signs — must match what the gateway verifies.
// Format: "AttentionMarket:<vaultId>:<paymentId>"
function buildSignMessage(vaultId, paymentId) {
  return `AttentionMarket:${vaultId}:${paymentId}`
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

function CopyBox({ value }) {
  const [copied, setCopied] = useState(false)
  function copy() {
    navigator.clipboard.writeText(value)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: '8px',
      background: 'var(--bg)', border: '1px solid var(--border2)',
      borderRadius: 'var(--r)', padding: '10px 14px',
    }}>
      <span style={{
        fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--accent)',
        flex: 1, wordBreak: 'break-all',
      }}>{value}</span>
      <button
        onClick={copy}
        style={{
          background: copied ? 'var(--teal)22' : 'var(--bg2)',
          border: `1px solid ${copied ? 'var(--teal)' : 'var(--border2)'}`,
          borderRadius: '4px', padding: '4px 10px', cursor: 'pointer',
          fontFamily: 'var(--font-mono)', fontSize: '11px',
          color: copied ? 'var(--teal)' : 'var(--text2)',
          whiteSpace: 'nowrap', transition: 'all 0.15s', flexShrink: 0,
        }}
      >{copied ? 'copied ✓' : 'copy'}</button>
    </div>
  )
}

// Shown after winning — two-step: confirm bid tx, then sign delivery auth
function WonPanel({ vaultId, paymentId, txDigest, sellerName, gatewayEmail }) {
  const { mutateAsync: signPersonalMessage } = useSignPersonalMessage()
  const [sigStep, setSigStep] = useState('ready') // ready | signing | done | error
  const [subjectTag, setSubjectTag] = useState('')
  const [errMsg, setErrMsg] = useState('')

  async function sign() {
    setSigStep('signing')
    setErrMsg('')
    try {
      const message = buildSignMessage(vaultId, paymentId)
      const msgBytes = new TextEncoder().encode(message)
      const { signature } = await signPersonalMessage({ message: msgBytes })
      // signature is base64url — the gateway will verify this
      const tag = `[attn:${signature}]`
      setSubjectTag(tag)
      setSigStep('done')
    } catch (e) {
      setErrMsg(e.message || 'Signing failed')
      setSigStep('error')
    }
  }

  return (
    <div style={{ padding: '4px 0' }}>
      <div style={{ textAlign: 'center', marginBottom: '24px' }}>
        <div style={{ fontSize: '36px', marginBottom: '10px' }}>🎉</div>
        <div style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '18px', color: 'var(--teal)', marginBottom: '6px' }}>
          Slot won!
        </div>
        <a
          href={`https://suiscan.xyz/testnet/tx/${txDigest}`}
          target="_blank" rel="noopener noreferrer"
          style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', borderBottom: '1px solid var(--text3)44' }}
        >View transaction →</a>
      </div>

      {/* Step 2 — sign delivery auth */}
      <div style={{
        background: 'var(--bg2)', border: '1px solid var(--border)', borderRadius: 'var(--r)',
        padding: '20px',
      }}>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: '12px' }}>
          Step 2 — generate your delivery signature
        </div>

        {sigStep === 'done' ? (
          <>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '14px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '16px' }}>
              Add this tag to the <strong style={{ color: 'var(--text)' }}>subject line</strong> of your email to {sellerName}.
              The gateway will verify your wallet signature and deliver your message.
            </p>

            <div style={{ marginBottom: '16px' }}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginBottom: '6px' }}>Subject tag</div>
              <CopyBox value={subjectTag} />
            </div>

            <div style={{
              background: 'var(--bg)', border: '1px solid var(--border)', borderRadius: 'var(--r)',
              padding: '12px 14px', marginBottom: '16px',
            }}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginBottom: '6px' }}>Example subject</div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)' }}>
                Hey {sellerName.split(' ')[0]}, loved your talk on DeFi {subjectTag}
              </div>
            </div>

            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.8',
              borderTop: '1px solid var(--border)', paddingTop: '12px',
            }}>
              ⚠ The tag must appear in the subject line exactly as shown.<br />
              ⚠ Send from the email address you entered when bidding.<br />
              ⚠ This signature is single-use and tied to your wallet.
            </div>
          </>
        ) : (
          <>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '14px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '16px' }}>
              Sign a message with your wallet to prove you own the winning address.
              No gas required — this is just a cryptographic signature.
            </p>

            {/* Gateway email — shown before signing so they know where to send */}
            <div style={{
              background: 'var(--bg)', border: '1px solid var(--border2)',
              borderRadius: 'var(--r)', padding: '14px 16px', marginBottom: '16px',
            }}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginBottom: '6px' }}>
                Send your email to
              </div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '15px', color: 'var(--accent)', fontWeight: 600 }}>
                {gatewayEmail}
              </div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '4px' }}>
                Include the subject tag below to prove your win
              </div>
            </div>
            {sigStep === 'error' && (
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', marginBottom: '12px' }}>
                {errMsg}
              </div>
            )}
            <Btn
              onClick={sign}
              disabled={sigStep === 'signing'}
              style={{ width: '100%', padding: '12px' }}
            >
              {sigStep === 'signing' ? 'Check your wallet…' : 'Sign delivery auth →'}
            </Btn>
          </>
        )}
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
  const [step, setStep]           = useState('idle') // idle | bidding | won | error
  const [txDigest, setTxDigest]   = useState('')
  const [paymentId, setPaymentId] = useState('')
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
      // Hash the email — raw address is never sent to the contract
      const emailHash    = sha256(bidEmail.toLowerCase().trim())
      const emailHashHex = emailHash  // hex string
      // payment_id = sha256(emailHashHex + ":" + vaultId)
      const pid          = sha256(`${emailHashHex}:${vaultId}`)
      const pidBytes     = Array.from(Buffer.from(pid, 'hex'))
      const emailHashBytes = Array.from(Buffer.from(emailHashHex, 'hex'))

      const tx = new Transaction()
      const coin = tx.splitCoins(tx.gas, [suiToMist(bidAmount)])
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::bid`,
        arguments: [
          tx.object(REGISTRY_ID),
          tx.object(vaultId),
          tx.pure.vector('u8', pidBytes),
          tx.pure.vector('u8', emailHashBytes),  // hash, not plaintext
          coin,
        ],
      })

      const res = await signAndExecute({ transaction: tx, options: { showEffects: true } })
      setTxDigest(res.digest)
      setPaymentId(pid)
      setStep('won')
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
      </div>

      {/* Bid / win panel */}
      <Card style={{ padding: '28px' }}>
        <SectionLabel>{step === 'won' ? 'Delivery instructions' : 'Place a bid'}</SectionLabel>

        {step === 'won' ? (
          <WonPanel
            vaultId={vaultId}
            paymentId={paymentId}
            txDigest={txDigest}
            sellerName={vault.name}
            gatewayEmail={vault.gatewayEmail}
          />
        ) : (
          <>
            <p style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', marginBottom: '20px', lineHeight: '1.7' }}>
              Win a slot and {vault.name} will receive your email.
              Minimum bid: <strong style={{ color: 'var(--accent)' }}>{minBid} SUI</strong>.
              {full && ' All slots full — outbid the lowest holder to take their slot.'}
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <Input label="Your email address" value={bidEmail} onChange={setBidEmail} placeholder="you@example.com" type="email" />
              <Input label={`Bid amount (min ${minBid} SUI)`} value={bidAmount} onChange={setBidAmount} placeholder={minBid} mono />
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
              Your email address is never stored on-chain. You will be asked to sign a delivery proof after bidding. Bids are non-refundable unless outbid.
            </p>
          </>
        )}
      </Card>
    </PageWrap>
  )
}
