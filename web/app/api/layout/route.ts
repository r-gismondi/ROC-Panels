import { launchLayout, readLayoutState } from "@/lib/launch-layout"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function GET() {
  return NextResponse.json({ layouts: readLayoutState() })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { computer?: unknown; preset?: unknown } | null
  if (!body || typeof body.computer !== "string" || typeof body.preset !== "string") {
    return NextResponse.json({ error: "Pick a preset." }, { status: 400 })
  }
  const result = await launchLayout(body.computer, body.preset)
  if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
  return NextResponse.json({ message: result.message })
}
