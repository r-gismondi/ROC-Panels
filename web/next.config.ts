import type { NextConfig } from "next"
import path from "path"
import { fileURLToPath } from "url"

const nextConfig: NextConfig = {
  output: "standalone",
  turbopack: {
    root: path.dirname(fileURLToPath(import.meta.url)),
  },
  async headers() {
    return [{ source: "/", headers: [{ key: "Cache-Control", value: "no-store" }] }]
  },
}

export default nextConfig
