export function XdcLogo({ size = 28 }: { size?: number }) {
  return (
    // Official XDC mark (CoinMarketCap #2634)
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src="/xdc.png"
      alt=""
      width={size}
      height={size}
      aria-hidden
      style={{ width: size, height: size, borderRadius: "50%", display: "block" }}
    />
  );
}
