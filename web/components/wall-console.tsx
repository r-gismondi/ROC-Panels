"use client"

import { useEffect, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent, type ReactNode } from "react"
import { DragCoach } from "@/components/drag-coach"
import { OnScreenKeyboard, TypeField, backspaceAtCaret, insertAtCaret, usePhysicalTyping } from "@/components/on-screen-keyboard"
import { PresetCoach } from "@/components/preset-coach"
import { Reveal, StatusLine, motionStyle, usePresence } from "@/components/presence"
import { Slider } from "@/components/ui/slider"
import { C_CONNECT_ID, C_CONNECT_NAME, C_CONNECT_URL, programIconClass, programIconSrc } from "@/lib/c-connect"
import {
  adaptCustomView,
  canApplyCustomView,
  CUSTOM_VIEW_SCREENS,
  groupsFromBuckets,
  isCustomViewId,
  MAX_VIEW_GROUPS,
  validateViewBuckets,
  type CustomView,
} from "@/lib/custom-view-model"
import { GROUP_COLOR, presetZones, type Preset, type Screen } from "@/lib/preset-zones"

type PanelId = 1 | 2

type PinnedApp = { id: string; name: string; path: string; locked?: boolean }
type SavedLink = { id: string; name: string; url: string }
type DragItem = { kind: "program" | "link"; id: string; x: number; y: number; over: string }

function asPreset(view: CustomView): Preset {
  return { id: view.id, name: view.name, groups: view.groups }
}

const C_CONNECT_PIN: PinnedApp = { id: C_CONNECT_ID, name: C_CONNECT_NAME, path: C_CONNECT_URL, locked: true }

function withCConnect(pins: PinnedApp[]) {
  return [C_CONNECT_PIN, ...pins.filter((pin) => pin.id !== C_CONNECT_ID)]
}

const GROUP_LABEL = {
  "101": "screens 1–8",
  "102": "screens 9–12 and 14–17",
  "103": "screens 13 and 18",
} as const

type Computer = keyof typeof GROUP_LABEL

const REMOTE_PANEL: Record<Computer, string> = {
  "101": "Panel 1",
  "102": "Panel 2",
  "103": "Panel 3",
}

type Selection = { panel: PanelId; screen: string | "all" | "every" }

// Frame borders are 2px. 4px is as close as neighboring colors can sit without stacking.
const SCREEN_GAP = 4

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

function presetById(list: Preset[], id: string, fallbackId: string) {
  return list.find((item) => item.id === id) ?? list.find((item) => item.id === fallbackId) ?? list[0]
}

function chosenPreset(list: Preset[], id: string) {
  if (!id) return null
  return list.find((item) => item.id === id) ?? null
}

