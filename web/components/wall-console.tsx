"use client"

import { useState } from "react"
import { Slider } from "@/components/ui/slider"

type PanelId = 1 | 2 | 3

type Screen = { id: string; hdmi: string }

type Preset = { id: string; name: string; groups: Record<string, number> }

type Selection = { panel: PanelId; screen: string | "all" }

const GROUP_COLOR = ["#3ec8ff", "#d56bff", "#7eb6ff", "#5eead4", "#f0c27a"]

const PANEL_1: Screen[][] = [
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

const PANEL_2: Screen[][] = [
  [
    { id: "TV9", hdmi: "HDMI 1" },
    { id: "TV10", hdmi: "HDMI 1" },
    { id: "TV11", hdmi: "HDMI 2" },
    { id: "TV12", hdmi: "HDMI 2" },
  ],
  [
    { id: "TV14", hdmi: "HDMI 1" },
    { id: "TV15", hdmi: "HDMI 1" },
    { id: "TV16", hdmi: "HDMI 2" },
    { id: "TV17", hdmi: "HDMI 2" },
  ],
]

const PANEL_3: Screen[][] = [
  [{ id: "TV13", hdmi: "HDMI 1" }],
  [{ id: "TV18", hdmi: "HDMI 2" }],
]

function groups(ids: string[], buckets: string[][]): Record<string, number> {
  const map: Record<string, number> = {}
  buckets.forEach((bucket, index) => bucket.forEach((id) => (map[id] = index)))
  ids.forEach((id, index) => {
    if (!(id in map)) map[id] = index
  })
  return map
}

const IDS: Record<PanelId, string[]> = {
  1: PANEL_1.flat().map((screen) => screen.id),
  2: PANEL_2.flat().map((screen) => screen.id),
  3: PANEL_3.flat().map((screen) => screen.id),
}

const SCREENS = [...PANEL_1.flat(), ...PANEL_2.flat(), ...PANEL_3.flat()]

function initialPower() {
  return Object.fromEntries(SCREENS.map((screen) => [screen.id, true]))
}

function initialBrightness() {
  return Object.fromEntries(SCREENS.map((screen) => [screen.id, 80]))
}

const PRESETS: Record<PanelId, Preset[]> = {
  1: [
    { id: "independent", name: "Independent", groups: groups(IDS[1], IDS[1].map((id) => [id])) },
    { id: "split", name: "Split", groups: groups(IDS[1], [["TV1", "TV2", "TV5", "TV6"], ["TV3", "TV4", "TV7", "TV8"]]) },
    { id: "focus", name: "Focus", groups: groups(IDS[1], [["TV1", "TV5"], ["TV2", "TV3", "TV6", "TV7"], ["TV4", "TV8"]]) },
    {
      id: "focus-split",
      name: "Focus split",
      groups: groups(IDS[1], [["TV1"], ["TV5"], ["TV2", "TV3", "TV6", "TV7"], ["TV4"], ["TV8"]]),
    },
    { id: "full", name: "Full", groups: groups(IDS[1], [IDS[1]]) },
  ],
  2: [
    { id: "independent", name: "Independent", groups: groups(IDS[2], IDS[2].map((id) => [id])) },
    { id: "split", name: "Split", groups: groups(IDS[2], [["TV9", "TV10", "TV14", "TV15"], ["TV11", "TV12", "TV16", "TV17"]]) },
    { id: "focus", name: "Focus", groups: groups(IDS[2], [["TV9", "TV14"], ["TV10", "TV11", "TV15", "TV16"], ["TV12", "TV17"]]) },
    {
      id: "focus-split",
      name: "Focus split",
      groups: groups(IDS[2], [["TV9"], ["TV14"], ["TV10", "TV11", "TV15", "TV16"], ["TV12"], ["TV17"]]),
    },
    { id: "full", name: "Full", groups: groups(IDS[2], [IDS[2]]) },
  ],
  3: [
    { id: "independent", name: "Independent", groups: groups(IDS[3], [["TV13"], ["TV18"]]) },
    { id: "full", name: "Full", groups: groups(IDS[3], [IDS[3]]) },
  ],
}

export function WallConsole() {
  const [selection, setSelection] = useState<Selection>({ panel: 1, screen: "all" })
  const [preset, setPreset] = useState<Record<PanelId, string>>({ 1: "focus", 2: "focus", 3: "independent" })
  const [power, setPower] = useState<Record<string, boolean>>(initialPower)
  const [brightness, setBrightness] = useState<Record<string, number>>(initialBrightness)

  const panel = selection.panel
  const targets = selection.screen === "all" ? IDS[panel] : [selection.screen]
  const allOn = targets.every((id) => power[id])
  const allOff = targets.every((id) => !power[id])
  const brightnessValues = targets.map((id) => brightness[id])
  const sameBrightness = brightnessValues.every((value) => value === brightnessValues[0])
  const shownBrightness = sameBrightness
    ? brightnessValues[0]
    : Math.round(brightnessValues.reduce((sum, value) => sum + value, 0) / brightnessValues.length)
  const activePreset = PRESETS[panel].find((item) => item.id === preset[panel]) ?? PRESETS[panel][0]
  const current = selection.screen === "all" ? null : SCREENS.find((screen) => screen.id === selection.screen)

  function applyPower(on: boolean) {
    setPower((currentPower) => {
      const next = { ...currentPower }
      targets.forEach((id) => {
        next[id] = on
      })
      return next
    })
  }

  function applyBrightness(level: number) {
    setBrightness((currentBrightness) => {
      const next = { ...currentBrightness }
      targets.forEach((id) => {
        next[id] = level
      })
      return next
    })
  }

  return (
    <main className="flex min-h-svh flex-col bg-[radial-gradient(circle_at_top,#1650c8_0%,#06215f_42%,#03102e_100%)] text-white">
      <header className="flex items-center justify-between gap-4 border-b border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="flex items-center gap-3">
          <img src="/mt-logo.png" alt="MT" className="h-10 w-auto" />
          <div>
            <p className="text-sm font-semibold tracking-[0.14em] whitespace-nowrap">REMOTE OPERATION CENTER</p>
            <p className="text-[11px] tracking-[0.22em] text-cyan-100/70">PANEL CONTROL</p>
          </div>
        </div>
        <p className="hidden text-xs tracking-[0.18em] text-cyan-100/70 sm:block">THIS STAND</p>
      </header>

      <section className="grid flex-1 gap-4 px-4 py-4 lg:grid-cols-[1.2fr_0.8fr_1.35fr] lg:px-6">
        <PanelFrame
          panel={1}
          title="Panel 1"
          detail="192.168.0.101"
          rows={PANEL_1}
          preset={PRESETS[1].find((item) => item.id === preset[1])!}
          selection={selection}
          power={power}
          onSelect={setSelection}
        />

        <div className="flex flex-col gap-4">
          <div className="flex flex-col justify-center gap-4 rounded-2xl border border-cyan-300/40 bg-[#0a2f86]/55 p-4 shadow-[0_0_28px_rgba(40,140,255,0.25)]">
            <div>
              <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">
                {selection.screen === "all" ? "WHOLE PANEL" : "ONE SCREEN"}
              </p>
              <h1 className="mt-1 text-3xl font-semibold tracking-wide">
                {selection.screen === "all" ? `Panel ${panel}` : current?.id}
              </h1>
              <p className="mt-1 text-sm text-cyan-100/80">
                {selection.screen === "all"
                  ? `All ${targets.length} screens. Tap one screen to adjust it alone.`
                  : `${current?.hdmi}. Tap the panel around the screens to adjust all of them.`}
              </p>
            </div>

            <div className="grid grid-cols-2 gap-2">
              <GlowButton active={allOn} onClick={() => applyPower(true)}>
                On
              </GlowButton>
              <GlowButton active={allOff} tone="alert" onClick={() => applyPower(false)}>
                Off
              </GlowButton>
            </div>

            <div>
              <div className="mb-2 flex items-baseline justify-between text-sm">
                <span>Brightness</span>
                <span className="font-mono text-cyan-100">{sameBrightness ? `${shownBrightness}%` : "Mixed"}</span>
              </div>
              <Slider
                min={0}
                max={100}
                value={[shownBrightness]}
                onValueChange={(value) => applyBrightness(Array.isArray(value) ? value[0] : value)}
                aria-label="Brightness"
              />
            </div>

            <p className="text-xs leading-5 text-cyan-100/70">
              {allOn ? "Power on" : allOff ? "Power off" : "Power is mixed"} for{" "}
              {selection.screen === "all" ? `panel ${panel}` : current?.id}. Nothing is sent to the displays yet.
            </p>
          </div>

          <PanelFrame
            panel={3}
            title="Panel 3"
            detail="192.168.0.103"
            rows={PANEL_3}
            preset={PRESETS[3].find((item) => item.id === preset[3])!}
            selection={selection}
            power={power}
            onSelect={setSelection}
          />
        </div>

        <PanelFrame
          panel={2}
          title="Panel 2"
          detail="192.168.0.102"
          rows={PANEL_2}
          preset={PRESETS[2].find((item) => item.id === preset[2])!}
          selection={selection}
          power={power}
          onSelect={setSelection}
        />
      </section>

      <footer className="border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="mb-2 flex items-center justify-between gap-3">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">PANEL {panel} PRESETS</p>
          <p className="text-xs text-cyan-100/70">{activePreset.name}</p>
        </div>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
          {PRESETS[panel].map((item) => (
            <GlowButton
              key={item.id}
              active={item.id === preset[panel]}
              onClick={() => setPreset((currentPreset) => ({ ...currentPreset, [panel]: item.id }))}
            >
              {item.name}
            </GlowButton>
          ))}
        </div>
      </footer>
    </main>
  )
}

function PanelFrame({
  panel,
  title,
  detail,
  rows,
  preset,
  selection,
  power,
  onSelect,
}: {
  panel: PanelId
  title: string
  detail: string
  rows: Screen[][]
  preset: Preset
  selection: Selection
  power: Record<string, boolean>
  onSelect: (selection: Selection) => void
}) {
  const ids = rows.flat().map((screen) => screen.id)
  const whole = selection.panel === panel && selection.screen === "all"
  const allOn = ids.every((id) => power[id])
  const allOff = ids.every((id) => !power[id])

  return (
    <section
      onClick={() => onSelect({ panel, screen: "all" })}
      className={`cursor-pointer rounded-2xl border bg-[#071a4d]/70 p-3 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
        whole ? "border-white shadow-[0_0_24px_rgba(180,230,255,0.35)]" : selection.panel === panel ? "border-cyan-300/70" : "border-cyan-300/25"
      }`}
    >
      <div className="mb-3 flex items-end justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">{title}</h2>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">{allOn ? "ON" : allOff ? "OFF" : "MIXED"}</span>
      </div>
      <div className="flex flex-col gap-2">
        {rows.map((row) => (
          <div key={row[0].id} className="grid gap-2" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
            {row.map((screen) => {
              const group = preset.groups[screen.id] ?? 0
              const color = GROUP_COLOR[group % GROUP_COLOR.length]
              const isSelected = selection.screen === screen.id
              const on = power[screen.id]
              return (
                <button
                  key={screen.id}
                  type="button"
                  onClick={(event) => {
                    event.stopPropagation()
                    onSelect({ panel, screen: screen.id })
                  }}
                  className="min-h-16 rounded-lg border px-1 py-2 text-center transition"
                  style={{
                    borderColor: isSelected ? "#ffffff" : color,
                    background: on ? `${color}33` : "rgba(0,0,0,0.45)",
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
