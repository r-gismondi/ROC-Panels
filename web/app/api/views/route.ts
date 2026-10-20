import { addCustomView, customViewsFor, readCustomViews, removeCustomView } from "@/lib/custom-views"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

function parseBuckets(value: unknown): string[][] | null {
  if (!Array.isArray(value)) return null
  const buckets: string[][] = []
  for (const item of value) {
    if (!Array.isArray(item)) return null
    buckets.push(item.filter((screen): screen is string => typeof screen === "string"))
  }
  return buckets
}

export async function GET(request: Request) {
  const computer = new URL(request.url).searchParams.get("computer")
  if (computer === "101" || computer === "102" || computer === "103") {
    return NextResponse.json({ views: customViewsFor(computer) })
  }
  return NextResponse.json({ views: readCustomViews() })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as {
    action?: unknown
    id?: unknown
    name?: unknown
    computer?: unknown
    groups?: unknown
    screens?: unknown
  } | null
  if (!body || typeof body.action !== "string") {
    return NextResponse.json({ error: "Choose a custom view." }, { status: 400 })
  }
  if (body.action === "add") {
    if (body.computer !== "101" && body.computer !== "102" && body.computer !== "103") {
      return NextResponse.json({ error: "Choose a panel first." }, { status: 400 })
    }
    if (typeof body.name !== "string") {
      return NextResponse.json({ error: "Type a name, then tap screens to add." }, { status: 400 })
    }
    const fromGroups = parseBuckets(body.groups)
    const fromScreens =
      Array.isArray(body.screens) && body.screens.every((item) => typeof item === "string")
        ? [body.screens.filter((item): item is string => typeof item === "string")]
        : null
    const buckets = fromGroups ?? fromScreens
    if (!buckets) {
      return NextResponse.json({ error: "Type a name, then tap screens to add." }, { status: 400 })
    }
    const result = addCustomView(body.computer, body.name, buckets)
    if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
    return NextResponse.json({ views: result.views, selectedId: result.selectedId })
  }
  if (body.action === "remove") {
    if (typeof body.id !== "string") return NextResponse.json({ error: "Choose a custom view." }, { status: 400 })
    return NextResponse.json({ views: removeCustomView(body.id) })
  }
  return NextResponse.json({ error: "Choose a custom view." }, { status: 400 })
}
