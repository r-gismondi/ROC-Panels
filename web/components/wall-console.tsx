"use client"

import { useEffect, useRef, useState } from "react"
import { Slider } from "@/components/ui/slider"

type PanelId = 1 | 2

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

const COMPUTER_2: Screen[][] = [
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

const COMPUTER_3: Screen[][] = [
  [{ id: "TV13", hdmi: "HDMI 1" }],
  [{ id: "TV18", hdmi: "HDMI 2" }],
]

const COMPUTER_2_IDS = COMPUTER_2.flat().map((screen) => screen.id)
const COMPUTER_3_IDS = COMPUTER_3.flat().map((screen) => screen.id)

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
  2: [...COMPUTER_2_IDS, ...COMPUTER_3_IDS],
}

const SCREENS = [...PANEL_1.flat(), ...COMPUTER_2.flat(), ...COMPUTER_3.flat()]

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
    { id: "full", name: "Full", groups: groups(IDS[2], [COMPUTER_2_IDS]) },
  ],
}

const COMPUTER_3_PRESETS: Preset[] = [
  { id: "independent", name: "Independent", groups: groups(COMPUTER_3_IDS, [["TV13"], ["TV18"]]) },
  { id: "full", name: "Full", groups: groups(COMPUTER_3_IDS, [COMPUTER_3_IDS]) },
]

const DEFAULT_URL = "https://ccv2.mtllc.us/landing"

const COMPUTER_OF: Record<string, "101" | "102" | "103"> = {}
for (const id of IDS[1]) COMPUTER_OF[id] = "101"
for (const id of COMPUTER_2_IDS) COMPUTER_OF[id] = "102"
for (const id of COMPUTER_3_IDS) COMPUTER_OF[id] = "103"

function screenNumber(id: string) {
  return id.replace("TV", "")
}

function zoneDetail(ids: string[]) {
  const nums = ids.map(screenNumber)
  if (nums.length <= 1) return `Screen ${nums[0] ?? ""} has its own window.`
  if (nums.length === 2) return `Screens ${nums[0]} and ${nums[1]} share this window. The address updates both.`
  const last = nums[nums.length - 1]
  return `Screens ${nums.slice(0, -1).join(", ")} and ${last} share this window. The address updates all of them.`
}

