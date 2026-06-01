import { useState, useEffect } from 'react'
import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { useNavigate } from 'react-router-dom'
import { fetchVaultsByOwner, mistToSui, PACKAGE_ID } from '../lib/sui.js'
import { Card, Btn, Spinner, PageWrap, SectionLabel, StatNum, Tag } from '../components/ui.jsx'

// Fetch VaultCap objects owned by this account
async function fetchVaultCaps(client, ownerAddress) {
  const res = await client.getOwnedObjects({
    owner: ownerAddress,
    filter: { StructType: `${PACKAGE_ID}::attention_market::VaultCap` },
    options: { showContent: true },
  })
  const caps = {}
  for (const obj of res.data) {
    const vaultId = obj.data?.content?.fields?.vault_id
    if (vaultId) caps[vaultId] = obj.data.objectId
  }
  return caps
}

function SlotRow({ slot, index }) {
  const empty = slot.bidder === '0x0000000000000000000000000000000000000000000000000000000000000000'
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: '12px', padding: '10px 14px',
      background: 'var(--bg2)', borderRadius: 'var(--r)',
      borderLeft: `3px solid ${empty ? 'var(--border)' : 'var(--amber)'}`,
    }}>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', width: '20px' }}>#{index + 1}</span>
      <span style={{ flex: 1, fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text2)' }}>
        {empty ? 'open' : `${slot.bidder.slice(0, 10)}… · hash: ${slot.senderEmailHash?.slice(0, 10) ?? '—'}…`}
      </span>
      <span style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '13px', color: empty ? 'var(--text3)' : 'var(--amber)' }}>
        {empty ? '—' : `${mistToSui(slot.amount)} SUI`}
      </span>
      {!empty && slot.paymentId && (
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', color: 'var(--text3)' }}>
          pid: {slot.paymentId.slice(0, 8)}…
        </span>
      )}
    </div>
  )
}

