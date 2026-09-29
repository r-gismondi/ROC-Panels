"use client"

import { useState } from "react"

function ProgramMark({ id }: { id: string }) {
  const [hidden, setHidden] = useState(false)
  if (hidden) return <span className="h-6 w-6 shrink-0" />
  return (
    <img
      src={`/api/apps/icon?id=${encodeURIComponent(id)}`}
      alt=""
      draggable={false}
      className="h-6 w-6 shrink-0"
      onError={() => setHidden(true)}
    />
  )
}

export function DragCoach({ name, id }: { name: string; id: string }) {
  const tiles = ["1", "2", "3", "4"]
  return (
    <div className="flex h-full min-h-56 flex-col overflow-hidden rounded-xl border border-cyan-300/80 bg-[#071a4d]/55 shadow-[0_0_24px_rgba(80,200,255,0.16)]">
      <p className="px-3 pt-3 text-[11px] tracking-[0.18em] text-cyan-100/70">DRAG ONTO A SCREEN</p>
      <div className="relative min-h-48 flex-1">
        <div className="grid grid-cols-4 gap-2 px-4 pt-3">
          {tiles.map((tile) => (
            <div
              key={tile}
              className={`flex h-16 items-end rounded-sm border border-cyan-300/40 bg-[#0a2f86]/55 px-1 pb-1 text-[10px] text-cyan-50/80 ${tile === "3" ? "coach-hot" : ""}`}
            >
              {tile}
            </div>
          ))}
        </div>
        <div className="pointer-events-none absolute bottom-4 left-4 flex max-w-[10rem] items-center gap-2 rounded-lg border border-cyan-300/25 bg-[#08245f]/45 px-2 py-1.5 text-xs text-cyan-50/45">
          <ProgramMark id={id} />
          <span className="truncate">{name}</span>
        </div>
        <div className="coach-chip pointer-events-none absolute flex max-w-[10rem] items-center gap-2 rounded-lg border border-cyan-200 bg-cyan-400/25 px-2 py-1.5 text-xs shadow-[0_10px_24px_rgba(0,0,0,0.35)]">
          <ProgramMark id={id} />
          <span className="truncate">{name}</span>
        </div>
        <div className="coach-cursor pointer-events-none absolute">
          <svg viewBox="0 0 24 24" className="h-7 w-7 fill-white drop-shadow-[0_2px_2px_rgba(0,0,0,0.65)]" aria-hidden="true">
            <path d="M5.2 2.8 19.4 11.2 12.2 12.6 16.4 21.2 13.2 22.6 8.8 13.6 5.2 16.4Z" />
          </svg>
        </div>
      </div>
    </div>
  )
}
