"use client"

import { useEffect, useRef } from "react"
import { presetZones, type Preset, type Screen } from "@/lib/preset-zones"

const LOOP = 4600

export function PresetCoach({ rows, preset }: { rows: Screen[][]; preset: Preset }) {
  const stageRef = useRef<HTMLDivElement>(null)
  const columns = rows.reduce((count, row) => Math.max(count, row.length), 1)
  const zones = presetZones(rows, preset)

  useEffect(() => {
    const stage = stageRef.current
    if (!stage) return
    const cursor = stage.querySelector<HTMLElement>("[data-coach='cursor']")
    const press = stage.querySelector<HTMLElement>("[data-coach='press']")
    const confirm = stage.querySelector<HTMLElement>("[data-coach='confirm']")
    if (!cursor || !press || !confirm) return
    const timing = { duration: LOOP, iterations: Infinity, easing: "ease-in-out" }
    const animations = [
      ...[...stage.querySelectorAll<HTMLElement>("[data-coach='zone']")].map((zone, index) =>
        zone.animate(
          [
            { opacity: 0, transform: "scale(0.86)", offset: 0 },
            { opacity: 0, transform: "scale(0.86)", offset: 0.1 },
            { opacity: 1, transform: "scale(1.04)", offset: 0.22 },
            { opacity: 1, transform: "scale(1)", offset: 0.28 },
            { opacity: 1, transform: "scale(1)", offset: 0.9 },
            { opacity: 0, transform: "scale(1)", offset: 1 },
          ],
          { ...timing, delay: index * 90 },
        ),
      ),
      ...[...stage.querySelectorAll<HTMLElement>("[data-coach='window']")].map((frame) =>
        frame.animate(
          [
            { opacity: 0, offset: 0 },
            { opacity: 0, offset: 0.6 },
            { opacity: 1, offset: 0.68 },
            { opacity: 1, offset: 0.9 },
            { opacity: 0, offset: 1 },
          ],
          timing,
        ),
      ),
      cursor.animate(
        [
          { left: "34%", top: "24%", transform: "scale(1)", offset: 0 },
          { left: "34%", top: "24%", transform: "scale(1)", offset: 0.3 },
          { left: "10%", top: "80%", transform: "scale(1)", offset: 0.5 },
          { left: "10%", top: "80%", transform: "scale(0.92)", offset: 0.55 },
          { left: "10%", top: "80%", transform: "scale(1)", offset: 0.9 },
          { left: "34%", top: "24%", transform: "scale(1)", offset: 1 },
        ],
        timing,
      ),
      press.animate(
        [
          { opacity: 0, transform: "scale(0.4)", offset: 0 },
          { opacity: 0, transform: "scale(0.4)", offset: 0.52 },
          { opacity: 0.9, transform: "scale(1)", offset: 0.57 },
          { opacity: 0, transform: "scale(0.4)", offset: 0.66 },
          { opacity: 0, transform: "scale(0.4)", offset: 1 },
        ],
        { ...timing, easing: "ease-out" },
      ),
      confirm.animate(
        [
          { borderColor: "rgba(165, 243, 252, 0.6)", boxShadow: "none", offset: 0 },
          { borderColor: "rgba(165, 243, 252, 0.6)", boxShadow: "none", offset: 0.54 },
          { borderColor: "#ffffff", boxShadow: "0 0 16px rgba(126, 232, 255, 0.9)", offset: 0.6 },
          { borderColor: "#ffffff", boxShadow: "0 0 16px rgba(126, 232, 255, 0.9)", offset: 0.88 },
          { borderColor: "rgba(165, 243, 252, 0.6)", boxShadow: "none", offset: 1 },
        ],
        timing,
      ),
    ]
    return () => animations.forEach((animation) => animation.cancel())
  }, [rows, preset])

  return (
    <div className="flex h-full min-h-56 flex-col overflow-hidden rounded-xl border border-cyan-300/80 bg-[#071a4d]/55 shadow-[0_0_24px_rgba(80,200,255,0.16)]">
      <p className="px-3 pt-3 text-[11px] tracking-[0.18em] text-cyan-100/70">PREVIEW · EACH COLORED BOX IS ONE EDGE WINDOW</p>
      <div ref={stageRef} className="relative min-h-48 flex-1">
        <div
          className="relative mx-auto mt-3 grid gap-x-3 gap-y-1.5"
          style={{
            gridTemplateColumns: `repeat(${columns}, 4.5rem)`,
            gridTemplateRows: `repeat(${rows.length}, auto)`,
            justifyContent: "center",
          }}
        >
          {rows.map((row, r) =>
            row.map((screen, c) => (
              <div
                key={screen.id}
                className="flex aspect-video items-end rounded-sm border border-cyan-300/40 bg-[#0a2f86]/55 px-1 pb-0.5 text-[10px] text-cyan-50/80"
                style={{ gridRow: r + 1, gridColumn: c + 1 }}
              >
                {screen.id.replace("TV", "")}
              </div>
            )),
          )}
          {zones.map((zone, index) => (
            <div
              key={zone.key}
              data-coach="zone"
              className="pointer-events-none absolute overflow-hidden rounded-sm border-2 opacity-0"
              style={{
                gridRow: `${zone.row} / span ${zone.rows}`,
                gridColumn: `${zone.col} / span ${zone.cols}`,
                top: 0,
                right: 0,
                bottom: 0,
                left: 0,
                borderColor: zone.color,
                background: `${zone.color}26`,
                boxShadow: `0 0 6px ${zone.color}`,
              }}
            >
              <span
                className="absolute top-0.5 left-0.5 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[10px] font-semibold leading-none text-[#03102e]"
                style={{ background: zone.color }}
              >
                {index + 1}
              </span>
              <span data-coach="window" className="absolute inset-0 flex flex-col opacity-0">
                <span className="h-2 w-full bg-white/85" />
                <span className="flex flex-1 items-center justify-center text-[10px] font-semibold tracking-[0.14em] text-white">EDGE</span>
              </span>
            </div>
          ))}
        </div>
        <span
          data-coach="confirm"
          className="pointer-events-none absolute left-4 bottom-4 rounded-lg border border-cyan-200/60 bg-cyan-400/25 px-4 py-2 text-sm tracking-wide"
        >
          Confirm
        </span>
        <p className="absolute right-4 bottom-4 left-32 text-xs leading-5 text-cyan-100/80">
          The screens show the preview. Confirm opens Edge in these windows. Cancel keeps the current layout.
        </p>
        <div data-coach="cursor" className="pointer-events-none absolute left-[34%] top-[24%]">
          <span data-coach="press" className="absolute left-0.5 top-1 h-2.5 w-2.5 rounded-full border-2 border-cyan-100 opacity-0" />
          <svg viewBox="0 0 24 24" className="h-7 w-7 fill-white drop-shadow-[0_2px_2px_rgba(0,0,0,0.65)]" aria-hidden="true">
            <path d="M5.2 2.8 19.4 11.2 12.2 12.6 16.4 21.2 13.2 22.6 8.8 13.6 5.2 16.4Z" />
          </svg>
        </div>
      </div>
    </div>
  )
}
