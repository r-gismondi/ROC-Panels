const fs = require("fs")
const path = require("path")
const { spawn } = require("child_process")

const nextRoot = path.join(__dirname, "..", "node_modules", "next")
const file = path.join(nextRoot, "dist", "lib", "picocolors.js")
const marker = "/* wall-console: bind picocolors exports */"

if (!fs.existsSync(file)) {
  console.error("Next is not installed in this folder. Run npm install here, then start again.")
  process.exit(1)
}

const src = fs.readFileSync(file, "utf8")
if (!src.includes(marker)) {
  fs.appendFileSync(
    file,
    "\n" +
      marker +
      "\nmodule.exports = { __esModule: true, reset, bold, dim, italic, underline, inverse, hidden, strikethrough, black, red, green, yellow, blue, magenta, purple, cyan, white, gray, bgBlack, bgRed, bgGreen, bgYellow, bgBlue, bgMagenta, bgCyan, bgWhite };\n",
  )
}

const colors = require(file)
if (typeof colors.bold !== "function") {
  console.error("Next's color helper still has no bold function. Delete node_modules and run npm install again.")
  process.exit(1)
}

const args = process.argv.slice(2)
if (args.length === 0) {
  process.exit(0)
}

const child = spawn(process.execPath, [path.join(nextRoot, "dist", "bin", "next"), ...args], {
  stdio: "inherit",
})
child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal)
    return
  }
  process.exit(code ?? 1)
})