function normalizeUrl(value: string) {
  const trimmed = value.trim()
  if (!trimmed) return ""
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

export function WallConsole() {
  const [selection, setSelection] = useState<Selection>({ panel: 1, screen: "all" })
  const [preset, setPreset] = useState<Record<PanelId, string>>({ 1: "focus", 2: "focus" })
  const [applied, setApplied] = useState<Record<PanelId, string>>({ 1: "focus", 2: "focus" })
  const [computer3Preset, setComputer3Preset] = useState("independent")
  const [computer3Applied, setComputer3Applied] = useState("independent")
  const [power, setPower] = useState<Record<string, boolean>>(initialPower)
  const [brightness, setBrightness] = useState<Record<string, number>>(initialBrightness)
  const [layoutStatus, setLayoutStatus] = useState("Preset buttons preview the layout here. Confirm opens Edge on that computer.")
  const [addresses, setAddresses] = useState<Record<string, string>>({})
  const [keyboardOpen, setKeyboardOpen] = useState(false)
  const [replaceAddress, setReplaceAddress] = useState(false)
  const layoutBusy = useRef(false)
  const brightnessTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const controlRef = useRef<HTMLDivElement>(null)
  const [controlHeight, setControlHeight] = useState<number>()

  useEffect(() => {
    const control = controlRef.current
    if (!control) return
    const measure = () => setControlHeight(control.offsetHeight)
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(control)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (!SCREENS.some((screen) => screen.id === selection.screen)) setKeyboardOpen(false)
    else setReplaceAddress(true)
  }, [selection])

  useEffect(() => {
    return () => {
      if (brightnessTimer.current) clearTimeout(brightnessTimer.current)
    }
  }, [])

  useEffect(() => {
    let cancel = false
    void (async () => {
      try {
        const response = await fetch("/api/display")
        const body = (await response.json()) as { screens?: Record<string, { power: boolean; brightness: number }> }
        if (cancel || !body.screens) return
        setPower((currentPower) => {
          const next = { ...currentPower }
          for (const [id, value] of Object.entries(body.screens ?? {})) next[id] = value.power
          return next
        })
        setBrightness((currentBrightness) => {
          const next = { ...currentBrightness }
          for (const [id, value] of Object.entries(body.screens ?? {})) next[id] = value.brightness
          return next
        })
      } catch {
        // The controls keep their last values until a display answers.
      }
    })()
    return () => {
      cancel = true
    }
  }, [])

  useEffect(() => {
    let cancel = false
    void (async () => {
      const next: Record<string, string> = {}
      for (const computer of ["101", "102", "103"]) {
        try {
          const response = await fetch(`/api/address?computer=${computer}`)
          const body = (await response.json()) as { addresses?: Record<string, string> }
          Object.assign(next, body.addresses ?? {})
        } catch {
          // The field keeps the landing page until a screen is opened.
        }
      }
      if (!cancel) setAddresses((existing) => ({ ...next, ...existing }))
    })()
    return () => {
      cancel = true
    }
  }, [])

  const panel = selection.panel
  const computer3Scope = selection.panel === 2 && (selection.screen === "computer-3" || COMPUTER_3_IDS.includes(selection.screen))
  const computer2Scope = selection.panel === 2 && (selection.screen === "computer-2" || COMPUTER_2_IDS.includes(selection.screen))
  const targets =
    selection.screen === "all"
      ? IDS[panel]
      : selection.screen === "computer-2"
        ? COMPUTER_2_IDS
        : selection.screen === "computer-3"
          ? COMPUTER_3_IDS
          : [selection.screen]
  const allOn = targets.every((id) => power[id])
  const allOff = targets.every((id) => !power[id])
  const brightnessValues = targets.map((id) => brightness[id])
  const sameBrightness = brightnessValues.every((value) => value === brightnessValues[0])
  const shownBrightness = sameBrightness
    ? brightnessValues[0]
    : Math.round(brightnessValues.reduce((sum, value) => sum + value, 0) / brightnessValues.length)
  const computer2Preset = PRESETS[2].find((item) => item.id === preset[2]) ?? PRESETS[2][0]
  const activeComputer3Preset = COMPUTER_3_PRESETS.find((item) => item.id === computer3Preset) ?? COMPUTER_3_PRESETS[0]
  const current = SCREENS.find((screen) => screen.id === selection.screen)
  const scopeLabel =
    selection.screen === "all"
      ? "WHOLE PANEL"
      : selection.screen === "computer-2"
        ? "COMPUTER 2"
        : selection.screen === "computer-3"
          ? "COMPUTER 3"
          : "ONE SCREEN"
  const scopeTitle =
    selection.screen === "all"
      ? `Panel ${panel}`
      : selection.screen === "computer-2"
        ? "Computer 2"
        : selection.screen === "computer-3"
          ? "Computer 3"
          : current?.id
  const scopeDetail =
    selection.screen === "all"
      ? `All ${targets.length} screens. Tap one screen to adjust it alone.`
      : selection.screen === "computer-2"
        ? "Screens 9–12 and 14–17 on 192.168.0.102. Tap the panel edge to adjust every screen on panel 2."
        : selection.screen === "computer-3"
          ? "Screens 13 and 18 on 192.168.0.103. Tap the panel edge to adjust every screen on panel 2."
          : `${current?.hdmi}. Tap the panel around the screens to adjust all of them.`

  async function applyPower(on: boolean) {
    const screens = [...targets]
    const previous: Record<string, boolean> = {}
    screens.forEach((id) => {
      previous[id] = power[id]
    })
    setPower((currentPower) => {
      const next = { ...currentPower }
      screens.forEach((id) => {
        next[id] = on
      })
      return next
    })
    setLayoutStatus(on ? "Turning the screens on…" : "Turning the screens off…")
    try {
      const response = await fetch("/api/display", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ screens, power: on }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string; failed?: string[] } | null
      const failed = new Set(body?.failed ?? (response.ok ? [] : screens))
      if (!response.ok || failed.size > 0) {
        setPower((currentPower) => {
          const next = { ...currentPower }
          failed.forEach((id) => {
            if (id in previous) next[id] = previous[id]
          })
          return next
        })
      }
      setLayoutStatus(body?.message || body?.error || "The screens did not change.")
    } catch {
      setPower((currentPower) => ({ ...currentPower, ...previous }))
      setLayoutStatus("Could not reach the displays.")
    }
  }

  function applyBrightness(level: number) {
    const screens = [...targets]
    const previous: Record<string, number> = {}
    screens.forEach((id) => {
      previous[id] = brightness[id]
    })
    setBrightness((currentBrightness) => {
      const next = { ...currentBrightness }
      screens.forEach((id) => {
        next[id] = level
      })
      return next
    })
    if (brightnessTimer.current) clearTimeout(brightnessTimer.current)
    brightnessTimer.current = setTimeout(() => {
      void sendBrightness(screens, level, previous)
    }, 80)
  }

  async function sendBrightness(screens: string[], level: number, previous: Record<string, number>) {
    setLayoutStatus("Setting the brightness…")
    try {
      const response = await fetch("/api/display", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ screens, brightness: level }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string; failed?: string[] } | null
      const failed = new Set(body?.failed ?? (response.ok ? [] : screens))
      if (!response.ok || failed.size > 0) {
        setBrightness((currentBrightness) => {
          const next = { ...currentBrightness }
          failed.forEach((id) => {
            if (id in previous) next[id] = previous[id]
          })
          return next
        })
      }
      setLayoutStatus(body?.message || body?.error || "The brightness did not change.")
    } catch {
      setBrightness((currentBrightness) => ({ ...currentBrightness, ...previous }))
      setLayoutStatus("Could not reach the displays.")
    }
  }

  const footer =
    panel === 1
      ? { label: "PANEL 1 PRESETS", presets: PRESETS[1], activeId: preset[1], appliedId: applied[1], computer: "101" as const, target: "Panel 1" }
      : computer3Scope
        ? {
            label: "COMPUTER 3 PRESETS",
            presets: COMPUTER_3_PRESETS,
            activeId: computer3Preset,
            appliedId: computer3Applied,
            computer: "103" as const,
            target: "Computer 3",
          }
        : { label: "COMPUTER 2 PRESETS", presets: PRESETS[2], activeId: preset[2], appliedId: applied[2], computer: "102" as const, target: "Computer 2" }

  async function runLayout(computer: "101" | "102" | "103", id: string) {
    if (layoutBusy.current) return false
    layoutBusy.current = true
    setLayoutStatus(id === "close" ? "Closing Edge…" : "Opening the layout…")
    try {
      const response = await fetch("/api/layout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer, preset: id }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      setLayoutStatus(body?.message || body?.error || "The layout did not start.")
      return response.ok
    } catch {
      setLayoutStatus("Could not reach the layout service.")
      return false
    } finally {
      layoutBusy.current = false
    }
  }

  async function runVnc(computer: "101" | "102" | "103") {
    const name = computer === "101" ? "Computer 1" : computer === "102" ? "Computer 2" : "Computer 3"
    setLayoutStatus(`Opening VNC to ${name}…`)
    try {
      const response = await fetch("/api/vnc", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      setLayoutStatus(body?.message || body?.error || "VNC did not open.")
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    }
  }

  const addressComputer = current ? COMPUTER_OF[current.id] : null
  const addressPreset =
    addressComputer === "103"
      ? COMPUTER_3_PRESETS.find((item) => item.id === computer3Applied) ?? COMPUTER_3_PRESETS[0]
      : addressComputer === "101"
        ? PRESETS[1].find((item) => item.id === applied[1]) ?? PRESETS[1][0]
        : PRESETS[2].find((item) => item.id === applied[2]) ?? PRESETS[2][0]
  const addressIds = addressComputer === "103" ? COMPUTER_3_IDS : addressComputer === "101" ? IDS[1] : COMPUTER_2_IDS
  const zoneIds = current ? addressIds.filter((id) => addressPreset.groups[id] === addressPreset.groups[current.id]) : []
  const shownZone = zoneIds.length > 0 ? zoneIds : current ? [current.id] : []
  const addressValue = current ? addresses[current.id] ?? DEFAULT_URL : DEFAULT_URL
  const previewPending = footer.activeId !== footer.appliedId

  function insertAddress(token: string) {
    if (!current) return
    const id = current.id
    setAddresses((existing) => {
      const value = existing[id] ?? DEFAULT_URL
      const base = replaceAddress ? "" : value
      return { ...existing, [id]: base + token }
    })
    setReplaceAddress(false)
  }

  function insertScheme() {
    if (!current) return
    const id = current.id
    setAddresses((existing) => {
      const value = existing[id] ?? DEFAULT_URL
      if (replaceAddress || value.trim() === "") return { ...existing, [id]: "https://" }
      if (/^https?:\/\//i.test(value)) return existing
      return { ...existing, [id]: `https://${value}` }
    })
    setReplaceAddress(false)
  }

  function backspaceAddress() {
    if (!current) return
    const id = current.id
    setAddresses((existing) => {
      const value = existing[id] ?? DEFAULT_URL
      return { ...existing, [id]: replaceAddress ? "" : value.slice(0, -1) }
    })
    setReplaceAddress(false)
  }

  function clearAddress() {
    if (!current) return
    const id = current.id
    setAddresses((existing) => ({ ...existing, [id]: "" }))
    setReplaceAddress(false)
  }

  async function runAddress() {
    if (!current || !addressComputer) return
    if (layoutBusy.current) return
    if (previewPending) {
      setLayoutStatus(`Confirm the layout preview on ${footer.target}, then set the address.`)
      return
    }
    const url = normalizeUrl(addresses[current.id] ?? DEFAULT_URL)
    if (!/^https?:\/\/\S+$/.test(url) || /[\s"'<>\\]/.test(url)) {
      setLayoutStatus("Type a full address, such as https://example.com.")
      setKeyboardOpen(true)
      return
    }
    setAddresses((existing) => ({ ...existing, [current.id]: url }))
    layoutBusy.current = true
    const label = shownZone.length > 1 ? `screens ${shownZone.map(screenNumber).join(", ")}` : `screen ${screenNumber(current.id)}`
    setLayoutStatus(`Opening the address on ${label}…`)
    try {
      const response = await fetch("/api/address", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer: addressComputer, screen: current.id, url }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      setLayoutStatus(body?.message || body?.error || "The address did not open.")
      if (response.ok) setKeyboardOpen(false)
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
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

      <section className="grid items-start gap-4 px-4 py-4 lg:grid-cols-[4fr_minmax(16rem,18rem)_5fr] lg:px-6">
        <PanelFrame
          panel={1}
          title="Panel 1"
          detail="192.168.0.101"
          rows={PANEL_1}
          preset={PRESETS[1].find((item) => item.id === preset[1])!}
          selection={selection}
          power={power}
          onSelect={setSelection}
          height={controlHeight}
        />

        <div ref={controlRef} className="flex flex-col justify-center gap-4 rounded-2xl border border-cyan-300/40 bg-[#0a2f86]/55 p-4 shadow-[0_0_28px_rgba(40,140,255,0.25)]">
            <div>
              <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{scopeLabel}</p>
              <h1 className="mt-1 text-3xl font-semibold tracking-wide">{scopeTitle}</h1>
              <p className="mt-1 min-h-[3.75rem] text-sm leading-5 text-cyan-100/80">{scopeDetail}</p>
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

            {current ? (
              <div className="flex flex-col gap-2">
                <div className="flex items-baseline justify-between gap-2">
                  <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">ADDRESS</p>
                  <p className="text-[11px] text-cyan-100/70">Screen {screenNumber(current.id)}</p>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setKeyboardOpen(true)
                    setReplaceAddress(true)
                  }}
                  className={`min-h-16 rounded-lg border px-3 py-2 text-left ${
                    keyboardOpen && replaceAddress ? "border-white bg-white/10" : "border-cyan-300/40 bg-[#08245f]/80"
                  }`}
                >
                  <span className="block break-all font-mono text-sm leading-5">{addressValue || "Tap to type an address"}</span>
                </button>
                <p className="text-xs leading-5 text-cyan-100/80">
                  {zoneDetail(shownZone)}
                  {previewPending ? " Confirm the layout preview, then set the address." : ""}
                </p>
                <GlowButton active onClick={() => void runAddress()}>
                  Open address
                </GlowButton>
              </div>
            ) : (
              <p className="text-xs leading-5 text-cyan-100/80">Tap one screen to type its address.</p>
            )}

            <p className="text-xs leading-5 text-cyan-100/70">
              {allOn ? "Power on" : allOff ? "Power off" : "Power is mixed"} for{" "}
              {selection.screen === "all" ? `panel ${panel}` : scopeTitle}.
            </p>
            <p className="min-h-10 whitespace-pre-wrap text-xs leading-5 text-cyan-100">{layoutStatus}</p>
          </div>

        <section
          onClick={() => setSelection({ panel: 2, screen: "all" })}
          className={`flex cursor-pointer flex-col rounded-2xl border bg-[#071a4d]/70 p-3 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
            selection.panel === 2 && selection.screen === "all"
              ? "border-white shadow-[0_0_24px_rgba(180,230,255,0.35)]"
              : selection.panel === 2
                ? "border-cyan-300/70"
                : "border-cyan-300/25"
          }`}
          style={controlHeight ? { height: controlHeight } : undefined}
        >
          <div className="mb-3 flex items-end justify-between gap-2">
            <div>
              <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">Panel 2</h2>
              <p className="text-xs text-cyan-100/70">Screens 9–18</p>
            </div>
            <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">
              {IDS[2].every((id) => power[id]) ? "ON" : IDS[2].every((id) => !power[id]) ? "OFF" : "MIXED"}
            </span>
          </div>
          <div className="grid min-h-0 flex-1 items-stretch gap-2 lg:grid-cols-5">
            <ComputerFrame
              className="lg:col-span-4"
              title="Computer 2"
              detail="192.168.0.102"
              rows={COMPUTER_2}
              preset={computer2Preset}
              selected={computer2Scope}
              selection={selection}
              power={power}
              onSelectFrame={() => setSelection({ panel: 2, screen: "computer-2" })}
              onSelectScreen={(screen) => setSelection({ panel: 2, screen })}
            />
            <ComputerFrame
              className="lg:col-span-1"
              title="Computer 3"
              detail="192.168.0.103"
              rows={COMPUTER_3}
              preset={activeComputer3Preset}
              selected={computer3Scope}
              selection={selection}
              power={power}
              onSelectFrame={() => setSelection({ panel: 2, screen: "computer-3" })}
              onSelectScreen={(screen) => setSelection({ panel: 2, screen })}
            />
          </div>
        </section>
      </section>

      <footer className="border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <PresetRow
          label={footer.label}
          presets={footer.presets}
          activeId={footer.activeId}
          pending={footer.activeId !== footer.appliedId}
          onSelect={(id) => {
            const name = footer.presets.find((item) => item.id === id)?.name ?? id
            if (footer.computer === "103") setComputer3Preset(id)
            else if (footer.computer === "101") setPreset((currentPreset) => ({ ...currentPreset, 1: id }))
            else setPreset((currentPreset) => ({ ...currentPreset, 2: id }))
            setLayoutStatus(
              id === footer.appliedId
                ? `${name} is the current layout for ${footer.target}.`
                : `Previewing ${name} on ${footer.target}. Confirm to open Edge, or cancel.`,
            )
          }}
          onConfirm={() => {
            void (async () => {
              const ok = await runLayout(footer.computer, footer.activeId)
              if (!ok) return
              if (footer.computer === "103") setComputer3Applied(footer.activeId)
              else if (footer.computer === "101") setApplied((currentApplied) => ({ ...currentApplied, 1: footer.activeId }))
              else setApplied((currentApplied) => ({ ...currentApplied, 2: footer.activeId }))
            })()
          }}
          onCancel={() => {
            if (footer.computer === "103") setComputer3Preset(footer.appliedId)
            else if (footer.computer === "101") setPreset((currentPreset) => ({ ...currentPreset, 1: footer.appliedId }))
            else setPreset((currentPreset) => ({ ...currentPreset, 2: footer.appliedId }))
            setLayoutStatus(`Canceled the preview on ${footer.target}.`)
          }}
          onClose={() => {
            void runLayout(footer.computer, "close")
          }}
        />
        <div className="mt-3 border-t border-cyan-300/25 pt-3">
          <p className="mb-2 flex items-center gap-1.5 text-[11px] tracking-[0.2em] text-cyan-100/70">
            <img src="/realvnc.png" alt="" width={20} height={20} className="size-5 shrink-0" />
            VNC
          </p>
          <p className="mb-2 text-xs text-cyan-100/70">Opens on this screen. Close returns here.</p>
          <div className="grid grid-cols-3 gap-2 sm:max-w-xl">
            <GlowButton onClick={() => void runVnc("101")}>Computer 1</GlowButton>
            <GlowButton onClick={() => void runVnc("102")}>Computer 2</GlowButton>
            <GlowButton onClick={() => void runVnc("103")}>Computer 3</GlowButton>
          </div>
        </div>
      </footer>
      {keyboardOpen && current ? (
        <AddressKeyboard
          label={`Screen ${screenNumber(current.id)}`}
          value={addressValue}
          selected={replaceAddress}
          detail={zoneDetail(shownZone)}
          onInsert={insertAddress}
          onScheme={insertScheme}
          onBackspace={backspaceAddress}
          onClear={clearAddress}
          onOpen={() => void runAddress()}
          onClose={() => setKeyboardOpen(false)}
        />
      ) : null}
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
  height,
}: {
  panel: PanelId
  title: string
  detail: string
  rows: Screen[][]
  preset: Preset
  selection: Selection
  power: Record<string, boolean>
  onSelect: (selection: Selection) => void
  height?: number
}) {
  const ids = rows.flat().map((screen) => screen.id)
  const whole = selection.panel === panel && selection.screen === "all"
  const allOn = ids.every((id) => power[id])
  const allOff = ids.every((id) => !power[id])

  return (
    <section
      onClick={() => onSelect({ panel, screen: "all" })}
      className={`flex cursor-pointer flex-col rounded-2xl border bg-[#071a4d]/70 p-3 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
        whole ? "border-white shadow-[0_0_24px_rgba(180,230,255,0.35)]" : selection.panel === panel ? "border-cyan-300/70" : "border-cyan-300/25"
      }`}
      style={height ? { height } : undefined}
    >
      <div className="mb-3 flex items-end justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">{title}</h2>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">{allOn ? "ON" : allOff ? "OFF" : "MIXED"}</span>
      </div>
      <div className="flex min-h-0 flex-1 flex-col rounded-xl border border-transparent p-2">
        {/* Reserves the same space as the computer label on panel 2, so every screen is the same height. */}
        <p className="invisible truncate text-[11px] font-semibold tracking-[0.08em] whitespace-nowrap uppercase" aria-hidden="true">
          Computer
        </p>
        <p className="invisible mb-2 truncate text-[10px] whitespace-nowrap" aria-hidden="true">
          192.168.0.101
        </p>
        <div className="flex min-h-0 flex-1 flex-col gap-2">
        {rows.map((row) => (
          <div key={row[0].id} className="grid min-h-0 flex-1 gap-2" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
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
                  className="h-full min-h-0 rounded-lg border px-1 py-2 text-center transition"
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
      </div>
    </section>
  )
}

function ComputerFrame({
  className = "",
  title,
  detail,
  rows,
  preset,
  selected,
  selection,
  power,
  onSelectFrame,
  onSelectScreen,
}: {
  className?: string
  title: string
  detail: string
  rows: Screen[][]
  preset: Preset
  selected: boolean
  selection: Selection
  power: Record<string, boolean>
  onSelectFrame: () => void
  onSelectScreen: (screen: string) => void
}) {
  return (
    <div
      onClick={(event) => {
        event.stopPropagation()
        onSelectFrame()
      }}
      className={`flex h-full min-h-0 min-w-0 flex-col rounded-xl border p-2 ${className} ${selected ? "border-white bg-white/5" : "border-cyan-300/35"}`}
    >
      <p className="truncate text-[11px] font-semibold tracking-[0.08em] whitespace-nowrap uppercase">{title}</p>
      <p className="mb-2 truncate text-[10px] whitespace-nowrap text-cyan-100/70">{detail}</p>
      <div className="flex min-h-0 flex-1 flex-col gap-2">
        {rows.map((row) => (
          <div key={row[0].id} className="grid min-h-0 flex-1 gap-2" style={{ gridTemplateColumns: `repeat(${row.length}, minmax(0, 1fr))` }}>
            {row.map((screen) => (
              <ScreenButton
                key={screen.id}
                screen={screen}
                preset={preset}
                selected={selection.screen === screen.id}
                on={power[screen.id]}
                onSelect={() => onSelectScreen(screen.id)}
              />
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}

function ScreenButton({
  screen,
  preset,
  selected,
  on,
  onSelect,
}: {
  screen: Screen
  preset: Preset
  selected: boolean
  on: boolean
  onSelect: () => void
}) {
  const group = preset.groups[screen.id] ?? 0
  const color = GROUP_COLOR[group % GROUP_COLOR.length]
  return (
    <button
      type="button"
      onClick={(event) => {
        event.stopPropagation()
        onSelect()
      }}
      className="h-full min-h-0 rounded-lg border px-1 py-2 text-center transition"
      style={{
        borderColor: selected ? "#ffffff" : color,
        background: on ? `${color}33` : "rgba(0,0,0,0.45)",
        boxShadow: selected ? `0 0 16px ${color}` : undefined,
      }}
    >
      <span className="block text-sm font-semibold">{screen.id.replace("TV", "")}</span>
      <span className="block text-[10px] text-cyan-50/80">{screen.hdmi}</span>
    </button>
  )
}

function PresetRow({
  label,
  presets,
  activeId,
  pending,
  onSelect,
  onConfirm,
  onCancel,
  onClose,
}: {
  label: string
  presets: Preset[]
  activeId: string
  pending: boolean
  onSelect: (id: string) => void
  onConfirm: () => void
  onCancel: () => void
  onClose: () => void
}) {
  return (
    <div>
      <div className="mb-2 flex items-end justify-between gap-3">
        <div>
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{label}</p>
          <p className="text-xs text-cyan-100/80">{pending ? "Preview on the screens. Confirm opens Edge." : "Choose a preset to preview it on the screens."}</p>
        </div>
        <GlowButton tone="alert" onClick={onClose}>
          Close Edge
        </GlowButton>
      </div>
      <div className={`grid grid-cols-2 gap-2 ${presets.length > 2 ? "sm:grid-cols-5" : "sm:grid-cols-2 sm:max-w-md"}`}>
        {presets.map((item) => (
          <GlowButton key={item.id} active={item.id === activeId} onClick={() => onSelect(item.id)}>
            {item.name}
          </GlowButton>
        ))}
      </div>
      {pending ? (
        <div className="mt-2 grid max-w-md grid-cols-2 gap-2">
          <GlowButton active onClick={onConfirm}>
            Confirm
          </GlowButton>
          <GlowButton onClick={onCancel}>
            Cancel
          </GlowButton>
        </div>
      ) : null}
    </div>
  )
}

const ADDRESS_KEYS = [
  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["z", "x", "c", "v", "b", "n", "m", ".", "-", "_"],
]

function AddressKeyboard({
  label,
  value,
  selected,
  detail,
  onInsert,
  onScheme,
  onBackspace,
  onClear,
  onOpen,
  onClose,
}: {
  label: string
  value: string
  selected: boolean
  detail: string
  onInsert: (token: string) => void
  onScheme: () => void
  onBackspace: () => void
  onClear: () => void
  onOpen: () => void
  onClose: () => void
}) {
  const shortcuts = ["https://", "www.", "/", ":", ".com", "?", "&", "=", "#", "%"]
  return (
    <div className="fixed inset-x-0 bottom-0 z-40 max-h-[70vh] overflow-y-auto border-t border-cyan-300/40 bg-[#03102e]/95 p-3 shadow-[0_-12px_40px_rgba(0,0,0,0.45)] select-none">
      <div className="mx-auto flex w-full max-w-[1600px] flex-col gap-2">
        <div className="flex items-baseline justify-between gap-3">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{label}</p>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <div className={`min-h-12 rounded-lg border px-3 py-2 ${selected ? "border-white bg-white/10" : "border-cyan-300/40 bg-[#08245f]/80"}`}>
          <p className="break-all font-mono text-base leading-6">{value || " "}</p>
        </div>
        {selected ? <p className="text-xs text-cyan-100/70">The address is selected. The next key replaces it.</p> : null}
        {ADDRESS_KEYS.map((row) => (
          <div key={row.join("")} className="flex gap-2">
            {row.map((key) => (
              <KeyButton key={key} onClick={() => onInsert(key)}>
                {key}
              </KeyButton>
            ))}
          </div>
        ))}
        <div className="flex gap-2">
          {shortcuts.map((key) => (
            <KeyButton key={key} onClick={() => (key === "https://" ? onScheme() : onInsert(key))}>
              {key}
            </KeyButton>
          ))}
        </div>
        <div className="grid grid-cols-2 gap-2">
          <KeyButton onClick={onClear}>Clear</KeyButton>
          <KeyButton onClick={onBackspace}>Backspace</KeyButton>
        </div>
        <div className="grid grid-cols-[2fr_1fr] gap-2">
          <button
            type="button"
            onClick={onOpen}
            className="min-h-14 rounded-lg border border-cyan-200 bg-cyan-400/25 text-base tracking-wide shadow-[0_0_16px_rgba(80,200,255,0.35)]"
          >
            Open address
          </button>
          <KeyButton onClick={onClose}>Hide keyboard</KeyButton>
        </div>
      </div>
    </div>
  )
}

function KeyButton({ children, onClick }: { children: string; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="min-h-14 flex-1 rounded-lg border border-cyan-300/40 bg-[#08245f] px-2 text-lg tracking-wide touch-manipulation"
    >
      {children}
    </button>
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
