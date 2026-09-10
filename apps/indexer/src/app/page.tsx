export default function HomePage() {
  return (
    <main style={{ fontFamily: "system-ui", padding: "2rem", maxWidth: 640 }}>
      <h1>veXDC Indexer</h1>
      <p>
        Read API for positions, protocol TVL/revenue, and adapters. Sync and
        keeper endpoints are cron-authenticated.
      </p>
      <ul>
        <li>
          <code>GET /api/health</code>
        </li>
        <li>
          <code>POST /api/sync</code>
        </li>
        <li>
          <code>GET /api/positions/[address]</code>
        </li>
        <li>
          <code>GET /api/positions/[tokenId]/earnings</code>
        </li>
        <li>
          <code>GET /api/protocol/tvl</code>
        </li>
        <li>
          <code>GET /api/protocol/revenue</code>
        </li>
        <li>
          <code>GET /api/protocol/stakers</code>
        </li>
        <li>
          <code>GET /api/protocol/fees-by-venue</code>
        </li>
        <li>
          <code>GET /api/adapters</code>
        </li>
        <li>
          <code>POST /api/keeper</code>
        </li>
      </ul>
    </main>
  );
}
