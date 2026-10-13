import { openRemote } from "@/lib/launch-layout"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { computer?: unknown } | null
  if (!body || typeof body.computer !== "string") {
    return NextResponse.json({ error: "Pick a panel." }, { status: 400 })
  }
  const result = openRemote(body.computer)
  if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
  return NextResponse.json({ message: result.message })
}
