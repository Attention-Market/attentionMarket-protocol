import { useState, useEffect } from 'react'
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit'
import { Transaction } from '@mysten/sui/transactions'
import { useNavigate } from 'react-router-dom'
import {
  fetchVaultsByOwner, fetchRegistry,
  mistToSui, applyFee,
  PACKAGE_ID, REGISTRY_ID,
} from '../lib/sui.js'
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
        {empty ? 'open' : `${slot.bidder.slice(0, 10)}…`}
      </span>
      <span style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: '13px', color: empty ? 'var(--text3)' : 'var(--amber)' }}>
        {empty ? '—' : `${mistToSui(slot.amount)} SUI`}
      </span>
    </div>
  )
}

// Shows a fee breakdown line: "10.000 SUI → fee 5% (0.500) → you receive 9.500"
function FeeBreakdown({ amountMist, feeBps, style }) {
  if (amountMist <= 0) return null
  const { fee, net } = applyFee(amountMist, feeBps)
  const pct = (feeBps / 100).toFixed(feeBps % 100 === 0 ? 0 : 1)
  return (
    <div style={{
      fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)',
      display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap',
      ...style,
    }}>
      <span style={{ color: 'var(--text2)' }}>{mistToSui(amountMist)} SUI</span>
      {feeBps > 0 && <>
        <span>→</span>
        <span style={{ color: 'var(--red)' }}>platform fee {pct}% (−{mistToSui(fee)} SUI)</span>
        <span>→</span>
        <span style={{ color: 'var(--teal)', fontWeight: 600 }}>you receive {mistToSui(net)} SUI</span>
      </>}
      {feeBps === 0 && <span style={{ color: 'var(--teal)', fontWeight: 600 }}>→ you receive {mistToSui(net)} SUI (no fee)</span>}
    </div>
  )
}

function CloseThreadModal({ vault, capId, onClose, onDone, signAndExecute }) {
  const [paymentIdInput, setPaymentIdInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [err,  setErr]  = useState('')

  async function submit() {
    if (!paymentIdInput.trim()) return
    setBusy(true); setErr('')
    try {
      const tx = new Transaction()
      const pidBytes = Array.from(
        new Uint8Array(paymentIdInput.trim().match(/.{1,2}/g).map(b => parseInt(b, 16)))
      )
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
          Permanently invalidates this winner's delivery token. The gateway will reject
          all future emails from this thread. Cannot be undone.
        </p>
        <div style={{ marginBottom: '16px' }}>
          <label style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase', display: 'block', marginBottom: '6px' }}>
            Payment ID (hex)
          </label>
          <input
            value={paymentIdInput}
            onChange={e => setPaymentIdInput(e.target.value)}
            placeholder="64-char hex from the winner's receipt"
            style={{
              width: '100%', background: 'var(--bg2)', border: '1px solid var(--border2)',
              borderRadius: 'var(--r)', padding: '10px 14px', color: 'var(--text)',
              fontFamily: 'var(--font-mono)', fontSize: '12px', outline: 'none', boxSizing: 'border-box',
            }}
          />
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginTop: '6px' }}>
            The winner can find their payment_id on their receipts page.
          </div>
        </div>
        {err && <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', marginBottom: '12px' }}>{err}</div>}
        <div style={{ display: 'flex', gap: '10px' }}>
          <Btn variant="ghost" onClick={onClose} style={{ flex: 1 }}>Cancel</Btn>
          <Btn variant="danger" onClick={submit} disabled={busy || !paymentIdInput.trim()} style={{ flex: 1 }}>
            {busy ? 'Closing…' : 'Close thread'}
          </Btn>
        </div>
      </div>
    </div>
  )
}

function CloseVaultModal({ vault, capId, onClose, onDone, signAndExecute }) {
  const [busy, setBusy] = useState(false)
  const [err,  setErr]  = useState('')

  const ZERO_ADDR = '0x0000000000000000000000000000000000000000000000000000000000000000'
  const activeSlots = vault.slots.filter(s => s.bidder !== ZERO_ADDR)

  async function submit() {
    setBusy(true); setErr('')
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
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
          <span style={{ fontSize: '20px' }}>⚠️</span>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 700 }}>Delete vault permanently</div>
        </div>
        <p style={{ fontFamily: 'var(--font-body)', fontSize: '13px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '16px' }}>
          This will permanently destroy <em>{vault.name}</em>. Cannot be undone.
        </p>
        <div style={{
          background: 'var(--bg2)', border: '1px solid var(--border)',
          borderRadius: 'var(--r)', padding: '14px 16px', marginBottom: '20px',
          display: 'flex', flexDirection: 'column', gap: '8px',
        }}>
          {[
            { icon: activeSlots.length > 0 ? '↩' : '✓', color: activeSlots.length > 0 ? 'var(--teal)' : 'var(--text3)',
              text: activeSlots.length > 0 ? `${activeSlots.length} active bidder(s) will be refunded automatically` : 'No active bids to refund' },
            { icon: vault.balance > 0 ? '↩' : '✓', color: vault.balance > 0 ? 'var(--teal)' : 'var(--text3)',
              text: vault.balance > 0 ? `${mistToSui(vault.balance)} SUI pending balance returned to you` : 'No pending balance' },
            { icon: '⚠', color: 'var(--amber)', text: 'Settle all epochs first — transaction will fail if closed_threads table is non-empty' },
            { icon: '⚠', color: 'var(--amber)', text: `Gateway email ${vault.gatewayEmail} will be freed` },
          ].map((item, i) => (
            <div key={i} style={{ display: 'flex', gap: '8px', alignItems: 'flex-start' }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: item.color, flexShrink: 0, marginTop: '1px' }}>{item.icon}</span>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', lineHeight: '1.6' }}>{item.text}</span>
            </div>
          ))}
        </div>
        {err && (
          <div style={{
            fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)',
            background: 'color-mix(in srgb, var(--red) 10%, transparent)',
            border: '1px solid color-mix(in srgb, var(--red) 30%, transparent)',
            borderRadius: 'var(--r)', padding: '10px 12px', marginBottom: '16px',
          }}>{err}</div>
        )}
        <div style={{ display: 'flex', gap: '10px' }}>
          <Btn variant="ghost" onClick={onClose} style={{ flex: 1 }} disabled={busy}>Cancel</Btn>
          <Btn variant="danger" onClick={submit} disabled={busy} style={{ flex: 1 }}>
            {busy ? 'Deleting vault…' : 'Delete vault'}
          </Btn>
        </div>
      </div>
    </div>
  )
}

