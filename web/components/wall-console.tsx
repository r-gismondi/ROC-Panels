"use client"

import { useMemo, useState } from "react"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Separator } from "@/components/ui/separator"
import { Slider } from "@/components/ui/slider"
import { Switch } from "@/components/ui/switch"

type Panel = {
  number: number
  host: string
  port: number
  read: boolean
  displayId?: number
  model?: string
  power: boolean
  backlight: number
  screenOn?: boolean
}

type Zone = { n: number; c: number; r: number; w: number; h: number }

type Layout = { id: string; name: string; detail: string; zones: Zone[] }

const PREFIX = "192.168.0"
const HOST_OFFSET = 1
const PORT = 1515

const LAYOUTS: Layout[] = [
  { id: "full", name: "Full", detail: "One window fills the desktop", zones: [{ n: 1, c: 0, r: 0, w: 12, h: 12 }] },
  {
    id: "columns-2",
    name: "Two columns",
    detail: "Side by side",
    zones: [
      { n: 1, c: 0, r: 0, w: 6, h: 12 },
      { n: 2, c: 6, r: 0, w: 6, h: 12 },
    ],
  },
  {
    id: "columns-3",
    name: "Three columns",
    detail: "Equal vertical bands",
    zones: [
      { n: 1, c: 0, r: 0, w: 4, h: 12 },
      { n: 2, c: 4, r: 0, w: 4, h: 12 },
      { n: 3, c: 8, r: 0, w: 4, h: 12 },
    ],
  },
  {
    id: "grid",
    name: "Grid",
    detail: "Four equal zones",
    zones: [
      { n: 1, c: 0, r: 0, w: 6, h: 6 },
      { n: 2, c: 6, r: 0, w: 6, h: 6 },
      { n: 3, c: 0, r: 6, w: 6, h: 6 },
      { n: 4, c: 6, r: 6, w: 6, h: 6 },
    ],
  },
  {
    id: "focus",
    name: "Focus",
    detail: "Large area with two stacked sides",
    zones: [
      { n: 1, c: 0, r: 0, w: 8, h: 12 },
      { n: 2, c: 8, r: 0, w: 4, h: 6 },
      { n: 3, c: 8, r: 6, w: 4, h: 6 },
    ],
  },
  {
    id: "rows",
    name: "Rows",
    detail: "Top and bottom",
    zones: [
      { n: 1, c: 0, r: 0, w: 12, h: 6 },
      { n: 2, c: 0, r: 6, w: 12, h: 6 },
    ],
  },
]

function address(panelNumber: number) {
  return `${PREFIX}.${HOST_OFFSET + panelNumber}`
}

const INITIAL_PANEL: Panel = {
  number: 1,
  host: address(1),
  port: PORT,
  read: true,
  displayId: 1,
  model: "VH55C-R",
  power: true,
  backlight: 80,
  screenOn: true,
}

