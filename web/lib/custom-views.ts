import crypto from "crypto"
import fs from "fs"
import path from "path"
import {
  CUSTOM_VIEW_SCREENS,
  groupsFromSelection,
  isCustomViewId,
  selectionIsRectangle,
  type CustomView,
} from "@/lib/custom-view-model"
import { installRoot } from "@/lib/install-root"
import { zonesFromGroups, type ZoneSpec } from "@/lib/screen-geometry"

export type { CustomView }
export { groupsFromSelection, isCustomViewId, CUSTOM_VIEW_SCREENS as screenIdsFor }

function viewsFile() {
  return path.join(installRoot(), "custom-views.json")
}

export function readCustomViews(): CustomView[] {
  try {
    const parsed = JSON.parse(fs.readFileSync(viewsFile(), "utf8")) as unknown
    if (!Array.isArray(parsed)) return []
    return parsed.filter((item): item is CustomView => {
      if (!item || typeof item !== "object") return false
      const view = item as CustomView
      return (
        typeof view.id === "string" &&
        isCustomViewId(view.id) &&
        typeof view.name === "string" &&
        (view.computer === "101" || view.computer === "102" || view.computer === "103") &&
        view.groups != null &&
        typeof view.groups === "object"
      )
    })
  } catch {
    return []
  }
}

function writeCustomViews(views: CustomView[]) {
  const file = viewsFile()
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const temporary = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temporary, JSON.stringify(views, null, 2), "utf8")
  fs.renameSync(temporary, file)
}

export function customViewsFor(computer: "101" | "102" | "103") {
  return readCustomViews().filter((view) => view.computer === computer)
}

export function findCustomView(id: string) {
  return readCustomViews().find((view) => view.id === id) ?? null
}

export function addCustomView(
  computer: "101" | "102" | "103",
  name: string,
  selected: string[],
): { ok: true; views: CustomView[]; selectedId: string } | { ok: false; message: string } {
  const display = name.trim().slice(0, 40)
  if (!display) return { ok: false, message: "Type a name for this view." }
  const all = CUSTOM_VIEW_SCREENS[computer]
  const picked = [...new Set(selected.filter((id) => all.includes(id)))]
  if (picked.length === 0) return { ok: false, message: "Tap at least one screen on this panel to add it." }
  if (selected.some((id) => !all.includes(id))) {
    return { ok: false, message: "You can only select screens from the panel you have selected." }
  }
  if (!selectionIsRectangle(computer, picked)) {
    return { ok: false, message: "Those screens need to form one solid block." }
  }
  const views = readCustomViews()
  if (views.filter((view) => view.computer === computer).length >= 12) {
    return { ok: false, message: "Remove a custom view before adding another." }
  }
  const view: CustomView = {
    id: `custom-${crypto.randomUUID()}`,
    name: display,
    computer,
    groups: groupsFromSelection(computer, picked),
  }
  const next = [...views, view]
  writeCustomViews(next)
  return { ok: true, views: next, selectedId: view.id }
}

export function removeCustomView(id: string) {
  const next = readCustomViews().filter((view) => view.id !== id)
  writeCustomViews(next)
  return next
}

export function zonesForCustomView(view: CustomView): ZoneSpec[] {
  return zonesFromGroups(view.groups)
}
