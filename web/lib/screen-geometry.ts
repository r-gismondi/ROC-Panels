export type ZoneSpec = { title: string; x: number; y: number; w: number; h: number }

const SCREEN_RECTS: Record<string, { x: number; y: number; w: number; h: number }> = {
  TV1: { x: 0, y: 0, w: 960, h: 540 },
  TV2: { x: 960, y: 0, w: 960, h: 540 },
  TV3: { x: 1920, y: 0, w: 960, h: 540 },
  TV4: { x: 2880, y: 0, w: 960, h: 540 },
  TV5: { x: 0, y: 540, w: 960, h: 540 },
  TV6: { x: 960, y: 540, w: 960, h: 540 },
  TV7: { x: 1920, y: 540, w: 960, h: 540 },
  TV8: { x: 2880, y: 540, w: 960, h: 540 },
  TV9: { x: 0, y: 0, w: 960, h: 540 },
  TV10: { x: 960, y: 0, w: 960, h: 540 },
  TV11: { x: 1920, y: 0, w: 960, h: 540 },
  TV12: { x: 2880, y: 0, w: 960, h: 540 },
  TV14: { x: 0, y: 540, w: 960, h: 540 },
  TV15: { x: 960, y: 540, w: 960, h: 540 },
  TV16: { x: 1920, y: 540, w: 960, h: 540 },
  TV17: { x: 2880, y: 540, w: 960, h: 540 },
  TV13: { x: 0, y: 0, w: 1920, h: 1080 },
  TV18: { x: 0, y: 1080, w: 1920, h: 1080 },
}

export function zonesFromGroups(groups: Record<string, number>): ZoneSpec[] {
  const buckets = new Map<number, string[]>()
  for (const [id, group] of Object.entries(groups)) {
    if (!SCREEN_RECTS[id]) continue
    const list = buckets.get(group)
    if (list) list.push(id)
    else buckets.set(group, [id])
  }
  return [...buckets.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([, ids]) => {
      const rects = ids.map((id) => SCREEN_RECTS[id])
      const x = Math.min(...rects.map((rect) => rect.x))
      const y = Math.min(...rects.map((rect) => rect.y))
      const right = Math.max(...rects.map((rect) => rect.x + rect.w))
      const bottom = Math.max(...rects.map((rect) => rect.y + rect.h))
      const ordered = [...ids].sort((a, b) => {
        const left = SCREEN_RECTS[a]
        const rightRect = SCREEN_RECTS[b]
        return left.y - rightRect.y || left.x - rightRect.x
      })
      return { title: ordered.join(" "), x, y, w: right - x, h: bottom - y }
    })
}
