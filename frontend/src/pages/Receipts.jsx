import { useState, useEffect } from 'react'
import { useCurrentAccount, useSignPersonalMessage, useSuiClient } from '@mysten/dapp-kit'
import { useNavigate } from 'react-router-dom'
import { mistToSui, PACKAGE_ID } from '../lib/sui.js'
import { Card, Btn, Spinner, PageWrap, Tag } from '../components/ui.jsx'

function buildSignMessage(vaultId, paymentId) {
  return `AttentionMarket:${vaultId}:${paymentId}`
}

function bytesToHex(bytes) {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
}

function CopyBox({ value, label }) {
  const [copied, setCopied] = useState(false)
  function copy() {
    navigator.clipboard.writeText(value)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }
  return (
    <div>
      {label && (
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', marginBottom: '6px' }}>{label}</div>
      )}
      <div style={{
        display: 'flex', alignItems: 'flex-start', gap: '8px',
        background: 'var(--bg)', border: '1px solid var(--border2)',
        borderRadius: 'var(--r)', padding: '10px 14px',
      }}>
        <span style={{
          fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--accent)',
          flex: 1, wordBreak: 'break-all', lineHeight: '1.6',
        }}>{value}</span>
        <button
          onClick={copy}
          style={{
            background: copied ? 'var(--teal)22' : 'var(--bg2)',
            border: `1px solid ${copied ? 'var(--teal)' : 'var(--border2)'}`,
            borderRadius: '4px', padding: '4px 10px', cursor: 'pointer',
            fontFamily: 'var(--font-mono)', fontSize: '11px',
            color: copied ? 'var(--teal)' : 'var(--text2)',
            whiteSpace: 'nowrap', transition: 'all 0.15s', flexShrink: 0, marginTop: '1px',
          }}
        >{copied ? 'copied ✓' : 'copy'}</button>
      </div>
    </div>
  )
}

