import { execFile } from "child_process"
import path from "path"
import { promisify } from "util"
import { NextResponse } from "next/server"
import { scriptsDir } from "@/lib/install-root"

const execFileAsync = promisify(execFile)

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { action?: string } | null
  const action = body?.action === "minimize" ? "Minimize" : body?.action === "close" ? "Close" : ""
  if (!action) return NextResponse.json({ error: "Choose minimize or close." }, { status: 400 })
  try {
    await execFileAsync(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(scriptsDir(), "Set-ConsoleWindow.ps1"), "-Action", action],
      { timeout: 8000, windowsHide: true },
    )
    return NextResponse.json({ ok: true })
  } catch (error) {
    const failed = error as { stderr?: string; message?: string }
    const detail = `${failed.stderr || ""} ${failed.message || ""}`.replace(/\s+/g, " ").trim()
    return NextResponse.json({ error: detail || "The console window could not be changed." }, { status: 500 })
  }
}
