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

test("the pill opacity slider is the fill level itself, so 100% means solid", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /BodyText \{ text: "Pill opacity"/)
  assert.doesNotMatch(settings, /pill\.opacity/)
  const bar = read("Bar.qml")
  assert.match(bar, /color: Util\.alpha\(pillColor, fillOpacity\)/)
  assert.match(bar, /Border\.flat\(Util\.alpha\(pillColor, borderOpacity\), borderWidth\)/)
  assert.doesNotMatch(bar, /masterOpacity/)
})

test("the settings card forces keyboard focus into its text fields on click", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /component FocusField: TextField/)
  assert.match(settings, /forceActiveFocus/)
  assert.doesNotMatch(settings, /            TextField \{/)
})

test("the settings card shows a scrollbar when a tab overflows", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /id: scrollArea/)
  assert.match(settings, /width: parent\.width - Style\.space\(10\)/)
  assert.match(settings, /width: scrollArea\.width/)
  assert.match(settings, /id: scrollBar/)
  assert.match(settings, /visible: scrollArea\.contentHeight > viewport\.height/)
  assert.match(settings, /thumbHeight/)
  assert.match(settings, /onPressed: function\(mouse\) \{ scrollBar\.scrollTo\(mouse\.y\) \}/)
})

test("the widgets tab shows a row for every plugin even when kinds are unknown", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /rowShown/)
  assert.match(settings, /kindList\(pluginRow\.modelData\)\.length === 0/)
  assert.match(settings, /plugins\.length \+ " plugins · " \+ popup\.activePlugins \+ " active"/)
})

test("the widgets tab sorts active plugins first, then disabled, each alphabetical", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /readonly property var sortedPlugins/)
  assert.match(settings, /model: popup\.sortedPlugins/)
  assert.match(settings, /var ae = a\.enabled === true \? 0 : 1/)
  assert.match(settings, /String\(a\.name \|\| a\.id \|\| ""\)\.toLowerCase\(\)/)
})

test("the bar exposes the workspaces widget's settings like the menu's", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /function nyxiriWorkspacesEntryKey\(\)/)
  assert.match(bar, /function nyxiriWorkspacesSetting\(name, fallback\)/)
  assert.match(bar, /nyxiriWorkspacesAvailable: nyxiriWorkspacesEntryKey\(\) !== ""/)
  assert.match(bar, /function writeWorkspacesSettings\(patch\)/)
  assert.match(bar, /updateEntryInline\("devi\.nyxiri-workspaces", next\)/)
})

test("the settings card offers workspaces mode and hide-empty controls", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /text: "WORKSPACES"/)
  assert.match(settings, /workspacesSetting\("mode", "10"\)/)
  assert.match(settings, /value: "active", label: "Active only"/)
  assert.match(settings, /workspacesSetting\("hideEmpty", false\)/)
  assert.match(settings, /setWorkspaces\(\{ hideEmpty: !checked \}\)/)
  assert.match(settings, /popup\.bar\.nyxiriWorkspacesAvailable/)
})

test("the settings card has a workspaces tab with a marker style picker", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /\{ value: "workspaces", label: "Workspaces" \}/)
  assert.match(settings, /visible: popup\.tab === "workspaces"/)
  // Choice rows, not dropdowns: a dropdown popup is clipped by this card's
  // window, so the last style option fell off the bottom edge.
  assert.match(settings, /popup\.workspacesSetting\("mode", "10"\) === modelData\.value/)
  assert.match(settings, /popup\.setWorkspaces\(\{ mode: modelData\.value \}\)/)
  assert.match(settings, /popup\.workspacesSetting\("style", "numbers"\) === modelData\.value/)
  assert.match(settings, /popup\.setWorkspaces\(\{ style: modelData\.value \}\)/)
  assert.match(settings, /\{ value: "dots", label: "Dots" \}/)
  assert.match(settings, /\{ value: "magic", label: "Magic" \}/)
  assert.match(settings, /\{ value: "default", label: "Default" \}/)
  assert.match(settings, /\{ value: "aurora", label: "Aurora" \}/)
  assert.match(settings, /\{ value: "apps", label: "Apps" \}/)
  // Eight styles no longer fit one row, so the style picker wraps.
  assert.match(settings, /\/\/ Eight styles no longer fit one row, so this one wraps/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ mode: value \}\)/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ style: value \}\)/)
})

test("upstream snapshots are present", () => {
  for (const name of ["upstream/Bar.qml", "upstream/BarModel.js", "upstream/bar-manifest.json"]) {
    assert.ok(fs.existsSync(path.join(root, name)), name)
  }
})
