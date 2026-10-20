import { addLink, launchLink, readLinks, removeLink } from "@/lib/saved-links"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function GET() {
  return NextResponse.json({ links: readLinks() })
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as {
    action?: unknown
    id?: unknown
    name?: unknown
    url?: unknown
    screen?: unknown
  } | null
  if (!body || typeof body.action !== "string") {
    return NextResponse.json({ error: "Choose a site." }, { status: 400 })
  }
  if (body.action === "add") {
    if (typeof body.name !== "string" || typeof body.url !== "string") {
      return NextResponse.json({ error: "Type a name and an address." }, { status: 400 })
    }
    const result = addLink(body.name, body.url)
    if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
    return NextResponse.json({ links: result.links, selectedId: result.selectedId })
  }
  if (body.action === "remove") {
    if (typeof body.id !== "string") return NextResponse.json({ error: "Choose a site." }, { status: 400 })
    return NextResponse.json({ links: removeLink(body.id) })
  }
  if (body.action === "launch") {
    if (typeof body.id !== "string" || typeof body.screen !== "string") {
      return NextResponse.json({ error: "Choose a site, then tap a screen." }, { status: 400 })
    }
    const result = await launchLink(body.id, body.screen)
    if (!result.ok) return NextResponse.json({ error: result.message }, { status: 400 })
    return NextResponse.json({ message: result.message })
  }
  return NextResponse.json({ error: "Choose a site." }, { status: 400 })
}
