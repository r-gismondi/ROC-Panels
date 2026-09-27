import { execFile } from "child_process"
import { promisify } from "util"

const execFileAsync = promisify(execFile)

const HOSTS: Record<string, string> = {
  "101": "192.168.0.101",
  "102": "192.168.0.102",
  "103": "192.168.0.103",
}

const BATS: Record<string, string> = {
  independent: "Edge-Independent.bat",
  split: "Edge-Split.bat",
  focus: "Edge-Focus.bat",
  "focus-split": "Edge-Focus-Split.bat",
  full: "Edge-Full.bat",
}

const ALLOWED: Record<string, string[]> = {
  "101": ["independent", "split", "focus", "focus-split", "full"],
  "102": ["independent", "split", "focus", "focus-split", "full"],
  "103": ["independent", "full"],
}

const TASK = "WallLayout"

export type LaunchResult = { ok: true; message: string } | { ok: false; message: string }

export function layoutCommand(computer: string, preset: string) {
  const host = HOSTS[computer]
  const allowed = ALLOWED[computer]
  const bat = BATS[preset]
  if (!host || !allowed || !bat || !allowed.includes(preset)) return null
  return {
    host,
    bat,
    path: `C:\\layouts\\computer-${computer}\\${bat}`,
    label:
      preset === "focus-split" ? "Focus split" : preset.charAt(0).toUpperCase() + preset.slice(1),
  }
}

function redact(text: string, password: string) {
  if (!password) return text
  return text.split(password).join("***")
}

async function schtasks(args: string[], password: string) {
  try {
    const { stdout } = await execFileAsync("schtasks.exe", args, { windowsHide: true, timeout: 30000 })
    return { ok: true as const, text: stdout.trim() }
  } catch (error) {
    const failed = error as { code?: string; stdout?: string; stderr?: string; message?: string }
    if (failed.code === "ENOENT") return { ok: false as const, text: "schtasks was not found." }
    const text = redact(`${failed.stdout ?? ""}\n${failed.stderr ?? ""}`.trim() || failed.message || "The layout task failed.", password)
    return { ok: false as const, text }
  }
}

export async function launchLayout(computer: string, preset: string): Promise<LaunchResult> {
  const command = layoutCommand(computer, preset)
  if (!command) return { ok: false, message: "That preset is not on this computer." }
  if (process.platform !== "win32") {
    return {
      ok: false,
      message: "Run this page on a Windows computer on the wall network. Preset buttons launch the Edge layouts from there.",
    }
  }
  const user = process.env.LAYOUT_USER || "Administrator"
  const password = process.env.LAYOUT_PASSWORD || ""
  if (!password) return { ok: false, message: "Set LAYOUT_PASSWORD to the wall Administrator password, then restart this page." }

  const auth = ["/S", command.host, "/U", user, "/P", password]
  await schtasks(["/End", ...auth, "/TN", TASK], password)

  const created = await schtasks(
    ["/Create", ...auth, "/RU", user, "/SC", "ONCE", "/ST", "00:00", "/TN", TASK, "/TR", command.path, "/F", "/IT"],
    password,
  )
  const task = created.ok
    ? created
    : await schtasks(
        ["/Create", ...auth, "/RU", user, "/RP", password, "/SC", "ONCE", "/ST", "00:00", "/RL", "HIGHEST", "/TN", TASK, "/TR", command.path, "/F"],
        password,
      )
  if (!task.ok) return { ok: false, message: task.text }

  const started = await schtasks(["/Run", ...auth, "/TN", TASK], password)
  if (!started.ok) return { ok: false, message: started.text }
  if (created.ok) return { ok: true, message: `Opened ${command.label} on ${command.host}.` }
  return {
    ok: true,
    message: `Started ${command.label} on ${command.host}. Windows may stay off the desktop because the interactive option was rejected.`,
  }
}
