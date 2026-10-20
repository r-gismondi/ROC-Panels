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

function prepareLink(name: string, url: string): { ok: true; name: string; url: string } | { ok: false; message: string } {
  const display = name.trim().slice(0, 40)
  const address = normalizeLinkUrl(url)
  if (!display) return { ok: false, message: "Type a name for this site." }
  if (!validLinkUrl(address)) return { ok: false, message: "Type a full address, such as https://example.com." }
  return { ok: true, name: display, url: address }
}

export function addLink(name: string, url: string): { ok: true; links: SavedLink[]; selectedId: string } | { ok: false; message: string } {
  const prepared = prepareLink(name, url)
  if (!prepared.ok) return prepared
  const links = readLinks()
  const existing = links.find((link) => link.url.toLowerCase() === prepared.url.toLowerCase())
  if (existing) return { ok: true, links, selectedId: existing.id }
  if (links.length >= 24) return { ok: false, message: "Remove a site before adding another." }
  const link = { id: crypto.randomUUID(), name: prepared.name, url: prepared.url }
  const next = [...links, link]
  writeLinks(next)
  return { ok: true, links: next, selectedId: link.id }
}

export function updateLink(
  id: string,
  name: string,
  url: string,
): { ok: true; links: SavedLink[]; selectedId: string } | { ok: false; message: string } {
  const prepared = prepareLink(name, url)
  if (!prepared.ok) return prepared
  const links = readLinks()
  const index = links.findIndex((link) => link.id === id)
  if (index < 0) return { ok: false, message: "That site is no longer saved." }
  const clash = links.find((link) => link.id !== id && link.url.toLowerCase() === prepared.url.toLowerCase())
  if (clash) return { ok: false, message: "Another saved site already uses that address." }
  const next = links.map((link, i) => (i === index ? { ...link, name: prepared.name, url: prepared.url } : link))
  writeLinks(next)
  return { ok: true, links: next, selectedId: id }
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
