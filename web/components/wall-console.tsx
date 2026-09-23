"use client"

import { useState } from "react"
import { Slider } from "@/components/ui/slider"

type WallId = 1 | 2

type Screen = { id: string; hdmi: string }

type Preset = { id: string; name: string; groups: Record<string, number> }

const GROUP_COLOR = ["#3ec8ff", "#d56bff", "#7eb6ff", "#5eead4", "#f0c27a"]

const WALL_1: Screen[][] = [
  [
    { id: "TV1", hdmi: "HDMI 1" },
    { id: "TV2", hdmi: "HDMI 1" },
    { id: "TV3", hdmi: "HDMI 2" },
    { id: "TV4", hdmi: "HDMI 2" },
  ],
  [
    { id: "TV5", hdmi: "HDMI 1" },
    { id: "TV6", hdmi: "HDMI 1" },
    { id: "TV7", hdmi: "HDMI 2" },
    { id: "TV8", hdmi: "HDMI 2" },
  ],
]

const WALL_2: Screen[][] = [
  [
    { id: "TV9", hdmi: "HDMI 1" },
    { id: "TV10", hdmi: "HDMI 1" },
    { id: "TV11", hdmi: "HDMI 2" },
    { id: "TV12", hdmi: "HDMI 2" },
    { id: "TV13", hdmi: "C3 HDMI 1" },
  ],
  [
    { id: "TV14", hdmi: "HDMI 1" },
    { id: "TV15", hdmi: "HDMI 1" },
    { id: "TV16", hdmi: "HDMI 2" },
    { id: "TV17", hdmi: "HDMI 2" },
    { id: "TV18", hdmi: "C3 HDMI 2" },
  ],
]

function groups(ids: string[], buckets: string[][]): Record<string, number> {
  const map: Record<string, number> = {}
  buckets.forEach((bucket, index) => bucket.forEach((id) => (map[id] = index)))
  ids.forEach((id, index) => {
    if (!(id in map)) map[id] = index
  })
  return map
}

const IDS1 = WALL_1.flat().map((screen) => screen.id)
const IDS2 = WALL_2.flat().map((screen) => screen.id)

const PRESETS: Record<WallId, Preset[]> = {
  1: [
    { id: "independent", name: "Independent", groups: groups(IDS1, IDS1.map((id) => [id])) },
    { id: "split", name: "Split", groups: groups(IDS1, [["TV1", "TV2", "TV5", "TV6"], ["TV3", "TV4", "TV7", "TV8"]]) },
    { id: "focus", name: "Focus", groups: groups(IDS1, [["TV1", "TV5"], ["TV2", "TV3", "TV6", "TV7"], ["TV4", "TV8"]]) },
    {
      id: "focus-split",
      name: "Focus split",
      groups: groups(IDS1, [["TV1"], ["TV5"], ["TV2", "TV3", "TV6", "TV7"], ["TV4"], ["TV8"]]),
    },
    { id: "full", name: "Full", groups: groups(IDS1, [IDS1]) },
  ],
  2: [
    { id: "independent", name: "Independent", groups: groups(IDS2, IDS2.map((id) => [id])) },
    {
      id: "dual-1",
      name: "Dual focus 1",
      groups: groups(IDS2, [
        ["TV9", "TV10", "TV14", "TV15"],
        ["TV11", "TV16"],
        ["TV12", "TV13", "TV17", "TV18"],
      ]),
    },
    {
      id: "dual-2",
      name: "Dual focus 2",
      groups: groups(IDS2, [
        ["TV9", "TV10", "TV14", "TV15"],
        ["TV11", "TV12", "TV16", "TV17"],
        ["TV13", "TV18"],
      ]),
    },
    {
      id: "dual-3",
      name: "Dual focus 3",
      groups: groups(IDS2, [
        ["TV9", "TV14"],
        ["TV10", "TV11", "TV15", "TV16"],
        ["TV12", "TV13", "TV17", "TV18"],
      ]),
    },
    { id: "full", name: "Full", groups: groups(IDS2, [IDS2]) },
  ],
}

