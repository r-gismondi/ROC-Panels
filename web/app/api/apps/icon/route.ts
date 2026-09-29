import { readProgramIcon } from "@/lib/pinned-apps"
import { NextResponse } from "next/server"

export const runtime = "nodejs"

export async function GET(request: Request) {
  const id = new URL(request.url).searchParams.get("id") ?? ""
  const bytes = await readProgramIcon(id)
  if (!bytes) return new NextResponse(null, { status: 404 })
  return new NextResponse(new Uint8Array(bytes), {
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "private, max-age=86400",
    },
  })
}
