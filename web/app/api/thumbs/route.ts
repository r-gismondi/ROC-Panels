import { ensureThumbCaptures } from "@/lib/thumbs"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function POST() {
  await ensureThumbCaptures()
  return NextResponse.json({ ok: true })
}