export function WallConsole() {
  const [wall, setWall] = useState<WallId>(1)
  const [selected, setSelected] = useState<string | null>(null)
  const [preset, setPreset] = useState<Record<WallId, string>>({ 1: "focus", 2: "dual-2" })
  const [power, setPower] = useState<Record<WallId, boolean>>({ 1: true, 2: true })
  const [brightness, setBrightness] = useState<Record<WallId, number>>({ 1: 80, 2: 80 })

  const screens = wall === 1 ? WALL_1.flat() : WALL_2.flat()
  const current = screens.find((screen) => screen.id === selected) ?? null
  const activePreset = PRESETS[wall].find((item) => item.id === preset[wall]) ?? PRESETS[wall][0]

  function chooseScreen(nextWall: WallId, id: string) {
    setWall(nextWall)
    setSelected(id)
  }

  return (
    <main className="flex min-h-svh flex-col bg-[radial-gradient(circle_at_top,#1650c8_0%,#06215f_42%,#03102e_100%)] text-white">
      <header className="flex items-center justify-between gap-4 border-b border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="flex items-center gap-3">
          <span className="grid size-9 place-items-center rounded-full border border-cyan-300/70 shadow-[0_0_16px_rgba(80,200,255,0.45)]">
            <span className="size-3 rounded-full bg-cyan-300" />
          </span>
          <div>
            <p className="text-sm font-semibold tracking-[0.16em]">OPERATIONS FLOOR</p>
            <p className="text-[11px] tracking-[0.22em] text-cyan-100/70">WALL CONTROL</p>
          </div>
        </div>
        <p className="hidden text-xs tracking-[0.18em] text-cyan-100/70 sm:block">THIS STAND</p>
      </header>

      <section className="grid flex-1 gap-4 px-4 py-4 lg:grid-cols-[1.2fr_0.8fr_1.35fr] lg:px-6">
        <Wall
          title="Left wall"
          detail="Panel 1 · 192.168.0.101"
          rows={WALL_1}
          preset={PRESETS[1].find((item) => item.id === preset[1])!}
          active={wall === 1}
          selected={selected}
          powered={power[1]}
          onSelect={(id) => chooseScreen(1, id)}
        />

        <div className="flex flex-col justify-center gap-4 rounded-2xl border border-cyan-300/40 bg-[#0a2f86]/55 p-4 shadow-[0_0_28px_rgba(40,140,255,0.25)]">
          <div>
            <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">SELECTED SCREEN</p>
            <h1 className="mt-1 text-3xl font-semibold tracking-wide">{current ? current.id : "Tap a screen"}</h1>
            <p className="mt-1 text-sm text-cyan-100/80">
              {current
                ? `${wall === 1 ? "Left wall" : "Right wall"} · ${current.hdmi}`
                : "Power, brightness, and the window preset apply to the wall you touch."}
            </p>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <GlowButton active={power[wall]} onClick={() => setPower((value) => ({ ...value, [wall]: true }))}>
              On
            </GlowButton>
            <GlowButton active={!power[wall]} tone="alert" onClick={() => setPower((value) => ({ ...value, [wall]: false }))}>
              Off
            </GlowButton>
          </div>

          <div>
            <div className="mb-2 flex items-baseline justify-between text-sm">
              <span>Brightness</span>
              <span className="font-mono text-cyan-100">{brightness[wall]}%</span>
            </div>
            <Slider
              min={0}
              max={100}
              value={[brightness[wall]]}
              onValueChange={(value) => {
                const next = Array.isArray(value) ? value[0] : value
                setBrightness((current) => ({ ...current, [wall]: next }))
              }}
              aria-label="Brightness"
            />
          </div>

          <p className="text-xs leading-5 text-cyan-100/70">
            {power[wall] ? "Power on" : "Power off"} staged for the {wall === 1 ? "left" : "right"} wall.
            Nothing is sent to the panels or the window computers yet.
          </p>
        </div>

        <Wall
          title="Right wall"
          detail="Panel 2 · 192.168.0.102 and .103"
          rows={WALL_2}
          preset={PRESETS[2].find((item) => item.id === preset[2])!}
          active={wall === 2}
          selected={selected}
          powered={power[2]}
          onSelect={(id) => chooseScreen(2, id)}
        />
      </section>

      <footer className="border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="mb-2 flex items-center justify-between gap-3">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">
            {wall === 1 ? "LEFT WALL PRESETS" : "RIGHT WALL PRESETS"}
          </p>
          <p className="text-xs text-cyan-100/70">{activePreset.name}</p>
        </div>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
          {PRESETS[wall].map((item) => (
            <GlowButton
              key={item.id}
              active={item.id === preset[wall]}
              onClick={() => setPreset((current) => ({ ...current, [wall]: item.id }))}
            >
              {item.name}
            </GlowButton>
          ))}
        </div>
      </footer>
    </main>
  )
}

function Wall({
  title,
  detail,
  rows,
  preset,
  active,
  selected,
  powered,
  onSelect,
}: {
  title: string
  detail: string
  rows: Screen[][]
  preset: Preset
  active: boolean
  selected: string | null
  powered: boolean
  onSelect: (id: string) => void
}) {
  return (
    <section
      className={`rounded-2xl border bg-[#071a4d]/70 p-3 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
        active ? "border-cyan-300/70" : "border-cyan-300/25"
      }`}
    >
      <div className="mb-3 flex items-end justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">{title}</h2>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">{powered ? "ON" : "OFF"}</span>
      </div>
      <div className="flex flex-col gap-2">
        {rows.map((row) => (
          <div key={row[0].id} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
            {row.map((screen) => {
              const group = preset.groups[screen.id] ?? 0
              const color = GROUP_COLOR[group % GROUP_COLOR.length]
              const isSelected = selected === screen.id
              return (
                <button
                  key={screen.id}
                  type="button"
                  onClick={() => onSelect(screen.id)}
                  className="min-h-16 rounded-lg border px-1 py-2 text-center transition"
                  style={{
                    borderColor: isSelected ? "#ffffff" : color,
                    background: powered ? `${color}33` : "rgba(0,0,0,0.35)",
                    boxShadow: isSelected ? `0 0 16px ${color}` : undefined,
                  }}
                >
                  <span className="block text-sm font-semibold">{screen.id.replace("TV", "")}</span>
                  <span className="block text-[10px] text-cyan-50/80">{screen.hdmi}</span>
                </button>
              )
            })}
          </div>
        ))}
      </div>
    </section>
  )
}

function GlowButton({
  children,
  active,
  onClick,
  tone = "normal",
}: {
  children: string
  active?: boolean
  onClick: () => void
  tone?: "normal" | "alert"
}) {
  const alert = tone === "alert"
  return (
    <button
      type="button"
      onClick={onClick}
      className={`min-h-11 rounded-lg border px-3 text-sm tracking-wide transition ${
        active
          ? alert
            ? "border-fuchsia-300 bg-fuchsia-500/30 shadow-[0_0_16px_rgba(220,80,255,0.35)]"
            : "border-cyan-200 bg-cyan-400/25 shadow-[0_0_16px_rgba(80,200,255,0.35)]"
          : "border-cyan-300/35 bg-[#08245f]/80 hover:border-cyan-200/70"
      }`}
    >
      {children}
    </button>
  )
}
