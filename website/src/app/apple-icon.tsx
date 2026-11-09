import { ImageResponse } from "next/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    (
      <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center", background: "#000" }}>
        <div style={{ width: 104, height: 104, borderRadius: 104, border: "14px solid #fff", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ width: 38, height: 38, borderRadius: 38, background: "#fff" }} />
        </div>
      </div>
    ),
    size,
  );
}
