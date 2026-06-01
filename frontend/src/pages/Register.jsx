import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { PACKAGE_ID, REGISTRY_ID, CATEGORIES, suiToMist } from '../lib/sui.js'
import { Card, Btn, Input, Textarea, PageWrap, SectionLabel } from '../components/ui.jsx'

export default function Register() {
  const account = useCurrentAccount()
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction()
  const nav = useNavigate()

  const [form, setForm] = useState({
    name:           '',
    bio:            '',
    category:       0,
    socialHandle:   '',
    gatewayEmail:   '',
    slotsPerEpoch:  '3',
    epochDuration:  '1',
    floorBid:       '0.01',
  })
  const [step, setStep]     = useState('idle')
  const [errMsg, setErrMsg] = useState('')
  const [txDigest, setTxDigest] = useState('')

  const set = (k) => (v) => setForm(f => ({ ...f, [k]: v }))

  async function submit() {
    if (!account) return
    setStep('signing')
    setErrMsg('')

    try {
      const floorMist     = suiToMist(form.floorBid)
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
          tx.pure.string(form.gatewayEmail),
          tx.pure.u64(slotsPerEpoch),
          tx.pure.u64(epochDuration),
          tx.pure.u64(floorMist),
        ],
      })

      const res = await signAndExecute({ transaction: tx, options: { showEffects: true } })
      setTxDigest(res.digest)
      setStep('done')
    } catch (e) {
      console.error(e)
      setErrMsg(e.message || 'Transaction failed')
      setStep('error')
    }
  }

  const valid = form.name.trim() && form.bio.trim() && form.gatewayEmail.includes('@') && parseFloat(form.floorBid) >= 0.001

  if (step === 'done') return (
    <PageWrap maxWidth="600px">
      <div style={{ textAlign: 'center', padding: '40px 0' }}>
        <div style={{ fontSize: '48px', marginBottom: '16px' }}>🎉</div>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '24px', fontWeight: 800, marginBottom: '12px' }}>
          You're live on the market!
        </div>
        <p style={{ fontFamily: 'var(--font-body)', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '24px' }}>
          Your attention vault is deployed. Now run your gateway so you can receive emails from auction winners.
        </p>
        <Card style={{ padding: '20px', marginBottom: '24px', textAlign: 'left' }}>
          <SectionLabel>Next steps</SectionLabel>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', lineHeight: '2' }}>
            1. Copy your vault ID from the transaction<br />
            2. Set <code style={{ color: 'var(--accent)' }}>RECIPIENT_VAULT_ID</code> in gateway/.env<br />
            3. Run <code style={{ color: 'var(--accent)' }}>npm start</code> in the gateway folder<br />
            4. Point your domain MX at your gateway server
          </div>
        </Card>
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

  return (
    <PageWrap maxWidth="600px">
      <div style={{ marginBottom: '32px' }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '26px', fontWeight: 800, marginBottom: '8px' }}>
          List your attention
        </div>
        <p style={{ fontFamily: 'var(--font-body)', color: 'var(--text2)', lineHeight: '1.7' }}>
          Set your price, define your slots, and let people bid for your inbox.
          Your real email stays private — only your gateway knows it.
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>

        {/* Public profile */}
        <Card style={{ padding: '24px' }}>
          <SectionLabel>Public profile</SectionLabel>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <Input label="Display name" value={form.name} onChange={set('name')} placeholder="Alice Chen" />
            <Input
              label="Gateway email — public address senders write to"
              value={form.gatewayEmail}
              onChange={set('gatewayEmail')}
              placeholder="alice@attentionmarket.xyz"
              type="email"
            />
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)',
              lineHeight: '1.7', padding: '10px 14px', background: 'var(--bg2)', borderRadius: 'var(--r)',
            }}>
              This is shown to auction winners so they know where to send their email.
              Point your domain's MX record at your gateway server, then use that address here.
              Your real inbox is never revealed.
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
            <Input
              label="Epoch duration (Sui epochs, 1 ≈ 24h)"
              value={form.epochDuration}
              onChange={set('epochDuration')}
              placeholder="1"
              mono
            />
            <div style={{
              background: 'var(--bg2)', borderRadius: 'var(--r)', padding: '14px 16px',
              fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)', lineHeight: '1.8',
            }}>
              <strong style={{ color: 'var(--text)' }}>Summary:</strong><br />
              {parseInt(form.slotsPerEpoch) || 1} senders can bid per ~{parseInt(form.epochDuration) || 1} day period.<br />
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
            disabled={!valid || step === 'signing'}
            style={{ width: '100%', padding: '14px', fontSize: '16px' }}
          >
            {step === 'signing' ? 'Confirm in wallet…' : 'Deploy my attention vault →'}
          </Btn>
        )}

        <p style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', textAlign: 'center', lineHeight: '1.7' }}>
          Deploying creates a shared on-chain object. Your email address is never stored on-chain.<br />
          Gas fee: ~0.01 SUI
        </p>
      </div>
    </PageWrap>
  )
}
