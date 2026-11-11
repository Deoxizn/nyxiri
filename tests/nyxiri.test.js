"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")

const Nyxiri = require("./_load-nyxiri.js")

test("defaults cover every section and pill key", () => {
  const config = Nyxiri.defaults()
  assert.deepEqual(config.sections, { left: "island", center: "island", right: "island" })
  assert.equal(config.pill.color, "accent")
  assert.equal(config.pill.surface, "theme")
  assert.equal(config.pill.surfaceOpacity, 1)
  assert.equal(config.pill.textShadow, true)
  assert.deepEqual(config.monitors, {})
})

test("normalize fills defaults and clamps numbers", () => {
  const config = Nyxiri.normalize({
    sections: { left: "mini", center: "nope" },
    pill: { fillOpacity: 2, borderOpacity: -1, borderWidth: 99, radius: -4, color: "  red  ", surfaceOpacity: 2, textShadow: false },
    monitors: { "DP-1": { enabled: false, widgets: { mode: "only", list: [" clock ", "clock", 3] } } }
  })
  assert.equal(config.sections.left, "mini")
  assert.equal(config.sections.center, "island")
  assert.equal(config.pill.fillOpacity, 1)
  assert.equal(config.pill.borderOpacity, 0)
  assert.equal(config.pill.surfaceOpacity, 1)
  assert.equal(config.pill.textShadow, false)
  assert.equal(config.pill.borderWidth, 6)
  assert.equal(config.pill.radius, 0)
  assert.equal(config.pill.color, "red")
  assert.deepEqual(config.monitors["DP-1"], { enabled: false, widgets: { mode: "only", list: ["clock"] } })
})

test("normalize ignores unknown and prototype keys", () => {
  const raw = JSON.parse('{"__proto__":{"polluted":true},"constructor":{"x":1},"nope":1}')
  const config = Nyxiri.normalize(raw)
  assert.equal(config.polluted, undefined)
  assert.equal({}.polluted, undefined)
})

test("normalize rejects non-object input", () => {
  assert.deepEqual(Nyxiri.normalize(null), Nyxiri.defaults())
  assert.deepEqual(Nyxiri.normalize("nope"), Nyxiri.defaults())
  assert.deepEqual(Nyxiri.normalize([]), Nyxiri.defaults())
})

test("merge is pure and deep", () => {
  const base = Nyxiri.defaults()
  const next = Nyxiri.merge(base, { sections: { left: "mini" }, pill: { fillOpacity: 0.5 } })
  assert.equal(base.sections.left, "island")
  assert.equal(base.pill.fillOpacity, 0.18)
  assert.equal(next.sections.left, "mini")
  assert.equal(next.sections.right, "island")
  assert.equal(next.pill.fillOpacity, 0.5)
})

test("merge replaces arrays and deletes null keys", () => {
  const next = Nyxiri.merge(
    { monitors: { "DP-1": { enabled: false }, "HDMI-A-1": { enabled: false } } },
    { monitors: { "DP-1": null } }
  )
  assert.deepEqual(next.monitors, { "HDMI-A-1": { enabled: false } })
})

test("merge ignores prototype pollution attempts", () => {
  const patch = JSON.parse('{"__proto__":{"polluted":true},"pill":{"__proto__":{"x":1}}}')
  const next = Nyxiri.merge({}, patch)
  assert.equal(next.polluted, undefined)
  assert.equal({}.polluted, undefined)
  assert.deepEqual(next.pill, {})
})

test("sectionMode folds centerBegin and centerEnd into center", () => {
  const config = Nyxiri.normalize({ sections: { center: "mini" } })
  assert.equal(Nyxiri.sectionMode(config, "center"), "mini")
  assert.equal(Nyxiri.sectionMode(config, "centerBegin"), "mini")
  assert.equal(Nyxiri.sectionMode(config, "centerEnd"), "mini")
  assert.equal(Nyxiri.sectionMode(config, "left"), "island")
  assert.equal(Nyxiri.sectionMode(config, "tray"), "island")
})

