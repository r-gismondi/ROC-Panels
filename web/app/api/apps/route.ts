import { browseForProgram, launchPinned, listedPins, removePin } from "@/lib/pinned-apps"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function GET() {
  return NextResponse.json({ pins: listedPins() })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { action?: unknown; id?: unknown; screen?: unknown } | null
  if (!body || typeof body.action !== "string") {
    return NextResponse.json({ error: "Choose a program." }, { status: 400 })
  }
  if (body.action === "browse") {
    const result = await browseForProgram()
    if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
    return NextResponse.json({ pins: result.pins, selectedId: result.selectedId, canceled: Boolean(result.canceled) })
  }
  if (body.action === "remove") {
    if (typeof body.id !== "string") return NextResponse.json({ error: "Choose a program." }, { status: 400 })
    return NextResponse.json({ pins: removePin(body.id) })
  }
  if (body.action === "launch") {
    if (typeof body.id !== "string" || typeof body.screen !== "string") {
      return NextResponse.json({ error: "Choose a program, then tap a screen." }, { status: 400 })
    }
    const result = await launchPinned(body.id, body.screen)
    if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
    return NextResponse.json({ message: result.message })
  }
  return NextResponse.json({ error: "Choose a program." }, { status: 400 })
}