function ReceiptCard({ receipt }) {
  const nav = useNavigate()
  const { mutateAsync: signPersonalMessage } = useSignPersonalMessage()
  const suiClient = useSuiClient()

  const [sigState,     setSigState]    = useState('idle') // idle | signing | done | error
  const [subjectTag,   setSubjectTag]  = useState('')
  const [errMsg,       setErrMsg]      = useState('')
  const [expanded,     setExpanded]    = useState(false)
  const [closed,       setClosed]      = useState(null)  // null=checking, true=closed, false=open
  const [closeReason,  setCloseReason] = useState(null)  // 'thread' | 'vault'
  const [checking,     setChecking]    = useState(true)

  const paymentIdHex = bytesToHex(receipt.payment_id)
  const vaultId      = receipt.vault_id

  useEffect(() => { checkClosed() }, [vaultId, paymentIdHex])

  async function checkClosed() {
    setChecking(true)
    try {
      const obj = await suiClient.getObject({
        id: vaultId,
        options: { showContent: true },
      })

      // Vault was deleted — object exists in history but has no content
      if (!obj.data || !obj.data.content) {
        setClosed(true)
        setCloseReason('vault')
        return
      }

      const fields = obj.data.content.fields
      if (!fields) {
        setClosed(false)
        return
      }

      // closed_threads is a Sui Table — its entries are dynamic fields
      const tableId = fields.closed_threads?.fields?.id?.id
      if (!tableId) {
        setClosed(false)
        return
      }

      try {
        const df = await suiClient.getDynamicFieldObject({
          parentId: tableId,
          name: {
            type: 'vector<u8>',
            value: Array.from(paymentIdHex.match(/.{1,2}/g).map(b => parseInt(b, 16))),
          },
        })
        if (df?.data) {
          setClosed(true)
          setCloseReason('thread')
        } else {
          setClosed(false)
        }
      } catch {
        // Dynamic field not found — thread is open
        setClosed(false)
      }
    } catch (e) {
      console.error('Error checking closed status:', e)
      // If we can't reach the object at all, treat as vault deleted
      setClosed(true)
      setCloseReason('vault')
    } finally {
      setChecking(false)
    }
  }

  async function generateToken() {
    if (closed) return
    setSigState('signing')
    setErrMsg('')
    try {
      const message  = buildSignMessage(vaultId, paymentIdHex)
      const msgBytes = new TextEncoder().encode(message)
      const { signature } = await signPersonalMessage({ message: msgBytes })
      setSubjectTag(`[attn:${signature}]`)
      setSigState('done')
    } catch (e) {
      setErrMsg(e.message || 'Signing failed')
      setSigState('error')
    }
  }

  const isClosed       = closed === true
  const isVaultDeleted = isClosed && closeReason === 'vault'

  // Badge and copy differ depending on why it's closed
  const closedBadgeText = isVaultDeleted ? 'Vault deleted' : 'Thread closed'
  const closedHeading   = isVaultDeleted
    ? 'The seller has deleted this vault.'
    : 'This conversation has been closed by the seller.'
  const closedBody      = isVaultDeleted
    ? 'The vault no longer exists on-chain. The gateway will reject any emails using this receipt\'s token. This receipt is kept as a historical record of your winning bid.'
    : 'The gateway will reject any emails using this receipt\'s token. New delivery tokens cannot be generated for closed threads. This receipt is kept as a historical record of your winning bid.'

  return (
    <Card style={{
      padding: '24px', marginBottom: '16px',
      opacity: isClosed ? 0.75 : 1,
      borderLeft: isClosed ? '3px solid var(--red)' : '3px solid var(--border)',
    }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap', marginBottom: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px', flexWrap: 'wrap' }}>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: '17px', fontWeight: 700 }}>
              {receipt.seller_name}
            </div>
            {isClosed && (
              <span style={{
                fontFamily: 'var(--font-mono)', fontSize: '10px', fontWeight: 700,
                color: 'var(--red)', background: 'color-mix(in srgb, var(--red) 12%, transparent)',
                border: '1px solid color-mix(in srgb, var(--red) 30%, transparent)',
                borderRadius: '4px', padding: '2px 7px', letterSpacing: '0.06em', textTransform: 'uppercase',
              }}>{closedBadgeText}</span>
            )}
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: isClosed ? 'var(--text3)' : 'var(--accent)', marginBottom: '6px' }}>
            {receipt.gateway_email}
          </div>
          <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
            <Tag>Epoch {receipt.auction_epoch}</Tag>
            <Tag color="var(--teal)">{mistToSui(receipt.amount_paid)} SUI</Tag>
            <Tag color="var(--text3)">Slot #{receipt.slot_index + 1}</Tag>
          </div>
        </div>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
          {!isVaultDeleted && (
            <Btn variant="ghost" onClick={() => nav(`/profile/${vaultId}`)}>
              View vault
            </Btn>
          )}
          <Btn variant="ghost" onClick={() => setExpanded(e => !e)}>
            {expanded ? 'Hide details' : 'Details'}
          </Btn>
        </div>
      </div>

      {/* Expandable details */}
      {expanded && (
        <div style={{
          background: 'var(--bg2)', borderRadius: 'var(--r)',
          padding: '14px 16px', marginBottom: '16px',
          display: 'flex', flexDirection: 'column', gap: '10px',
        }}>
          {[
            { label: 'Vault ID',          value: vaultId },
            { label: 'Payment ID',        value: paymentIdHex },
            { label: 'Receipt object ID', value: receipt.id },
          ].map(({ label, value }) => (
            <div key={label}>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '10px', color: 'var(--text3)', marginBottom: '3px', textTransform: 'uppercase', letterSpacing: '0.06em' }}>{label}</div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text2)', wordBreak: 'break-all' }}>{value}</div>
            </div>
          ))}
        </div>
      )}

      {/* Token section */}
      <div style={{
        background: isClosed ? 'color-mix(in srgb, var(--red) 5%, var(--bg2))' : 'var(--bg2)',
        border: `1px solid ${isClosed ? 'color-mix(in srgb, var(--red) 25%, transparent)' : 'var(--border)'}`,
        borderRadius: 'var(--r)', padding: '18px',
      }}>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: isClosed ? 'var(--red)' : 'var(--text3)', letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: '12px' }}>
          Delivery token
        </div>

        {checking ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <Spinner size="sm" />
            <span style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>Checking status…</span>
          </div>

        ) : isClosed ? (
          <div style={{
            display: 'flex', alignItems: 'flex-start', gap: '10px',
            padding: '12px 14px',
            background: 'color-mix(in srgb, var(--red) 8%, transparent)',
            border: '1px solid color-mix(in srgb, var(--red) 25%, transparent)',
            borderRadius: 'var(--r)',
          }}>
            <span style={{ fontSize: '16px', flexShrink: 0 }}>{isVaultDeleted ? '🗑️' : '🚫'}</span>
            <div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', fontWeight: 600, marginBottom: '6px' }}>
                {closedHeading}
              </div>
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.8' }}>
                {closedBody}
              </div>
            </div>
          </div>

        ) : sigState === 'done' ? (
          <>
            <div style={{ marginBottom: '14px' }}>
              <CopyBox label="Paste into your email subject line" value={subjectTag} />
            </div>
            <div style={{
              fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.9',
              borderTop: '1px solid var(--border)', paddingTop: '12px', marginBottom: '14px',
            }}>
              <div style={{ marginBottom: '4px' }}>⚠ Tag must appear in the subject line exactly as shown.</div>
              <div style={{ marginBottom: '4px' }}>⚠ Send from the email address you used when bidding.</div>
              <div>✓ Token is valid until the seller closes this conversation.</div>
            </div>
            <Btn variant="ghost" onClick={() => { setSigState('idle'); setSubjectTag('') }} style={{ width: '100%' }}>
              Regenerate token
            </Btn>
          </>

        ) : (
          <>
            <p style={{ fontFamily: 'var(--font-body)', fontSize: '13px', color: 'var(--text2)', lineHeight: '1.7', marginBottom: '16px' }}>
              Sign with your wallet to prove ownership of this slot.
              No gas — free cryptographic signature. Generate a fresh token any time.
            </p>
            {sigState === 'error' && (
              <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--red)', marginBottom: '12px' }}>
                {errMsg}
              </div>
            )}
            <Btn onClick={generateToken} disabled={sigState === 'signing'} style={{ width: '100%', padding: '11px' }}>
              {sigState === 'signing' ? 'Check your wallet…' : 'Generate delivery token →'}
            </Btn>
          </>
        )}
      </div>
    </Card>
  )
}