function SettleModal({ vault, capId, feeBps, onClose, onDone, signAndExecute }) {
  const [busy, setBusy] = useState(false)
  const [err,  setErr]  = useState('')

  const ZERO_ADDR  = '0x0000000000000000000000000000000000000000000000000000000000000000'
  const winners    = vault.slots.filter(s => s.bidder !== ZERO_ADDR)
  const totalMist  = winners.reduce((sum, s) => sum + s.amount, 0)

  async function submit() {
    setBusy(true); setErr('')
    try {
      const tx = new Transaction()
      tx.moveCall({
        target: `${PACKAGE_ID}::attention_market::settle_epoch`,
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
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 700, marginBottom: '4px' }}>
          Settle epoch {vault.epoch}
        </div>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginBottom: '20px' }}>
          {vault.name}
        </div>

        {/* What settling does */}
        <div style={{
          background: 'var(--bg2)', border: '1px solid var(--border)',
          borderRadius: 'var(--r)', padding: '14px 16px', marginBottom: '20px',
          display: 'flex', flexDirection: 'column', gap: '8px',
        }}>
          {[
            { icon: '🏆', text: `Mints a soulbound AttentionReceipt to each of the ${winners.length} slot winner${winners.length !== 1 ? 's' : ''}` },
            { icon: '🔄', text: `Resets all ${vault.slotsPerEpoch} slots and opens epoch ${vault.epoch + 1} for new bids` },
            { icon: '💸', text: 'Transfers collected funds to your wallet immediately (minus platform fee)' },
          ].map((item, i) => (
            <div key={i} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start' }}>
              <span style={{ fontSize: '13px', flexShrink: 0 }}>{item.icon}</span>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', lineHeight: '1.6' }}>{item.text}</span>
            </div>
          ))}
        </div>

        {/* Payout breakdown */}
        <div style={{
          background: 'color-mix(in srgb, var(--accent) 6%, transparent)',
          border: '1px solid color-mix(in srgb, var(--accent) 20%, transparent)',
          borderRadius: 'var(--r)', padding: '14px 16px', marginBottom: '20px',
        }}>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: '10px' }}>
            Payout for this epoch
          </div>
          {winners.length === 0 ? (
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>
              No winners this epoch — nothing to pay out.
            </div>
          ) : (
            <>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', marginBottom: '10px' }}>
                {winners.map((s, i) => (
                  <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'var(--font-mono)', fontSize: '11px' }}>
                    <span style={{ color: 'var(--text3)' }}>{s.bidder.slice(0, 10)}…</span>
                    <span style={{ color: 'var(--amber)' }}>{mistToSui(s.amount)} SUI</span>
                  </div>
                ))}
                <div style={{ borderTop: '1px solid var(--border)', marginTop: '4px', paddingTop: '8px' }}>
                  <FeeBreakdown amountMist={totalMist} feeBps={feeBps} />
                </div>
              </div>
            </>
          )}
        </div>

        {err && (
          <div style={{
            fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)',
            background: 'color-mix(in srgb, var(--red) 10%, transparent)',
            border: '1px solid color-mix(in srgb, var(--red) 30%, transparent)',
            borderRadius: 'var(--r)', padding: '10px 12px', marginBottom: '16px',
          }}>{err}</div>
        )}
        <div style={{ display: 'flex', gap: '10px' }}>
          <Btn variant="ghost" onClick={onClose} style={{ flex: 1 }} disabled={busy}>Cancel</Btn>
          <Btn onClick={submit} disabled={busy} style={{ flex: 1 }}>
            {busy ? 'Settling…' : `Settle epoch ${vault.epoch}`}
          </Btn>
        </div>
      </div>
    </div>
  )
}

