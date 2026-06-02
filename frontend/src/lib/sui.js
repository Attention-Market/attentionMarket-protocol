import { SuiGrpcClient } from '@mysten/sui/grpc'

export const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
})

export const PACKAGE_ID  = import.meta.env.VITE_PACKAGE_ID  || ''
export const REGISTRY_ID = import.meta.env.VITE_REGISTRY_ID || ''

export const CATEGORIES = [
  { id: 0, label: 'General',      emoji: '💬' },
  { id: 1, label: 'Consulting',   emoji: '🧠' },
  { id: 2, label: 'Feedback',     emoji: '📝' },
  { id: 3, label: 'Investing',    emoji: '💰' },
  { id: 4, label: 'Mentorship',   emoji: '🎓' },
  { id: 5, label: 'Hiring',       emoji: '🤝' },
  { id: 6, label: 'Partnerships', emoji: '🔗' },
]

export function categoryById(id) {
  return CATEGORIES.find(c => c.id === id) || CATEGORIES[0]
}

export function mistToSui(mist) {
  return (Number(mist) / 1e9).toFixed(3)
}

export function suiToMist(sui) {
  return BigInt(Math.ceil(parseFloat(sui) * 1e9))
}

/**
 * Fetch current Sui epoch info for countdown calculations.
 * Uses client.core.getCurrentSystemState() which returns systemState
 * with epoch, epochStartTimestampMs, and epochDurationMs.
 */
export async function fetchEpochInfo() {
  const res = await client.core.getCurrentSystemState()
  const s   = res.systemState
  return {
    currentEpoch:    Number(s.epoch),
    epochStartMs:    Number(s.epochStartTimestampMs),
    epochDurationMs: Number(s.parameters?.epochDurationMs ?? s.epochDurationMs),
  }
}

/** Fetch the Registry object to get all vault IDs */
export async function fetchRegistry() {
  if (!REGISTRY_ID) {
    return { vault_ids: [], total_sellers: 0, total_bids: 0 }
  }
  const { object } = await client.core.getObject({
    objectId: REGISTRY_ID,
    include: { json: true },
  })
  const f = object?.json
  if (!f) return { vault_ids: [], total_sellers: 0, total_bids: 0 }
  return {
    vault_ids:     f.vault_ids || [],
    total_sellers: Number(f.total_sellers),
    total_bids:    Number(f.total_bids),
  }
}

/** Fetch a single AttentionVault by object ID */
export async function fetchVault(id) {
  const { object } = await client.core.getObject({
    objectId: id,
    include: { json: true },
  })
  const f = object?.json
  if (!f) return null
  return parseVaultFields(id, f)
}

/** Fetch multiple vaults in parallel */
export async function fetchAllVaults(ids) {
  if (!ids.length) return []
  const results = await Promise.allSettled(ids.map(fetchVault))
  return results.filter(r => r.status === 'fulfilled' && r.value).map(r => r.value)
}

function parseVaultFields(id, f) {
  const slots = (f.slots || []).map(s => {
    const sf = s?.fields || s
    const toHex = (arr) => arr
      ? Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('')
      : ''
    return {
      bidder:          sf.bidder,
      amount:          Number(sf.amount),
      senderEmailHash: toHex(sf.sender_email_hash),
      paymentId:       toHex(sf.payment_id),
    }
  })

  const filledSlots = slots.filter(
    s => s.bidder !== '0x0000000000000000000000000000000000000000000000000000000000000000'
  )
  const lowestBid = filledSlots.length < slots.length
    ? Number(f.floor_bid)
    : filledSlots.length > 0
      ? Math.min(...filledSlots.map(s => s.amount))
      : Number(f.floor_bid)

  return {
    id,
    owner:          f.owner,
    name:           f.name,
    bio:            f.bio,
    category:       Number(f.category),
    socialHandle:   f.social_handle,
    gatewayEmail:   f.gateway_email,
    epoch:          Number(f.epoch),
    epochStart:     Number(f.epoch_start),
    epochDuration:  Number(f.epoch_duration),
    slotsPerEpoch:  Number(f.slots_per_epoch),
    floorBid:       Number(f.floor_bid),
    lowestBid,
    slotsAvailable: slots.length - filledSlots.length,
    slots,
    balance:        Number(f.balance?.fields?.value || 0),
    totalEarned:    Number(f.total_earned),
    totalBids:      Number(f.total_bids),
  }
}

/** Fetch all vaults owned by a given address (for seller dashboard) */
export async function fetchVaultsByOwner(ownerAddr) {
  const reg = await fetchRegistry()
  const all = await fetchAllVaults(reg.vault_ids)
  return all.filter(v => v.owner === ownerAddr)
}