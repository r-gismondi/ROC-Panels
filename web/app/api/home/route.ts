import { NextResponse } from "next/server"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type Listener = ReadableStreamDefaultController<Uint8Array>

const store = globalThis as typeof globalThis & { homeListeners?: Set<Listener> }
const listeners = (store.homeListeners ??= new Set<Listener>())
const encoder = new TextEncoder()

function send(listener: Listener, text: string) {
  try {
    listener.enqueue(encoder.encode(text))
  } catch {
    listeners.delete(listener)
  }
}

export function GET(request: Request) {
  let ping: ReturnType<typeof setInterval> | undefined
  let self: Listener | undefined
  const stop = () => {
    if (ping) clearInterval(ping)
    if (self) listeners.delete(self)
  }
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      self = controller
      listeners.add(controller)
      send(controller, ": ready\n\n")
      ping = setInterval(() => send(controller, ": ping\n\n"), 25000)
      request.signal.addEventListener("abort", stop)
    },
    cancel: stop,
  })
  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  })
}

export function POST() {
  for (const listener of [...listeners]) send(listener, "data: home\n\n")
  return NextResponse.json({ ok: true })
}