export default function Dashboard() {
  const account = useCurrentAccount()
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction()
  const suiClient = useSuiClient()
  const nav = useNavigate()

  const [vaults,  setVaults]  = useState([])
  const [caps,    setCaps]    = useState({})
  const [feeBps,  setFeeBps]  = useState(0)
  const [loading, setLoading] = useState(true)
  const [modal,   setModal]   = useState(null) // { type: 'thread'|'vault'|'settle', vaultId }

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
      const [vs, cs, reg] = await Promise.all([
        fetchVaultsByOwner(account.address),
        fetchVaultCaps(account.address),
        fetchRegistry(),
      ])
      setVaults(vs)
      setCaps(cs)
      setFeeBps(reg.fee_bps)
    } catch (e) { console.error(e) }
    finally { setLoading(false) }
  }

  const closeModal = () => setModal(null)
  const modalVault = modal ? vaults.find(v => v.id === modal.vaultId) : null
  const modalCapId = modal ? caps[modal.vaultId] : null

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
      {modal?.type === 'thread' && modalVault && (
        <CloseThreadModal
          vault={modalVault} capId={modalCapId}
          onClose={closeModal}
          onDone={() => { closeModal(); setTimeout(load, 2000) }}
          signAndExecute={signAndExecute}
        />
      )}
      {modal?.type === 'vault' && modalVault && (
        <CloseVaultModal
          vault={modalVault} capId={modalCapId}
          onClose={closeModal}
          onDone={() => { closeModal(); setTimeout(load, 2000) }}
          signAndExecute={signAndExecute}
        />
      )}
      {modal?.type === 'settle' && modalVault && (
        <SettleModal
          vault={modalVault} capId={modalCapId} feeBps={feeBps}
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
      ) : vaults.map(vault => {
        const capId = caps[vault.id]
        const { net: settleNet } = applyFee(vault.balance, feeBps)
        const feePct = (feeBps / 100).toFixed(feeBps % 100 === 0 ? 0 : 1)

        return (
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
                {!capId && <Tag color="var(--red)">No cap found</Tag>}
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
              <SectionLabel>Current epoch slots</SectionLabel>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                {vault.slots.map((slot, i) => <SlotRow key={i} slot={slot} index={i} />)}
              </div>
            </div>

            {/* Settle info box */}
            <div style={{
              marginBottom: '20px', padding: '12px 16px',
              background: 'color-mix(in srgb, var(--accent) 6%, transparent)',
              border: '1px solid color-mix(in srgb, var(--accent) 20%, transparent)',
              borderRadius: 'var(--r)',
              display: 'flex', flexDirection: 'column', gap: '6px',
            }}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)' }}>
                Settling mints receipts to all current winners and opens the next epoch for new bids.
              </div>
              {vault.balance > 0 && (
                <FeeBreakdown amountMist={vault.balance} feeBps={feeBps} />
              )}
              {vault.balance === 0 && (
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)' }}>
                  No bids this epoch — settling is free and resets the slots.
                </div>
              )}
            </div>

            {/* Actions */}
            <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap', paddingTop: '16px', borderTop: '1px solid var(--border)' }}>
              <Btn
                onClick={() => setModal({ type: 'settle', vaultId: vault.id })}
                disabled={!capId}
              >
                Settle epoch {vault.epoch} & mint receipts
                {vault.balance > 0 && feeBps > 0 && (
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', opacity: 0.7, marginLeft: '6px' }}>
                    → {mistToSui(settleNet)} SUI after {feePct}% fee
                  </span>
                )}
                {vault.balance > 0 && feeBps === 0 && (
                  <span style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', opacity: 0.7, marginLeft: '6px' }}>
                    → {mistToSui(vault.balance)} SUI
                  </span>
                )}
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
                disabled={!capId}
              >
                Close a thread
              </Btn>
              <Btn
                variant="danger"
                onClick={() => setModal({ type: 'vault', vaultId: vault.id })}
                disabled={!capId}
                style={{ marginLeft: 'auto' }}
              >
                Delete vault
              </Btn>
            </div>
          </Card>
        )
      })}
    </PageWrap>
  )
}