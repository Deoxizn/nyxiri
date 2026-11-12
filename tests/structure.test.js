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

test("the settings card is a KeyboardPanel and does not redeclare bar", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /^KeyboardPanel \{/m)
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

test("the settings card is a KeyboardPanel so its text fields take input", () => {
  const settings = read("NyxiriSettings.qml")
  assert.match(settings, /^KeyboardPanel \{/m)
  assert.doesNotMatch(settings, /^PopupCard \{/m)
  // A PopupCard is an xdg-popup: it only receives keys after a click
  // routes focus through its parent surface, so the wordmark and image
  // fields showed a blinking cursor and swallowed every key, and no
  // amount of forceActiveFocus fixed it. KeyboardPanel is the stock
  // layer-shell fix (Exclusive prime, then OnDemand), the same way the
  // weather panel's location search works.
})

test("text fields commit as you type instead of only on Enter", () => {
  const settings = read("NyxiriSettings.qml")
  // The field owns its text and only syncs from the saved value when that
  // value changes, so an unrelated layout write can't snap in-progress
  // typing back to the last saved value (the wordmark/image hit-or-miss).
  assert.match(settings, /property string settingText/)
  assert.match(settings, /onSettingTextChanged:/)
  // A debounced commit after the last keystroke, plus an immediate commit
  // on Enter or focus loss, so closing the card can't lose the edit.
  assert.match(settings, /signal commit\(string value\)/)
  assert.match(settings, /commitTimer\.restart\(\)/)
  assert.match(settings, /onEditingFinished: commitNow\(\)/)
  // Every text field uses the new contract, no bound `text:` left.
  assert.match(settings, /settingText: popup\.menuSetting\("wordmark", "Nyxiri"\)/)
  assert.match(settings, /settingText: popup\.menuSetting\("iconSource", ""\)/)
  assert.match(settings, /settingText: popup\.pill\.customColor/)
  assert.match(settings, /onCommit: function\(value\) \{ popup\.setMenu\(\{ wordmark: value \}\) \}/)
  assert.match(settings, /onCommit: function\(value\) \{ popup\.setMenu\(\{ iconSource: value \}\) \}/)
  assert.doesNotMatch(settings, /text: popup\.menuSetting\(/)
  assert.doesNotMatch(settings, /text: popup\.pill\.customColor/)
  assert.doesNotMatch(settings, /onEditingFinished: popup\.setMenu\(/)
})

test("the menu wordmark has presets above the custom field", () => {
  const settings = read("NyxiriSettings.qml")
  // Presets are one-tap fills of the same field: the widget renders every
  // wordmark uppercased with wide letterspacing, so the presets are canned
  // strings, not image assets.
  assert.match(settings, /text: "Wordmark"/)
  assert.match(settings, /\{ value: "Arch", label: "Arch" \}/)
  assert.match(settings, /\{ value: "Hyprland", label: "Hyprland" \}/)
  assert.match(settings, /\{ value: "Nyxiri", label: "Nyxiri" \}/)
  assert.match(settings, /\{ value: "Omarchy", label: "Omarchy" \}/)
  assert.match(settings, /onClicked: popup\.setMenu\(\{ wordmark: modelData\.value \}\)/)
  assert.match(settings, /String\(popup\.menuSetting\("wordmark", "Nyxiri"\)\)\.toUpperCase\(\)/)
})

test("the menu trigger uses choice rows, not dropdowns", () => {
  const settings = read("NyxiriSettings.qml")
  // Dropdown popups are clipped by the card's window, so the Custom
  // option never showed, and their clicks clear the card's focus grab,
  // so picking an option closed the card. Choice rows have neither
  // problem, same as Mode and Style.
  assert.match(settings, /text: "Icon mode"/)
  assert.match(settings, /\{ value: "wordmark", label: "Wordmark" \}/)
  assert.match(settings, /onClicked: popup\.setMenu\(\{ iconMode: modelData\.value \}\)/)
  assert.match(settings, /text: "Glyph"/)
  assert.match(settings, /\{ value: "custom", label: "Custom" \}/)
  assert.match(settings, /onClicked: popup\.setMenu\(\{ glyph: modelData\.value \}\)/)
  assert.doesNotMatch(settings, /onChanged: function\(value\) \{ popup\.setMenu\(\{ iconMode: value \}\) \}/)
  assert.doesNotMatch(settings, /onChanged: function\(value\) \{ popup\.setMenu\(\{ glyph: value \}\) \}/)
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

test("the bar api no longer carries the removed center reveal properties", () => {
  const bar = read("Bar.qml")
  // Upstream c149add removed centerSectionRevealHeld and
  // _centerHoverRevealSuppressed from PluginBarApi; assigning them throws
  // and aborts the api wiring, so no widget gets settings or clicks.
  assert.doesNotMatch(bar, /api\.centerSectionRevealHeld/)
  assert.doesNotMatch(bar, /api\._centerHoverRevealSuppressed/)
  assert.doesNotMatch(bar, /_setCenterHoverRevealSuppressed/)
  // The same commit tells widgets in the tray drawer outright.
  assert.match(bar, /property bool inTraySection: false/)
  assert.match(bar, /inTraySection = owner\.region === "tray"/)
  assert.match(bar, /if \("inTraySection" in target\) target\.inTraySection = inTraySection/)
})

test("the settings card probe cleanup uses the bare watchdog id", () => {
  const settings = read("NyxiriSettings.qml")
  // The watchdog timer is nested, so popup.probeWatchdog does not resolve;
  // the bare id is the one that works (as the other two uses already do).
  assert.doesNotMatch(settings, /popup\.probeWatchdog/)
  assert.match(settings, /probeWatchdog\.running = false/)
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
  // The icon size slider only shows for the Apps style, and writes back
  // through the workspaces settings.
  assert.match(settings, /visible: popup\.bar\.nyxiriWorkspacesAvailable && popup\.workspacesSetting\("style", "numbers"\) === "apps"/)
  assert.match(settings, /text: "App icon size"/)
  assert.match(settings, /popup\.workspacesSetting\("iconSize", 16\)/)
  assert.match(settings, /popup\.setWorkspaces\(\{ iconSize: value \}\)/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ mode: value \}\)/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ style: value \}\)/)
})

test("the settings card has a classic workspaces toggle and a per-monitor ranges field", () => {
  const settings = read("NyxiriSettings.qml")
  // The mode is Hyprland state, not a widget setting: the card asks the
  // workspaces plugin's bin/mode, through bash (pushes land mode 644).
  assert.match(settings, /devi\.nyxiri-workspaces\/bin\/mode/)
  assert.match(settings, /\["bash", popup\.classicModeScript, "status"\]/)
  assert.match(settings, /\["bash", popup\.classicModeScript, classic \? "classic" : "4\.5"\]/)
  assert.match(settings, /label: "Classic workspaces"/)
  assert.match(settings, /onClicked: popup\.switchClassic\(!checked\)/)
  assert.match(settings, /refreshClassicMode\(\)/)
  // The ranges field only shows while classic is on, and writes back
  // through the workspaces settings like every other field.
  assert.match(settings, /visible: popup\.bar\.nyxiriWorkspacesAvailable && popup\.classicMode/)
  assert.match(settings, /text: "Workspaces per monitor"/)
  assert.match(settings, /placeholderText: "DP-1:1-5,HDMI-A-1:6-10"/)
  assert.match(settings, /popup\.workspacesSetting\("ranges", ""\)/)
  assert.match(settings, /popup\.setWorkspaces\(\{ ranges: value \}\)/)
  // In classic with a range set, the ranges decide how many show, so
  // Ten vs Five is a no-op: a hint under Mode says the modes are really
  // a 4.5 thing. Without a range, Mode still sets the count, so the
  // hint stays hidden.
  assert.match(settings, /text: "Modes really only for 4\.5"/)
  assert.match(settings, /visible: popup\.bar\.nyxiriWorkspacesAvailable && popup\.classicMode && popup\.workspacesSetting\("ranges", ""\) !== ""/)
})

test("upstream snapshots are present", () => {
  for (const name of ["upstream/Bar.qml", "upstream/BarModel.js", "upstream/bar-manifest.json"]) {
    assert.ok(fs.existsSync(path.join(root, name)), name)
  }
})
