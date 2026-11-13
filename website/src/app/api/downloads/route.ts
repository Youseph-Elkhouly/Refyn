import { NextResponse } from "next/server";
import { initialDownloadCount } from "@/lib/downloadCount";

const KEY = "refyn:download-count";

async function redisCommand(...command: (string | number)[]) {
  const url = process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token) throw new Error("Download counter storage is not configured");

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`Download counter storage returned ${response.status}`);
  const payload = (await response.json()) as { result?: unknown; error?: string };
  if (payload.error) throw new Error(payload.error);
  return payload.result;
}

function unavailable() {
  return NextResponse.json({ error: "Download counter is not configured" }, { status: 503 });
}

export async function GET() {
  try {
    const value = await redisCommand("GET", KEY);
    const count = value === null ? initialDownloadCount : Number(value);
    if (!Number.isSafeInteger(count) || count < 0) throw new Error("Invalid stored download count");
    return NextResponse.json({ count }, { headers: { "Cache-Control": "no-store, max-age=0" } });
  } catch {
    return unavailable();
  }
}

export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return NextResponse.json({ error: "Cross-origin counter updates are not allowed" }, { status: 403 });
  }

  try {
    // Seed once; concurrent clicks remain safe because SET NX only initializes the key once.
    await redisCommand("SET", KEY, initialDownloadCount, "NX");
    const count = Number(await redisCommand("INCR", KEY));
    if (!Number.isSafeInteger(count) || count < initialDownloadCount) throw new Error("Invalid stored download count");
    return NextResponse.json({ count }, { headers: { "Cache-Control": "no-store, max-age=0" } });
  } catch {
    return unavailable();
  }
}
