"use client"

import { useEffect, useState, type CSSProperties, type ReactNode } from "react"

export const MOTION_MS = 480

export const motionStyle: CSSProperties = {
  transitionProperty: "opacity, transform, translate, max-width, grid-template-rows",
  transitionDuration: `${MOTION_MS}ms`,
  transitionTimingFunction: "cubic-bezier(0.22, 1, 0.36, 1)",
}

export function usePresence(show: boolean, duration = MOTION_MS) {
  const [mounted, setMounted] = useState(show)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (show) {
      setMounted(true)
      const timer = window.setTimeout(() => setVisible(true), 40)
      return () => window.clearTimeout(timer)
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
  const hidden = motion === "up" ? "translate-y-6 opacity-0" : motion === "down" ? "-translate-y-4 opacity-0" : "translate-y-4 scale-[0.96] opacity-0"
  return (
    <div className={`${visible ? "translate-y-0 scale-100 opacity-100" : hidden} ${className}`} style={motionStyle}>
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

  return (
    <p className={`${on ? "opacity-100" : "opacity-0"} ${className}`} style={{ transition: "opacity 180ms ease" }}>
      {shown}
    </p>
  )
}
