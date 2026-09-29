"use client"

import { useEffect, useState, type ReactNode } from "react"

export function usePresence(show: boolean, duration = 300) {
  const [mounted, setMounted] = useState(show)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    let inner = 0
    if (show) {
      setMounted(true)
      const outer = requestAnimationFrame(() => {
        inner = requestAnimationFrame(() => setVisible(true))
      })
      return () => {
        cancelAnimationFrame(outer)
        cancelAnimationFrame(inner)
      }
    }
    setVisible(false)
    const timer = window.setTimeout(() => setMounted(false), duration)
    return () => window.clearTimeout(timer)
  }, [show, duration])

  return { mounted, visible }
}

export function Reveal({
  show,
  children,
  className = "",
  motion = "fade",
}: {
  show: boolean
  children: ReactNode
  className?: string
  motion?: "fade" | "up" | "down"
}) {
  const { mounted, visible } = usePresence(show)
  if (!mounted) return null
  const hidden = motion === "up" ? "translate-y-3 opacity-0" : motion === "down" ? "-translate-y-2 opacity-0" : "translate-y-1 opacity-0 scale-[0.98]"
  return (
    <div className={`transition-[opacity,transform] duration-300 ease-out motion-reduce:transition-none ${visible ? "translate-y-0 scale-100 opacity-100" : hidden} ${className}`}>
      {children}
    </div>
  )
}

export function StatusLine({ text, className = "" }: { text: string; className?: string }) {
  const [shown, setShown] = useState(text)
  const [on, setOn] = useState(true)

  useEffect(() => {
    if (text === shown) return
    setOn(false)
    const timer = window.setTimeout(() => {
      setShown(text)
      setOn(true)
    }, 140)
    return () => window.clearTimeout(timer)
  }, [text, shown])

  return <p className={`transition-opacity duration-150 motion-reduce:transition-none ${on ? "opacity-100" : "opacity-0"} ${className}`}>{shown}</p>
}
