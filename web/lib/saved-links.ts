import crypto from "crypto"
import fs from "fs"
import { operatorFile, writeOperatorJson } from "@/lib/operator-data"
import { launchScreenAddress, type LaunchResult } from "@/lib/launch-layout"

export type SavedLink = { id: string; name: string; url: string }

function linksFile() {
  return operatorFile("saved-links.json")
}

export function readLinks(): SavedLink[] {
  try {
    const parsed = JSON.parse(fs.readFileSync(linksFile(), "utf8")) as unknown
    if (!Array.isArray(parsed)) return []
    return parsed.filter((item): item is SavedLink => {
      if (!item || typeof item !== "object") return false
      const link = item as SavedLink
      return typeof link.id === "string" && typeof link.name === "string" && typeof link.url === "string"
    })
  } catch {
    return []
  }
}

function writeLinks(links: SavedLink[]) {
  writeOperatorJson(linksFile(), links)
}

export function normalizeLinkUrl(value: string) {
  const trimmed = value.trim()
  if (!trimmed) return ""
  if (/^https?:\/\//i.test(trimmed)) return trimmed
  return `https://${trimmed}`
}

function validLinkUrl(url: string) {
  return /^https?:\/\/\S+$/i.test(url) && !/[\s"'<>\\]/.test(url) && url.length <= 2048
}

export function addLink(name: string, url: string): { ok: true; links: SavedLink[]; selectedId: string } | { ok: false; message: string } {
  const display = name.trim().slice(0, 40)
  const address = normalizeLinkUrl(url)
  if (!display) return { ok: false, message: "Type a name for this site." }
  if (!validLinkUrl(address)) return { ok: false, message: "Type a full address, such as https://example.com." }
  const links = readLinks()
  const existing = links.find((link) => link.url.toLowerCase() === address.toLowerCase())
  if (existing) return { ok: true, links, selectedId: existing.id }
  if (links.length >= 24) return { ok: false, message: "Remove a site before adding another." }
  const link = { id: crypto.randomUUID(), name: display, url: address }
  const next = [...links, link]
  writeLinks(next)
  return { ok: true, links: next, selectedId: link.id }
}

export function removeLink(id: string) {
  const next = readLinks().filter((link) => link.id !== id)
  writeLinks(next)
  return next
}

export async function launchLink(id: string, screen: string): Promise<LaunchResult> {
  const link = readLinks().find((item) => item.id === id)
  if (!link) return { ok: false, message: "Choose a site, then tap a screen." }
  return launchScreenAddress(screen, link.url, link.name)
}
