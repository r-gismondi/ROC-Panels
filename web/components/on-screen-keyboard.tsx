"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"

type KeySpec = { label: string; insert?: string; action?: "shift" | "backspace" | "space" | "enter" | "clear"; grow?: number }

const ROW_1: KeySpec[] = [
  { label: "`", insert: "`" },
  { label: "1", insert: "1" },
  { label: "2", insert: "2" },
  { label: "3", insert: "3" },
  { label: "4", insert: "4" },
  { label: "5", insert: "5" },
  { label: "6", insert: "6" },
  { label: "7", insert: "7" },
  { label: "8", insert: "8" },
  { label: "9", insert: "9" },
  { label: "0", insert: "0" },
  { label: "-", insert: "-" },
  { label: "=", insert: "=" },
  { label: "Backspace", action: "backspace", grow: 1.6 },
]

const ROW_1_SHIFT: KeySpec[] = [
  { label: "~", insert: "~" },
  { label: "!", insert: "!" },
  { label: "@", insert: "@" },
  { label: "#", insert: "#" },
  { label: "$", insert: "$" },
  { label: "%", insert: "%" },
  { label: "^", insert: "^" },
  { label: "&", insert: "&" },
  { label: "*", insert: "*" },
  { label: "(", insert: "(" },
  { label: ")", insert: ")" },
  { label: "_", insert: "_" },
  { label: "+", insert: "+" },
  { label: "Backspace", action: "backspace", grow: 1.6 },
]

const ROW_2: KeySpec[] = [
  { label: "q", insert: "q" },
  { label: "w", insert: "w" },
  { label: "e", insert: "e" },
  { label: "r", insert: "r" },
  { label: "t", insert: "t" },
  { label: "y", insert: "y" },
  { label: "u", insert: "u" },
  { label: "i", insert: "i" },
  { label: "o", insert: "o" },
  { label: "p", insert: "p" },
  { label: "[", insert: "[" },
  { label: "]", insert: "]" },
  { label: "\\", insert: "\\" },
]

const ROW_2_SHIFT: KeySpec[] = [
  { label: "Q", insert: "Q" },
  { label: "W", insert: "W" },
  { label: "E", insert: "E" },
  { label: "R", insert: "R" },
  { label: "T", insert: "T" },
  { label: "Y", insert: "Y" },
  { label: "U", insert: "U" },
  { label: "I", insert: "I" },
  { label: "O", insert: "O" },
  { label: "P", insert: "P" },
  { label: "{", insert: "{" },
  { label: "}", insert: "}" },
  { label: "|", insert: "|" },
]

const ROW_3: KeySpec[] = [
  { label: "a", insert: "a" },
  { label: "s", insert: "s" },
  { label: "d", insert: "d" },
  { label: "f", insert: "f" },
  { label: "g", insert: "g" },
  { label: "h", insert: "h" },
  { label: "j", insert: "j" },
  { label: "k", insert: "k" },
  { label: "l", insert: "l" },
  { label: ";", insert: ";" },
  { label: "'", insert: "'" },
]

const ROW_3_SHIFT: KeySpec[] = [
  { label: "A", insert: "A" },
  { label: "S", insert: "S" },
  { label: "D", insert: "D" },
  { label: "F", insert: "F" },
  { label: "G", insert: "G" },
  { label: "H", insert: "H" },
  { label: "J", insert: "J" },
  { label: "K", insert: "K" },
  { label: "L", insert: "L" },
  { label: ":", insert: ":" },
  { label: '"', insert: '"' },
]

const ROW_4: KeySpec[] = [
  { label: "Shift", action: "shift", grow: 1.5 },
  { label: "z", insert: "z" },
  { label: "x", insert: "x" },
  { label: "c", insert: "c" },
  { label: "v", insert: "v" },
  { label: "b", insert: "b" },
  { label: "n", insert: "n" },
  { label: "m", insert: "m" },
  { label: ",", insert: "," },
  { label: ".", insert: "." },
  { label: "/", insert: "/" },
  { label: "Shift", action: "shift", grow: 1.5 },
]

