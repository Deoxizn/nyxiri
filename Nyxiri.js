.pragma library

// Nyxiri configuration helpers.
//
// Everything Nyxiri owns lives under `bar.nyxiri` in shell.json, so the host
// bar API passes it in through `barConfig.nyxiri`. This module is pure: it
// normalizes what came off disk, merges partial edits, answers per-monitor
// questions, and resolves a colour role from the active theme's colors.toml.
//
// Keep it free of QML imports so `node --test` can load it directly.

var SECTIONS = ["left", "center", "right"]
var MODES = ["island", "mini"]
var WIDGET_MODES = ["all", "only", "except"]
var SURFACES = ["theme", "clear"]
var DEFAULT_COLOR = "accent"
var HEX_COLOR = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
var PROTECTED_KEYS = ["__proto__", "constructor", "prototype"]

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOwn(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

function isSafeKey(key) {
  return PROTECTED_KEYS.indexOf(String(key)) === -1
}

function clone(value) {
  if (Array.isArray(value)) {
    var list = []
    for (var i = 0; i < value.length; i++) list.push(clone(value[i]))
    return list
  }
  if (isPlainObject(value)) {
    var out = {}
    for (var key in value) {
      if (!hasOwn(value, key) || !isSafeKey(key)) continue
      out[key] = clone(value[key])
    }
    return out
  }
  return value
}

function defaults() {
  return {
    version: 1,
    sections: { left: "island", center: "island", right: "island" },
    pill: {
      color: DEFAULT_COLOR,
      customColor: "",
      fillOpacity: 0.18,
      borderOpacity: 0.35,
      borderWidth: 1,
      radius: 999,
      padding: 6,
      inset: 2,
      miniGap: 2,
      surface: "theme",
      surfaceOpacity: 1
    },
    monitors: {}
  }
}

function numberIn(value, fallback, minimum, maximum) {
  var number = Number(value)
  if (!isFinite(number)) return fallback
  if (number < minimum) return minimum
  if (number > maximum) return maximum
  return number
}

function stringIn(value, allowed, fallback) {
  var text = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(text) === -1 ? fallback : text
}

function isHexColor(value) {
  return typeof value === "string" && HEX_COLOR.test(value.trim())
}

function monitorEntry(raw) {
  var out = { enabled: true, widgets: { mode: "all", list: [] } }
  if (!isPlainObject(raw)) return out
  if (typeof raw.enabled === "boolean") out.enabled = raw.enabled
  var widgets = isPlainObject(raw.widgets) ? raw.widgets : null
  if (widgets) {
    out.widgets.mode = stringIn(widgets.mode, WIDGET_MODES, "all")
    if (Array.isArray(widgets.list)) {
      var list = []
      for (var i = 0; i < widgets.list.length; i++) {
        var rule = widgets.list[i]
        if (typeof rule !== "string") continue
        rule = rule.trim()
        if (rule && list.indexOf(rule) === -1) list.push(rule)
      }
      out.widgets.list = list
    }
  }
  return out
}

// Returns a complete, validated config. Unknown keys are dropped, so a stale
// field can never leak back into a persisted write.
function normalize(raw) {
  var out = defaults()
  if (!isPlainObject(raw)) return out

  var sections = isPlainObject(raw.sections) ? raw.sections : null
  if (sections) {
    for (var s = 0; s < SECTIONS.length; s++) {
      var section = SECTIONS[s]
      if (hasOwn(sections, section)) out.sections[section] = stringIn(sections[section], MODES, out.sections[section])
    }
  }

  var pill = isPlainObject(raw.pill) ? raw.pill : null
  if (pill) {
    if (typeof pill.color === "string" && pill.color.trim()) out.pill.color = pill.color.trim()
    if (typeof pill.customColor === "string" && isHexColor(pill.customColor)) out.pill.customColor = pill.customColor.trim()
    out.pill.fillOpacity = numberIn(pill.fillOpacity, out.pill.fillOpacity, 0, 1)
    out.pill.borderOpacity = numberIn(pill.borderOpacity, out.pill.borderOpacity, 0, 1)
    out.pill.borderWidth = Math.round(numberIn(pill.borderWidth, out.pill.borderWidth, 0, 6))
    out.pill.radius = Math.round(numberIn(pill.radius, out.pill.radius, 0, 999))
    out.pill.padding = Math.round(numberIn(pill.padding, out.pill.padding, 0, 32))
    out.pill.inset = Math.round(numberIn(pill.inset, out.pill.inset, 0, 16))
    out.pill.miniGap = Math.round(numberIn(pill.miniGap, out.pill.miniGap, 0, 16))
    out.pill.surface = stringIn(pill.surface, SURFACES, out.pill.surface)
    out.pill.surfaceOpacity = numberIn(pill.surfaceOpacity, out.pill.surfaceOpacity, 0, 1)
  }

  if (isPlainObject(raw.monitors)) {
    for (var name in raw.monitors) {
      if (!hasOwn(raw.monitors, name) || !isSafeKey(name)) continue
      var key = String(name).trim()
      if (!key) continue
      out.monitors[key] = monitorEntry(raw.monitors[name])
    }
  }

  return out
}

// Deep merge used for every write. `null` removes a key, arrays and scalars
// replace, and prototype keys are ignored. `base` is never modified.
function merge(base, patch) {
  var out = isPlainObject(base) ? clone(base) : {}
  if (!isPlainObject(patch)) return out
  for (var key in patch) {
    if (!hasOwn(patch, key) || !isSafeKey(key)) continue
    var value = patch[key]
    if (value === null) {
      delete out[key]
    } else if (isPlainObject(value) && isPlainObject(out[key])) {
      out[key] = merge(out[key], value)
    } else {
      out[key] = clone(value)
    }
  }
  return out
}

function sectionMode(config, section) {
  var name = String(section === undefined || section === null ? "" : section)
  if (name === "centerBegin" || name === "centerEnd") name = "center"
  if (SECTIONS.indexOf(name) === -1) return "island"
  var sections = config && isPlainObject(config.sections) ? config.sections : null
  var mode = sections && hasOwn(sections, name) ? sections[name] : "island"
  return MODES.indexOf(mode) === -1 ? "island" : mode
}

function monitorFor(config, screenName) {
  var name = String(screenName === undefined || screenName === null ? "" : screenName)
  var monitors = config && isPlainObject(config.monitors) ? config.monitors : null
  if (!name || !monitors || !hasOwn(monitors, name)) return monitorEntry(null)
  return monitorEntry(monitors[name])
}

// A layout key is `id#serial` (BarModel.layoutWidgets). A rule may name the
// whole key or just the id, and the id is what survives a reload.
function baseWidgetId(key) {
  var text = String(key === undefined || key === null ? "" : key)
  var hash = text.indexOf("#")
  return hash === -1 ? text : text.substring(0, hash)
}

function ruleMatches(rule, key) {
  var wanted = String(rule === undefined || rule === null ? "" : rule).trim()
  if (!wanted) return false
  var full = String(key === undefined || key === null ? "" : key)
  return wanted === full || wanted === baseWidgetId(full)
}

function allows(config, screenName, widgetKey) {
  var monitor = monitorFor(config, screenName)
  var mode = monitor.widgets.mode
  if (mode === "all") return true
  var list = monitor.widgets.list
  var found = false
  for (var i = 0; i < list.length; i++) {
    if (ruleMatches(list[i], widgetKey)) {
      found = true
      break
    }
  }
  return mode === "only" ? found : !found
}

function filterKeys(config, screenName, keys) {
  if (!Array.isArray(keys)) return []
  var monitor = monitorFor(config, screenName)
  if (monitor.widgets.mode === "all") return keys.slice()
  var out = []
  for (var i = 0; i < keys.length; i++) {
    if (allows(config, screenName, keys[i])) out.push(keys[i])
  }
  return out
}

// colors.toml is a flat table of `role = "#rrggbb"` lines. Unknown syntax is
// skipped rather than failing the whole palette.
function parseColorsToml(text) {
  var palette = {}
  if (typeof text !== "string") return palette
  var lines = text.split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line || line.charAt(0) === "#" || line.charAt(0) === "[") continue
    var equals = line.indexOf("=")
    if (equals === -1) continue
    var key = line.substring(0, equals).trim()
    if (!key) continue
    var value = line.substring(equals + 1).trim()
    var first = value.charAt(0)
    var last = value.charAt(value.length - 1)
    if (value.length >= 2 && ((first === '"' && last === '"') || (first === "'" && last === "'"))) {
      value = value.substring(1, value.length - 1)
    } else {
      // Unquoted value with a trailing comment: keep the token before it.
      var comment = value.indexOf(" #")
      if (comment > 0) value = value.substring(0, comment).trim()
    }
    if (isHexColor(value)) palette[key] = value
  }
  return palette
}