function savedPreset(id: string | undefined, allowed: string[]) {
  if (!id || id === "close" || !allowed.includes(id)) return ""
  return id
}
export function WallConsole() {
  const [selection, setSelection] = useState<Selection>({ panel: 1, screen: "all" })
  const [preset, setPreset] = useState<Record<PanelId, string>>({ 1: "", 2: "" })
  const [applied, setApplied] = useState<Record<PanelId, string>>({ 1: "", 2: "" })
  const [computer3Preset, setComputer3Preset] = useState("")
  const [computer3Applied, setComputer3Applied] = useState("")
  const [customViews, setCustomViews] = useState<CustomView[]>([])
  const [power, setPower] = useState<Record<string, boolean>>(initialPower)
  const [brightness, setBrightness] = useState<Record<string, number>>(initialBrightness)
  const [layoutStatus, setLayoutStatus] = useState("Preset buttons preview the layout here. Confirm opens Edge on these screens.")
  const [pins, setPins] = useState<PinnedApp[]>([C_CONNECT_PIN])
  const [links, setLinks] = useState<SavedLink[]>([])
  const [armedApp, setArmedApp] = useState("")
  const [armedLink, setArmedLink] = useState("")
  const [programStatus, setProgramStatus] = useState("")
  const [linkStatus, setLinkStatus] = useState("")
  const [browseBusy, setBrowseBusy] = useState(false)
  const [linkEditorOpen, setLinkEditorOpen] = useState(false)
  const [editingLinkId, setEditingLinkId] = useState("")
  const [linkName, setLinkName] = useState("")
  const [linkUrl, setLinkUrl] = useState("")
  const [linkField, setLinkField] = useState<"name" | "url">("name")
  const [linkReplace, setLinkReplace] = useState(false)
  const [viewEditorOpen, setViewEditorOpen] = useState(false)
  const [viewName, setViewName] = useState("")
  const [viewBuckets, setViewBuckets] = useState<string[][]>([[]])
  const [viewBucketIndex, setViewBucketIndex] = useState(0)
  const [viewReplace, setViewReplace] = useState(false)
  const [viewBusy, setViewBusy] = useState(false)
  const [viewStatus, setViewStatus] = useState("")
  const [panelGuardOpen, setPanelGuardOpen] = useState(false)
  const [removeViewAsk, setRemoveViewAsk] = useState<{ id: string; name: string } | null>(null)
  const removeViewHold = useRef<{ id: string; name: string } | null>(null)
  const [linkBusy, setLinkBusy] = useState(false)
  const linkNameRef = useRef<HTMLInputElement | null>(null)
  const linkUrlRef = useRef<HTMLInputElement | null>(null)
  const linkCaret = useRef({ start: 0, end: 0 })
  const viewNameRef = useRef<HTMLInputElement | null>(null)
  const viewCaret = useRef({ start: 0, end: 0 })
  const addressInputRef = useRef<HTMLInputElement | null>(null)
  const addressCaret = useRef({ start: 0, end: 0 })
  const [remoteAsk, setRemoteAsk] = useState<Computer | "">("")
  const remoteHold = useRef<Computer>("101")
  const [addresses, setAddresses] = useState<Record<string, string>>({})
  const [keyboardOpen, setKeyboardOpen] = useState(false)
  const [replaceAddress, setReplaceAddress] = useState(false)
  const layoutBusy = useRef(false)
  const launchLock = useRef(false)
  const brightnessTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const brightnessDraft = useRef<number | null>(null)
  const screenHold = useRef<Screen | undefined>(undefined)
  const coachHold = useRef<PinnedApp | null>(null)
  const dragSession = useRef<{ pointerId: number; kind: "program" | "link"; id: string; x: number; y: number; dragging: boolean } | null>(null)
  const [drag, setDrag] = useState<DragItem | null>(null)
  const armedRef = useRef("")
  const armedLinkRef = useRef("")
  const launchPin = useRef("")
  const launchLinkId = useRef("")
  const scrollArea = useRef<HTMLDivElement>(null)
  const presetCoachHold = useRef<{ rows: Screen[][]; preset: Preset } | null>(null)

  useEffect(() => {
    if (!SCREENS.some((screen) => screen.id === selection.screen)) setKeyboardOpen(false)
    else setReplaceAddress(true)
  }, [selection])

  useEffect(() => {
    const events = new EventSource("/api/home")
    events.onmessage = (event) => {
      if (event.data !== "home") return
      setKeyboardOpen(false)
      setLinkEditorOpen(false)
      setEditingLinkId("")
      setViewEditorOpen(false)
      setPanelGuardOpen(false)
      setRemoteAsk("")
      scrollArea.current?.scrollTo({ top: 0, behavior: "smooth" })
    }
    return () => events.close()
  }, [])

  useEffect(() => {
    if (!keyboardOpen) return
    function closeKeyboard(event: PointerEvent) {
      const target = event.target
      if (target instanceof Element && (target.closest("[data-keyboard]") || target.closest("[data-typeable]"))) return
      setKeyboardOpen(false)
    }
    window.addEventListener("pointerdown", closeKeyboard, true)
    return () => window.removeEventListener("pointerdown", closeKeyboard, true)
  }, [keyboardOpen])

  useEffect(() => {
    if (!armedApp && !armedLink) return
    function cancelArmed(event: PointerEvent) {
      const target = event.target
      if (
        target instanceof Element &&
        (target.closest("[data-screen-id]") || target.closest("[data-program-id]") || target.closest("[data-link-id]"))
      ) {
        return
      }
      setArmedApp("")
      setArmedLink("")
    }
    window.addEventListener("pointerdown", cancelArmed)
    return () => window.removeEventListener("pointerdown", cancelArmed)
  }, [armedApp, armedLink])

  useEffect(() => {
    if (!linkEditorOpen) return
    function closeEditor(event: PointerEvent) {
      const target = event.target
      if (target instanceof Element && target.closest("[data-link-editor]")) return
      setLinkEditorOpen(false)
      setEditingLinkId("")
    }
    window.addEventListener("pointerdown", closeEditor, true)
    return () => window.removeEventListener("pointerdown", closeEditor, true)
  }, [linkEditorOpen])

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

  const [thumbStamp, setThumbStamp] = useState(() => Date.now())
  useEffect(() => {
    void fetch("/api/thumbs", { method: "POST" })
    const timer = window.setInterval(() => setThumbStamp(Date.now()), 2500)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    let cancel = false
    void (async () => {
      try {
        const viewsResponse = await fetch("/api/views")
        const viewsBody = (await viewsResponse.json()) as { views?: CustomView[] }
        const views = viewsBody.views ?? []
        if (!cancel) setCustomViews(views)
        const response = await fetch("/api/layout", { cache: "no-store" })
        const body = (await response.json()) as { layouts?: Record<string, string> }
        if (cancel || !body.layouts) return
        const customIds = (computer: "101" | "102" | "103") =>
          views.filter((view) => canApplyCustomView(view, computer)).map((view) => view.id)
        const panel1 = savedPreset(body.layouts["101"], [...PRESETS[1].map((item) => item.id), ...customIds("101")])
        const panel2 = savedPreset(body.layouts["102"], [...PRESETS[2].map((item) => item.id), ...customIds("102")])
        const computer3 = savedPreset(body.layouts["103"], [...COMPUTER_3_PRESETS.map((item) => item.id), ...customIds("103")])
        if (panel1) {
          setPreset((current) => ({ ...current, 1: panel1 }))
          setApplied((current) => ({ ...current, 1: panel1 }))
        }
        if (panel2) {
          setPreset((current) => ({ ...current, 2: panel2 }))
          setApplied((current) => ({ ...current, 2: panel2 }))
        }
        if (computer3) {
          setComputer3Preset(computer3)
          setComputer3Applied(computer3)
        }
      } catch {
        // The buttons stay unselected until a layout command has been saved.
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

  useEffect(() => {
    let cancel = false
    void (async () => {
      try {
        const response = await fetch("/api/apps")
        const body = (await response.json()) as { pins?: PinnedApp[] }
        if (!cancel && body.pins) setPins(withCConnect(body.pins))
      } catch {
        // The shelf stays empty until a program is added.
      }
    })()
    return () => {
      cancel = true
    }
  }, [])

  useEffect(() => {
    let cancel = false
    void (async () => {
      try {
        const response = await fetch("/api/links")
        const body = (await response.json()) as { links?: SavedLink[] }
        if (!cancel && body.links) setLinks(body.links)
      } catch {
        // The shelf stays empty until a site is saved.
      }
    })()
    return () => {
      cancel = true
    }
  }, [])

  const panel = selection.panel
  const computer3Scope = selection.panel === 2 && (selection.screen === "computer-3" || COMPUTER_3_IDS.includes(selection.screen))
  const computer2Scope = selection.panel === 2 && (selection.screen === "computer-2" || COMPUTER_2_IDS.includes(selection.screen))
  const everyScreen = selection.screen === "every"
  const targets = everyScreen
    ? SCREENS.map((screen) => screen.id)
    : selection.screen === "all"
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
  const customFor = (computer: "101" | "102" | "103") =>
    customViews
      .filter((view) => canApplyCustomView(view, computer))
      .map((view) => asPreset(adaptCustomView(view, computer)!))
  const panel1Presets = [...PRESETS[1], ...customFor("101")]
  const panel2Presets = [...PRESETS[2], ...customFor("102")]
  const computer3Presets = [...COMPUTER_3_PRESETS, ...customFor("103")]
  const computer2Preset = chosenPreset(panel2Presets, preset[2])
  const activeComputer3Preset = chosenPreset(computer3Presets, computer3Preset) ?? COMPUTER_3_PRESETS[0]
  const pending1 = preset[1] !== "" && preset[1] !== applied[1]
  const pending2 = preset[2] !== "" && preset[2] !== applied[2]
  const pending3 = computer3Preset !== "" && computer3Preset !== computer3Applied
  const viewComputer: "101" | "102" | "103" = panel === 1 ? "101" : computer3Scope ? "103" : "102"
  const viewAllowed = CUSTOM_VIEW_SCREENS[viewComputer]
  const viewAssigned = viewBuckets.flat()
  const viewCurrentBucket = viewBuckets[viewBucketIndex] ?? []
  const draftViewPreset =
    viewEditorOpen && viewAssigned.length > 0
      ? ({ id: "draft", name: viewName.trim() || "Custom", groups: groupsFromBuckets(viewComputer, viewBuckets) } satisfies Preset)
      : null
  const current = SCREENS.find((screen) => screen.id === selection.screen)
  if (current) screenHold.current = current
  const addressPresence = usePresence(Boolean(current))
  const addressScreen = current ?? (addressPresence.mounted ? screenHold.current : undefined)
  const keyboardPresence = usePresence(Boolean(keyboardOpen && addressScreen))
  const browsePresence = usePresence(browseBusy)
  const remotePresence = usePresence(Boolean(remoteAsk))
  if (remoteAsk) remoteHold.current = remoteAsk
  const remoteComputer = remoteAsk || remoteHold.current
  const scopeLabel = everyScreen
    ? "ALL SCREENS"
    : selection.screen === "all"
      ? "WHOLE PANEL"
      : selection.screen === "computer-2" || selection.screen === "computer-3"
        ? "SCREENS"
        : "ONE SCREEN"
  const scopeTitle = everyScreen
    ? "Panels 1 and 2"
    : selection.screen === "all"
      ? `Panel ${panel}`
      : selection.screen === "computer-2"
        ? "Screens 9–12 and 14–17"
        : selection.screen === "computer-3"
          ? "Screens 13 and 18"
          : current?.id
  const scopeDetail = everyScreen
    ? `All ${targets.length} screens. Tap a panel or one screen to adjust it alone.`
    : selection.screen === "all"
      ? `All ${targets.length} screens. Tap one screen to adjust it alone.`
      : selection.screen === "computer-2" || selection.screen === "computer-3"
        ? "Tap the panel edge to adjust every screen on panel 2."
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
    brightnessDraft.current = level
    setBrightness((currentBrightness) => {
      const next = { ...currentBrightness }
      screens.forEach((id) => {
        next[id] = level
      })
      return next
    })
    if (brightnessTimer.current) clearTimeout(brightnessTimer.current)
    brightnessTimer.current = setTimeout(() => {
      if (brightnessDraft.current === level) brightnessDraft.current = null
      void sendBrightness(screens, level, previous)
    }, 80)
  }

  function stepBrightness(delta: number) {
    const base = brightnessDraft.current ?? shownBrightness
    const next = Math.min(100, Math.max(0, Math.round(base) + delta))
    if (next === base && brightnessValues.every((value) => value === next)) return
    applyBrightness(next)
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
      ? {
          label: "PANEL 1 PRESETS",
          presets: panel1Presets,
          activeId: preset[1],
          appliedId: applied[1],
          computer: "101" as const,
          target: GROUP_LABEL["101"],
          rows: PANEL_1,
        }
      : computer3Scope
        ? {
            label: "SCREENS 13 AND 18",
            presets: computer3Presets,
            activeId: computer3Preset,
            appliedId: computer3Applied,
            computer: "103" as const,
            target: GROUP_LABEL["103"],
            rows: COMPUTER_3,
          }
        : {
            label: "SCREENS 9–12, 14–17",
            presets: panel2Presets,
            activeId: preset[2],
            appliedId: applied[2],
            computer: "102" as const,
            target: GROUP_LABEL["102"],
            rows: COMPUTER_2,
          }

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

  function zoneFor(screenId: string) {
    const computer = COMPUTER_OF[screenId]
    const layoutId = computer === "101" ? applied[1] : computer === "102" ? applied[2] : computer3Applied
    const list = computer === "103" ? computer3Presets : computer === "101" ? panel1Presets : panel2Presets
    const active = list.find((item) => item.id === layoutId)
    const ids = computer === "103" ? COMPUTER_3_IDS : computer === "101" ? IDS[1] : COMPUTER_2_IDS
    const group = active?.groups[screenId]
    const zone = active ? ids.filter((id) => active.groups[id] === group) : [screenId]
    return { computer, zone }
  }

  function zoneLabel(zone: string[]) {
    return zone.length > 1 ? `screens ${zone.map(screenNumber).join(", ")}` : `screen ${screenNumber(zone[0] ?? "")}`
  }

  async function closeComputers(computers: Array<"101" | "102" | "103">, done: string) {
    if (layoutBusy.current) return
    layoutBusy.current = true
    const where = computers.map((computer) => GROUP_LABEL[computer]).join(" and ")
    setLayoutStatus(`Closing Edge on ${where}…`)
    try {
      const results = await Promise.all(
        computers.map(async (computer) => {
          const response = await fetch("/api/layout", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ computer, preset: "close" }),
          })
          const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
          return { computer, ok: response.ok, text: body?.message || body?.error || "The layout did not start." }
        }),
      )
      const failed = results.filter((item) => !item.ok)
      setLayoutStatus(failed.length === 0 ? done : failed.map((item) => item.text).join(" "))
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
  }

  async function closeAllEdge() {
    await closeComputers(["101", "102", "103"], "Closed Edge on every screen.")
  }

  async function clearCConnectLogin() {
    if (layoutBusy.current) return
    layoutBusy.current = true
    setLayoutStatus("Clearing the shared C-Connect login on every screen…")
    try {
      const results = await Promise.all(
        (["101", "102", "103"] as const).map(async (computer) => {
          const response = await fetch("/api/layout", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ computer, preset: "reset-login" }),
          })
          const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
          return { computer, ok: response.ok, text: body?.message || body?.error || "The login did not clear." }
        }),
      )
      const failed = results.filter((item) => !item.ok)
      if (failed.length === 0) {
        setApplied({ 1: "", 2: "" })
        setComputer3Applied("")
        setPreset({ 1: "", 2: "" })
        setComputer3Preset("")
        setLayoutStatus("Cleared C-Connect login on every screen. Open a preset and sign in with your account.")
      } else {
        setLayoutStatus(failed.map((item) => item.text).join(" "))
      }
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
  }

  async function closeSelectedEdge() {
    if (selection.screen === "every") {
      await closeAllEdge()
      return
    }
    if (selection.screen === "all") {
      if (panel === 1) await closeComputers(["101"], "Closed Edge on screens 1–8.")
      else await closeComputers(["102", "103"], "Closed Edge on screens 9–18.")
      return
    }
    if (selection.screen === "computer-2") {
      await closeComputers(["102"], "Closed Edge on screens 9–12 and 14–17.")
      return
    }
    if (selection.screen === "computer-3") {
      await closeComputers(["103"], "Closed Edge on screens 13 and 18.")
      return
    }
    const screenId = selection.screen
    const computer = COMPUTER_OF[screenId]
    if (!computer || layoutBusy.current) return
    layoutBusy.current = true
    const { zone } = zoneFor(screenId)
    const label = zoneLabel(zone)
    setLayoutStatus(`Closing Edge on ${label}…`)
    try {
      const response = await fetch("/api/layout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer, preset: "close", screen: screenId }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string; empty?: boolean } | null
      if (!response.ok) {
        setLayoutStatus(body?.error || "Edge did not close.")
        return
      }
      setLayoutStatus(`Closed Edge on ${label}.`)
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
  }

  async function refreshComputers(computers: Array<"101" | "102" | "103">, done: string) {
    if (layoutBusy.current) return
    layoutBusy.current = true
    const where = computers.map((computer) => GROUP_LABEL[computer]).join(" and ")
    setLayoutStatus(`Refreshing Edge on ${where}…`)
    try {
      const results = await Promise.all(
        computers.map(async (computer) => {
          const response = await fetch("/api/layout", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ computer, preset: "refresh" }),
          })
          const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
          return { computer, ok: response.ok, text: body?.message || body?.error || "The pages did not refresh." }
        }),
      )
      const failed = results.filter((item) => !item.ok)
      setLayoutStatus(failed.length === 0 ? done : failed.map((item) => item.text).join(" "))
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
  }

  async function refreshSelectedEdge() {
    if (selection.screen === "every") {
      await refreshComputers(["101", "102", "103"], "Refreshed Edge on every screen.")
      return
    }
    if (selection.screen === "all") {
      if (panel === 1) await refreshComputers(["101"], "Refreshed Edge on screens 1–8.")
      else await refreshComputers(["102", "103"], "Refreshed Edge on screens 9–18.")
      return
    }
    if (selection.screen === "computer-2") {
      await refreshComputers(["102"], "Refreshed Edge on screens 9–12 and 14–17.")
      return
    }
    if (selection.screen === "computer-3") {
      await refreshComputers(["103"], "Refreshed Edge on screens 13 and 18.")
      return
    }
    const screenId = selection.screen
    const computer = COMPUTER_OF[screenId]
    if (!computer || layoutBusy.current) return
    layoutBusy.current = true
    const { zone } = zoneFor(screenId)
    const label = zoneLabel(zone)
    setLayoutStatus(`Refreshing Edge on ${label}…`)
    try {
      const response = await fetch("/api/layout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer, preset: "refresh", screen: screenId }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      if (!response.ok) {
        setLayoutStatus(body?.error || "The pages did not refresh.")
        return
      }
      setLayoutStatus(`Refreshed Edge on ${label}.`)
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      layoutBusy.current = false
    }
  }

  async function controlWindow(action: "minimize" | "close") {
    try {
      const response = await fetch("/api/window", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      })
      if (!response.ok) {
        const body = (await response.json().catch(() => null)) as { error?: string } | null
        setLayoutStatus(body?.error || "The console window could not be changed.")
      }
    } catch {
      setLayoutStatus("Could not reach the console window.")
    }
  }

  function askRemote(computer: Computer) {
    if (armedApp || armedLink) {
      setArmedApp("")
      setArmedLink("")
      return
    }
    setRemoteAsk(computer)
  }

  async function runRemote(computer: Computer) {
    setRemoteAsk("")
    setLayoutStatus(`Opening the remote desktop for ${REMOTE_PANEL[computer]}…`)
    try {
      const response = await fetch("/api/remote", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ computer }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      setLayoutStatus(body?.message || body?.error || "The remote desktop did not open.")
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    }
  }

  const addressComputer = addressScreen ? COMPUTER_OF[addressScreen.id] : null
  const addressPreset =
    addressComputer === "103"
      ? presetById(computer3Presets, computer3Applied, "independent")
      : addressComputer === "101"
        ? presetById(panel1Presets, applied[1], "focus")
        : presetById(panel2Presets, applied[2], "focus")
  const addressIds = addressComputer === "103" ? COMPUTER_3_IDS : addressComputer === "101" ? IDS[1] : COMPUTER_2_IDS
  const zoneIds = addressScreen ? addressIds.filter((id) => addressPreset.groups[id] === addressPreset.groups[addressScreen.id]) : []
  const shownZone = zoneIds.length > 0 ? zoneIds : addressScreen ? [addressScreen.id] : []
  const addressValue = addressScreen ? addresses[addressScreen.id] ?? DEFAULT_URL : DEFAULT_URL
  const previewPending = footer.activeId !== "" && footer.activeId !== footer.appliedId

  function focusAddressInput(selectAll = false) {
    const input = addressInputRef.current
    if (!input) return
    input.focus()
    const end = input.value.length
    if (selectAll) input.setSelectionRange(0, end)
    else input.setSelectionRange(end, end)
    addressCaret.current = {
      start: input.selectionStart ?? end,
      end: input.selectionEnd ?? end,
    }
  }

  function readAddressCaret() {
    const input = addressInputRef.current
    if (!input) return addressCaret.current
    return {
      start: input.selectionStart ?? input.value.length,
      end: input.selectionEnd ?? input.value.length,
    }
  }

  function applyAddressEdit(next: { value: string; caret: number }) {
    if (!current) return
    const id = current.id
    setAddresses((existing) => ({ ...existing, [id]: next.value }))
    setReplaceAddress(false)
    addressCaret.current = { start: next.caret, end: next.caret }
    requestAnimationFrame(() => {
      const input = addressInputRef.current
      if (!input) return
      input.focus()
      input.setSelectionRange(next.caret, next.caret)
    })
  }

  function insertAddress(token: string) {
    if (!current) return
    const value = addresses[current.id] ?? DEFAULT_URL
    const caret = readAddressCaret()
    applyAddressEdit(insertAtCaret(value, token, caret.start, caret.end, replaceAddress))
  }

  function insertScheme() {
    if (!current) return
    const value = addresses[current.id] ?? DEFAULT_URL
    if (replaceAddress || value.trim() === "") {
      applyAddressEdit({ value: "https://", caret: "https://".length })
      return
    }
    if (/^https?:\/\//i.test(value)) {
      setReplaceAddress(false)
      focusAddressInput()
      return
    }
    applyAddressEdit({ value: `https://${value}`, caret: `https://${value}`.length })
  }

  function backspaceAddress() {
    if (!current) return
    const value = addresses[current.id] ?? DEFAULT_URL
    const caret = readAddressCaret()
    applyAddressEdit(backspaceAtCaret(value, caret.start, caret.end, replaceAddress))
  }

  function clearAddress() {
    applyAddressEdit({ value: "", caret: 0 })
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

  function pressScreen() {
    launchPin.current = armedRef.current
    launchLinkId.current = armedLinkRef.current
  }

  function choose(next: Selection) {
    if (viewEditorOpen) {
      if (/^TV\d+$/.test(next.screen)) {
        if (!viewAllowed.includes(next.screen)) {
          setPanelGuardOpen(true)
          return
        }
        setViewBuckets((current) => {
          const inCurrent = (current[viewBucketIndex] ?? []).includes(next.screen)
          const nextBuckets = current.map((bucket) => bucket.filter((id) => id !== next.screen))
          while (nextBuckets.length <= viewBucketIndex) nextBuckets.push([])
          if (!inCurrent) nextBuckets[viewBucketIndex] = [...(nextBuckets[viewBucketIndex] ?? []), next.screen]
          return nextBuckets.length > 0 ? nextBuckets : [[]]
        })
        setViewStatus("")
        return
      }
      if (next.panel === 1 && viewComputer !== "101") {
        setPanelGuardOpen(true)
        return
      }
      if (next.panel === 2 && viewComputer === "101") {
        setPanelGuardOpen(true)
        return
      }
      return
    }
    setSelection(next)
    const pin = launchPin.current
    const linkId = launchLinkId.current
    launchPin.current = ""
    launchLinkId.current = ""
    if (!/^TV\d+$/.test(next.screen)) return
    if (pin) void openProgram(pin, next.screen)
    else if (linkId) void openSavedLink(linkId, next.screen)
  }

  function openViewEditor() {
    setViewEditorOpen(true)
    setViewName("")
    setViewBuckets([[]])
    setViewBucketIndex(0)
    setViewReplace(false)
    setViewStatus("Type a name, paint group 1, then tap New group for another Edge window.")
    requestAnimationFrame(() => {
      const input = viewNameRef.current
      if (!input) return
      input.focus()
      const end = input.value.length
      input.setSelectionRange(end, end)
      viewCaret.current = { start: end, end }
    })
  }

  function addViewGroup() {
    if (viewBuckets.length >= MAX_VIEW_GROUPS) {
      setViewStatus(`This view already has ${MAX_VIEW_GROUPS} groups.`)
      return
    }
    if ((viewBuckets[viewBucketIndex] ?? []).length === 0) {
      setViewStatus("Add screens to this group before starting another.")
      return
    }
    setViewBuckets((current) => [...current, []])
    setViewBucketIndex(viewBuckets.length)
    setViewStatus(`Paint group ${viewBuckets.length + 1}. Tap screens that should share that Edge window.`)
  }

  function insertViewToken(token: string) {
    const input = viewNameRef.current
    const start = input?.selectionStart ?? viewCaret.current.start
    const end = input?.selectionEnd ?? viewCaret.current.end
    const next = insertAtCaret(viewName, token, start, end, viewReplace)
    setViewName(next.value.slice(0, 40))
    setViewReplace(false)
    viewCaret.current = { start: next.caret, end: next.caret }
    requestAnimationFrame(() => {
      if (!input) return
      input.focus()
      input.setSelectionRange(next.caret, next.caret)
    })
  }

  function backspaceView() {
    const input = viewNameRef.current
    const start = input?.selectionStart ?? viewCaret.current.start
    const end = input?.selectionEnd ?? viewCaret.current.end
    const next = backspaceAtCaret(viewName, start, end)
    setViewName(next.value)
    setViewReplace(false)
    viewCaret.current = { start: next.caret, end: next.caret }
    requestAnimationFrame(() => {
      if (!input) return
      input.focus()
      input.setSelectionRange(next.caret, next.caret)
    })
  }

  async function saveCustomView() {
    if (viewBusy) return
    if (!viewName.trim()) {
      setViewStatus("Type a name for this view.")
      return
    }
    const checked = validateViewBuckets(viewComputer, viewBuckets)
    if (!checked.ok) {
      setViewStatus(checked.message)
      return
    }
    setViewBusy(true)
    setViewStatus("Saving…")
    try {
      const response = await fetch("/api/views", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "add", computer: viewComputer, name: viewName, groups: checked.buckets }),
      })
      const body = (await response.json().catch(() => null)) as {
        views?: CustomView[]
        selectedId?: string
        error?: string
      } | null
      if (!response.ok || !body?.views || !body.selectedId) {
        setViewStatus(body?.error || "The view did not save.")
        return
      }
      setCustomViews(body.views)
      const id = body.selectedId
      const name = body.views.find((view) => view.id === id)?.name ?? viewName.trim()
      if (viewComputer === "103") setComputer3Preset(id)
      else if (viewComputer === "101") setPreset((current) => ({ ...current, 1: id }))
      else setPreset((current) => ({ ...current, 2: id }))
      setViewEditorOpen(false)
      setLayoutStatus(`Previewing ${name} on ${GROUP_LABEL[viewComputer]}. Confirm to open Edge, or cancel.`)
    } catch {
      setViewStatus("Could not save the view.")
    } finally {
      setViewBusy(false)
    }
  }

  async function removeCustomView(id: string) {
    try {
      const response = await fetch("/api/views", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "remove", id }),
      })
      const body = (await response.json().catch(() => null)) as { views?: CustomView[] } | null
      if (!response.ok || !body?.views) {
        setLayoutStatus("The custom view could not be removed.")
        return
      }
      setCustomViews(body.views)
      if (preset[1] === id) {
        setPreset((current) => ({ ...current, 1: applied[1] === id ? "" : applied[1] }))
        if (applied[1] === id) setApplied((current) => ({ ...current, 1: "" }))
      }
      if (preset[2] === id) {
        setPreset((current) => ({ ...current, 2: applied[2] === id ? "" : applied[2] }))
        if (applied[2] === id) setApplied((current) => ({ ...current, 2: "" }))
      }
      if (computer3Preset === id) {
        setComputer3Preset(computer3Applied === id ? "" : computer3Applied)
        if (computer3Applied === id) setComputer3Applied("")
      }
      setLayoutStatus("Removed the custom view.")
    } catch {
      setLayoutStatus("Could not remove the custom view.")
    }
  }

  function rememberApplied(computer: "101" | "102" | "103", id: string) {
    if (computer === "103") {
      setComputer3Preset(id)
      setComputer3Applied(id)
      return
    }
    const panelId: PanelId = computer === "101" ? 1 : 2
    setPreset((currentPreset) => ({ ...currentPreset, [panelId]: id }))
    setApplied((currentApplied) => ({ ...currentApplied, [panelId]: id }))
  }

  async function runningLayout(computer: "101" | "102" | "103") {
    const known = computer === "101" ? applied[1] : computer === "102" ? applied[2] : computer3Applied
    if (known) return known
    try {
      const response = await fetch("/api/layout", { cache: "no-store" })
      const body = (await response.json()) as { layouts?: Record<string, string> }
      const builtins =
        computer === "103" ? COMPUTER_3_PRESETS.map((item) => item.id) : computer === "101" ? PRESETS[1].map((item) => item.id) : PRESETS[2].map((item) => item.id)
      const allowed = [...builtins, ...customViews.filter((view) => canApplyCustomView(view, computer)).map((view) => view.id)]
      const saved = savedPreset(body.layouts?.[computer], allowed)
      if (saved) rememberApplied(computer, saved)
      return saved
    } catch {
      return ""
    }
  }

  function zoneForScreen(screenId: string, layoutId: string) {
    const computer = COMPUTER_OF[screenId]
    if (!computer) return [screenId]
    const list =
      computer === "103" ? computer3Presets : computer === "101" ? panel1Presets : panel2Presets
    const active = list.find((item) => item.id === layoutId)
    const ids = computer === "103" ? COMPUTER_3_IDS : computer === "101" ? IDS[1] : COMPUTER_2_IDS
    const group = active?.groups[screenId]
    return active ? ids.filter((id) => active.groups[id] === group) : [screenId]
  }

  async function openProgram(pinId: string, screenId: string) {
    const pin = pins.find((item) => item.id === pinId)
    if (!pin) return
    const computer = COMPUTER_OF[screenId]
    if (!computer) return
    if (launchLock.current || layoutBusy.current) {
      setProgramStatus("Wait for the layout to finish opening.")
      return
    }
    launchLock.current = true
    const layoutId = await runningLayout(computer)
    const zone = zoneForScreen(screenId, layoutId)
    const label = zone.length > 1 ? `screens ${zone.map(screenNumber).join(", ")}` : `screen ${screenNumber(screenId)}`
    const opening = `Opening ${pin.name} on ${label}…`
    setProgramStatus(opening)
    setLayoutStatus(opening)
    try {
      const response = await fetch("/api/apps", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "launch", id: pin.id, screen: screenId }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      if (!response.ok) {
        const note = body?.error || "The program did not open."
        setProgramStatus(note)
        setLayoutStatus(note)
        return
      }
      const note = `Opened ${pin.name} on ${label}.`
      setProgramStatus(note)
      setLayoutStatus(note)
      if (pin.id === C_CONNECT_ID) {
        setAddresses((existing) => {
          const next = { ...existing }
          for (const id of zone) next[id] = C_CONNECT_URL
          return next
        })
      }
      setArmedApp("")
      setArmedLink("")
    } catch {
      const note = "Could not reach the layout service."
      setProgramStatus(note)
      setLayoutStatus(note)
    } finally {
      launchLock.current = false
    }
  }

  async function openSavedLink(linkId: string, screenId: string) {
    const link = links.find((item) => item.id === linkId)
    if (!link) return
    const computer = COMPUTER_OF[screenId]
    if (!computer) return
    if (launchLock.current || layoutBusy.current) {
      setLinkStatus("Wait for the layout to finish opening.")
      return
    }
    launchLock.current = true
    const layoutId = await runningLayout(computer)
    const zone = zoneForScreen(screenId, layoutId)
    const label = zone.length > 1 ? `screens ${zone.map(screenNumber).join(", ")}` : `screen ${screenNumber(screenId)}`
    const opening = `Opening ${link.name} on ${label}…`
    setLinkStatus(opening)
    setLayoutStatus(opening)
    try {
      const response = await fetch("/api/links", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "launch", id: link.id, screen: screenId }),
      })
      const body = (await response.json().catch(() => null)) as { message?: string; error?: string } | null
      if (!response.ok) {
        const note = body?.error || "The site did not open."
        setLinkStatus(note)
        setLayoutStatus(note)
        return
      }
      const note = `Opened ${link.name} on ${label}.`
      setLinkStatus(note)
      setLayoutStatus(note)
      setAddresses((existing) => {
        const next = { ...existing }
        for (const id of zone) next[id] = link.url
        return next
      })
      setArmedApp("")
      setArmedLink("")
    } catch {
      const note = "Could not reach the layout service."
      setLinkStatus(note)
      setLayoutStatus(note)
    } finally {
      launchLock.current = false
    }
  }

  function screenUnder(x: number, y: number) {
    for (const hit of document.elementsFromPoint(x, y)) {
      const tile = hit.closest("[data-screen-id]")
      if (tile) return tile.getAttribute("data-screen-id") ?? ""
    }
    return ""
  }

  function shelfPointer(kind: "program" | "link", itemId: string) {
    return {
      onPointerDown(event: ReactPointerEvent<HTMLButtonElement>) {
        if (event.button !== 0) return
        event.preventDefault()
        dragSession.current = { pointerId: event.pointerId, kind, id: itemId, x: event.clientX, y: event.clientY, dragging: false }
        event.currentTarget.setPointerCapture(event.pointerId)
      },
      onPointerMove(event: ReactPointerEvent<HTMLButtonElement>) {
        const session = dragSession.current
        if (!session || session.pointerId !== event.pointerId) return
        const dx = event.clientX - session.x
        const dy = event.clientY - session.y
        if (!session.dragging && dx * dx + dy * dy < 36) return
        session.dragging = true
        setDrag({ kind: session.kind, id: session.id, x: event.clientX, y: event.clientY, over: screenUnder(event.clientX, event.clientY) })
      },
      onPointerUp(event: ReactPointerEvent<HTMLButtonElement>) {
        const session = dragSession.current
        if (!session || session.pointerId !== event.pointerId) return
        dragSession.current = null
        if (!session.dragging) {
          if (kind === "program") {
            setProgramStatus("")
            setArmedLink("")
            setArmedApp((currentId) => (currentId === itemId ? "" : itemId))
          } else {
            setLinkStatus("")
            setArmedApp("")
            setArmedLink((currentId) => (currentId === itemId ? "" : itemId))
          }
          setDrag(null)
          return
        }
        const screenId = screenUnder(event.clientX, event.clientY)
        setDrag(null)
        if (!screenId) return
        setSelection({ panel: COMPUTER_OF[screenId] === "101" ? 1 : 2, screen: screenId })
        if (kind === "program") void openProgram(itemId, screenId)
        else void openSavedLink(itemId, screenId)
      },
      onPointerCancel() {
        dragSession.current = null
        setDrag(null)
      },
    }
  }

  function programPointer(pinId: string) {
    return shelfPointer("program", pinId)
  }

  function linkPointer(linkId: string) {
    return shelfPointer("link", linkId)
  }

  async function browseProgram() {
    if (browseBusy) return
    setBrowseBusy(true)
    setProgramStatus("")
    setArmedLink("")
    closeLinkEditor()
    setLayoutStatus("Choose a program.")
    try {
      const response = await fetch("/api/apps", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "browse" }),
      })
      const body = (await response.json().catch(() => null)) as { pins?: PinnedApp[]; selectedId?: string; canceled?: boolean; error?: string } | null
      if (!response.ok || !body?.pins) {
        setLayoutStatus(body?.error || "The program list could not be opened.")
        return
      }
      setPins(withCConnect(body.pins))
      if (body.selectedId) {
        setArmedApp(body.selectedId)
        setArmedLink("")
      }
      setLayoutStatus(body.canceled ? "No program was added." : "Tap a screen, or drag the program onto it.")
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    } finally {
      setBrowseBusy(false)
    }
  }

  async function removeProgram(id: string) {
    if (armedApp === id) setArmedApp("")
    try {
      const response = await fetch("/api/apps", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "remove", id }),
      })
      const body = (await response.json().catch(() => null)) as { pins?: PinnedApp[] } | null
      if (body?.pins) setPins(withCConnect(body.pins))
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    }
  }

  function openLinkEditor(link?: SavedLink) {
    setArmedApp("")
    setArmedLink("")
    setLinkStatus("")
    setEditingLinkId(link?.id ?? "")
    setLinkName(link?.name ?? "")
    setLinkUrl(link?.url ?? "https://")
    setLinkField("name")
    setLinkReplace(false)
    linkCaret.current = { start: 0, end: 0 }
    setLinkEditorOpen(true)
    setKeyboardOpen(false)
    requestAnimationFrame(() => {
      const input = linkNameRef.current
      if (!input) return
      input.focus()
      if (link) {
        input.setSelectionRange(0, input.value.length)
        setLinkReplace(true)
        linkCaret.current = { start: 0, end: input.value.length }
      } else {
        input.setSelectionRange(0, 0)
      }
    })
  }

  function closeLinkEditor() {
    setLinkEditorOpen(false)
    setEditingLinkId("")
  }

  function focusLinkField(field: "name" | "url", selectAll = false) {
    setLinkField(field)
    const input = field === "name" ? linkNameRef.current : linkUrlRef.current
    if (!input) return
    input.focus()
    const end = input.value.length
    if (selectAll) {
      input.setSelectionRange(0, end)
      setLinkReplace(true)
    } else {
      input.setSelectionRange(end, end)
      setLinkReplace(false)
    }
    linkCaret.current = {
      start: input.selectionStart ?? end,
      end: input.selectionEnd ?? end,
    }
  }

  function readLinkCaret() {
    const input = linkField === "name" ? linkNameRef.current : linkUrlRef.current
    if (!input) return linkCaret.current
    return {
      start: input.selectionStart ?? input.value.length,
      end: input.selectionEnd ?? input.value.length,
    }
  }

  function applyLinkEdit(next: { value: string; caret: number }) {
    const field = linkField
    const value = field === "name" ? next.value.slice(0, 40) : next.value
    const caret = field === "name" ? Math.min(next.caret, value.length) : next.caret
    if (field === "name") setLinkName(value)
    else setLinkUrl(value)
    setLinkReplace(false)
    linkCaret.current = { start: caret, end: caret }
    requestAnimationFrame(() => {
      const input = field === "name" ? linkNameRef.current : linkUrlRef.current
      if (!input) return
      input.focus()
      input.setSelectionRange(caret, caret)
    })
  }

  function insertLinkToken(token: string) {
    const value = linkField === "name" ? linkName : linkUrl
    const caret = readLinkCaret()
    applyLinkEdit(insertAtCaret(value, token, caret.start, caret.end, linkReplace))
  }

  function insertLinkScheme() {
    if (linkField !== "url") {
      setLinkField("url")
      setLinkUrl("https://")
      setLinkReplace(false)
      requestAnimationFrame(() => focusLinkField("url"))
      return
    }
    if (linkReplace || linkUrl.trim() === "") {
      applyLinkEdit({ value: "https://", caret: "https://".length })
      return
    }
    if (/^https?:\/\//i.test(linkUrl)) {
      setLinkReplace(false)
      focusLinkField("url")
      return
    }
    applyLinkEdit({ value: `https://${linkUrl}`, caret: `https://${linkUrl}`.length })
  }

  function backspaceLink() {
    const value = linkField === "name" ? linkName : linkUrl
    const caret = readLinkCaret()
    applyLinkEdit(backspaceAtCaret(value, caret.start, caret.end, linkReplace))
  }

  function clearLinkField() {
    applyLinkEdit({ value: "", caret: 0 })
  }

  async function saveLink() {
    if (linkBusy) return
    setLinkBusy(true)
    setLinkStatus("")
    const editing = editingLinkId !== ""
    try {
      const response = await fetch("/api/links", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          editing
            ? { action: "update", id: editingLinkId, name: linkName, url: linkUrl }
            : { action: "add", name: linkName, url: linkUrl },
        ),
      })
      const body = (await response.json().catch(() => null)) as { links?: SavedLink[]; selectedId?: string; error?: string } | null
      if (!response.ok || !body?.links) {
        setLinkStatus(body?.error || (editing ? "The site could not be updated." : "The site could not be saved."))
        return
      }
      setLinks(body.links)
      closeLinkEditor()
      if (body.selectedId) {
        setArmedApp("")
        setArmedLink(body.selectedId)
      }
      setLinkStatus("Tap a screen, or drag the site onto it.")
      setLayoutStatus("Tap a screen, or drag the site onto it.")
    } catch {
      setLinkStatus("Could not reach the layout service.")
    } finally {
      setLinkBusy(false)
    }
  }

  async function removeSavedLink(id: string) {
    if (armedLink === id) setArmedLink("")
    try {
      const response = await fetch("/api/links", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "remove", id }),
      })
      const body = (await response.json().catch(() => null)) as { links?: SavedLink[] } | null
      if (body?.links) setLinks(body.links)
    } catch {
      setLayoutStatus("Could not reach the layout service.")
    }
  }

  armedRef.current = armedApp
  armedLinkRef.current = armedLink
  const armedPin = pins.find((pin) => pin.id === armedApp) ?? null
  if (armedPin) coachHold.current = armedPin
  const coachPin = armedPin ?? coachHold.current
  const coachPresence = usePresence(Boolean(armedPin) && !drag)
  const linkEditorPresence = usePresence(linkEditorOpen)
  usePhysicalTyping(linkEditorOpen, {
    onInsert: insertLinkToken,
    onBackspace: backspaceLink,
    onEnter: () => {
      void saveLink()
    },
    onEscape: () => closeLinkEditor(),
  })
  const viewEditorPresence = usePresence(viewEditorOpen)
  const panelGuardPresence = usePresence(panelGuardOpen)
  if (removeViewAsk) removeViewHold.current = removeViewAsk
  const removeViewShown = removeViewAsk ?? removeViewHold.current
  const removeViewPresence = usePresence(Boolean(removeViewAsk))
  usePhysicalTyping(viewEditorOpen && !panelGuardOpen && !removeViewAsk, {
    onInsert: insertViewToken,
    onBackspace: backspaceView,
    onEnter: () => {
      void saveCustomView()
    },
    onEscape: () => setViewEditorOpen(false),
  })
  const addressScreenId = addressScreen?.id ?? ""
  useEffect(() => {
    if (!keyboardOpen || !addressScreenId) return
    requestAnimationFrame(() => focusAddressInput(true))
  }, [keyboardOpen, addressScreenId])
  const shownPreset = footer.presets.find((item) => item.id === footer.activeId)
  if (previewPending && shownPreset) presetCoachHold.current = { rows: footer.rows, preset: shownPreset }
  const presetCoach = presetCoachHold.current
  const presetCoachPresence = usePresence(previewPending && !viewEditorOpen && Boolean(shownPreset))

  return (
    <main className="flex h-svh flex-col overflow-hidden bg-[radial-gradient(circle_at_top,#1650c8_0%,#06215f_42%,#03102e_100%)] text-white">
      <header className="flex items-center justify-between gap-4 border-b border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="flex items-center gap-3">
          <img src="/mt-logo.png" alt="MT" className="h-10 w-auto" />
          <div>
            <p className="text-sm font-semibold tracking-[0.14em] whitespace-nowrap">REMOTE OPERATION CENTER</p>
            <p className="text-[11px] tracking-[0.22em] text-cyan-100/70">PANEL CONTROL</p>
          </div>
        </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              aria-label="Minimize"
              onClick={() => void controlWindow("minimize")}
              className="flex h-9 w-11 items-center justify-center rounded-lg border border-cyan-200/35 bg-[#16315f] text-lg leading-none text-cyan-50 transition hover:bg-white/10"
            >
              –
            </button>
            <button
              type="button"
              aria-label="Close"
              onClick={() => void controlWindow("close")}
              className="flex h-9 w-11 items-center justify-center rounded-lg border border-cyan-200/35 bg-[#16315f] text-xl leading-none text-cyan-50 transition hover:bg-red-500/40"
            >
              ×
            </button>
          </div>
      </header>

      <div ref={scrollArea} className="flex min-h-0 flex-1 flex-col overflow-x-hidden overflow-y-auto pb-24">
      <section className="flex flex-col gap-3 px-4 py-3 lg:px-6">
        <div className="rounded-2xl border border-cyan-300/40 bg-[#0a2f86]/55 p-3 shadow-[0_0_28px_rgba(40,140,255,0.25)]">
          <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
            <div className="min-w-64 flex-[1.2] basis-64">
              <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{scopeLabel}</p>
              <h1 className="mt-0.5 line-clamp-2 text-2xl font-semibold leading-tight tracking-wide">{scopeTitle}</h1>
              <p className="mt-1 line-clamp-2 text-sm leading-5 text-cyan-100/80">{scopeDetail}</p>
            </div>

            <div className="grid w-80 shrink-0 grid-cols-3 gap-2">
              <GlowButton active={everyScreen} onClick={() => setSelection({ panel, screen: everyScreen ? "all" : "every" })}>
                Select All
              </GlowButton>
              <GlowButton active={allOn} onClick={() => applyPower(true)}>
                On
              </GlowButton>
              <GlowButton active={allOff} tone="alert" onClick={() => applyPower(false)}>
                Off
              </GlowButton>
            </div>

            <div className="min-w-56 flex-1 basis-56">
              <div className="mb-2 flex items-baseline justify-between text-sm">
                <span>Brightness</span>
                <span className="text-cyan-100 tabular-nums">{sameBrightness ? `${shownBrightness}%` : "Mixed"}</span>
              </div>
              <div className="flex items-center gap-2">
                <Slider
                  className="min-w-0 flex-1"
                  min={0}
                  max={100}
                  value={[shownBrightness]}
                  onValueChange={(value) => applyBrightness(Array.isArray(value) ? value[0] : value)}
                  aria-label="Brightness"
                />
                <div className="flex shrink-0 gap-1">
                  <button
                    type="button"
                    aria-label="Decrease brightness"
                    disabled={!brightnessValues.some((value) => value > 0)}
                    onClick={() => stepBrightness(-1)}
                    className="flex h-8 w-8 items-center justify-center rounded-md border border-cyan-200/35 bg-[#16315f] text-xs leading-none text-cyan-50 transition hover:bg-white/10 disabled:pointer-events-none disabled:opacity-40"
                  >
                    ▼
                  </button>
                  <button
                    type="button"
                    aria-label="Increase brightness"
                    disabled={!brightnessValues.some((value) => value < 100)}
                    onClick={() => stepBrightness(1)}
                    className="flex h-8 w-8 items-center justify-center rounded-md border border-cyan-200/35 bg-[#16315f] text-xs leading-none text-cyan-50 transition hover:bg-white/10 disabled:pointer-events-none disabled:opacity-40"
                  >
                    ▲
                  </button>
                </div>
              </div>
            </div>

            <div className="min-w-56 flex-1 basis-64">
              <p className={`text-xs leading-5 text-cyan-100/80 ${current ? "invisible" : ""}`} aria-hidden={Boolean(current)}>
                Tap one screen to type its address.
              </p>
              <StatusLine text={layoutStatus} className="line-clamp-2 min-h-10 text-xs leading-5 text-cyan-100" />
            </div>
          </div>

          {addressPresence.mounted && addressScreen ? (
            <div className={`grid ${addressPresence.visible ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0"}`} style={motionStyle}>
              <div className="overflow-hidden">
                <div className="mt-3 flex flex-wrap items-end gap-3 border-t border-cyan-300/25 pt-3">
                  <div className="min-w-64 flex-1">
                    <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">ADDRESS</p>
                    <button
                      type="button"
                      data-typeable
                      onClick={() => {
                        closeLinkEditor()
                        setKeyboardOpen(true)
                        setReplaceAddress(true)
                      }}
                      className={`mt-2 w-full rounded-lg border px-3 py-2 text-left ${
                        keyboardOpen && replaceAddress ? "border-white bg-white/10" : "border-cyan-300/40 bg-[#08245f]/80"
                      }`}
                    >
                      <span className="block truncate text-sm leading-5">{addressValue || "Tap to type an address"}</span>
                    </button>
                    <p className="mt-2 line-clamp-2 text-xs leading-5 text-cyan-100/80">
                      {zoneDetail(shownZone)}
                      {previewPending ? " Confirm the layout preview, then set the address." : ""}
                    </p>
                  </div>
                  <GlowButton active onClick={() => void runAddress()}>
                    Open address
                  </GlowButton>
                </div>
              </div>
            </div>
          ) : null}
        </div>

        <div className="grid items-stretch gap-4 lg:grid-cols-[4fr_5fr]">
        <PanelFrame
          panel={1}
          title="Panel 1"
          detail="Screens 1–8"
          rows={PANEL_1}
          preset={viewComputer === "101" && draftViewPreset ? draftViewPreset : chosenPreset(panel1Presets, preset[1])}
          pending={pending1 && !viewEditorOpen}
          selection={selection}
          power={power}
          thumbStamp={thumbStamp}
          pickedIds={viewEditorOpen && viewComputer === "101" ? viewCurrentBucket : []}
          onSelect={choose}
          onPress={pressScreen}
          onOpenRemote={() => askRemote("101")}
          remoteLabel={REMOTE_PANEL["101"]}
          dropTarget={drag?.over ?? ""}
        />

        <section
          onClick={() => {
            if (viewEditorOpen && viewComputer === "101") {
              setPanelGuardOpen(true)
              return
            }
            if (viewEditorOpen) return
            setSelection({ panel: 2, screen: "all" })
          }}
          className={`flex h-full min-h-0 cursor-pointer flex-col rounded-2xl border bg-[#071a4d]/70 p-3 pb-5 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
            (selection.panel === 2 && selection.screen === "all") || everyScreen
              ? "border-white shadow-[0_0_24px_rgba(180,230,255,0.35)]"
              : selection.panel === 2
                ? "border-cyan-300/70"
                : "border-cyan-300/25"
          }`}
        >
          <div className="mb-3 flex items-end justify-between gap-2">
            <div>
              <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">Panel 2</h2>
              <p className="text-xs text-cyan-100/70">Screens 9–18</p>
            </div>
            <div className="flex items-center gap-2">
              <PreviewChip show={pending2 || pending3} />
              <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">
                {IDS[2].every((id) => power[id]) ? "ON" : IDS[2].every((id) => !power[id]) ? "OFF" : "MIXED"}
              </span>
            </div>
          </div>
          <div
            className="flex w-full items-stretch justify-center gap-2 [container-type:inline-size]"
            style={{ ["--pad" as string]: "1.25rem", ["--seam" as string]: `${SCREEN_GAP}px`, ["--tile" as string]: "max(0px, calc((100cqi - 4 * var(--pad) - 0.5rem - 3 * var(--seam)) / 5))" }}
          >
            <ComputerFrame
              className="shrink-0"
              style={{ width: "calc(4 * var(--tile) + 3 * var(--seam) + 2 * var(--pad))" }}
              rows={COMPUTER_2}
              preset={viewComputer === "102" && draftViewPreset ? draftViewPreset : computer2Preset}
              pending={pending2 && !viewEditorOpen}
              selected={computer2Scope}
              selection={selection}
              power={power}
              thumbStamp={thumbStamp}
              pickedIds={viewEditorOpen && viewComputer === "102" ? viewCurrentBucket : []}
              onSelectFrame={() => {
                if (viewEditorOpen && viewComputer !== "102") {
                  setPanelGuardOpen(true)
                  return
                }
                setSelection({ panel: 2, screen: "computer-2" })
              }}
              onSelectScreen={(screen) => choose({ panel: 2, screen })}
              onPress={pressScreen}
              onOpenRemote={() => askRemote("102")}
              remoteLabel={REMOTE_PANEL["102"]}
              dropTarget={drag?.over ?? ""}
            />
            <ComputerFrame
              className="shrink-0"
              style={{ width: "calc(var(--tile) + 2 * var(--pad))" }}
              rows={COMPUTER_3}
              preset={viewComputer === "103" && draftViewPreset ? draftViewPreset : activeComputer3Preset}
              pending={pending3 && !viewEditorOpen}
              selected={computer3Scope}
              selection={selection}
              power={power}
              thumbStamp={thumbStamp}
              pickedIds={viewEditorOpen && viewComputer === "103" ? viewCurrentBucket : []}
              onSelectFrame={() => {
                if (viewEditorOpen && viewComputer !== "103") {
                  setPanelGuardOpen(true)
                  return
                }
                setSelection({ panel: 2, screen: "computer-3" })
              }}
              onSelectScreen={(screen) => choose({ panel: 2, screen })}
              onPress={pressScreen}
              onOpenRemote={() => askRemote("103")}
              remoteLabel={REMOTE_PANEL["103"]}
              dropTarget={drag?.over ?? ""}
            />
          </div>
        </section>
        </div>
      </section>

      <footer className="shrink-0 border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="flex min-w-0 flex-col gap-4 overflow-hidden lg:flex-row lg:items-stretch">
        <div className="min-w-0 flex-1">
        <PresetRow
          label={footer.label}
          rows={footer.rows}
          presets={footer.presets}
          activeId={footer.activeId}
          pending={previewPending && !viewEditorOpen}
          creating={viewEditorOpen}
          onCreate={openViewEditor}
          onRemove={(id) => {
            const name = footer.presets.find((item) => item.id === id)?.name ?? "this view"
            setRemoveViewAsk({ id, name })
          }}
          onSelect={(id) => {
            if (viewEditorOpen) return
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
          onRefresh={() => {
            void refreshSelectedEdge()
          }}
          onClose={() => {
            void closeSelectedEdge()
          }}
          onCloseAll={() => {
            void closeAllEdge()
          }}
          onClearLogin={() => {
            void clearCConnectLogin()
          }}
        />
        </div>
        {presetCoachPresence.mounted && presetCoach ? (
          <div className={`relative shrink-0 overflow-hidden ${presetCoachPresence.visible ? "h-56 w-full lg:w-[34rem]" : "h-0 w-0"}`}>
            <div className="absolute inset-0 overflow-hidden">
              <div
                className={`h-full ${presetCoachPresence.visible ? "translate-y-0 scale-100 opacity-100" : "translate-y-4 scale-95 opacity-0"}`}
                style={motionStyle}
              >
                <PresetCoach key={`${presetCoach.preset.id}-${presetCoach.rows.length}`} rows={presetCoach.rows} preset={presetCoach.preset} />
              </div>
            </div>
          </div>
        ) : null}
        </div>
      </footer>
      <section className="shrink-0 border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="flex min-w-0 flex-col gap-4 overflow-hidden lg:flex-row lg:items-stretch">
          <div className="min-w-0 flex-1">
            <div className="mb-2">
              <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">PROGRAMS</p>
              <StatusLine
                text={
                  programStatus
                    ? programStatus
                    : armedApp
                      ? "Tap a screen to open it there. Tap anywhere else to cancel."
                      : "Browse for a program, then tap a screen or drag it onto one."
                }
                className="line-clamp-2 min-h-10 text-xs leading-5 text-cyan-100/80"
              />
            </div>
            <div className="flex items-stretch gap-2 overflow-x-auto overflow-y-hidden pb-1">
              <GlowButton active={browseBusy} onClick={() => void browseProgram()}>
                {browseBusy ? "Opening…" : "Browse"}
              </GlowButton>
              {pins.map((pin) => (
                <div key={pin.id} className="flex shrink-0">
                  <button
                    type="button"
                    data-program-id={pin.id}
                    {...programPointer(pin.id)}
                    className={`flex min-h-11 max-w-56 cursor-grab touch-none items-center gap-2 border px-3 text-sm tracking-wide select-none active:cursor-grabbing ${
                      pin.locked ? "rounded-lg" : "rounded-l-lg border-r-0"
                    } ${
                      armedApp === pin.id
                        ? "border-cyan-200 bg-cyan-400/25 shadow-[0_0_16px_rgba(80,200,255,0.35)]"
                        : "border-cyan-300/35 bg-[#08245f]/80"
                    }`}
                  >
                    <ProgramIcon id={pin.id} />
                    <span className="min-w-0 truncate">{pin.name}</span>
                  </button>
                  {pin.locked ? null : (
                    <button
                      type="button"
                      aria-label={`Remove ${pin.name}`}
                      onClick={() => void removeProgram(pin.id)}
                      className={`min-h-11 rounded-r-lg border px-3 text-sm ${
                        armedApp === pin.id ? "border-cyan-200 bg-cyan-400/25" : "border-cyan-300/35 bg-[#08245f]/80"
                      }`}
                    >
                      ×
                    </button>
                  )}
                </div>
              ))}
            </div>
          </div>
          {coachPresence.mounted ? (
            <div
              className={`relative shrink-0 overflow-hidden ${coachPresence.visible ? "h-56 w-full lg:w-[34rem]" : "h-0 w-0"}`}
            >
              <div className="absolute inset-0 overflow-hidden">
                <div
                  className={`h-full ${coachPresence.visible ? "translate-y-0 scale-100 opacity-100" : "translate-y-4 scale-95 opacity-0"}`}
                  style={motionStyle}
                >
                  {coachPin ? <DragCoach name={coachPin.name} id={coachPin.id} /> : null}
                </div>
              </div>
            </div>
          ) : null}
        </div>
      </section>
      <section className="shrink-0 border-t border-cyan-300/30 px-4 py-3 sm:px-6">
        <div className="mb-2">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">WEB ADDRESSES</p>
          <StatusLine
            text={
              linkStatus
                ? linkStatus
                : armedLink
                  ? "Tap a screen to open it there. Tap anywhere else to cancel."
                  : "Add or edit a site, then tap a screen or drag it onto one."
            }
            className="line-clamp-2 min-h-10 text-xs leading-5 text-cyan-100/80"
          />
        </div>
        <div className="flex items-stretch gap-2 overflow-x-auto overflow-y-hidden pb-1">
          <GlowButton active={linkEditorOpen && !editingLinkId} onClick={() => openLinkEditor()}>
            Add site
          </GlowButton>
          {links.map((link) => {
            const active = armedLink === link.id || editingLinkId === link.id
            const chip = active
              ? "border-cyan-200 bg-cyan-400/25 shadow-[0_0_16px_rgba(80,200,255,0.35)]"
              : "border-cyan-300/35 bg-[#08245f]/80"
            return (
              <div key={link.id} className="flex shrink-0">
                <button
                  type="button"
                  data-link-id={link.id}
                  {...linkPointer(link.id)}
                  className={`flex min-h-11 max-w-56 cursor-grab touch-none items-center gap-2 rounded-l-lg border border-r-0 px-3 text-sm tracking-wide select-none active:cursor-grabbing ${chip}`}
                >
                  <LinkGlyph />
                  <span className="min-w-0 truncate">{link.name}</span>
                </button>
                <button
                  type="button"
                  aria-label={`Edit ${link.name}`}
                  onClick={() => openLinkEditor(link)}
                  className={`min-h-11 border border-x-0 px-3 text-sm tracking-wide ${chip}`}
                >
                  Edit
                </button>
                <button
                  type="button"
                  aria-label={`Remove ${link.name}`}
                  onClick={() => void removeSavedLink(link.id)}
                  className={`min-h-11 rounded-r-lg border px-3 text-sm ${chip}`}
                >
                  ×
                </button>
              </div>
            )
          })}
        </div>
      </section>
      </div>
      {drag
        ? (() => {
            if (drag.kind === "program") {
              const pin = pins.find((item) => item.id === drag.id)
              if (!pin) return null
              return (
                <div
                  className="pointer-events-none fixed z-50 flex max-w-56 -translate-x-1/2 -translate-y-1/2 items-center gap-2 rounded-lg border border-cyan-200 bg-cyan-400/30 px-3 py-2 text-sm shadow-[0_12px_30px_rgba(0,0,0,0.45)]"
                  style={{ left: drag.x, top: drag.y }}
                >
                  <ProgramIcon id={pin.id} />
                  <span className="truncate">{pin.name}</span>
                </div>
              )
            }
            const link = links.find((item) => item.id === drag.id)
            if (!link) return null
            return (
              <div
                className="pointer-events-none fixed z-50 flex max-w-56 -translate-x-1/2 -translate-y-1/2 items-center gap-2 rounded-lg border border-cyan-200 bg-cyan-400/30 px-3 py-2 text-sm shadow-[0_12px_30px_rgba(0,0,0,0.45)]"
                style={{ left: drag.x, top: drag.y }}
              >
                <LinkGlyph />
                <span className="truncate">{link.name}</span>
              </div>
            )
          })()
        : null}
      {keyboardPresence.mounted && addressScreen ? (
        <AddressKeyboard
          label={`Screen ${screenNumber(addressScreen.id)}`}
          value={addressValue}
          selected={replaceAddress}
          detail={zoneDetail(shownZone)}
          motionClass={keyboardPresence.visible ? "translate-y-0 opacity-100" : "translate-y-full opacity-0"}
          inputRef={(node) => {
            addressInputRef.current = node
          }}
          onValueChange={(value) => {
            if (!addressScreen) return
            setAddresses((existing) => ({ ...existing, [addressScreen.id]: value }))
            setReplaceAddress(false)
          }}
          onCaret={(start, end) => {
            addressCaret.current = { start, end }
            if (start === end) setReplaceAddress(false)
          }}
          onInsert={insertAddress}
          onScheme={insertScheme}
          onBackspace={backspaceAddress}
          onClear={clearAddress}
          onOpen={() => void runAddress()}
          onClose={() => setKeyboardOpen(false)}
        />
      ) : null}
      {browsePresence.mounted ? (
        <div className={`fixed inset-0 z-50 flex items-center justify-center bg-[#03102e]/55 ${browsePresence.visible ? "opacity-100" : "opacity-0"}`} style={motionStyle}>
          <div className={`w-[min(28rem,92vw)] rounded-2xl border border-cyan-300/80 bg-[#071a4d] px-8 py-7 text-center shadow-[0_0_32px_rgba(80,200,255,0.2)] ${browsePresence.visible ? "translate-y-0 scale-100" : "translate-y-4 scale-95"}`} style={motionStyle}>
            <p className="text-[11px] tracking-[0.18em] text-cyan-100/70">PROGRAMS</p>
            <p className="mt-2 text-2xl font-semibold tracking-wide">Choose a program</p>
          </div>
        </div>
      ) : null}
      {remotePresence.mounted ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="remote-ask-title"
          onClick={() => setRemoteAsk("")}
          className={`fixed inset-0 z-50 flex items-center justify-center bg-[#03102e]/60 backdrop-blur-[2px] ${remotePresence.visible ? "opacity-100" : "opacity-0"} ${remoteAsk ? "" : "pointer-events-none"}`}
          style={motionStyle}
        >
          <div
            onClick={(event) => event.stopPropagation()}
            className={`w-[min(30rem,92vw)] rounded-2xl border border-cyan-300/80 bg-[#071a4d] px-8 pt-8 pb-7 text-center shadow-[0_0_40px_rgba(80,200,255,0.25)] ${remotePresence.visible ? "translate-y-0 scale-100" : "translate-y-4 scale-95"}`}
            style={motionStyle}
          >
            <span className="mx-auto flex h-16 w-16 items-center justify-center rounded-full border border-cyan-200/80 bg-gradient-to-b from-cyan-400/35 to-[#0a3a8c] shadow-[0_0_24px_rgba(80,200,255,0.45)]">
              <RemoteIcon className="h-8 w-8" />
            </span>
            <p className="mt-4 text-[11px] tracking-[0.18em] text-cyan-100/70">
              {REMOTE_PANEL[remoteComputer].toUpperCase()} · {GROUP_LABEL[remoteComputer].toUpperCase()}
            </p>
            <p id="remote-ask-title" className="mt-2 text-2xl font-semibold tracking-wide">
              Do you want to access this panel?
            </p>
            <div className="mt-6 grid grid-cols-2 gap-3">
              <GlowButton onClick={() => setRemoteAsk("")}>No</GlowButton>
              <GlowButton active onClick={() => void runRemote(remoteComputer)}>
                Yes
              </GlowButton>
            </div>
          </div>
        </div>
      ) : null}
      {linkEditorPresence.mounted ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="link-editor-title"
          className={`fixed inset-0 z-50 flex items-end justify-center bg-[#03102e]/60 backdrop-blur-[2px] sm:items-center ${linkEditorPresence.visible ? "opacity-100" : "opacity-0"} ${linkEditorOpen ? "" : "pointer-events-none"}`}
          style={motionStyle}
        >
          <div
            data-link-editor
            className={`flex max-h-[92vh] w-[min(56rem,96vw)] flex-col overflow-y-auto rounded-t-2xl border border-cyan-300/80 bg-[#071a4d] px-5 py-5 shadow-[0_0_40px_rgba(80,200,255,0.25)] sm:rounded-2xl sm:px-8 sm:py-7 ${linkEditorPresence.visible ? "translate-y-0 scale-100" : "translate-y-4 scale-95"}`}
            style={motionStyle}
          >
            <p className="text-[11px] tracking-[0.18em] text-cyan-100/70">WEB ADDRESSES</p>
            <p id="link-editor-title" className="mt-1 text-2xl font-semibold tracking-wide">
              {editingLinkId ? "Edit site" : "Save a site"}
            </p>
            <p className="mt-2 text-xs text-cyan-100/70">Type on this keyboard, a physical keyboard, or paste with Ctrl+V.</p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <TypeField
                label="SITE NAME"
                value={linkName}
                active={linkField === "name"}
                maxLength={40}
                inputRef={(node) => {
                  linkNameRef.current = node
                }}
                onFocus={() => setLinkField("name")}
                onChange={(value) => {
                  setLinkName(value.slice(0, 40))
                  setLinkReplace(false)
                }}
                onCaret={(start, end) => {
                  linkCaret.current = { start, end }
                  if (start === end) setLinkReplace(false)
                }}
              />
              <TypeField
                label="ADDRESS"
                value={linkUrl}
                active={linkField === "url"}
                mono
                inputRef={(node) => {
                  linkUrlRef.current = node
                }}
                onFocus={() => setLinkField("url")}
                onChange={(value) => {
                  setLinkUrl(value)
                  setLinkReplace(false)
                }}
                onCaret={(start, end) => {
                  linkCaret.current = { start, end }
                  if (start === end) setLinkReplace(false)
                }}
              />
            </div>
            {linkReplace ? <p className="mt-2 text-xs text-cyan-100/70">The field is selected. The next key replaces it.</p> : null}
            <div className="mt-3">
              <OnScreenKeyboard
                showUrlShortcuts={linkField === "url"}
                onInsert={insertLinkToken}
                onBackspace={backspaceLink}
                onClear={clearLinkField}
                onScheme={insertLinkScheme}
                onEnter={() => void saveLink()}
                footer={
                  <div className="mt-2 grid grid-cols-2 gap-3">
                    <GlowButton onClick={closeLinkEditor}>Cancel</GlowButton>
                    <GlowButton active onClick={() => void saveLink()}>
                      {linkBusy ? "Saving…" : editingLinkId ? "Save changes" : "Save"}
                    </GlowButton>
                  </div>
                }
              />
            </div>
          </div>
        </div>
      ) : null}
      {viewEditorPresence.mounted ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="view-editor-title"
          className={`fixed inset-x-0 bottom-0 z-40 flex justify-center px-4 pb-4 pt-2 sm:px-6 ${viewEditorPresence.visible ? "opacity-100" : "opacity-0"} ${viewEditorOpen ? "" : "pointer-events-none"}`}
          style={motionStyle}
        >
          <div
            data-view-editor
            className={`w-full max-w-3xl rounded-2xl border border-cyan-300/80 bg-[#071a4d] px-5 py-4 shadow-[0_0_40px_rgba(80,200,255,0.25)] ${viewEditorPresence.visible ? "translate-y-0" : "translate-y-4"}`}
            style={motionStyle}
          >
            <p className="text-[11px] tracking-[0.18em] text-cyan-100/70">CUSTOM VIEW</p>
            <p id="view-editor-title" className="mt-1 text-xl font-semibold tracking-wide">
              Create custom
            </p>
            <p className="mt-1 text-xs text-cyan-100/70">
              Name this view, then paint Edge window groups on {GROUP_LABEL[viewComputer]}. Use New group for another window.
            </p>
            <div className="mt-3">
              <TypeField
                label="VIEW NAME"
                value={viewName}
                active
                maxLength={40}
                inputRef={(node) => {
                  viewNameRef.current = node
                }}
                onFocus={() => undefined}
                onChange={(value) => {
                  setViewName(value.slice(0, 40))
                  setViewReplace(false)
                }}
                onCaret={(start, end) => {
                  viewCaret.current = { start, end }
                  if (start === end) setViewReplace(false)
                }}
              />
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {viewBuckets.map((bucket, index) => (
                <GlowButton key={`group-${index}`} active={index === viewBucketIndex} onClick={() => setViewBucketIndex(index)}>
                  <span className="flex items-center gap-2">
                    <span
                      className="inline-block h-3 w-3 rounded-sm border"
                      style={{
                        borderColor: GROUP_COLOR[index % GROUP_COLOR.length],
                        background: `${GROUP_COLOR[index % GROUP_COLOR.length]}99`,
                      }}
                    />
                    Group {index + 1}
                    {bucket.length > 0 ? ` · ${bucket.map(screenNumber).join(",")}` : ""}
                  </span>
                </GlowButton>
              ))}
              <GlowButton onClick={addViewGroup}>New group</GlowButton>
            </div>
            <p className="mt-2 text-xs text-cyan-100/80">
              {viewCurrentBucket.length === 0
                ? `Group ${viewBucketIndex + 1} is empty. Tap screens that should share this Edge window.`
                : `Group ${viewBucketIndex + 1}: screens ${viewCurrentBucket
                    .map(screenNumber)
                    .sort((a, b) => Number(a) - Number(b))
                    .join(", ")}.`}
              {viewAssigned.length < viewAllowed.length
                ? " Screens left out each get their own window."
                : ""}
            </p>
            {viewStatus ? <p className="mt-1 text-xs text-cyan-100/70">{viewStatus}</p> : null}
            <div className="mt-3">
              <OnScreenKeyboard
                onInsert={insertViewToken}
                onBackspace={backspaceView}
                onClear={() => {
                  setViewName("")
                  setViewReplace(false)
                  viewCaret.current = { start: 0, end: 0 }
                }}
                onEnter={() => void saveCustomView()}
                footer={
                  <div className="mt-2 grid grid-cols-2 gap-3">
                    <GlowButton onClick={() => setViewEditorOpen(false)}>Cancel</GlowButton>
                    <GlowButton active onClick={() => void saveCustomView()}>
                      {viewBusy ? "Saving…" : "Save view"}
                    </GlowButton>
                  </div>
                }
              />
            </div>
          </div>
        </div>
      ) : null}
      {panelGuardPresence.mounted ? (
        <div
          role="alertdialog"
          aria-modal="true"
          aria-labelledby="panel-guard-title"
          className={`fixed inset-0 z-50 flex items-center justify-center bg-[#03102e]/60 backdrop-blur-[2px] px-4 ${panelGuardPresence.visible ? "opacity-100" : "opacity-0"} ${panelGuardOpen ? "" : "pointer-events-none"}`}
          style={motionStyle}
        >
          <div
            className={`w-[min(28rem,96vw)] rounded-2xl border border-cyan-300/80 bg-[#071a4d] px-6 py-6 shadow-[0_0_40px_rgba(80,200,255,0.25)] ${panelGuardPresence.visible ? "translate-y-0 scale-100" : "translate-y-4 scale-95"}`}
            style={motionStyle}
          >
            <p className="text-[11px] tracking-[0.18em] text-cyan-100/70">CUSTOM VIEW</p>
            <p id="panel-guard-title" className="mt-1 text-xl font-semibold tracking-wide">
              Wrong panel
            </p>
            <p className="mt-3 text-sm leading-6 text-cyan-50/90">
              You can only select screens from the panel you have selected.
            </p>
            <div className="mt-5">
              <GlowButton active onClick={() => setPanelGuardOpen(false)}>
                OK
              </GlowButton>
            </div>
          </div>
        </div>
      ) : null}
      {removeViewPresence.mounted && removeViewShown ? (
        <div
          role="alertdialog"
          aria-modal="true"
          aria-labelledby="remove-view-title"
          className={`fixed inset-0 z-50 flex items-center justify-center bg-[#03102e]/60 backdrop-blur-[2px] px-4 ${removeViewPresence.visible ? "opacity-100" : "opacity-0"} ${removeViewAsk ? "" : "pointer-events-none"}`}
          style={motionStyle}
          onClick={() => setRemoveViewAsk(null)}
        >
          <div
            onClick={(event) => event.stopPropagation()}
            className={`w-[min(28rem,96vw)] rounded-2xl border border-cyan-300/80 bg-[#071a4d] px-6 py-6 shadow-[0_0_40px_rgba(80,200,255,0.25)] ${removeViewPresence.visible ? "translate-y-0 scale-100" : "translate-y-4 scale-95"}`}
            style={motionStyle}
          >
            <p className="text-[11px] tracking-[0.18em] text-cyan-100/70">CUSTOM VIEW</p>
            <p id="remove-view-title" className="mt-1 text-xl font-semibold tracking-wide">
              Delete this view?
            </p>
            <p className="mt-3 text-sm leading-6 text-cyan-50/90">
              Remove <span className="font-semibold text-white">{removeViewShown.name}</span>? This cannot be undone.
            </p>
            <div className="mt-5 grid grid-cols-2 gap-3">
              <GlowButton onClick={() => setRemoveViewAsk(null)}>Cancel</GlowButton>
              <GlowButton
                tone="alert"
                active
                onClick={() => {
                  const id = removeViewShown.id
                  setRemoveViewAsk(null)
                  void removeCustomView(id)
                }}
              >
                Delete
              </GlowButton>
            </div>
          </div>
        </div>
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
  pending,
  selection,
  power,
  thumbStamp,
  pickedIds = [],
  onSelect,
  onPress,
  onOpenRemote,
  remoteLabel,
  dropTarget,
}: {
  panel: PanelId
  title: string
  detail: string
  rows: Screen[][]
  preset: Preset | null
  pending: boolean
  selection: Selection
  power: Record<string, boolean>
  thumbStamp: number
  pickedIds?: string[]
  onSelect: (selection: Selection) => void
  onPress: () => void
  onOpenRemote: () => void
  remoteLabel: string
  dropTarget: string
}) {
  const ids = rows.flat().map((screen) => screen.id)
  const whole = (selection.panel === panel && selection.screen === "all") || selection.screen === "every"
  const allOn = ids.every((id) => power[id])
  const allOff = ids.every((id) => !power[id])

  return (
    <section
      onClick={() => onSelect({ panel, screen: "all" })}
      className={`flex h-full min-h-0 cursor-pointer flex-col rounded-2xl border bg-[#071a4d]/70 p-3 pb-5 shadow-[0_0_24px_rgba(30,120,255,0.18)] ${
        whole ? "border-white shadow-[0_0_24px_rgba(180,230,255,0.35)]" : selection.panel === panel ? "border-cyan-300/70" : "border-cyan-300/25"
      }`}
    >
      <div className="mb-3 flex items-end justify-between gap-2">
        <div>
          <h2 className="text-sm font-semibold tracking-[0.16em] uppercase">{title}</h2>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <div className="flex items-center gap-2">
          <PreviewChip show={pending} />
          <span className="text-[11px] tracking-[0.14em] text-cyan-100/80">{allOn ? "ON" : allOff ? "OFF" : "MIXED"}</span>
        </div>
      </div>
      <ScreenWall
        rows={rows}
        preset={preset}
        pending={pending}
        selection={selection}
        power={power}
        thumbStamp={thumbStamp}
        pickedIds={pickedIds}
        onSelect={(screen) => onSelect({ panel, screen })}
        onPress={onPress}
        onOpenRemote={onOpenRemote}
        remoteLabel={remoteLabel}
        dropTarget={dropTarget}
      />
    </section>
  )
}

