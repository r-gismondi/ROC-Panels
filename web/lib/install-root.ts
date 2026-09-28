import path from "path"

export function installRoot() {
  const configured = process.env.ROC_ROOT
  if (configured) return configured
  const cwd = process.cwd().replace(/\\/g, "/")
  return cwd.endsWith("/web") ? path.resolve(process.cwd(), "..") : process.cwd()
}

export function scriptsDir() {
  if (process.env.ROC_ROOT) return path.join(process.env.ROC_ROOT, "scripts")
  return path.join(process.cwd(), "scripts")
}
