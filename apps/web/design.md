# veXDC Web — Design System

Visual and UX specification for `apps/web`. Implementation must follow this document.

---

## 1. Product intent

**veXDC** is vote-escrowed XDC: lock native XDC for protocol revenue share. The UI should feel like a **sovereign treasury desk** — calm, precise, on-chain — not a generic DeFi dashboard or purple SaaS template.

Primary jobs:

1. Make locking XDC feel consequential and clear (amount + duration → weight).
2. Show positions and earnings without clutter.
3. Guide exit/claim flows through cooldown states without surprise.

---

## 2. Brand & first viewport

### Brand test

After removing the nav, the first viewport must still read as **veXDC** — not “another staking app.” The wordmark `veXDC` is the hero-level signal; no secondary headline may overpower it.

### Hero composition (landing `/`)

One composition, full-bleed atmosphere:

| Element | Role |
|---------|------|
| **veXDC** | Display wordmark (Syne), dominant |
| One line | “Lock XDC. Earn protocol revenue.” |
| CTA group | Connect wallet + scroll/focus deposit |
| Dominant visual | Full-bleed teal depth field with ember filament (not an inset card image) |

**Do not** put stats, TVL chips, schedule rows, or promo badges in the first viewport.

### Wordmark treatment

- Font: Syne ExtraBold / Bold
- Tracking: slightly tight (`-0.03em`)
- Color: `--ink-bright` with a soft ember underline filament (1–2px gradient stroke under the “ve”)
- Optional micro-motion: wordmark fades up 12px on load (220ms ease-out); filament draws left→right once

---

## 3. Color system (XDC teal × ember)

Dark-first. No purple gradients. No cream paper look. No neon glow stacks.

```css
:root {
  /* Surfaces */
  --bg-deep: #041012;
  --bg-base: #07181b;
  --bg-raised: #0c2428;
  --bg-inset: #061416;
  --bg-overlay: rgba(4, 16, 18, 0.72);

  /* Teal spine (XDC-adjacent) */
  --teal-900: #0a3d42;
  --teal-700: #0f6b72;
  --teal-500: #1a9b8e;
  --teal-300: #3ecfbf;
  --teal-100: #b8f0e8;

  /* Ember accents (action / heat) */
  --ember-700: #b33a08;
  --ember-500: #e85d04;
  --ember-400: #f48c06;
  --ember-200: #ffba6a;

  /* Ink */
  --ink-bright: #eef7f6;
  --ink-primary: #c5d9d6;
  --ink-muted: #7a9a96;
  --ink-faint: #4a6865;

  /* Semantic */
  --ok: #2db88a;
  --warn: #e8b84a;
  --danger: #e04b4b;
  --border: rgba(62, 207, 191, 0.14);
  --border-strong: rgba(62, 207, 191, 0.32);
  --focus-ring: rgba(244, 140, 6, 0.55);

  /* Charts */
  --chart-tvl: var(--teal-300);
  --chart-revenue: var(--ember-400);
  --chart-earnings: var(--teal-500);
  --chart-grid: rgba(122, 154, 150, 0.18);
}
```

### Atmosphere

Background is never flat `#000`. Use:

1. Radial teal wash from upper-left (`--teal-900` → transparent).
2. Soft ember glow anchored lower-right (very low opacity, ~6–10%).
3. Fine diagonal hatch or noise at 3–5% opacity for texture (CSS or SVG pattern).

---

## 4. Typography

| Role | Font | Weight | Size (desktop) | Notes |
|------|------|--------|----------------|-------|
| Display / brand | **Syne** | 700–800 | clamp(3rem, 8vw, 5.5rem) | Wordmark only / section titles |
| Headings | **Syne** | 600–700 | 1.5–2rem | Section heads |
| Body / UI | **IBM Plex Sans** | 400–500 | 0.9375–1rem | Forms, tables, copy |
| Mono / amounts | **IBM Plex Mono** | 400–500 | 0.875–1rem | Balances, token IDs, addresses |

Line-height: body 1.5; display 1.05. Avoid Inter, Roboto, Arial, system-ui as primary.

Load via `next/font/google`: Syne, IBM_Plex_Sans, IBM_Plex_Mono.

---

## 5. Layout & spacing

- Max content width: `1120px` (`--shell-max`)
- Page pad: `1.25rem` mobile → `2rem` desktop
- Vertical rhythm: 8px base; section gaps `4–6rem`
- Header: sticky, translucent `--bg-overlay` + blur(12px), hairline `--border`

### Breakpoints

| Name | Width |
|------|-------|
| sm | 640px |
| md | 768px |
| lg | 1024px |

Mobile: single column; deposit form full width; charts stack; position manage expands inline (no side drawer required).

---

## 6. Components (interaction containers only)

Default: **no decorative cards**. Surfaces that hold forms, lists, or charts may use a raised panel only when it aids interaction:

- Background: `--bg-raised`
- Border: `1px solid var(--border)`
- Radius: `12px` (not pill-full)
- Shadow: none or a single soft `0 12px 40px rgba(0,0,0,0.35)` — never multi-layer glow

### Buttons

| Variant | Use | Look |
|---------|-----|------|
| **Primary** | Deposit, Claim, Confirm exit | Ember fill `--ember-500`, text `--bg-deep`, hover `--ember-400` |
| **Secondary** | Extend, Increase, Cancel | Teal outline / translucent teal fill |
| **Ghost** | Nav / tertiary | Text + underline on hover |
| **Danger** | Emergency exit | `--danger` outline |