function ComputerFrame({
  className = "",
  style,
  rows,
  preset,
  pending,
  selected,
  selection,
  power,
  thumbStamp,
  pickedIds = [],
  onSelectFrame,
  onSelectScreen,
  onPress,
  onOpenRemote,
  remoteLabel,
  dropTarget,
}: {
  className?: string
  style?: CSSProperties
  rows: Screen[][]
  preset: Preset | null
  pending: boolean
  selected: boolean
  selection: Selection
  power: Record<string, boolean>
  thumbStamp: number
  pickedIds?: string[]
  onSelectFrame: () => void
  onSelectScreen: (screen: string) => void
  onPress: () => void
  onOpenRemote: () => void
  remoteLabel: string
  dropTarget: string
}) {
  return (
    <div
      onClick={(event) => {
        event.stopPropagation()
        onSelectFrame()
      }}
      style={style}
      className={`flex min-w-0 flex-col rounded-xl border py-3 ${className} ${selected ? "border-white bg-white/5" : "border-cyan-300/35"}`}
    >
      <ScreenWall
        rows={rows}
        preset={preset}
        pending={pending}
        selection={selection}
        power={power}
        thumbStamp={thumbStamp}
        pickedIds={pickedIds}
        onSelect={onSelectScreen}
        onPress={onPress}
        onOpenRemote={onOpenRemote}
        remoteLabel={remoteLabel}
        dropTarget={dropTarget}
      />
    </div>
  )
}

