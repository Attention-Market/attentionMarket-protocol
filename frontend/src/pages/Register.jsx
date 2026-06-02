import { useState, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { PACKAGE_ID, REGISTRY_ID, CATEGORIES, suiToMist } from '../lib/sui.js'
import { encryptEmail } from '../lib/encrypt.js'
import { Card, Btn, Input, Textarea, PageWrap, SectionLabel } from '../components/ui.jsx'
import { bcs } from '@mysten/sui/bcs'
// Base64 string → Uint8Array (needed to pass encrypted blobs as vector<u8>)
function base64ToBytes(b64) {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
}

export default function Register() {
  const account = useCurrentAccount()
  const nav = useNavigate()

  const [form, setForm] = useState({
    name: '',
    bio: '',
    category: 0,
    socialHandle: '',
    gatewayHandle: '',   // just the part before @attention.email
    realEmail: '',   // never leaves the browser in plaintext
    slotsPerEpoch: '3',
    epochDuration: '1',
    floorBid: '0.01',
  })
  const [step, setStep] = useState('idle')   // idle | encrypting | signing | done | error
  const [errMsg, setErrMsg] = useState('')
  const [txDigest, setTxDigest] = useState('')

  const set = (k) => (v) => setForm(f => ({ ...f, [k]: v }))

  const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction()
  const submitting = useRef(false)

  async function submit() {
    if (!account || submitting.current) return
    submitting.current = true
    setErrMsg('')

    try {
      // ── 1. Encrypt the real email before touching the blockchain ──────────
      setStep('encrypting')
      const { ephemeralPublicKey, iv, ciphertext } = await encryptEmail(form.realEmail)

      // Convert Base64 → raw bytes for vector<u8> Move arguments
      const epkBytes = base64ToBytes(ephemeralPublicKey)
      const ivBytes = base64ToBytes(iv)
      const ctBytes = base64ToBytes(ciphertext)

      // ── 2. Build the transaction ──────────────────────────────────────────
      const floorMist = suiToMist(form.floorBid)
      const slotsPerEpoch = parseInt(form.slotsPerEpoch) || 1
      const epochDuration = parseInt(form.epochDuration) || 1

      const tx = new Transaction()
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::register`,
        arguments: [
          tx.object(REGISTRY_ID),
          tx.pure.string(form.name),
          tx.pure.string(form.bio),
          tx.pure.u8(form.category),
          tx.pure.string(form.socialHandle),
          tx.pure.string(`${form.gatewayHandle}@attention.email`),
          // Encrypted real inbox — three blobs, order matches Move signature
          tx.pure(bcs.vector(bcs.u8()).serialize(epkBytes)),
          tx.pure(bcs.vector(bcs.u8()).serialize(ivBytes)),
          tx.pure(bcs.vector(bcs.u8()).serialize(ctBytes)),
          tx.pure.u64(slotsPerEpoch),
          tx.pure.u64(epochDuration),
          tx.pure.u64(floorMist),
        ],
      })

      // ── 3. Sign & execute ─────────────────────────────────────────────────
      setStep('signing')
      signAndExecuteTransaction(
        { transaction: tx },
        {
          onSuccess: (result) => {
            setTxDigest(result.digest)
            setStep('done')
            submitting.current = false
          },
          onError: (e) => {
            console.error(e)
            setErrMsg(e.message || 'Transaction failed')
            setStep('error')
            submitting.current = false
          },
        },
      )
    } catch (e) {
      // Encryption itself failed (e.g. missing PUBLIC_KEY env var)
      console.error(e)
      setErrMsg(`Encryption failed: ${e.message}`)
      setStep('error')
      submitting.current = false
    }
  }

  const valid =
    form.name.trim() &&
    form.bio.trim() &&
    form.gatewayHandle.trim() &&
    form.realEmail.includes('@') &&
    parseFloat(form.floorBid) >= 0.001

  // ── Done screen ────────────────────────────────────────────────────────────
  if (step === 'done') return (
    <PageWrap maxWidth="600px">
      <div style={{ textAlign: 'center', padding: '40px 0' }}>
        <div style={{ fontSize: '48px', marginBottom: '16px' }}>🎉</div>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '24px', fontWeight: 800, marginBottom: '12px' }}>
          You're live on the market!
        </div>
        <p style={{ fontFamily: 'var(--font-body)', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '24px' }}>
          Your attention vault is deployed.
        </p>
        <div style={{ display: 'flex', gap: '12px', justifyContent: 'center' }}>
          <a
            href={`https://suiscan.xyz/testnet/tx/${txDigest}`}
            target="_blank" rel="noopener noreferrer"
            style={{
              fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--teal)',
              borderBottom: '1px solid var(--teal)44', paddingBottom: '1px',
            }}
          >View transaction →</a>
          <button
            onClick={() => nav('/dashboard')}
            style={{
              background: 'var(--accent)', color: 'var(--bg)', border: 'none',
              borderRadius: 'var(--r)', padding: '8px 20px',
              fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '14px', cursor: 'pointer',
            }}
          >Go to dashboard</button>
        </div>
      </div>
    </PageWrap>
  )

  // ── Main form ──────────────────────────────────────────────────────────────
  return (
    <PageWrap maxWidth="600px">
      <div style={{ marginBottom: '32px' }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '26px', fontWeight: 800, marginBottom: '8px' }}>
          List your attention
        </div>
        <p style={{ fontFamily: 'var(--font-body)', color: 'var(--text2)', lineHeight: '1.7' }}>
          Set your price, define your slots, and let people bid for your inbox.
          Your real email stays hidden — only our private gateway knows it.
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>

        {/* Public profile */}
        <Card style={{ padding: '24px' }}>
          <SectionLabel>Public profile</SectionLabel>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <Input label="Display name" value={form.name} onChange={set('name')} placeholder="Alice Chen" />
            <div>
              <div style={{
                fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)',
                marginBottom: '8px', letterSpacing: '0.05em', textTransform: 'uppercase',
              }}>
                Gateway email — public address senders write to
              </div>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <input
                  value={form.gatewayHandle}
                  onChange={e => set('gatewayHandle')(e.target.value.replace(/[@\s]/g, ''))}
                  placeholder="alice"
                  style={{
                    flex: 1, minWidth: 0,
                    background: 'var(--bg2)', border: '1px solid var(--border2)',
                    borderRight: 'none',
                    borderRadius: 'var(--r) 0 0 var(--r)',
                    padding: '10px 12px',
                    fontFamily: 'var(--font-mono)', fontSize: '13px', color: 'var(--text)',
                    outline: 'none',
                  }}
                />
                <div style={{
                  background: 'var(--bg1)', border: '1px solid var(--border2)',
                  borderRadius: '0 var(--r) var(--r) 0',
                  padding: '10px 12px',
                  fontFamily: 'var(--font-mono)', fontSize: '13px', color: 'var(--text3)',
                  whiteSpace: 'nowrap', userSelect: 'none',
                }}>
                  @attention.email
                </div>
              </div>
              {form.gatewayHandle.trim() && (
                <div style={{
                  marginTop: '6px', fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)',
                }}>
                  → <span style={{ color: 'var(--text2)' }}>{form.gatewayHandle}@attention.email</span>
                </div>
              )}
            </div>
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)',
              lineHeight: '1.7', padding: '10px 14px', background: 'var(--bg2)', borderRadius: 'var(--r)',
            }}>
              Auction winners send to this address — your real inbox is never revealed.
            </div>
            <Textarea
              label="Bio — what kind of attention are you selling?"
              value={form.bio}
              onChange={set('bio')}
              placeholder="I'm a product designer at a Series B startup. I'm open to thoughtful cold outreach about design feedback, tooling partnerships, and genuine introductions. No sales pitches."
              rows={4}
            />
            <Input label="Social handle (optional, for verification)" value={form.socialHandle} onChange={set('socialHandle')} placeholder="alice" />
          </div>
        </Card>

        {/* Real inbox — private */}
        <Card style={{ padding: '24px', border: '1px solid var(--teal)33' }}>
          <SectionLabel>Private inbox</SectionLabel>

          {/* Encryption banner */}
          <div style={{
            display: 'flex', alignItems: 'flex-start', gap: '10px',
            background: 'var(--teal)11', border: '1px solid var(--teal)33',
            borderRadius: 'var(--r)', padding: '12px 14px', marginBottom: '16px',
          }}>
            <span style={{ fontSize: '16px', lineHeight: 1, marginTop: '1px' }}>🔒</span>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--teal)', lineHeight: '1.7' }}>
              <strong>End-to-end encrypted before it leaves your browser.</strong><br />
            </div>
          </div>

          <Input
            label="Your real inbox — where forwarded emails will actually land"
            value={form.realEmail}
            onChange={set('realEmail')}
            placeholder="alice@gmail.com"
            type="email"
          />

          {/* Live status indicator: shows when email looks valid */}
          {form.realEmail.includes('@') && (
            <div style={{
              marginTop: '8px',
              fontFamily: 'var(--font-mono)', fontSize: '11px',
              color: 'var(--teal)', display: 'flex', alignItems: 'center', gap: '6px',
            }}>
              <span style={{
                display: 'inline-block', width: '6px', height: '6px',
                borderRadius: '50%', background: 'var(--teal)',
              }} />
              Will be encrypted on submit — never stored in plaintext
            </div>
          )}
        </Card>

        {/* Category */}
        <Card style={{ padding: '24px' }}>
          <SectionLabel>Category</SectionLabel>
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
            {CATEGORIES.map(c => (
              <button
                key={c.id}
                onClick={() => set('category')(c.id)}
                style={{
                  background: form.category === c.id ? 'var(--accent)' : 'var(--bg2)',
                  color: form.category === c.id ? 'var(--bg)' : 'var(--text2)',
                  border: `1px solid ${form.category === c.id ? 'var(--accent)' : 'var(--border2)'}`,
                  borderRadius: '20px', padding: '6px 16px',
                  fontFamily: 'var(--font-mono)', fontSize: '12px', cursor: 'pointer',
                  transition: 'all 0.15s',
                }}
              >{c.emoji} {c.label}</button>
            ))}
          </div>
        </Card>

        {/* Auction params */}
        <Card style={{ padding: '24px' }}>
          <SectionLabel>Auction settings</SectionLabel>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <Input
              label="Floor bid (SUI) — minimum anyone can bid"
              value={form.floorBid}
              onChange={set('floorBid')}
              placeholder="0.01"
              mono
            />
            <Input
              label="Slots per epoch — inbox slots available per auction period"
              value={form.slotsPerEpoch}
              onChange={set('slotsPerEpoch')}
              placeholder="3"
              mono
            />

            {/* Epoch duration with inline explainer */}
            <div>
              <Input
                label="Epoch duration (number of Sui epochs)"
                value={form.epochDuration}
                onChange={set('epochDuration')}
                placeholder="7"
                mono
              />
              <div style={{
                marginTop: '8px', padding: '10px 12px',
                background: 'color-mix(in srgb, var(--accent) 6%, transparent)',
                border: '1px solid color-mix(in srgb, var(--accent) 20%, transparent)',
                borderRadius: 'var(--r)',
                display: 'flex', flexDirection: 'column', gap: '5px',
              }}>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', lineHeight: '1.7' }}>
                  ⏱ <strong style={{ color: 'var(--text)' }}>1 Sui epoch ≈ 24 hours</strong>, but epochs roll over at a fixed network time —
                  not from the moment you register. If you create a vault with duration&nbsp;1 at 23:00,
                  bidding may close in as little as 1 hour.
                </div>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.7' }}>
                  → Set <strong style={{ color: 'var(--text2)' }}>7</strong> for a guaranteed ~7-day window regardless of when you register.
                  After each epoch ends, you settle it to mint receipts and open the next round.
                </div>
              </div>
            </div>

            {/* Summary */}
            <div style={{
              background: 'var(--bg2)', borderRadius: 'var(--r)', padding: '14px 16px',
              fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', lineHeight: '1.8',
            }}>
              <strong style={{ color: 'var(--text)' }}>Summary:</strong><br />
              {parseInt(form.slotsPerEpoch) || 1} slot{(parseInt(form.slotsPerEpoch) || 1) !== 1 ? 's' : ''} available per epoch (~{parseInt(form.epochDuration) || 1} day{(parseInt(form.epochDuration) || 1) !== 1 ? 's' : ''}).<br />
              Minimum bid: {parseFloat(form.floorBid) || 0} SUI per slot.<br />
              Max revenue per epoch: ~{((parseInt(form.slotsPerEpoch) || 1) * (parseFloat(form.floorBid) || 0)).toFixed(3)} SUI (at floor price).
            </div>
          </div>
        </Card>

        {step === 'error' && (
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', wordBreak: 'break-word' }}>
            {errMsg}
          </div>
        )}

        {!account ? (
          <div style={{
            background: 'var(--bg1)', border: '1px solid var(--border)', borderRadius: 'var(--r)',
            padding: '20px', textAlign: 'center',
            fontFamily: 'var(--font-mono)', fontSize: '13px', color: 'var(--text2)',
          }}>
            Connect your wallet to deploy your vault
          </div>
        ) : (
          <Btn
            onClick={submit}
            disabled={!valid || step === 'encrypting' || step === 'signing'}
            style={{ width: '100%', padding: '14px', fontSize: '16px' }}
          >
            {step === 'encrypting' ? '🔒 Encrypting email…'
              : step === 'signing' ? 'Confirm in wallet…'
                : 'Deploy my attention vault →'}
          </Btn>
        )}

        <p style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', textAlign: 'center', lineHeight: '1.7' }}>
          Your real email is encrypted in-browser before the transaction is built.<br />
          Only your gateway's private key can decrypt it. Gas fee: ~0.01 SUI
        </p>
      </div>
    </PageWrap>
  )
}