function paletteRoles(palette) {
  if (!isPlainObject(palette)) return []
  var roles = []
  for (var key in palette) {
    if (hasOwn(palette, key)) roles.push(key)
  }
  roles.sort()
  return roles
}

function resolveColor(palette, pill, fallback) {
  var config = isPlainObject(pill) ? pill : {}
  var color = String(config.color === undefined || config.color === null ? DEFAULT_COLOR : config.color)
  if (color === "custom") {
    if (isHexColor(config.customColor)) return config.customColor.trim()
    return fallback
  }
  if (isHexColor(color)) return color.trim()
  if (isPlainObject(palette) && hasOwn(palette, color) && isHexColor(palette[color])) return palette[color]
  return fallback
}

// Node's test runner, and any future tooling, loads this through require().
// QML ignores the guard.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    SECTIONS: SECTIONS,
    MODES: MODES,
    WIDGET_MODES: WIDGET_MODES,
    SURFACES: SURFACES,
    defaults: defaults,
    normalize: normalize,
    merge: merge,
    sectionMode: sectionMode,
    monitorFor: monitorFor,
    allows: allows,
    filterKeys: filterKeys,
    baseWidgetId: baseWidgetId,
    ruleMatches: ruleMatches,
    parseColorsToml: parseColorsToml,
    paletteRoles: paletteRoles,
    resolveColor: resolveColor,
    isHexColor: isHexColor
  }
}