function ScreenWall({
  rows,
  preset,
  pending,
  selection,
  power,
  thumbStamp,
  pickedIds = [],
  onSelect,
  onPress,
  onOpenRemote,
  remoteLabel,
  dropTarget,
}: {
  rows: Screen[][]
  preset: Preset | null
  pending: boolean
  selection: Selection
  power: Record<string, boolean>
  thumbStamp: number
  pickedIds?: string[]
  onSelect: (screenId: string) => void
  onPress: () => void
  onOpenRemote: () => void
  remoteLabel: string
  dropTarget: string
}) {
  const columns = rows.reduce((count, row) => Math.max(count, row.length), 1)
  const rowCount = rows.length
  const zones = preset ? presetZones(rows, preset) : []
  const entrance = "zone-in 560ms cubic-bezier(0.22, 1, 0.36, 1) both"
  return (
    <div
      className="relative grid w-full p-5"
      style={{
        gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
        gridTemplateRows: `repeat(${rowCount}, auto)`,
        columnGap: SCREEN_GAP,
        rowGap: SCREEN_GAP,
      }}
    >
      {rows.map((row, r) =>
        row.map((screen, c) => (
          <div key={screen.id} className="min-w-0" style={{ gridRow: r + 1, gridColumn: c + 1 }}>
            <ScreenButton
              screen={screen}
              preset={preset}
              selected={selection.screen === screen.id}
              picked={pickedIds.includes(screen.id)}
              on={power[screen.id]}
              thumbStamp={thumbStamp}
              labelTop={columns === 1 && r === rowCount / 2 - 1}
              onSelect={() => onSelect(screen.id)}
              onPress={onPress}
              dropTarget={dropTarget}
            />
          </div>
        )),
      )}
      {zones.map((zone, index) => (
        <div
          key={zone.key}
          aria-hidden="true"
          className="pointer-events-none absolute z-[15] rounded-sm border-2"
          style={{
            gridRow: `${zone.row} / span ${zone.rows}`,
            gridColumn: `${zone.col} / span ${zone.cols}`,
            top: 0,
            right: 0,
            bottom: 0,
            left: 0,
            borderColor: zone.color,
            borderStyle: pending ? "dashed" : "solid",
            ["--zone" as string]: zone.color,
            animation: pending ? `${entrance}, zone-wait 1.6s ease-in-out 560ms infinite` : entrance,
          }}
        >
          <span
            className="absolute top-1 left-1 flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[11px] font-semibold leading-none text-[#03102e] shadow-[0_0_8px_rgba(0,0,0,0.5)]"
            style={{ background: zone.color }}
          >
            {index + 1}
          </span>
        </div>
      ))}
      <RemoteButton label={remoteLabel} onClick={onOpenRemote} />
    </div>
  )
}

