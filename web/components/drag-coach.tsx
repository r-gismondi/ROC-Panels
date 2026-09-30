"use client"

import { useEffect, useRef, useState } from "react"
import { programIconClass, programIconSrc } from "@/lib/c-connect"

function ProgramMark({ id }: { id: string }) {
  const [hidden, setHidden] = useState(false)
  if (hidden) return <span className="h-6 w-6 shrink-0" />
  return (
    <img
      src={programIconSrc(id)}
      alt=""
      draggable={false}
      className={programIconClass(id)}
      onError={() => setHidden(true)}
    />
  )
}

const LOOP = 3800

export function DragCoach({ name, id }: { name: string; id: string }) {
  const stageRef = useRef<HTMLDivElement>(null)
  const tiles = ["1", "2", "3", "4"]

  useEffect(() => {
    const stage = stageRef.current
    if (!stage) return
    const chip = stage.querySelector<HTMLElement>("[data-coach='chip']")
    const cursor = stage.querySelector<HTMLElement>("[data-coach='cursor']")
    const press = stage.querySelector<HTMLElement>("[data-coach='press']")
    const hot = stage.querySelector<HTMLElement>("[data-coach='hot']")
    if (!chip || !cursor || !press || !hot) return
    const animations = [
      chip.animate(
        [
          { left: "4%", top: "64%", transform: "scale(1)", offset: 0 },
          { left: "4%", top: "64%", transform: "scale(1)", offset: 0.16 },
          { left: "4%", top: "66%", transform: "scale(0.96)", offset: 0.24 },
          { left: "46%", top: "8%", transform: "scale(1)", offset: 0.68 },
          { left: "46%", top: "8%", transform: "scale(1)", offset: 0.8 },
          { left: "4%", top: "64%", transform: "scale(1)", offset: 1 },
        ],
        { duration: LOOP, iterations: Infinity, easing: "ease-in-out" },
      ),
      cursor.animate(
        [
          { left: "28%", top: "42%", transform: "scale(1)", offset: 0 },
          { left: "12%", top: "68%", transform: "scale(0.92)", offset: 0.16 },
          { left: "12%", top: "68%", transform: "scale(0.92)", offset: 0.24 },
          { left: "54%", top: "16%", transform: "scale(1)", offset: 0.68 },
          { left: "54%", top: "16%", transform: "scale(1)", offset: 0.8 },
          { left: "28%", top: "42%", transform: "scale(1)", offset: 1 },
        ],
        { duration: LOOP, iterations: Infinity, easing: "ease-in-out" },
      ),
      press.animate(
        [
          { opacity: 0, transform: "scale(0.4)", offset: 0 },
          { opacity: 0, transform: "scale(0.4)", offset: 0.18 },
          { opacity: 0.9, transform: "scale(1)", offset: 0.26 },
          { opacity: 0, transform: "scale(0.4)", offset: 0.36 },
          { opacity: 0, transform: "scale(0.4)", offset: 1 },
        ],
        { duration: LOOP, iterations: Infinity, easing: "ease-out" },
      ),
      hot.animate(
        [
          { borderColor: "rgba(103, 232, 249, 0.4)", boxShadow: "none", offset: 0 },
          { borderColor: "rgba(103, 232, 249, 0.4)", boxShadow: "none", offset: 0.64 },
          { borderColor: "#ffffff", boxShadow: "0 0 16px rgba(126, 232, 255, 0.9)", offset: 0.74 },
          { borderColor: "#ffffff", boxShadow: "0 0 16px rgba(126, 232, 255, 0.9)", offset: 0.86 },
          { borderColor: "rgba(103, 232, 249, 0.4)", boxShadow: "none", offset: 1 },
        ],
        { duration: LOOP, iterations: Infinity, easing: "ease-in-out" },
      ),
    ]
    return () => animations.forEach((animation) => animation.cancel())
  }, [])

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden rounded-xl border border-cyan-300/80 bg-[#071a4d]/55 shadow-[0_0_24px_rgba(80,200,255,0.16)]">
      <p className="px-3 pt-3 text-[11px] tracking-[0.18em] text-cyan-100/70">DRAG ONTO A SCREEN</p>
      <div ref={stageRef} className="relative min-h-0 flex-1">
        <div className="grid grid-cols-4 gap-2 px-4 pt-3">
          {tiles.map((tile) => (
            <div
              key={tile}
              data-coach={tile === "3" ? "hot" : undefined}
              className="flex h-16 items-end rounded-sm border border-cyan-300/40 bg-[#0a2f86]/55 px-1 pb-1 text-[10px] text-cyan-50/80"
            >
              {tile}
            </div>
          ))}
        </div>
        <div className="pointer-events-none absolute bottom-4 left-4 flex max-w-[10rem] items-center gap-2 rounded-lg border border-cyan-300/25 bg-[#08245f]/45 px-2 py-1.5 text-xs text-cyan-50/45">
          <ProgramMark id={id} />
          <span className="truncate">{name}</span>
        </div>
        <div
          data-coach="chip"
          className="pointer-events-none absolute left-[4%] top-[64%] flex max-w-[10rem] items-center gap-2 rounded-lg border border-cyan-200 bg-cyan-400/25 px-2 py-1.5 text-xs shadow-[0_10px_24px_rgba(0,0,0,0.35)]"
        >
          <ProgramMark id={id} />
          <span className="truncate">{name}</span>
        </div>
        <div data-coach="cursor" className="pointer-events-none absolute left-[28%] top-[42%]">
          <span data-coach="press" className="absolute left-0.5 top-1 h-2.5 w-2.5 rounded-full border-2 border-cyan-100 opacity-0" />
          <svg viewBox="0 0 24 24" className="h-7 w-7 fill-white drop-shadow-[0_2px_2px_rgba(0,0,0,0.65)]" aria-hidden="true">
            <path d="M5.2 2.8 19.4 11.2 12.2 12.6 16.4 21.2 13.2 22.6 8.8 13.6 5.2 16.4Z" />
          </svg>
        </div>
      </div>
    </div>
  )
}