export default function Receipts() {
  const account   = useCurrentAccount()
  const suiClient = useSuiClient()
  const nav       = useNavigate()

  const [receipts, setReceipts] = useState([])
  const [loading,  setLoading]  = useState(true)

  useEffect(() => {
    if (account) load()
    else setLoading(false)
  }, [account?.address])

  async function load() {
    setLoading(true)
    try {
      const res = await suiClient.getOwnedObjects({
        owner: account.address,
        filter: { StructType: `${PACKAGE_ID}::attention_market::AttentionReceipt` },
        options: { showContent: true },
      })

      const parsed = res.data
        .map(obj => {
          const fields = obj.data?.content?.fields
          if (!fields) return null
          return {
            id:                obj.data.objectId,
            vault_id:          fields.vault_id,
            seller:            fields.seller,
            seller_name:       fields.seller_name,
            gateway_email:     fields.gateway_email,
            sender_email_hash: fields.sender_email_hash,
            amount_paid:       Number(fields.amount_paid),
            auction_epoch:     Number(fields.auction_epoch),
            payment_id:        fields.payment_id,
            slot_index:        Number(fields.slot_index),
          }
        })
        .filter(Boolean)
        .sort((a, b) => b.auction_epoch - a.auction_epoch)

      setReceipts(parsed)
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  if (!account) return (
    <PageWrap>
      <div style={{ textAlign: 'center', padding: '80px 0' }}>
        <div style={{ fontFamily: 'var(--font-display)', fontSize: '20px', marginBottom: '8px' }}>Connect your wallet</div>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>Required to view your receipts</div>
      </div>
    </PageWrap>
  )

  if (loading) return (
    <PageWrap><div style={{ display: 'flex', justifyContent: 'center', padding: '80px' }}><Spinner /></div></PageWrap>
  )

  return (
    <PageWrap>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '32px', flexWrap: 'wrap', gap: '12px' }}>
        <div>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '24px', fontWeight: 800, marginBottom: '4px' }}>My receipts</div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)' }}>
            {account.address.slice(0, 16)}… · {receipts.length} receipt{receipts.length !== 1 ? 's' : ''}
          </div>
        </div>
        <Btn variant="ghost" onClick={load}>Refresh</Btn>
      </div>

      {receipts.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px 0' }}>
          <div style={{ fontSize: '40px', marginBottom: '16px' }}>🎫</div>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: '18px', fontWeight: 600, marginBottom: '8px' }}>No receipts yet</div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: '12px', color: 'var(--text3)', marginBottom: '24px' }}>
            Receipts appear here after a seller settles an epoch you bid in.
          </div>
          <Btn onClick={() => nav('/')}>Browse sellers →</Btn>
        </div>
      ) : (
        <>
          <div style={{
            padding: '10px 14px', marginBottom: '24px',
            background: 'color-mix(in srgb, var(--teal) 8%, transparent)',
            border: '1px solid color-mix(in srgb, var(--teal) 25%, transparent)',
            borderRadius: 'var(--r)',
            fontFamily: 'var(--font-mono)', fontSize: '11px', color: 'var(--text3)', lineHeight: '1.7',
          }}>
            ✓ Each receipt lets you generate a signed subject tag to send emails to that seller.
            Your token stays valid until the seller closes the conversation or deletes the vault.
          </div>
          {receipts.map(r => <ReceiptCard key={r.id} receipt={r} />)}
        </>
      )}
    </PageWrap>
  )
}