import { readAddresses, setLayoutAddress } from "@/lib/launch-layout"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function GET(request: Request) {
  const computer = new URL(request.url).searchParams.get("computer") ?? ""
  if (computer !== "101" && computer !== "102" && computer !== "103") {
    return NextResponse.json({ error: "Pick a screen group." }, { status: 400 })
  }
  return NextResponse.json({ addresses: readAddresses(computer) })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { computer?: unknown; screen?: unknown; url?: unknown } | null
  if (!body || typeof body.computer !== "string" || typeof body.screen !== "string" || typeof body.url !== "string") {
    return NextResponse.json({ error: "Pick a screen and an address." }, { status: 400 })
  }
  const result = await setLayoutAddress(body.computer, body.screen, body.url)
  if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
  return NextResponse.json({ message: result.message })
}