Min hit target 44×44px. Disabled: 40% opacity, `cursor: not-allowed`.

### Inputs & slider

- Amount field: large IBM Plex Mono, inset `--bg-inset`, teal focus border
- Duration slider: track `--teal-900`, fill `--teal-500`, thumb ember circle
- Labels always visible (not placeholder-only)

### Banner (contracts missing)

Full-width strip under header:

- Background: `rgba(232, 93, 4, 0.12)`
- Border-bottom: `--ember-500`
- Copy: **Contracts not deployed on this network**
- Subcopy: shell remains usable; writes disabled

### Connect button

Shows truncated address when connected; chain badge (`Apothem` / `XDC`). Wrong network → ember outline “Switch network”.

---

## 7. Page layouts

### `/` — Landing / deposit

```
┌─ Header: logo · Dashboard link · Connect ─────────────┐
│ [Contracts banner if needed]                          │
│                                                       │
│   veXDC                                               │
│   Lock XDC. Earn protocol revenue.                    │
│   [Connect]  [Lock XDC →]                             │
│                                                       │
│ ── full-bleed teal/ember field continues behind ──    │
│                                                       │
│   ┌─ Deposit panel ─────────────────────────────┐     │
│   │ Amount (XDC)     Duration 1–104 weeks       │     │
│   │ [======== slider ========]  52w · ~50% wt   │     │
│   │ Estimated unlock · weight hint              │     │
│   │ [ Deposit native XDC ]                      │     │
│   └─────────────────────────────────────────────┘     │
└───────────────────────────────────────────────────────┘
```

Deposit calls `Zap.zapCreateLock{value}(durationSeconds)` where `durationSeconds = weeks * 1 week`.

### `/dashboard` — Positions & charts

```
┌─ Header ──────────────────────────────────────────────┐
│ Your positions          Protocol                      │
│ ┌ list / manage ────┐   ┌ TVL chart ──────────────┐   │
│ │ #7  100k · 52w    │   │                         │   │
│ │ claim · manage    │   └─────────────────────────┘   │
│ └───────────────────┘   ┌ Revenue chart ──────────┐   │
│ Earnings (indexer)      │                         │   │
│ ┌ area/line chart ──┐   └─────────────────────────┘   │
│ └───────────────────┘                                 │
└───────────────────────────────────────────────────────┘
```

- Positions from RPC: `tokensOfOwner` + `locked` + `balanceOfNFT` + `exitRequest`
- Charts from indexer API (graceful empty state if indexer down)
- Selecting a position opens **Manage** inline (or `/position/[tokenId]`)

### Manage position

One purpose per control group:

1. **Increase** — native XDC via `zap.zapIncreaseAmount{value}(tokenId)`
2. **Extend** — weeks remaining → `escrow.increaseUnlockTime` or `keepAtMaxLock`
3. **Claim** — `distributor.claim(tokenId, rewardTokens)`
4. **Claim & lock** — `distributor.claimAndLock(tokenId)`
5. **Exit** — request withdraw / emergency → cooldown countdown → finalize; cancel when pending

Show cooldown `readyAt` clearly. Block increase/extend when exit pending.

---

## 8. Charts (Recharts)

- Dark tooltip: `--bg-raised`, border `--border`
- Grid: `--chart-grid`, no vertical lines preferred
- Axes: `--ink-muted`, IBM Plex Sans 12px
- TVL: area teal; Revenue: bar or line ember; Earnings: area teal-500
- Empty: centered muted copy “No indexed data yet”
- Legend text, not color alone

---

## 9. Motion (intentional, sparse)

Ship **2–3** purposeful motions:

1. **Hero brand** — fade/slide-up + ember filament draw (once)
2. **Primary button** — press scale `0.98` (120ms)
3. **Panel enter** — deposit / manage opacity 0→1 + 8px rise (180ms)

Respect `prefers-reduced-motion: reduce` (instant states).

No continuous glow pulses, no parallax noise, no emoji animations.

---

## 10. Copy tone

- Direct: “Deposit”, “Claim”, “Request exit”, “Finalize exit”
- Numbers always with units: `12,500 XDC`, `#7`, `52 weeks`
- Errors near the control; include short humanized revert when possible
- Mid-epoch note: “Earns from the next epoch snapshot”

---

## 11. Accessibility

- Contrast ≥ 4.5:1 for body on `--bg-base`
- Visible focus rings (`--focus-ring`)
- Slider keyboard operable
- Form labels associated with inputs
- Status messages via `aria-live` for tx pending / confirmed

---

## 12. Anti-patterns (explicitly forbidden)

- Purple-on-white / indigo gradient “AI SaaS” look
- Warm cream + terracotta newspaper layouts
- Inter / Roboto / Arial as primary fonts
- Card grids in the hero; floating badges on media
- Stat strips or pill clusters in the first viewport
- Tailwind utility soup that drifts from these tokens

---

## 13. Implementation mapping

| Spec | Code |
|------|------|
| Tokens | `src/app/globals.css` |
| Fonts | `src/app/layout.tsx` (`next/font`) |
| Landing | `src/app/page.tsx` + `DepositForm` |
| Dashboard | `src/app/dashboard/page.tsx` |
| Manage | `ManagePosition` + `/position/[tokenId]` |
| Wallet | `ConnectButton`, `providers.tsx`, `lib/wagmi.ts` |
| Chain/contracts | `lib/contracts.ts` + banner |
| Indexer charts | `lib/indexer.ts` + chart components |

CSS modules per component + global variables. No Tailwind required.