function PreviewChip({ show }: { show: boolean }) {
  if (!show) return null
  return (
    <span
      className="rounded-full border border-white bg-white/15 px-2 py-0.5 text-[11px] font-semibold tracking-[0.18em] text-white"
      style={{ animation: "chip-wait 1.6s ease-in-out infinite" }}
    >
      PREVIEW
    </span>
  )
}

function RemoteIcon({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className={className}>
      <rect x="2.5" y="3.5" width="19" height="13" rx="2" />
      <path d="M8.5 20.5h7M12 16.5v4" />
      <path d="M9 12.5l5.5-5.5M10.5 7h4v4" />
    </svg>
  )
}

function RemoteButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={`Remote access to ${label}`}
      title={`Remote access to ${label}`}
      onPointerDown={(event) => event.stopPropagation()}
      onClick={(event) => {
        event.stopPropagation()
        onClick()
      }}
      className="absolute top-1/2 left-1/2 z-20 flex h-12 w-12 -translate-x-1/2 -translate-y-1/2 touch-manipulation items-center justify-center rounded-full border border-cyan-200/90 bg-gradient-to-b from-[#1aa3e8] to-[#0a3a8c] text-white shadow-[0_0_0_4px_rgba(7,26,77,0.85),0_0_18px_rgba(80,200,255,0.55)] transition-[transform,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(7,26,77,0.85),0_0_26px_rgba(120,220,255,0.8)] active:scale-90"
    >
      <RemoteIcon className="h-6 w-6" />
    </button>
  )
}

