import { useState, useEffect } from 'react'
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { useNavigate } from 'react-router-dom'
import { fetchVaultsByOwner, mistToSui, PACKAGE_ID, REGISTRY_ID } from '../lib/sui.js'
import { Card, Btn, Spinner, PageWrap, SectionLabel, StatNum, Tag } from '../components/ui.jsx'

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

function CloseVaultModal({ vault, capId, onClose, onDone, signAndExecute }) {
  const [busy, setBusy] = useState(false)
  const [err, setErr]   = useState('')

  // Count active (non-empty) slots so we can warn the user about refunds
  const ZERO_ADDR = '0x0000000000000000000000000000000000000000000000000000000000000000'
  const activeSlots = vault.slots.filter(s => s.bidder !== ZERO_ADDR)

  async function submit() {
    setBusy(true)
    setErr('')
    try {
      const tx = new Transaction()
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::close_vault`,
        arguments: [
          tx.object(REGISTRY_ID),
          tx.object(vault.id),
          tx.object(capId),
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
        borderRadius: '12px', padding: '28px', width: '100%', maxWidth: '480px',
      }}>
        {/* Header */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
          <span style={{ fontSize: '20px' }}>⚠️</span>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 700 }}>
            Delete vault permanently
          </div>
        </div>

        {/* Warning copy */}
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '13px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '16px' }}>
          This will <strong>permanently destroy</strong> <em>{vault.name}</em> and cannot be undone.
          The VaultCap will be burned, the gateway email handle released, and all data deleted from chain.
        </p>

        {/* What will happen checklist */}
        <div style={{
          background: 'var(--bg2)', border: '1px solid var(--border)',
          borderRadius: 'var(--r)', padding: '14px 16px', marginBottom: '20px',
          display: 'flex', flexDirection: 'column', gap: '8px',
        }}>
          <CheckItem ok={activeSlots.length > 0}>
            {activeSlots.length > 0
              ? `${activeSlots.length} active bidder${activeSlots.length > 1 ? 's' : ''} will be refunded automatically`
              : 'No active bids to refund'}
          </CheckItem>
          <CheckItem ok={vault.balance > 0}>
            {vault.balance > 0
              ? `${mistToSui(vault.balance)} SUI pending balance will be returned to you`
              : 'No pending balance to return'}
          </CheckItem>
          <CheckItem warn>
            All closed threads must be settled first — transaction will fail otherwise
          </CheckItem>
          <CheckItem warn>
            Gateway email <strong>{vault.gatewayEmail}</strong> will be freed
          </CheckItem>
        </div>

        {err && (
          <div style={{
            fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)',
            background: 'color-mix(in srgb, var(--red) 10%, transparent)',
            border: '1px solid color-mix(in srgb, var(--red) 30%, transparent)',
            borderRadius: 'var(--r)', padding: '10px 12px', marginBottom: '16px',
          }}>
            {err}
          </div>
        )}

        <div style={{ display: 'flex', gap: '10px' }}>
          <Btn variant="ghost" onClick={onClose} style={{ flex: 1 }} disabled={busy}>
            Cancel
          </Btn>
          <Btn
            variant="danger"
            onClick={submit}
            disabled={busy}
            style={{ flex: 1 }}
          >
            {busy ? 'Deleting vault…' : 'Delete vault'}
          </Btn>
        </div>
      </div>
    </div>
  )
}

/** Small helper row inside the close-vault checklist */
function CheckItem({ ok, warn, children }) {
  const icon = warn ? '⚠' : ok ? '↩' : '✓'
  const color = warn ? 'var(--amber)' : ok ? 'var(--teal)' : 'var(--text3)'
  return (
    <div style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color, marginTop: '1px', flexShrink: 0 }}>{icon}</span>
      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', lineHeight: '1.6' }}>{children}</span>
    </div>
  )
}

export default function Dashboard() {
  const account = useCurrentAccount()
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction()
  const suiClient = useSuiClient()
  const nav = useNavigate()

  const [vaults,  setVaults]  = useState([])
  const [caps,    setCaps]    = useState({}) // vaultId → capObjectId
  const [loading, setLoading] = useState(true)
  const [busy,    setBusy]    = useState({})
  const [modal,   setModal]   = useState(null)       // { type: 'thread'|'vault', vaultId }

  async function fetchVaultCaps(ownerAddress) {
    const res = await suiClient.getOwnedObjects({
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

  useEffect(() => {
    if (account) load()
    else setLoading(false)
  }, [account?.address])

  async function load() {
    setLoading(true)
    try {
      const [vs, cs] = await Promise.all([
        fetchVaultsByOwner(account.address),
        fetchVaultCaps(account.address),
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

  const closeModal = () => setModal(null)

  const modalVault  = modal ? vaults.find(v => v.id === modal.vaultId) : null
  const modalCapId  = modal ? caps[modal.vaultId] : null

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
      {/* Close thread modal */}
      {modal?.type === 'thread' && modalVault && (
        <CloseThreadModal
          vault={modalVault}
          capId={modalCapId}
          onClose={closeModal}
          onDone={() => { closeModal(); setTimeout(load, 2000) }}
          signAndExecute={signAndExecute}
        />
      )}

      {/* Close vault modal */}
      {modal?.type === 'vault' && modalVault && (
        <CloseVaultModal
          vault={modalVault}
          capId={modalCapId}
          onClose={closeModal}
          onDone={() => { closeModal(); setTimeout(load, 2000) }}
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
              onClick={() => setModal({ type: 'thread', vaultId: vault.id })}
              disabled={!!busy[vault.id]}
            >
              Close a thread
            </Btn>

            {/* ── Close vault ── */}
            <Btn
              variant="danger"
              onClick={() => setModal({ type: 'vault', vaultId: vault.id })}
              disabled={!!busy[vault.id] || !caps[vault.id]}
              style={{ marginLeft: 'auto' }}
            >
              Delete vault
            </Btn>
          </div>
        </Card>
      ))}
    </PageWrap>
  )
}
