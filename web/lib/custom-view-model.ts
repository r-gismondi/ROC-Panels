export type CustomView = {
  id: string
  name: string
  computer: "101" | "102" | "103"
  groups: Record<string, number>
}

export const CUSTOM_VIEW_SCREENS: Record<"101" | "102" | "103", string[]> = {
  "101": ["TV1", "TV2", "TV3", "TV4", "TV5", "TV6", "TV7", "TV8"],
  "102": ["TV9", "TV10", "TV11", "TV12", "TV14", "TV15", "TV16", "TV17"],
  "103": ["TV13", "TV18"],
}

const GRIDS: Record<"101" | "102" | "103", string[][]> = {
  "101": [
    ["TV1", "TV2", "TV3", "TV4"],
    ["TV5", "TV6", "TV7", "TV8"],
  ],
  "102": [
    ["TV9", "TV10", "TV11", "TV12"],
    ["TV14", "TV15", "TV16", "TV17"],
  ],
  "103": [["TV13"], ["TV18"]],
}

export function isCustomViewId(id: string) {
  return id.startsWith("custom-")
}

export function groupsFromSelection(computer: "101" | "102" | "103", selected: string[]): Record<string, number> {
  const all = CUSTOM_VIEW_SCREENS[computer]
  const picked = new Set(selected.filter((id) => all.includes(id)))
  const map: Record<string, number> = {}
  let next = 0
  if (picked.size > 0) {
    for (const id of all) {
      if (picked.has(id)) map[id] = 0
    }
    next = 1
  }
  for (const id of all) {
    if (!(id in map)) map[id] = next++
  }
  return map
}

export function selectionIsRectangle(computer: "101" | "102" | "103", selected: string[]) {
  const rows = GRIDS[computer]
  const cells: { r: number; c: number }[] = []
  rows.forEach((row, r) =>
    row.forEach((id, c) => {
      if (selected.includes(id)) cells.push({ r, c })
    }),
  )
  if (cells.length === 0) return false
  const r0 = Math.min(...cells.map((cell) => cell.r))
  const r1 = Math.max(...cells.map((cell) => cell.r))
  const c0 = Math.min(...cells.map((cell) => cell.c))
  const c1 = Math.max(...cells.map((cell) => cell.c))
  if ((r1 - r0 + 1) * (c1 - c0 + 1) !== cells.length) return false
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      if (!selected.includes(rows[r][c])) return false
    }
  }
  return true
}
