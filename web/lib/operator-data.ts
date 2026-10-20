import fs from "fs"
import os from "os"
import path from "path"
import { installRoot } from "@/lib/install-root"

/** Operator-owned files live outside the install folder so pedestal rebuilds do not wipe them. */
export function operatorDataRoot() {
  if (process.env.ROC_DATA) return process.env.ROC_DATA
  const base = process.platform === "win32" && process.env.LOCALAPPDATA ? process.env.LOCALAPPDATA : path.join(os.homedir(), ".local", "share")
  return path.join(base, "ROC-Panels")
}

function legacyPath(name: string) {
  return path.join(installRoot(), name)
}

function currentPath(name: string) {
  return path.join(operatorDataRoot(), name)
}

/** Prefer the profile copy; if only the old install copy exists, migrate it once. */
export function operatorFile(name: string) {
  const next = currentPath(name)
  if (fs.existsSync(next)) return next
  const legacy = legacyPath(name)
  if (!fs.existsSync(legacy)) return next
  try {
    fs.mkdirSync(path.dirname(next), { recursive: true })
    fs.copyFileSync(legacy, next)
    return next
  } catch {
    return legacy
  }
}

export function operatorDir(name: string) {
  const next = currentPath(name)
  if (fs.existsSync(next)) return next
  const legacy = legacyPath(name)
  if (!fs.existsSync(legacy) || !fs.statSync(legacy).isDirectory()) return next
  try {
    fs.mkdirSync(path.dirname(next), { recursive: true })
    fs.cpSync(legacy, next, { recursive: true, force: false, errorOnExist: false })
    return next
  } catch {
    return legacy
  }
}

export function writeOperatorJson(file: string, value: unknown) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  const temporary = `${file}.${process.pid}.tmp`
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), "utf8")
  fs.renameSync(temporary, file)
}