function CloseThreadModal({ vault, capId, onClose, onDone, signAndExecute }) {
  const [paymentIdInput, setPaymentIdInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr]   = useState('')

  async function submit() {
    if (!paymentIdInput.trim()) return
    setBusy(true)
    setErr('')
    try {
      const tx = new Transaction()
      const pidBytes = Array.from(Buffer.from(paymentIdInput.trim(), 'hex'))
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::close_conversation`,
        arguments: [
          tx.object(vault.id),
          tx.object(capId),
          tx.pure.vector('u8', pidBytes),
        ],
      })
      await signAndExecute({ transaction: tx })
      onDone()
    } catch (e) {
      setErr(e.message || 'Transaction failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{
      position: 'fixed', inset: 0, background: '#000000cc',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      zIndex: 200, padding: '24px',
    }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{
        background: 'var(--bg1)', border: '1px solid var(--border)',
        borderRadius: '12px', padding: '28px', width: '100%', maxWidth: '440px',
      }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 700, marginBottom: '8px' }}>
          Close conversation
        </div>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '13px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '20px' }}>
          This permanently invalidates the winner's attention token. The gateway will reject
          all future emails from this thread in both directions. Cannot be undone.
        </p>
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase', display: 'block', marginBottom: '6px' }}>
            Payment ID (hex)
          </label>
          <input
            value={paymentIdInput}
            onChange={e => setPaymentIdInput(e.target.value)}
            placeholder="64-char hex payment_id from slot"
            style={{
              width: '100%', background: 'var(--bg2)', border: '1px solid var(--border2)',
              borderRadius: 'var(--r)', padding: '10px 14px', color: 'var(--text)',
              fontFamily: 'var(--font-mono)', fontSize: '12px', outline: 'none', boxSizing: 'border-box',
            }}
          />
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '6px' }}>
            Copy the payment_id from the slot row above
          </div>
        </div>
        {err && <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', marginBottom: '12px' }}>{err}</div>}
        <div style={{ display: 'flex', gap: '10px' }}>
          <Btn variant="ghost" onClick={onClose} style={{ flex: 1 }}>Cancel</Btn>
          <Btn
            variant="danger"
            onClick={submit}
            disabled={busy || !paymentIdInput.trim()}
            style={{ flex: 1 }}
          >
            {busy ? 'Closing…' : 'Close thread'}
          </Btn>
        </div>
      </div>
    </div>
  )
}

export default function Dashboard() {
  const account = useCurrentAccount()
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction()
  const nav = useNavigate()

  const [vaults,  setVaults]  = useState([])
  const [caps,    setCaps]    = useState({}) // vaultId → capObjectId
  const [loading, setLoading] = useState(true)
  const [busy,    setBusy]    = useState({})
  const [modal,   setModal]   = useState(null) // vaultId to show close modal for

  useEffect(() => {
    if (account) load()
    else setLoading(false)
  }, [account?.address])

  async function load() {
    setLoading(true)
    try {
      const { SuiClient, getFullnodeUrl } = await import('@mysten/sui/client')
      const client = new SuiClient({ url: getFullnodeUrl('testnet') })
      const [vs, cs] = await Promise.all([
        fetchVaultsByOwner(account.address),
        fetchVaultCaps(client, account.address),
      ])
      setVaults(vs)
      setCaps(cs)
    } catch (e) { console.error(e) }
    finally { setLoading(false) }
  }

  async function vaultAction(vaultId, fn) {
    const capId = caps[vaultId]
    if (!capId) return alert('VaultCap not found — are you the owner?')
    setBusy(b => ({ ...b, [vaultId]: fn }))
    try {
      const tx = new Transaction()
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::${fn}`,
        arguments: [tx.object(vaultId), tx.object(capId)],
      })
      await signAndExecute({ transaction: tx })
      setTimeout(load, 2000)
    } catch (e) { console.error(e) }
    finally { setBusy(b => ({ ...b, [vaultId]: null })) }
  }

  if (!account) return (
    <PageWrap>
      <div style={{ textAlign: 'center', padding: '80px 0' }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '20px', marginBottom: '8px' }}>Connect your wallet</div>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>Required to view your seller dashboard</div>
      </div>
    </PageWrap>
  )

  if (loading) return (
    <PageWrap><div style={{ display: 'flex', justifyContent: 'center', padding: '80px' }}><Spinner /></div></PageWrap>
  )

  return (
    <PageWrap>
      {modal && (
        <CloseThreadModal
          vault={vaults.find(v => v.id === modal)}
          capId={caps[modal]}
          onClose={() => setModal(null)}
          onDone={() => { setModal(null); setTimeout(load, 2000) }}
          signAndExecute={signAndExecute}
        />
      )}

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '32px' }}>
        <div>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '24px', fontWeight: 800, marginBottom: '4px' }}>Seller dashboard</div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>{account.address.slice(0, 16)}…</div>
        </div>
        <Btn onClick={() => nav('/register')} variant="outline">+ New vault</Btn>
      </div>

      {vaults.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px 0' }}>
          <div style={{ fontSize: '40px', marginBottom: '16px' }}>📭</div>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 600, marginBottom: '8px' }}>No vaults yet</div>
          <Btn onClick={() => nav('/register')} style={{ marginTop: '8px' }}>List my attention →</Btn>
        </div>
      ) : vaults.map(vault => (
        <Card key={vault.id} style={{ padding: '28px', marginBottom: '20px' }}>

          {/* Header */}
          <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: '20px', flexWrap: 'wrap', gap: '12px' }}>
            <div>
              <div style={{ fontFamily: 'var(--font-display)', fontSize: '20px', fontWeight: 700, marginBottom: '4px' }}>{vault.name}</div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--accent)', marginBottom: '4px' }}>{vault.gatewayEmail}</div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', color: 'var(--text3)', wordBreak: 'break-all' }}>{vault.id}</div>
            </div>
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
              <Tag color={vault.slotsAvailable > 0 ? 'var(--teal)' : 'var(--amber)'}>
                {vault.slotsAvailable > 0 ? `${vault.slotsAvailable} open` : 'Full'}
              </Tag>
              <Tag>Epoch {vault.epoch}</Tag>
              {!caps[vault.id] && <Tag color="var(--red)">No cap found</Tag>}
            </div>
          </div>

          {/* Stats */}
          <div style={{ display: 'flex', gap: '16px', marginBottom: '20px', flexWrap: 'wrap' }}>
            <StatNum value={`${mistToSui(vault.balance)} SUI`} label="Pending" accent="var(--accent)" />
            <StatNum value={`${mistToSui(vault.totalEarned)} SUI`} label="Total earned" />
            <StatNum value={vault.totalBids} label="Total bids" />
            <StatNum value={`${mistToSui(vault.floorBid)} SUI`} label="Floor bid" />
          </div>

          {/* Slots */}
          <div style={{ marginBottom: '20px' }}>
            <SectionLabel>Current slots</SectionLabel>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              {vault.slots.map((slot, i) => <SlotRow key={i} slot={slot} index={i} />)}
            </div>
          </div>

          {/* Actions */}
          <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap', paddingTop: '16px', borderTop: '1px solid var(--border)' }}>
            <Btn
              onClick={() => vaultAction(vault.id, 'withdraw')}
              disabled={vault.balance === 0 || !!busy[vault.id]}
            >
              {busy[vault.id] === 'withdraw' ? 'Withdrawing…' : `Withdraw ${mistToSui(vault.balance)} SUI`}
            </Btn>
            <Btn
              variant="ghost"
              onClick={() => vaultAction(vault.id, 'settle_epoch')}
              disabled={!!busy[vault.id]}
            >
              {busy[vault.id] === 'settle_epoch' ? 'Settling…' : 'Settle epoch'}
            </Btn>
            <Btn
              variant="ghost"
              onClick={() => nav(`/profile/${vault.id}`)}
            >
              View profile
            </Btn>
            <Btn
              variant="danger"
              onClick={() => setModal(vault.id)}
              disabled={!!busy[vault.id]}
            >
              Close a thread
            </Btn>
          </div>

          {/* Gateway reminder */}
          <div style={{
            marginTop: '14px', padding: '12px 16px',
            background: 'var(--bg2)', borderRadius: 'var(--r)',
            fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.8',
          }}>
            <strong style={{ color: 'var(--text2)' }}>Cloudflare Worker secrets:</strong>{' '}
            <code style={{ color: 'var(--accent)' }}>VAULT_ID={vault.id}</code>
            {' · '}
            <code style={{ color: 'var(--accent)' }}>SELLER_GATEWAY_EMAIL={vault.gatewayEmail}</code>
          </div>
        </Card>
      ))}
    </PageWrap>
  )
}