const ROW_4_SHIFT: KeySpec[] = [
  { label: "Shift", action: "shift", grow: 1.5 },
  { label: "Z", insert: "Z" },
  { label: "X", insert: "X" },
  { label: "C", insert: "C" },
  { label: "V", insert: "V" },
  { label: "B", insert: "B" },
  { label: "N", insert: "N" },
  { label: "M", insert: "M" },
  { label: "<", insert: "<" },
  { label: ">", insert: ">" },
  { label: "?", insert: "?" },
  { label: "Shift", action: "shift", grow: 1.5 },
]

const URL_SHORTCUTS = ["https://", "www.", ".com", ".net", ".org", "://", "/", "?", "&", "=", "#"]

export function insertAtCaret(value: string, token: string, start: number, end: number, replaceAll = false) {
  if (replaceAll) return { value: token, caret: token.length }
  const next = `${value.slice(0, start)}${token}${value.slice(end)}`
  return { value: next, caret: start + token.length }
}

export function backspaceAtCaret(value: string, start: number, end: number, replaceAll = false) {
  if (replaceAll) return { value: "", caret: 0 }
  if (start !== end) {
    const next = `${value.slice(0, start)}${value.slice(end)}`
    return { value: next, caret: start }
  }
  if (start <= 0) return { value, caret: 0 }
  const next = `${value.slice(0, start - 1)}${value.slice(start)}`
  return { value: next, caret: start - 1 }
}

export function OnScreenKeyboard({
  onInsert,
  onBackspace,
  onClear,
  onEnter,
  onScheme,
  showUrlShortcuts = false,
  footer,
}: {
  onInsert: (token: string) => void
  onBackspace: () => void
  onClear?: () => void
  onEnter?: () => void
  onScheme?: () => void
  showUrlShortcuts?: boolean
  footer?: ReactNode
}) {
  const [shift, setShift] = useState(false)
  const rows = shift
    ? [ROW_1_SHIFT, ROW_2_SHIFT, ROW_3_SHIFT, ROW_4_SHIFT]
    : [ROW_1, ROW_2, ROW_3, ROW_4]

  function press(key: KeySpec) {
    if (key.action === "shift") {
      setShift((value) => !value)
      return
    }
    if (key.action === "backspace") {
      onBackspace()
      return
    }
    if (key.action === "clear") {
      onClear?.()
      return
    }
    if (key.action === "enter") {
      onEnter?.()
      return
    }
    if (key.action === "space") {
      onInsert(" ")
      if (shift) setShift(false)
      return
    }
    if (key.insert != null) {
      onInsert(key.insert)
      if (shift && /^[A-Za-z]$/.test(key.insert)) setShift(false)
    }
  }

  return (
    <div className="flex flex-col gap-1.5 select-none">
      {rows.map((row, index) => (
        <div
          key={index}
          className="flex gap-1.5"
          style={{ paddingLeft: index === 1 ? "1.1rem" : index === 2 ? "2.2rem" : undefined, paddingRight: index === 1 ? "1.1rem" : index === 2 ? "2.2rem" : undefined }}
        >
          {row.map((key, keyIndex) => (
            <KeyCap
              key={`${key.label}-${keyIndex}`}
              active={key.action === "shift" && shift}
              grow={key.grow}
              onClick={() => press(key)}
            >
              {key.label}
            </KeyCap>
          ))}
        </div>
      ))}
      <div className="flex gap-1.5">
        {onClear ? (
          <KeyCap grow={1.2} onClick={() => onClear()}>
            Clear
          </KeyCap>
        ) : null}
        <KeyCap grow={6} onClick={() => press({ label: "Space", action: "space" })}>
          Space
        </KeyCap>
        {onEnter ? (
          <KeyCap grow={1.4} onClick={() => onEnter()}>
            Enter
          </KeyCap>
        ) : null}
      </div>
      {showUrlShortcuts ? (
        <div className="flex flex-wrap gap-1.5">
          {URL_SHORTCUTS.map((token) => (
            <KeyCap key={token} onClick={() => (token === "https://" && onScheme ? onScheme() : onInsert(token))}>
              {token}
            </KeyCap>
          ))}
        </div>
      ) : null}
      {footer}
    </div>
  )
}

