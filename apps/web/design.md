# veXDC Web — Design System

Visual and UX specification for `apps/web`. Implementation must follow this document.

Brand alignment: tokens and mood track **[xdcai.tech](https://xdcai.tech)** (dark near-black surfaces, cyan accent `#2dd4bf`, cool slate ink). veXDC remains a staking desk — not a purple AI SaaS template.

---

## 1. Product intent

**veXDC** is vote-escrowed XDC: lock native XDC for protocol revenue share. The UI should feel like a **sovereign treasury desk** — calm, precise, on-chain — sharing XDC AI’s cool cyan-on-near-black atmosphere.

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
| **veXDC** | Display wordmark (Space Grotesk), dominant |
| One line | “Lock XDC. Earn protocol revenue.” |
| CTA group | Connect wallet + scroll/focus deposit |
| Dominant visual | Full-bleed near-black field with cyan depth wash (not an inset card image) |

**Do not** put stats, TVL chips, schedule rows, or promo badges in the first viewport.

### Wordmark treatment

- Font: Space Grotesk Bold (700)
- Tracking: slightly tight (`-0.03em`)
- Color: `--ink-bright` with a soft cyan underline filament (1–2px gradient stroke under the “ve”)
- Optional micro-motion: wordmark fades up 12px on load (220ms ease-out); filament draws left→right once

---

## 3. Color system (xdcai.tech dark × cyan)

Extracted from xdcai.tech dark theme:

| Token (site) | Value | Role |
|--------------|-------|------|
| `--c-bg` | `#08090c` | Page ground |
| `--c-surface` | `#0f1117` | Raised panels |
| `--c-surface-2` | `#151823` | Nested / inset lift |
| `--c-border` | `#1f2330` | Hairlines |
| `--c-muted` | `#8b93a7` | Secondary copy |
| `--c-text` | `#e7eaf1` | Body ink |
| `--c-accent` | `#2dd4bf` | Primary accent (cyan) |
| `--c-accent-soft` | `#134e4a` | Soft accent wash |

Supporting signals from the same CSS: blue `#3884ff` (charts / links contrast), amber `#eab24a` (warn / coming-soon). Dark-first. No purple gradients. No cream paper look. No neon glow stacks.

```css
:root {
  /* Surfaces (xdcai near-black) */
  --bg-deep: #06070a;
  --bg-base: #08090c;
  --bg-raised: #0f1117;
  --bg-inset: #0a0c10;
  --bg-overlay: rgba(8, 9, 12, 0.78);

  /* Cyan spine (xdcai --c-accent) */
  --teal-900: #0a2f2c;
  --teal-700: #134e4a;
  --teal-500: #14b8a6;
  --teal-300: #2dd4bf;
  --teal-100: #99f6e4;

  /* Amber signal (warn / focus secondary — not primary CTA) */
  --ember-700: #a16207;
  --ember-500: #eab24a;
  --ember-400: #f59e0b;
  --ember-200: #fcd34d;

  /* Ink */
  --ink-bright: #f4f7fc;
  --ink-primary: #e7eaf1;
  --ink-muted: #8b93a7;
  --ink-faint: #55617d;

  /* Semantic */
  --ok: #2dd4bf;
  --warn: #eab24a;
  --danger: #fb2c36;
  --border: #1f2330;
  --border-strong: rgba(45, 212, 191, 0.35);
  --focus-ring: rgba(45, 212, 191, 0.55);

  /* Charts */
  --chart-tvl: var(--teal-300);
  --chart-revenue: #3884ff;
  --chart-earnings: var(--teal-500);
  --chart-grid: rgba(139, 147, 167, 0.18);
}
```

### Atmosphere

Background is never flat `#000`. Use:

1. Radial cyan wash from upper-left (`--teal-700` / accent soft → transparent).
2. Soft cool blue depth lower-right (very low opacity, ~5–8% of `#3884ff` or surface lift) — not warm orange glow.
3. Fine diagonal hatch or noise at 3–5% opacity for texture (CSS or SVG pattern).

---

## 4. Typography

xdcai.tech ships **Inter** + **JetBrains Mono**. We keep JetBrains Mono; body/display avoid Inter (and Roboto/Arial/system) per product rules — use a geometric tech pair that matches the same cool, product-engineering mood.

| Role | Font | Weight | Size (desktop) | Notes |
|------|------|--------|----------------|-------|
| Display / brand | **Space Grotesk** | 700 | clamp(3rem, 8vw, 5.5rem) | Wordmark / section titles |
| Headings | **Space Grotesk** | 600–700 | 1.5–2rem | Section heads |
| Body / UI | **Space Grotesk** | 400–500 | 0.9375–1rem | Forms, tables, copy |
| Mono / amounts | **JetBrains Mono** | 400–500 | 0.875–1rem | Balances, token IDs, addresses |

Line-height: body 1.5; display 1.05. Avoid Inter, Roboto, Arial, system-ui as primary.

Load via `next/font/google`: Space_Grotesk, JetBrains_Mono.

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
- Radius: `12px` (not pill-full) — aligns with xdcai `rounded-xl`
- Shadow: none or a single soft `0 12px 40px rgba(0,0,0,0.35)` — never multi-layer glow

### Buttons

| Variant | Use | Look |
|---------|-----|------|
| **Primary** | Deposit, Claim, Confirm exit, Connect | Cyan fill `--teal-300`, text `--bg-deep` (or white), hover `--teal-100`; optional soft accent shadow |
| **Secondary** | Extend, Increase, Cancel | Cyan outline / translucent cyan fill |
| **Ghost** | Nav / tertiary | Text + underline on hover |
| **Danger** | Emergency exit | `--danger` outline |
| **Warn outline** | Wrong network | Amber `--ember-500` outline |

Min hit target 44×44px. Disabled: 40% opacity, `cursor: not-allowed`.

### Inputs & slider

- Amount field: large JetBrains Mono, inset `--bg-inset`, cyan focus border
- Duration slider: track `--teal-900`, fill `--teal-500`, thumb cyan circle
- Labels always visible (not placeholder-only)

### Banner (contracts missing)

Full-width strip under header:

- Background: `rgba(234, 178, 74, 0.12)`
- Border-bottom: `--ember-500`
- Copy: **Contracts not deployed on this network**
- Subcopy: shell remains usable; writes disabled

### Connect button

Shows truncated address when connected; chain badge (`Apothem` / `XDC`). Wrong network → amber outline “Switch network”.

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
│ ── full-bleed cyan/near-black field continues ──      │
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
- Axes: `--ink-muted`, Space Grotesk 12px
- TVL: area cyan; Revenue: bar/line blue `#3884ff`; Earnings: area teal-500
- Empty: centered muted copy “No indexed data yet”
- Legend text, not color alone

---

## 9. Motion (intentional, sparse)

Ship **2–3** purposeful motions:

1. **Hero brand** — fade/slide-up + cyan filament draw (once)
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
| System | `/system` + `SystemStatus` (roles, addresses, health) |
| Admin | `/admin` + `AdminActions` (role-gated writes) |
| Motion | GSAP via `lib/gsap.ts` + `Reveal` (respects reduced-motion) |
| Wallet | `ConnectButton`, `providers.tsx`, `lib/wagmi.ts` |
| Chain/contracts | `lib/contracts.ts` + banner |
| Indexer charts | `lib/indexer.ts` + chart components |

CSS modules per component + global variables. No Tailwind required.

### System / Admin (data-dense)

- Dense 12-col grid, compact tables, KPI strip, role matrix cards
- Status pills for pause / authorization (not color alone — include text)
- Admin cards disabled + labeled when wallet lacks role
- No decorative cards; interaction panels only
