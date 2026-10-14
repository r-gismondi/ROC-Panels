export type Screen = { id: string; hdmi: string }

export type Preset = { id: string; name: string; groups: Record<string, number> }

export const GROUP_COLOR = ["#3ec8ff", "#d56bff", "#7eb6ff", "#5eead4", "#f0c27a"]

export type Zone = { key: string; color: string; ids: string[]; row: number; col: number; rows: number; cols: number }

// Every preset group is a rectangle of screens, so one box per group covers exactly its screens.
export function presetZones(rows: Screen[][], preset: Preset): Zone[] {
  const found = new Map<number, { ids: string[]; r0: number; r1: number; c0: number; c1: number }>()
  rows.forEach((row, r) =>
    row.forEach((screen, c) => {
      const group = preset.groups[screen.id] ?? 0
      const zone = found.get(group)
      if (!zone) found.set(group, { ids: [screen.id], r0: r, r1: r, c0: c, c1: c })
      else {
        zone.ids.push(screen.id)
        zone.r0 = Math.min(zone.r0, r)
        zone.r1 = Math.max(zone.r1, r)
        zone.c0 = Math.min(zone.c0, c)
        zone.c1 = Math.max(zone.c1, c)
      }
    }),
  )
  return [...found.entries()].map(([group, zone]) => ({
    key: `${preset.id}-${group}`,
    color: GROUP_COLOR[group % GROUP_COLOR.length],
    ids: zone.ids,
    row: zone.r0 + 1,
    col: zone.c0 + 1,
    rows: zone.r1 - zone.r0 + 1,
    cols: zone.c1 - zone.c0 + 1,
  }))
}
