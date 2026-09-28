import { execFile } from "child_process"
import path from "path"
import { promisify } from "util"

const execFileAsync = promisify(execFile)

export type DisplayRow = {
  screen: string
  ok: boolean
  power?: boolean
  brightness?: number
  error?: string
}

type ApplyResponse = { results?: DisplayRow[]; error?: string }

function repoRoot() {
  const cwd = process.cwd().replace(/\\/g, "/")
  return cwd.endsWith("/web") ? path.resolve(process.cwd(), "..") : process.cwd()
}

async function python(payload: unknown) {
  const cwd = repoRoot()
  const args = ["-m", "samsung_controller.apply", JSON.stringify(payload)]
  const options = { cwd, timeout: 40000, windowsHide: true, maxBuffer: 1024 * 1024 }
  try {
    return await execFileAsync("py", ["-3", ...args], options)
  } catch (error) {
    const failed = error as { code?: string }
    if (failed.code !== "ENOENT") throw error
    return execFileAsync("python", args, options)
  }
}

export async function controlDisplays(payload: unknown): Promise<{ ok: true; results: DisplayRow[] } | { ok: false; message: string }> {
  try {
    const { stdout } = await python(payload)
    const body = JSON.parse(stdout) as ApplyResponse
    if (body.error) return { ok: false, message: body.error }
    if (!body.results) return { ok: false, message: "The displays did not answer." }
    return { ok: true, results: body.results }
  } catch (error) {
    const failed = error as { code?: string; stdout?: string; message?: string }
    if (failed.code === "ENOENT") return { ok: false, message: "Python was not found, so the displays could not be changed." }
    if (failed.stdout) {
      try {
        const body = JSON.parse(failed.stdout) as ApplyResponse
        if (body.error) return { ok: false, message: body.error }
      } catch {
        // The process failed before it wrote a result.
      }
    }
    return { ok: false, message: failed.message || "The displays could not be reached." }
  }
}

export function screenList(value: unknown) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 18) return null
  const screens: string[] = []
  for (const item of value) {
    if (typeof item !== "string" || !/^TV([1-9]|1[0-8])$/.test(item)) return null
    if (!screens.includes(item)) screens.push(item)
  }
  return screens
}

function numbers(screens: string[]) {
  const labels = screens.map((screen) => screen.replace("TV", ""))
  if (labels.length === 1) return `screen ${labels[0]}`
  if (labels.length === 2) return `screens ${labels[0]} and ${labels[1]}`
  return `screens ${labels.slice(0, -1).join(", ")} and ${labels[labels.length - 1]}`
}

export function describeControl(power: boolean | null, brightness: number | null, results: DisplayRow[]) {
  const succeeded = results.filter((row) => row.ok).map((row) => row.screen)
  const failed = results.filter((row) => !row.ok)
  if (succeeded.length === 0) {
    return failed[0]?.error || "Those screens did not answer."
  }
  const changed = power === null ? `Set brightness to ${brightness}% on ${numbers(succeeded)}.` : `${power ? "Turned on" : "Turned off"} ${numbers(succeeded)}.`
  if (failed.length === 0) return changed
  return `${changed} ${numbers(failed.map((row) => row.screen))} did not answer.`
}