function ProgramIcon({ id }: { id: string }) {
  const [hidden, setHidden] = useState(false)
  if (hidden) return null
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

function LinkGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" className="h-5 w-5 shrink-0 text-cyan-100">
      <path d="M10 13a5 5 0 0 0 7.07 0l1.41-1.41a5 5 0 0 0-7.07-7.07L10 5.93" />
      <path d="M14 11a5 5 0 0 0-7.07 0L5.52 12.4a5 5 0 0 0 7.07 7.07L14 18.07" />
    </svg>
  )
}

function ScreenThumb({ id, stamp, dim }: { id: string; stamp: number; dim: boolean }) {
  const [src, setSrc] = useState("")
  useEffect(() => {
    const next = `/api/thumbs/${id}?v=${stamp}`
    const probe = new Image()
    probe.onload = () => setSrc(next)
    probe.src = next
  }, [id, stamp])
  if (!src) return null
  return (
    <img
      src={src}
      alt=""
      draggable={false}
      className={`block h-full w-full object-contain ${dim ? "opacity-40" : ""}`}
    />
  )
}

function ScreenButton({
  screen,
  preset,
  selected,
  picked = false,
  on,
  thumbStamp,
  labelTop = false,
  onSelect,
  onPress,
  dropTarget,
}: {
  screen: Screen
  preset: Preset | null
  selected: boolean
  picked?: boolean
  on: boolean
  thumbStamp: number
  labelTop?: boolean
  onSelect: () => void
  onPress: () => void
  dropTarget: string
}) {
  const group = preset ? preset.groups[screen.id] : undefined
  const color = group == null ? "#7eb6ff" : GROUP_COLOR[group % GROUP_COLOR.length]
  const number = screen.id.replace("TV", "")
  const hot = dropTarget === screen.id
  return (
    <button
      type="button"
      data-screen-id={screen.id}
      onPointerDown={(event) => {
        if (event.button !== 0) return
        event.stopPropagation()
        onPress()
      }}
      onClick={(event) => {
        event.stopPropagation()
        onSelect()
      }}
      className="relative block aspect-video w-full min-w-0 touch-manipulation overflow-hidden rounded-sm border text-center transition-[border-color,box-shadow,background-color] duration-200"
      style={{
        borderColor: hot || picked || selected ? "#ffffff" : color,
        background: on ? `${color}33` : "rgba(0,0,0,0.45)",
        boxShadow: hot || picked ? "0 0 18px #7ee8ff" : selected ? `0 0 16px ${color}` : undefined,
      }}
    >
      <span className="absolute inset-0">
        <ScreenThumb id={screen.id} stamp={thumbStamp} dim={!on} />
      </span>
      <span className={`pointer-events-none absolute inset-x-0 z-10 px-1 [text-shadow:0_1px_3px_rgba(0,0,0,0.85)] ${labelTop ? "top-1" : "bottom-1"}`}>
        <span className="block text-sm font-semibold leading-tight">{number}</span>
        <span className="block text-[10px] leading-tight text-cyan-50/90">{screen.hdmi}</span>
      </span>
    </button>
  )
}

