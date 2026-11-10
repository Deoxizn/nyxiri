"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(root, name), "utf8")

test("every NYXIRI-BEGIN block has a matching end", () => {
  const lines = read("Bar.qml").split(/\r?\n/)
  const stack = []
  const seen = new Set()
  for (let i = 0; i < lines.length; i++) {
    const begin = lines[i].match(/NYXIRI-BEGIN\s+([A-Za-z0-9_-]+)/)
    const end = lines[i].match(/NYXIRI-END\s+([A-Za-z0-9_-]+)/)
    if (begin) {
      assert.equal(stack.length, 0, `nested block at line ${i + 1}: ${begin[1]}`)
      stack.push({ name: begin[1], line: i + 1 })
      seen.add(begin[1])
    } else if (end) {
      assert.ok(stack.length > 0, `unmatched end at line ${i + 1}: ${end[1]}`)
      const open = stack.pop()
      assert.equal(open.name, end[1], `block ${open.name} closed as ${end[1]} at line ${i + 1}`)
    }
  }
  assert.deepEqual(stack, [], "unclosed Nyxiri blocks")
  assert.ok(seen.has("nyxiri-config"), "missing config block")
  assert.ok(seen.has("nyxiri-write"), "missing write block")
  assert.ok(seen.has("nyxiri-pill"), "missing pill block")
  assert.ok(seen.has("nyxiri-settings-card"), "missing settings block")
})

test("BarModel.js is unmodified upstream", () => {
  assert.equal(read("BarModel.js"), read("upstream/BarModel.js"))
})

test("the working bar imports the config module and keeps its entry point", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /import "Nyxiri\.js" as Nyxiri/)
  assert.match(bar, /function writeNyxiri\(patch\)/)
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.id, "devi.nyxiri")
  assert.deepEqual(manifest.kinds, ["bar"])
  assert.equal(manifest.entryPoints.bar, "Bar.qml")
})

test("the settings card is a PopupCard and does not redeclare bar", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /^PopupCard \{/m)
  assert.doesNotMatch(settings, /required property var bar/)
})

test("the settings card has a bar-surface opacity slider and a registry fallback for the plugin probe", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /surfaceOpacity/)
  assert.match(settings, /pluginsFromRegistry/)
  assert.match(settings, /probeWatchdog/)
  assert.match(settings, /useRegistryPlugins/)
})

test("the bar background honors the surface opacity setting", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /nyxiri\.pill\.surfaceOpacity/)
})

test("upstream snapshots are present", () => {
  for (const name of ["upstream/Bar.qml", "upstream/BarModel.js", "upstream/bar-manifest.json"]) {
    assert.ok(fs.existsSync(path.join(root, name)), name)
  }
})
