import path from "path"

export function installRoot() {
  const configured = process.env.ROC_ROOT
  if (configured) return configured
  const cwd = process.cwd().replace(/\\/g, "/")
  return cwd.endsWith("/web") ? path.resolve(process.cwd(), "..") : process.cwd()
}