function PresetGlyph({ rows, preset }: { rows: Screen[][]; preset: Preset }) {
  const columns = rows.reduce((count, row) => Math.max(count, row.length), 1)
  return (
    <span
      aria-hidden="true"
      className="grid h-7 gap-[2px]"
      style={{
        width: `${columns * 0.875 + 0.25}rem`,
        gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`,
        gridTemplateRows: `repeat(${rows.length}, minmax(0, 1fr))`,
      }}
    >
      {presetZones(rows, preset).map((zone) => (
        <span
          key={zone.key}
          className="rounded-[2px] border"
          style={{
            gridRow: `${zone.row} / span ${zone.rows}`,
            gridColumn: `${zone.col} / span ${zone.cols}`,
            borderColor: zone.color,
            background: `${zone.color}66`,
          }}
        />
      ))}
    </span>
  )
}

function PresetRow({
  label,
  rows,
  presets,
  activeId,
  pending,
  creating,
  onCreate,
  onRemove,
  onSelect,
  onConfirm,
  onCancel,
  onRefresh,
  onClose,
  onCloseAll,
  onClearLogin,
}: {
  label: string
  rows: Screen[][]
  presets: Preset[]
  activeId: string
  pending: boolean
  creating: boolean
  onCreate: () => void
  onRemove: (id: string) => void
  onSelect: (id: string) => void
  onConfirm: () => void
  onCancel: () => void
  onRefresh: () => void
  onClose: () => void
  onCloseAll: () => void
  onClearLogin: () => void
}) {
  return (
    <div>
      <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{label}</p>
          <p className="text-xs text-cyan-100/80">
            {creating
              ? "Name the view, paint a group, then tap New group for another Edge window."
              : pending
                ? "Preview on the screens. Confirm opens Edge."
                : "Choose a preset to preview it on the screens."}
          </p>
        </div>
        <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
          <GlowButton active={creating} onClick={onCreate}>
            <span className="flex items-center gap-2">
              <span className="flex h-5 w-5 items-center justify-center rounded-sm border border-dashed border-cyan-200/70 text-base leading-none">+</span>
              <span>Create custom</span>
            </span>
          </GlowButton>
          <GlowButton onClick={onRefresh}>Refresh</GlowButton>
          <GlowButton tone="alert" onClick={onClose}>
            Close Edge
          </GlowButton>
          <GlowButton tone="alert" onClick={onCloseAll}>
            Close all
          </GlowButton>
          <GlowButton tone="alert" onClick={onClearLogin}>
            Clear login
          </GlowButton>
        </div>
      </div>
      <div className="flex flex-wrap items-start gap-2">
        {presets.map((item) => (
          <div key={item.id} className="relative w-fit">
            <GlowButton active={activeId !== "" && item.id === activeId} onClick={() => onSelect(item.id)}>
              <span className="flex flex-col items-center gap-1.5 py-2">
                <PresetGlyph rows={rows} preset={item} />
                <span>{item.name}</span>
              </span>
            </GlowButton>
            {isCustomViewId(item.id) ? (
              <button
                type="button"
                aria-label={`Remove ${item.name}`}
                onClick={(event) => {
                  event.stopPropagation()
                  onRemove(item.id)
                }}
                className="absolute -right-1.5 -top-1.5 z-10 flex h-7 w-7 items-center justify-center rounded-full border border-cyan-200/50 bg-[#0a2f86] text-sm leading-none text-cyan-50 shadow-[0_0_10px_rgba(0,0,0,0.35)]"
              >
                ×
              </button>
            ) : null}
          </div>
        ))}
      </div>
      <Reveal show={pending} motion="down" className="mt-2">
        <div className="grid max-w-md grid-cols-2 gap-2">
          <GlowButton active onClick={onConfirm}>
            Confirm
          </GlowButton>
          <GlowButton onClick={onCancel}>
            Cancel
          </GlowButton>
        </div>
      </Reveal>
    </div>
  )
}

function AddressKeyboard({
  label,
  value,
  selected,
  detail,
  inputRef,
  onValueChange,
  onCaret,
  onInsert,
  onScheme,
  onBackspace,
  onClear,
  onOpen,
  onClose,
  motionClass,
}: {
  label: string
  value: string
  selected: boolean
  detail: string
  inputRef: (node: HTMLInputElement | null) => void
  onValueChange: (value: string) => void
  onCaret: (start: number, end: number) => void
  onInsert: (token: string) => void
  onScheme: () => void
  onBackspace: () => void
  onClear: () => void
  onOpen: () => void
  onClose: () => void
  motionClass: string
}) {
  usePhysicalTyping(true, {
    onInsert,
    onBackspace,
    onEnter: onOpen,
    onEscape: onClose,
  })
  return (
    <div
      data-keyboard
      className={`fixed inset-x-0 bottom-0 z-40 max-h-[74vh] overflow-y-auto border-t border-cyan-300/40 bg-[#03102e]/95 px-6 py-3 shadow-[0_-12px_40px_rgba(0,0,0,0.45)] sm:px-16 ${motionClass}`}
      style={motionStyle}
    >
      <div className="mx-auto flex w-full max-w-[1600px] flex-col gap-2">
        <div className="flex items-baseline justify-between gap-3">
          <p className="text-[11px] tracking-[0.2em] text-cyan-100/70">{label}</p>
          <p className="text-xs text-cyan-100/70">{detail}</p>
        </div>
        <p className="text-xs text-cyan-100/70">Type here, use a physical keyboard, or paste with Ctrl+V.</p>
        <TypeField
          label="ADDRESS"
          value={value}
          active
          mono
          inputRef={inputRef}
          onFocus={() => {}}
          onChange={onValueChange}
          onCaret={onCaret}
        />
        {selected ? <p className="text-xs text-cyan-100/70">The address is selected. The next key replaces it.</p> : null}
        <OnScreenKeyboard
          showUrlShortcuts
          onInsert={onInsert}
          onBackspace={onBackspace}
          onClear={onClear}
          onScheme={onScheme}
          onEnter={onOpen}
          footer={
            <div className="mt-2 grid grid-cols-[2fr_1fr] gap-2">
              <button
                type="button"
                onClick={onOpen}
                className="min-h-14 rounded-lg border border-cyan-200 bg-cyan-400/25 text-base tracking-wide shadow-[0_0_16px_rgba(80,200,255,0.35)]"
              >
                Open address
              </button>
              <button
                type="button"
                onClick={onClose}
                className="min-h-14 rounded-lg border border-cyan-300/40 bg-[#0a2a6a] px-2 text-base tracking-wide touch-manipulation"
              >
                Hide keyboard
              </button>
            </div>
          }
        />
      </div>
    </div>
  )
}

function GlowButton({
  children,
  active,
  onClick,
  tone = "normal",
}: {
  children: ReactNode
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
