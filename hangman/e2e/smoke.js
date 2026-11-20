// Browser smoke test, run in CI against a real production release
// (see .github/workflows/ci.yml). Usage: node e2e/smoke.js [base_url]
const path = require("path")
const fs = require("fs")
const {chromium, devices} = require("playwright")

const BASE = process.argv[2] || "http://localhost:4000"
const OUT = path.join(__dirname, "screenshots")
const ORDER = "eaiorntslcudpmhgbyfwkvxzjq".split("")
fs.mkdirSync(OUT, {recursive: true})

const step = (msg) => console.log("✓", msg)

async function connected(page) {
  await page.waitForFunction(() => window.liveSocket?.isConnected(), null, {timeout: 20000})
}

async function playRound(page) {
  for (const letter of ORDER) {
    if (await page.locator("#result").count()) break
    if (await page.locator(`button[data-key=${letter}]`).isDisabled()) continue
    await page.keyboard.press(letter)
    await page.waitForFunction((l) => document.querySelector(`button[data-key=${l}]`).disabled, letter)
  }
  await page.waitForSelector("#result")
  return page.getAttribute("#result", "data-status")
}

;(async () => {
  const browser = await chromium.launch()
  const errors = []

  const page = await browser.newPage({viewport: {width: 1440, height: 900}})
  page.on("pageerror", (e) => errors.push(e.message))
  await page.goto(BASE + "/hangman")
  await connected(page)
  step("LiveView connected")
  await page.screenshot({path: `${OUT}/menu.png`})

  await page.keyboard.press("ArrowRight")
  await page.waitForSelector(".guide-row.is-selected[data-show=big_bang]")
  await page.click("button[phx-value-difficulty=easy]")
  await page.keyboard.press("Enter")
  await page.waitForSelector("#board .tile")
  await page.waitForSelector("#mascot[data-show=big_bang]")
  await page.waitForTimeout(2300) // title card
  step("channel flipped with arrows; episode started from the keyboard")

  const status = await playRound(page)
  step(`round finished: ${status}`)
  await page.waitForTimeout(2500)
  await page.screenshot({path: `${OUT}/result.png`})
  if (!(await page.locator("#next").isVisible())) throw new Error("result buttons not visible")

  // X-ray mode: real process info, real code, live wire traffic.
  await page.keyboard.press("Enter")
  await page.waitForFunction(() => !document.querySelector("#result"))
  await page.click("#xray-toggle")
  await page.waitForSelector("#xray-panel")
  if (!(await page.textContent(".xp-runtime")).includes("#PID<")) throw new Error("no PID in x-ray")
  await page.click(".pin[phx-value-section=word]")
  await page.waitForSelector(".xp-code")
  await page.click(".xp-tabs button[phx-value-tab=wire]")
  await page.waitForTimeout(2300)
  await page.keyboard.press("e")
  await page.waitForSelector(".wire-row.wire-up")
  await page.screenshot({path: `${OUT}/xray.png`})
  step("x-ray panel shows PID, code and live wire traffic")
  await page.click("#xray-toggle")

  await page.reload()
  await connected(page)
  const played = JSON.parse(await page.evaluate(() => localStorage.getItem("hangman:stats:v1"))).played
  if (played !== 1) throw new Error(`expected 1 game in saved stats, got ${played}`)
  step("stats persisted across reload")

  // Same flow with WebSockets blocked, as behind Vercel's rewrite proxy.
  const lp = await browser.newPage()
  lp.on("pageerror", (e) => errors.push(e.message))
  await lp.routeWebSocket(/.*/, (ws) => ws.close())
  await lp.goto(BASE + "/hangman")
  await connected(lp)
  await lp.click("#play")
  await lp.waitForSelector("#board")
  await lp.waitForTimeout(2300)
  await lp.keyboard.press("e")
  await lp.waitForFunction(() => document.querySelector("button[data-key=e]").disabled)
  step("long-polling fallback works")

  const ctx = await browser.newContext({...devices["iPhone 14"]})
  const phone = await ctx.newPage()
  await phone.goto(BASE + "/hangman")
  await connected(phone)
  await phone.click("#play")
  await phone.waitForSelector("#board")
  await phone.waitForTimeout(2500)
  await phone.screenshot({path: `${OUT}/mobile.png`, fullPage: true})
  if (await phone.evaluate(() => document.documentElement.scrollWidth > window.innerWidth))
    throw new Error("horizontal overflow on mobile")
  step("mobile layout fits")

  if (errors.length) throw new Error("page errors:\n" + errors.join("\n"))
  await browser.close()
})().catch((e) => {
  console.error(e)
  process.exit(1)
})