export function WallConsole() {
  const [panels, setPanels] = useState<Panel[]>([INITIAL_PANEL])
  const [selected, setSelected] = useState(1)
  const [layoutId, setLayoutId] = useState("focus")
  const [gap, setGap] = useState(10)
  const [showNumbers, setShowNumbers] = useState(true)

  const panel = panels.find((item) => item.number === selected) ?? null
  const layout = LAYOUTS.find((item) => item.id === layoutId) ?? LAYOUTS[0]

  const staged = useMemo(() => {
    if (!panel?.read || panel.number !== 1) return null
    const notes: string[] = []
    if (panel.power !== INITIAL_PANEL.power) notes.push(panel.power ? "Power on" : "Power off")
    if (panel.backlight !== INITIAL_PANEL.backlight) notes.push(`Backlight ${panel.backlight}%`)
    return notes
  }, [panel])

  function updatePanel(number: number, patch: Partial<Panel>) {
    setPanels((current) => current.map((item) => (item.number === number ? { ...item, ...patch } : item)))
  }

  function addPanel() {
    const number = panels.reduce((max, item) => Math.max(max, item.number), 0) + 1
    setPanels((current) => [
      ...current,
      { number, host: address(number), port: PORT, read: false, power: true, backlight: 70 },
    ])
    setSelected(number)
  }

  function removePanel(number: number) {
    const remaining = panels.filter((item) => item.number !== number)
    setPanels(remaining)
    if (selected === number) setSelected(remaining[0]?.number ?? 0)
  }

  return (
    <main className="mx-auto flex min-h-svh w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs tracking-[0.18em] text-muted-foreground uppercase">Samsung wall</p>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight">Wall desk</h1>
          <p className="mt-2 max-w-xl text-sm text-muted-foreground">
            Power and brightness for the displays, and window layouts for this PC. This screen is a prototype: choices stay here until we connect them.
          </p>
        </div>
        <Badge variant="outline">Preview</Badge>
      </header>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Displays</CardTitle>
            <CardDescription>Panel 1 answered at {INITIAL_PANEL.host}:{PORT}. Further panels use the next addresses.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            {panels.length === 0 ? (
              <div className="rounded-lg border border-dashed px-4 py-8 text-sm text-muted-foreground">
                No displays in this desk. Add a panel to start a control card.
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                {panels.map((item) => (
                  <button
                    key={item.number}
                    type="button"
                    onClick={() => setSelected(item.number)}
                    className={`rounded-lg border px-3 py-2 text-left text-sm transition-colors ${
                      item.number === selected
                        ? "border-primary bg-primary/15"
                        : "border-border hover:bg-muted"
                    }`}
                  >
                    <span className="block font-medium">Panel {item.number}</span>
                    <span className="font-mono text-xs text-muted-foreground">{item.host}</span>
                  </button>
                ))}
              </div>
            )}

            <div className="flex gap-2">
              <Button type="button" size="sm" onClick={addPanel}>
                Add panel
              </Button>
              {panel ? (
                <Button type="button" size="sm" variant="outline" onClick={() => removePanel(panel.number)}>
                  Remove panel {panel.number}
                </Button>
              ) : null}
            </div>

            <Separator />

            {panel == null ? (
              <p className="text-sm text-muted-foreground">Select a panel to see its controls.</p>
            ) : !panel.read ? (
              <div className="rounded-lg bg-muted/60 px-4 py-6 text-sm">
                <p className="font-medium">Panel {panel.number} has not been read.</p>
                <p className="mt-1 text-muted-foreground">
                  {panel.host}:{panel.port} is the next address. Power and brightness stay off until a reading comes back from that display.
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-5">
                <div
                  className="relative overflow-hidden rounded-xl border"
                  style={{
                    background: panel.power
                      ? `color-mix(in oklch, var(--primary) ${Math.max(panel.backlight, 12)}%, black)`
                      : "oklch(0.12 0 0)",
                  }}
                >
                  <div className="flex aspect-video items-end p-4">
                    <div className="rounded-md bg-black/45 px-3 py-2 text-white backdrop-blur-sm">
                      <p className="text-sm font-medium">{panel.model}</p>
                      <p className="font-mono text-xs text-white/80">
                        ID {panel.displayId} · {panel.power ? "Power on" : "Power off"} · {panel.backlight}%
                      </p>
                    </div>
                  </div>
                </div>

                <dl className="grid grid-cols-2 gap-3 text-sm">
                  <div>
                    <dt className="text-muted-foreground">Address</dt>
                    <dd className="font-mono">{panel.host}:{panel.port}</dd>
                  </div>
                  <div>
                    <dt className="text-muted-foreground">Screen</dt>
                    <dd>{panel.screenOn ? "On" : "Off"}</dd>
                  </div>
                </dl>

                <div className="flex flex-col gap-2">
                  <span className="text-sm font-medium">Power</span>
                  <div className="grid grid-cols-2 gap-2">
                    <Button
                      type="button"
                      variant={panel.power ? "default" : "outline"}
                      onClick={() => updatePanel(panel.number, { power: true })}
                    >
                      On
                    </Button>
                    <Button
                      type="button"
                      variant={!panel.power ? "destructive" : "outline"}
                      onClick={() => updatePanel(panel.number, { power: false })}
                    >
                      Off
                    </Button>
                  </div>
                </div>

                <div className="flex flex-col gap-3">
                  <div className="flex items-baseline justify-between">
                    <span className="text-sm font-medium">Brightness</span>
                    <span className="font-mono text-sm">{panel.backlight}%</span>
                  </div>
                  <Slider
                    min={0}
                    max={100}
                    value={[panel.backlight]}
                    onValueChange={(value) => {
                      const next = Array.isArray(value) ? value[0] : value
                      updatePanel(panel.number, { backlight: next })
                    }}
                    aria-label="Brightness"
                  />
                </div>

                <p className="text-sm text-muted-foreground">
                  {staged && staged.length > 0
                    ? `${staged.join(" · ")} held in this preview. Nothing has been sent to the display.`
                    : "Matches the last reading: power on, brightness 80, screen on."}
                </p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Windows</CardTitle>
            <CardDescription>
              Layouts for arranging windows on this PC, in the same spirit as FancyZones. Applying them to real windows comes later.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
              {LAYOUTS.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => setLayoutId(item.id)}
                  className={`rounded-lg border px-3 py-2 text-left text-sm ${
                    item.id === layout.id ? "border-primary bg-primary/15" : "border-border hover:bg-muted"
                  }`}
                >
                  <span className="block font-medium">{item.name}</span>
                  <span className="text-xs text-muted-foreground">{item.detail}</span>
                </button>
              ))}
            </div>

            <div
              className="grid aspect-video rounded-xl bg-black/50 p-2"
              style={{
                gridTemplateColumns: "repeat(12, minmax(0, 1fr))",
                gridTemplateRows: "repeat(12, minmax(0, 1fr))",
                gap,
              }}
              aria-label={`${layout.name} layout`}
            >
              {layout.zones.map((zone) => (
                <div
                  key={zone.n}
                  style={{
                    gridColumn: `${zone.c + 1} / span ${zone.w}`,
                    gridRow: `${zone.r + 1} / span ${zone.h}`,
                  }}
                  className="flex items-start rounded-md bg-primary/20 p-2 text-xs font-medium text-primary ring-1 ring-primary/40"
                >
                  {showNumbers ? zone.n : null}
                </div>
              ))}
            </div>

            <div className="flex flex-col gap-3">
              <div className="flex items-baseline justify-between">
                <span className="text-sm font-medium">Space between zones</span>
                <span className="font-mono text-sm">{gap}px</span>
              </div>
              <Slider
                min={0}
                max={28}
                value={[gap]}
                onValueChange={(value) => setGap(Array.isArray(value) ? value[0] : value)}
                aria-label="Space between zones"
              />
            </div>

            <label className="flex items-center justify-between gap-3 text-sm">
              <span>Show zone numbers</span>
              <Switch checked={showNumbers} onCheckedChange={setShowNumbers} />
            </label>

            <Button type="button" disabled>
              Apply on this PC
            </Button>
            <p className="text-sm text-muted-foreground">
              {layout.name} is selected. Window movement is not connected, so this does not resize anything open on the desktop.
            </p>
          </CardContent>
        </Card>
      </div>
    </main>
  )
}
