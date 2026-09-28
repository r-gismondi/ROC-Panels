import { controlDisplays, describeControl, screenList } from "@/lib/display-control"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

const WALL = Array.from({ length: 18 }, (_, index) => `TV${index + 1}`)

export async function GET() {
  const result = await controlDisplays({ action: "read", screens: WALL })
  if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
  const screens: Record<string, { power: boolean; brightness: number }> = {}
  for (const row of result.results) {
    if (row.ok && typeof row.power === "boolean" && typeof row.brightness === "number") {
      screens[row.screen] = { power: row.power, brightness: row.brightness }
    }
  }
  return NextResponse.json({ screens })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { screens?: unknown; power?: unknown; brightness?: unknown } | null
  const screens = screenList(body?.screens)
  if (!body || !screens) return NextResponse.json({ error: "Pick a screen on this wall." }, { status: 400 })
  const power = body.power
  const brightness = body.brightness
  const hasPower = typeof power === "boolean"
  const hasBrightness = typeof brightness === "number" && Number.isInteger(brightness) && brightness >= 0 && brightness <= 100
  if (!hasPower && !hasBrightness) {
    return NextResponse.json({ error: "Pick power or a brightness from 0 to 100." }, { status: 400 })
  }
  const result = await controlDisplays({
    action: "set",
    screens,
    ...(hasPower ? { power } : {}),
    ...(hasBrightness ? { brightness } : {}),
  })
  if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
  const failed = result.results.filter((row) => !row.ok).map((row) => row.screen)
  const message = describeControl(hasPower ? power : null, hasBrightness ? brightness : null, result.results)
  if (failed.length === screens.length) return NextResponse.json({ error: message, failed }, { status: 400 })
  return NextResponse.json({ message, failed })
}