function KeyCap({
  children,
  onClick,
  grow = 1,
  active = false,
}: {
  children: ReactNode
  onClick: () => void
  grow?: number
  active?: boolean
}) {
  return (
    <button
      type="button"
      tabIndex={-1}
      onMouseDown={(event) => event.preventDefault()}
      onClick={onClick}
      style={grow ? { flexGrow: grow, flexBasis: 0 } : undefined}
      className={`min-h-12 min-w-10 rounded-md border px-2 text-base tracking-wide touch-manipulation sm:min-h-14 sm:text-lg ${
        active
          ? "border-cyan-200 bg-cyan-400/30 shadow-[0_0_12px_rgba(80,200,255,0.3)]"
          : "border-cyan-300/40 bg-[#0a2a6a] hover:border-cyan-200/70"
      }`}
    >
      {children}
    </button>
  )
}

export function TypeField({
  label,
  value,
  active,
  mono = false,
  maxLength,
  inputRef,
  onFocus,
  onChange,
  onCaret,
}: {
  label: string
  value: string
  active: boolean
  mono?: boolean
  maxLength?: number
  inputRef?: (node: HTMLInputElement | null) => void
  onFocus: () => void
  onChange: (value: string) => void
  onCaret: (start: number, end: number) => void
}) {
  return (
    <label
      className={`block rounded-lg border px-3 py-3 text-left ${
        active ? "border-white bg-white/10" : "border-cyan-300/40 bg-[#08245f]/80"
      }`}
    >
      <span className="text-[11px] tracking-[0.16em] text-cyan-100/70">{label}</span>
      <input
        ref={inputRef}
        value={value}
        maxLength={maxLength}
        spellCheck={false}
        autoCapitalize="off"
        autoCorrect="off"
        autoComplete="off"
        onFocus={(event) => {
          onFocus()
          onCaret(event.currentTarget.selectionStart ?? value.length, event.currentTarget.selectionEnd ?? value.length)
        }}
        onClick={(event) => {
          onCaret(event.currentTarget.selectionStart ?? value.length, event.currentTarget.selectionEnd ?? value.length)
        }}
        onSelect={(event) => {
          onCaret(event.currentTarget.selectionStart ?? value.length, event.currentTarget.selectionEnd ?? value.length)
        }}
        onKeyUp={(event) => {
          onCaret(event.currentTarget.selectionStart ?? value.length, event.currentTarget.selectionEnd ?? value.length)
        }}
        onChange={(event) => {
          onChange(event.target.value)
          onCaret(event.target.selectionStart ?? event.target.value.length, event.target.selectionEnd ?? event.target.value.length)
        }}
        className={`mt-1 w-full min-h-7 border-0 bg-transparent p-0 text-base leading-7 text-white outline-none ${
          mono ? "font-mono" : ""
        }`}
      />
    </label>
  )
}

export function usePhysicalTyping(
  enabled: boolean,
  handlers: {
    onInsert: (token: string) => void
    onBackspace: () => void
    onEnter?: () => void
    onEscape?: () => void
  },
) {
  const handlersRef = useRef(handlers)
  handlersRef.current = handlers
  useEffect(() => {
    if (!enabled) return
    function onKeyDown(event: KeyboardEvent) {
      const target = event.target
      if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) return
      if (event.ctrlKey || event.metaKey || event.altKey) return
      const current = handlersRef.current
      if (event.key === "Backspace") {
        event.preventDefault()
        current.onBackspace()
        return
      }
      if (event.key === "Enter") {
        event.preventDefault()
        current.onEnter?.()
        return
      }
      if (event.key === "Escape") {
        event.preventDefault()
        current.onEscape?.()
        return
      }
      if (event.key.length === 1) {
        event.preventDefault()
        current.onInsert(event.key)
      }
    }
    function onPaste(event: ClipboardEvent) {
      const target = event.target
      if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) return
      const text = event.clipboardData?.getData("text") ?? ""
      if (!text) return
      event.preventDefault()
      handlersRef.current.onInsert(text)
    }
    window.addEventListener("keydown", onKeyDown)
    window.addEventListener("paste", onPaste)
    return () => {
      window.removeEventListener("keydown", onKeyDown)
      window.removeEventListener("paste", onPaste)
    }
  }, [enabled])
}