test("monitorFor defaults to enabled and all widgets", () => {
  const config = Nyxiri.normalize({})
  assert.deepEqual(Nyxiri.monitorFor(config, "DP-9"), { enabled: true, widgets: { mode: "all", list: [] } })
  assert.deepEqual(Nyxiri.monitorFor(config, ""), { enabled: true, widgets: { mode: "all", list: [] } })
})

test("allows matches ids and id#serial keys", () => {
  const only = Nyxiri.normalize({
    monitors: { "DP-1": { widgets: { mode: "only", list: ["omarchy.clock"] } } }
  })
  assert.equal(Nyxiri.allows(only, "DP-1", "omarchy.clock#4"), true)
  assert.equal(Nyxiri.allows(only, "DP-1", "omarchy.audio#2"), false)
  assert.equal(Nyxiri.allows(only, "DP-2", "omarchy.audio#2"), true)

  const except = Nyxiri.normalize({
    monitors: { "DP-1": { widgets: { mode: "except", list: ["omarchy.tray#1"] } } }
  })
  assert.equal(Nyxiri.allows(except, "DP-1", "omarchy.tray#1"), false)
  assert.equal(Nyxiri.allows(except, "DP-1", "omarchy.clock#4"), true)
})

test("only mode with an empty list shows nothing", () => {
  const config = Nyxiri.normalize({ monitors: { "DP-1": { widgets: { mode: "only" } } } })
  assert.deepEqual(Nyxiri.filterKeys(config, "DP-1", ["a#1"]), [])
})

test("filterKeys leaves an unconfigured monitor untouched", () => {
  const config = Nyxiri.normalize({ monitors: { "DP-1": { widgets: { mode: "only", list: ["a"] } } } })
  const keys = ["a#1", "b#2"]
  const filtered = Nyxiri.filterKeys(config, "DP-2", keys)
  assert.deepEqual(filtered, keys)
  assert.notEqual(filtered, keys)
})

test("parseColorsToml reads quoted, single-quoted and unquoted values", () => {
  const palette = Nyxiri.parseColorsToml([
    "[colors]",
    'accent = "#7aa2f7"',
    "red = '#f7768e'",
    "green = #9ece6a",
    "blue = #7aa2f7 # comment",
    'invalid = "not-a-colour"',
    "# comment = \"#000000\"",
    ""
  ].join("\n"))
  assert.deepEqual(palette, {
    accent: "#7aa2f7",
    red: "#f7768e",
    green: "#9ece6a",
    blue: "#7aa2f7"
  })
})

test("paletteRoles is sorted", () => {
  assert.deepEqual(Nyxiri.paletteRoles({ red: "#ff0000", accent: "#00ff00" }), ["accent", "red"])
})

test("resolveColor prefers custom hex then the palette role", () => {
  const palette = { accent: "#7aa2f7", red: "#f7768e" }
  assert.equal(Nyxiri.resolveColor(palette, { color: "red" }, "#000000"), "#f7768e")
  assert.equal(Nyxiri.resolveColor(palette, { color: "missing" }, "#000000"), "#000000")
  assert.equal(Nyxiri.resolveColor(palette, { color: "custom", customColor: "#abcdef" }, "#000000"), "#abcdef")
  assert.equal(Nyxiri.resolveColor(palette, { color: "custom", customColor: "nope" }, "#000000"), "#000000")
  assert.equal(Nyxiri.resolveColor(palette, { color: "#123456" }, "#000000"), "#123456")
})

test("isHexColor accepts 3, 4, 6 and 8 digit colours", () => {
  for (const value of ["#fff", "#ffff", "#ffffff", "#ffffffff"]) assert.equal(Nyxiri.isHexColor(value), true, value)
  for (const value of ["fff", "#ff", "#gggggg", "#fffff"]) assert.equal(Nyxiri.isHexColor(value), false, value)
})
