import { ImageResponse } from "next/og";

export const alt = "Refyn: Better prompts. Better results. The AI prompt optimizer that lives in your Mac's notch.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", background: "#000", color: "#fff", padding: "0 72px", position: "relative" }}>
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 420,
            width: 360,
            height: 62,
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "0 26px",
            background: "#fff",
            borderBottomLeftRadius: 22,
            borderBottomRightRadius: 22,
          }}
        >
          <div style={{ width: 24, height: 24, borderRadius: 24, border: "3px solid #000", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <div style={{ width: 8, height: 8, borderRadius: 8, background: "#000" }} />
          </div>
          <div style={{ width: 11, height: 11, borderRadius: 11, background: "#000" }} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", marginTop: 190, fontSize: 118, fontWeight: 700, letterSpacing: -5, lineHeight: 1 }}>
          <span style={{ color: "#8c8c8c" }}>Better prompts.</span>
          <span>Better results.</span>
        </div>
        <div style={{ display: "flex", marginTop: 36, fontSize: 34, color: "#8c8c8c", letterSpacing: -0.6 }}>The AI prompt optimizer that lives in your Mac&apos;s notch.</div>
      </div>
    ),
    size,
  );
}
