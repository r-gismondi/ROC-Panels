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

export const MAX_VIEW_GROUPS = 5

export function isCustomViewId(id: string) {
  return id.startsWith("custom-")
}

/** Panel 1 and Panel 2 share the same 4×2 shape; screens 13/18 are a separate layout. */
export function panelFamily(computer: "101" | "102" | "103"): "wall4x2" | "wall1x2" {
  return computer === "103" ? "wall1x2" : "wall4x2"
}

export function canApplyCustomView(view: CustomView, computer: "101" | "102" | "103") {
  return panelFamily(view.computer) === panelFamily(computer)
}

/** Remap a saved view onto another computer that shares the same grid shape. */
export function adaptCustomView(view: CustomView, computer: "101" | "102" | "103"): CustomView | null {
  if (!canApplyCustomView(view, computer)) return null
  if (view.computer === computer) return view
  const from = CUSTOM_VIEW_SCREENS[view.computer]
  const to = CUSTOM_VIEW_SCREENS[computer]
  const groups: Record<string, number> = {}
  from.forEach((id, index) => {
    const group = view.groups[id]
    if (group == null || !to[index]) return
    groups[to[index]] = group
  })
  let next = Math.max(-1, ...Object.values(groups), -1) + 1
  for (const id of to) {
    if (!(id in groups)) groups[id] = next++
  }
  return { ...view, computer, groups }
}

/** Build preset groups from named buckets; leftover screens each get their own window. */
export function groupsFromBuckets(computer: "101" | "102" | "103", buckets: string[][]): Record<string, number> {
  const all = CUSTOM_VIEW_SCREENS[computer]
  const map: Record<string, number> = {}
  let next = 0
  for (const bucket of buckets) {
    const ids = [...new Set(bucket.filter((id) => all.includes(id)))]
    if (ids.length === 0) continue
    for (const id of ids) map[id] = next
    next += 1
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

export function normalizeBuckets(computer: "101" | "102" | "103", buckets: string[][]) {
  const allowed = new Set(CUSTOM_VIEW_SCREENS[computer])
  return buckets
    .map((bucket) => [...new Set(bucket.filter((id) => allowed.has(id)))])
    .filter((bucket) => bucket.length > 0)
}

export function validateViewBuckets(
  computer: "101" | "102" | "103",
  buckets: string[][],
): { ok: true; buckets: string[][] } | { ok: false; message: string } {
  const allowed = new Set(CUSTOM_VIEW_SCREENS[computer])
  for (const bucket of buckets) {
    if (bucket.some((id) => !allowed.has(id))) {
      return { ok: false, message: "You can only select screens from the panel you have selected." }
    }
  }
  const cleaned = normalizeBuckets(computer, buckets)
  if (cleaned.length === 0) {
    return { ok: false, message: "Tap screens to build at least one Edge window group." }
  }
  const used = new Set<string>()
  for (const bucket of cleaned) {
    for (const id of bucket) {
      if (used.has(id)) return { ok: false, message: "A screen can only belong to one group." }
      used.add(id)
    }
    if (!selectionIsRectangle(computer, bucket)) {
      return { ok: false, message: "Each group needs to form one solid block." }
    }
  }
  return { ok: true, buckets: cleaned }
}
