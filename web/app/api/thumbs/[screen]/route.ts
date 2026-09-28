import { NextResponse } from "next/server"
import { readThumb } from "@/lib/thumbs"

export const runtime = "nodejs"

export async function GET(_request: Request, context: { params: Promise<{ screen: string }> }) {
  const { screen } = await context.params
  const bytes = await readThumb(screen)
  if (!bytes) return new NextResponse(null, { status: 404 })
  return new NextResponse(new Uint8Array(bytes), {
    headers: {
      "Content-Type": "image/jpeg",
      "Cache-Control": "no-store",
    },
  })
}
