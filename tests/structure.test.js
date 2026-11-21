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
  assert.ok(seen.has("nyxiri-settings-window"), "missing settings window block")
})

test("BarModel.js is unmodified upstream", () => {
  assert.equal(read("BarModel.js"), read("upstream/BarModel.js"))
})

test("the working bar imports the config module and keeps its entry point", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /import "Nyxiri\.js" as Nyxiri/)
  assert.match(bar, /function writeNyxiri\(patch\)/)
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.id, "pizza.dirty.nyxiri")
  assert.deepEqual(manifest.kinds, ["bar"])
  assert.equal(manifest.entryPoints.bar, "Bar.qml")
})

test("the settings window is a PanelWindow and declares its own bar", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /^PanelWindow \{/m)
  assert.match(settings, /property var bar: null/)
})

test("the settings card has a bar-surface opacity slider and a registry fallback for the plugin probe", () => {
  const settings = read("NyxiriSettingsWindow.qml")
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
  const settings = read("NyxiriSettingsWindow.qml")
  // Label above the slider now, not crammed onto one row with it.
  assert.match(settings, /label: "Pill opacity"/)
  assert.match(settings, /component SliderRow: Column/)
  assert.doesNotMatch(settings, /pill\.opacity/)
  const bar = read("Bar.qml")
  assert.match(bar, /color: Util\.alpha\(pillColor, fillOpacity\)/)
  assert.match(bar, /Border\.flat\(Util\.alpha\(pillColor, borderOpacity\), borderWidth\)/)
  assert.doesNotMatch(bar, /masterOpacity/)
})

test("section headers are bigger with room under them, and sliders put the label above", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // SectionLabel is title size now, not caption, with space under it and
  // a full gap above it, so sections read as separate blocks.
  assert.match(settings, /component SectionLabel: Text/)
  assert.match(settings, /font\.pixelSize: Style\.font\.title/)
  assert.match(settings, /bottomPadding: Style\.spacing\.md/)
  assert.match(settings, /topPadding: Style\.space\(16\)/)
  // Sub-headers get the same treatment one step smaller.
  assert.match(settings, /component SubLabel: Text/)
  assert.match(settings, /font\.pixelSize: Style\.font\.body/)
  // Sliders are a SliderRow: label on its own line, slider full width.
  assert.match(settings, /component SliderRow: Column/)
  assert.match(settings, /label: "Background"/)
  assert.match(settings, /label: "Border"/)
  assert.match(settings, /label: "Padding"/)
  // Tab columns breathe instead of packing rows tight: double the old
  // lg spacing, so the gap between sections is twice what it was.
  assert.match(settings, /visible: popup\.tab === "appearance"\n\s+width: parent\.width\n\s+spacing: Style\.space\(16\)/)
  assert.match(settings, /visible: popup\.tab === "workspaces"\n\s+width: parent\.width\n\s+spacing: Style\.space\(16\)/)
  assert.match(settings, /visible: popup\.tab === "monitors"\n\s+width: parent\.width\n\s+spacing: Style\.space\(16\)/)
  assert.match(settings, /visible: popup\.tab === "plugins"\n\s+width: parent\.width\n\s+spacing: Style\.space\(16\)/)
})

test("the settings card forces keyboard focus into its text fields on click", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /component FocusField: TextField/)
  assert.match(settings, /forceActiveFocus/)
  assert.doesNotMatch(settings, /            TextField \{/)
})

test("the settings window is a PanelWindow so its text fields take input", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /^PanelWindow \{/m)
  assert.doesNotMatch(settings, /^PopupCard \{/m)
  // A PopupCard is an xdg-popup: it only receives keys after a click
  // routes focus through its parent surface, so the wordmark and image
  // fields showed a blinking cursor and swallowed every key, and no
  // amount of forceActiveFocus fixed it. PanelWindow is a real
  // layer-shell surface with OnDemand keyboard focus, so the fields
  // take input natively.
})

test("text fields commit as you type instead of only on Enter", () => {
  const settings = read("NyxiriSettingsWindow.qml")
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
  const settings = read("NyxiriSettingsWindow.qml")
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
  const settings = read("NyxiriSettingsWindow.qml")
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
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /id: scrollArea/)
  assert.match(settings, /width: parent\.width - Style\.space\(10\)/)
  assert.match(settings, /width: scrollArea\.width/)
  assert.match(settings, /id: scrollBar/)
  assert.match(settings, /visible: scrollArea\.contentHeight > viewport\.height/)
  assert.match(settings, /thumbHeight/)
  assert.match(settings, /onPressed: function\(mouse\) \{ scrollBar\.scrollTo\(mouse\.y\) \}/)
})

test("the plugins tab shows a row for every plugin even when kinds are unknown", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /rowShown/)
  assert.match(settings, /kindList\(modelData\)\.length === 0/)
  assert.match(settings, /plugins\.length \+ " plugins · " \+ popup\.activePlugins \+ " active · " \+ \(popup\.plugins\.length - popup\.activePlugins\) \+ " disabled"/)
})

test("the plugins tab sorts active plugins first, then disabled, each alphabetical", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /readonly property var sortedPlugins/)
  // One Repeater whose model switches on the sub-tab; both lists feed it.
  assert.match(settings, /model: popup\.pluginGroup === "active" \? popup\.activePluginList : popup\.disabledPluginList/)
  assert.doesNotMatch(settings, /model: popup\.sortedPlugins/)
  assert.match(settings, /var ae = a\.enabled === true \? 0 : 1/)
  assert.match(settings, /String\(a\.name \|\| a\.id \|\| ""\)\.toLowerCase\(\)/)
})

test("the bar exposes the workspaces widget's settings like the menu's", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /function nyxiriWorkspacesEntryKey\(\)/)
  assert.match(bar, /function nyxiriWorkspacesSetting\(name, fallback\)/)
  assert.match(bar, /nyxiriWorkspacesAvailable: nyxiriWorkspacesEntryKey\(\) !== ""/)
  assert.match(bar, /function writeWorkspacesSettings\(patch\)/)
  assert.match(bar, /updateEntryInline\("pizza\.dirty\.nyxiri-workspaces", next\)/)
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
  const settings = read("NyxiriSettingsWindow.qml")
  // The watchdog timer is nested, so popup.probeWatchdog does not resolve;
  // the bare id is the one that works (as the other two uses already do).
  assert.doesNotMatch(settings, /popup\.probeWatchdog/)
  assert.match(settings, /probeWatchdog\.running = false/)
})

test("the settings card offers workspaces mode and hide-empty controls", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /text: "WORKSPACES"/)
  assert.match(settings, /workspacesSetting\("mode", "10"\)/)
  assert.match(settings, /value: "active", label: "Active only"/)
  assert.match(settings, /workspacesSetting\("hideEmpty", false\)/)
  assert.match(settings, /setWorkspaces\(\{ hideEmpty: !checked \}\)/)
  assert.match(settings, /popup\.bar\.nyxiriWorkspacesAvailable/)
})

test("the settings card has a workspaces tab with a marker style picker", () => {
  const settings = read("NyxiriSettingsWindow.qml")
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
  assert.match(settings, /label: "App icon size"/)
  assert.match(settings, /popup\.workspacesSetting\("iconSize", 16\)/)
  assert.match(settings, /popup\.setWorkspaces\(\{ iconSize: value \}\)/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ mode: value \}\)/)
  assert.doesNotMatch(settings, /setWorkspaces\(\{ style: value \}\)/)
})

test("the settings card has a classic workspaces toggle and a per-monitor ranges field", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // The mode is Hyprland state, not a widget setting: the card asks the
  // workspaces plugin's bin/mode, through bash (pushes land mode 644).
  assert.match(settings, /pizza\.dirty\.nyxiri-workspaces\/bin\/mode/)
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
  // Hide empty is a no-op while Mode is Active only (Active already
  // shows just the focused workspace), so the toggle greys out there
  // and says why instead of silently doing nothing.
  assert.match(settings, /label: "Hide empty workspaces"/)
  assert.match(settings, /enabled: popup\.workspacesSetting\("mode", "10"\) !== "active"/)
  assert.match(settings, /description: popup\.workspacesSetting\("mode", "10"\) === "active" \? "Does nothing while Mode is Active only" : "Drops workspaces with no windows; the focused one always stays"/)
})

test("the settings card has a weather secondary-location field", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  const bar = read("Bar.qml")
  // The card reads/writes pizza.dirty.weather's layout entry the same way it
  // does the menu and workspaces entries, only when the widget is on
  // the bar.
  assert.match(bar, /Nyxiri\.baseWidgetId\(key\) === "pizza\.dirty\.weather"/)
  assert.match(bar, /function nyxiriWeatherSetting\(name, fallback\)/)
  assert.match(bar, /nyxiriWeatherAvailable: nyxiriWeatherEntryKey\(\) !== ""/)
  assert.match(bar, /function writeWeatherSettings\(patch\)/)
  assert.match(bar, /shell\.updateEntryInline\("pizza\.dirty\.weather", next\)/)
  assert.match(settings, /function weatherSetting\(name, fallback\)/)
  assert.match(settings, /function setWeather\(patch\)/)
  // The field lives in the Appearance tab's WEATHER section, commits the
  // raw string (a name or "lat,lon"), and explains itself.
  assert.match(settings, /text: "WEATHER"/)
  assert.match(settings, /text: "Secondary location"/)
  assert.match(settings, /placeholderText: "Tucson"/)
  assert.match(settings, /popup\.weatherSetting\("secondaryLocation", ""\)/)
  assert.match(settings, /popup\.setWeather\(\{ secondaryLocation: value \}\)/)
  assert.match(settings, /A second city shown under the main forecast/)
})

test("the settings card has a cycle-layout-on-click toggle", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // Clicking the focused workspace cycles tiling / scrolling / floating;
  // the toggle turns that off, so a double-click to focus a workspace
  // can't change the layout. Same string-"true" read as hideEmpty, on
  // by default.
  assert.match(settings, /label: "Cycle layout on click"/)
  assert.match(settings, /popup\.workspacesSetting\("cycleLayoutOnClick", true\)/)
  assert.match(settings, /popup\.workspacesSetting\("cycleLayoutOnClick", true\) === "true"/)
  assert.match(settings, /popup\.setWorkspaces\(\{ cycleLayoutOnClick: !checked \}\)/)
  assert.match(settings, /switches tiling, scrolling, floating/)
})

test("upstream snapshots are present", () => {
  for (const name of ["upstream/Bar.qml", "upstream/BarModel.js", "upstream/bar-manifest.json"]) {
    assert.ok(fs.existsSync(path.join(root, name)), name)
  }
})

test("the all-in-one installer covers the suite, cats optional, wallcraft out", () => {
  const install = read("scripts/install-all.sh")
  // Core: the bar and the widgets that belong to it.
  for (const id of ["pizza.dirty.nyxiri", "pizza.dirty.nyxiri-menu", "pizza.dirty.nyxiri-workspaces", "pizza.dirty.clock", "pizza.dirty.weather", "pizza.dirty.arch-updates"]) {
    assert.match(install, new RegExp("add_plugin " + id.replace(".", "\\.") + " https://github.com/Deoxizn/"))
  }
  // Cats are opt-in behind --with-cats, never installed by default.
  assert.match(install, /--with-cats\) with_cats=1/)
  assert.match(install, /if \(\( with_cats \)\)/)
  assert.match(install, /add_plugin pizza\.dirty\.cpurr/)
  assert.match(install, /add_plugin pizza\.dirty\.bongocat/)
  // Wallcraft is independent (its settings work without the bar), so it
  // is not installed here and is not mentioned at all.
  assert.doesNotMatch(install, /add_plugin pizza\.dirty\.wallcraft/)
  assert.doesNotMatch(install, /wallcraft/i)
  // Non-interactive: --yes skips the gum prompts, so the script is safe
  // to run off GitHub with bash <(curl ...). Already-installed plugins
  // are skipped, never removed. Menu goes on the bar before workspaces.
  assert.match(install, /omarchy plugin add "\$url" --enable --yes/)
  assert.match(install, /already installed, skipping/)
  assert.match(install, /omarchy bar use pizza\.dirty\.nyxiri/)
  assert.ok(install.indexOf('put pizza.dirty.nyxiri-menu left') < install.indexOf('put pizza.dirty.nyxiri-workspaces left'))
  assert.match(install, /omarchy restart shell/)
})

test("the README lists the installer and every plugin in the suite", () => {
  const readme = read("README.md")
  // The all-in-one installer is the install method.
  assert.match(readme, /scripts\/install-all\.sh/)
  assert.match(readme, /--with-cats/)
  // Every plugin the suite now includes, linked to its repo by its short
  // app id, not described in its own section: the details live in that
  // plugin's own README.
  for (const [id, repo] of [
    ["pizza.dirty.nyxiri", "Deoxizn/nyxiri"],
    ["pizza.dirty.nyxiri-menu", "Deoxizn/nyxiri-menu"],
    ["pizza.dirty.nyxiri-workspaces", "Deoxizn/nyxiri-workspaces"],
    ["pizza.dirty.clock", "Deoxizn/omarchy-clock"],
    ["pizza.dirty.weather", "Deoxizn/omarchy-weather"],
    ["pizza.dirty.arch-updates", "Deoxizn/Arch-Updates"],
    ["pizza.dirty.cpurr", "Deoxizn/omarchy-cpurr"],
    ["pizza.dirty.bongocat", "Deoxizn/omarchy-bongocat"],
  ]) {
    const short = id.substring(id.lastIndexOf(".") + 1)
    assert.match(readme, new RegExp("\\[\\*\\*" + short.replace(".", "\\.") + "\\*\\*\\]\\(https://github.com/" + repo + "\\)"))
    assert.doesNotMatch(readme, new RegExp("\\[\\*\\*" + id.replace(".", "\\.") + "\\*\\*\\]\\(https://github.com/" + repo + "\\)"))
  }
  for (const heading of ["## Clock widget", "## Weather widget", "## Arch updates widget", "## Cat widgets"]) {
    assert.doesNotMatch(readme, new RegExp(heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  }
  // Wallcraft is called out as a separate, independent install.
  assert.match(readme, /pizza\.dirty\.wallcraft/)
  assert.match(readme, /not included/)
})

test("the installer migrates old devi./deoxizn. ids to pizza.dirty. without a reinstall", () => {
  const install = read("scripts/install-all.sh")
  // A migrate step runs before any install, renaming the plugin dirs in
  // place for every old id, both prefixes.
  assert.match(install, /migrate_ids/)
  for (const pair of [
    ["devi.nyxiri", "pizza.dirty.nyxiri"],
    ["devi.nyxiri-menu", "pizza.dirty.nyxiri-menu"],
    ["devi.nyxiri-workspaces", "pizza.dirty.nyxiri-workspaces"],
    ["deoxizn.clock", "pizza.dirty.clock"],
    ["devi.weather", "pizza.dirty.weather"],
    ["devi.arch-updates", "pizza.dirty.arch-updates"],
    ["deoxizn.cpurr", "pizza.dirty.cpurr"],
    ["deoxizn.bongocat", "pizza.dirty.bongocat"],
    // No wallcraft pair: wallcraft is independent and left out of the
    // installer entirely, so there is nothing to migrate here.
  ]) {
    assert.match(install, new RegExp("migrate_one " + pair[0].replace(/\./g, "\\.") + " " + pair[1].replace(/\./g, "\\.")))
  }
  // The clock's config and cache dirs move to the new id.
  assert.match(install, /\.config\/deoxizn\.clock/)
  assert.match(install, /\.config\/pizza\.dirty\.clock/)
  assert.match(install, /\.cache\/deoxizn\.clock/)
  assert.match(install, /\.cache\/pizza\.dirty\.clock/)
  // shell.json layout entries are re-keyed (string or object id), bar.id
  // is updated, and the bar's own bar.nyxiri key is untouched: it is not
  // id-derived, the host hands the whole bar object and the bar reads
  // the nyxiri key in it.
  assert.match(install, /shell\.json/)
  assert.match(install, /bar\.get\("id"\) in mapping/)
  assert.doesNotMatch(install, /bar\.nyxiri.*pizza\.dirty\.nyxiri/)
  // A rename never clobbers an existing new-id dir.
  assert.match(install, /both old and new ids installed, leaving/)
})

test("the manifest id is pizza.dirty.nyxiri", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.id, "pizza.dirty.nyxiri")
})

test("the installer fixes stale installed manifest ids and restarts before the bar use", () => {
  const install = read("scripts/install-all.sh")
  // The catalog reads manifest.id, not the directory name, so a renamed
  // dir alone still shows up under the old id. The installer updates the
  // id inside each installed manifest too.
  assert.match(install, /fix_manifest_id/)
  assert.match(install, /jq --arg id "\$new" '\.id = \$id'/)
  // The manifest path is assigned on its own line, not inside the same
  // `local` statement: bash expands every word in a `local` before
  // assigning any of them, so $new there would read the outer value.
  assert.match(install, /manifest="\$PLUGINS_DIR\/\$new\/manifest\.json"/)
  assert.doesNotMatch(install, /local old="\$1" new="\$2" manifest=/)
  // The shell only learns the new ids by rescanning, so the restart
  // happens before the bar use and the puts, not after.
  assert.ok(install.indexOf("omarchy restart shell") < install.indexOf("omarchy bar use pizza.dirty.nyxiri"))
  assert.doesNotMatch(install, /put pizza\.dirty\.bongocat center\n\nomarchy restart shell/)
})

test("the monitors tab shows the short app id, not the full plugin id", () => {
  const nyxiri = read("Nyxiri.js")
  // Display-only helper: full id stays what rules store and match.
  assert.match(nyxiri, /function shortWidgetId\(key\)/)
  assert.match(nyxiri, /shortWidgetId: shortWidgetId/)
  const settings = read("NyxiriSettingsWindow.qml")
  assert.match(settings, /text: Nyxiri\.shortWidgetId\(modelData\)/)
  // Selection and toggling still use the full layout key.
  assert.match(settings, /selected: popup\.ruleContains\(monitorCard\.monitorName, modelData\)/)
  assert.match(settings, /onClicked: popup\.toggleRule\(monitorCard\.monitorName, modelData\)/)
})

test("the Widgets tab is now the Plugins tab, with Active and Disabled sub-tabs", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // Tab renamed.
  assert.match(settings, /\{ value: "plugins", label: "Plugins" \}/)
  assert.doesNotMatch(settings, /\{ value: "widgets", label: "Widgets" \}/)
  assert.match(settings, /visible: popup\.tab === "plugins"/)
  assert.doesNotMatch(settings, /popup\.tab === "widgets"/)
  // The tab validates the new value.
  assert.match(read("Bar.qml"), /\["appearance", "monitors", "plugins", "system"\]/)
  // Active / Disabled are sub-tabs now, not stacked groups: each group is
  // its own model from the sorted list, and only the picked one shows.
  assert.match(settings, /activePluginList: popup\.sortedPlugins\.filter\(function\(p\) \{ return p\.enabled === true \}\)/)
  assert.match(settings, /disabledPluginList: popup\.sortedPlugins\.filter\(function\(p\) \{ return p\.enabled !== true \}\)/)
  assert.match(settings, /property string pluginGroup: "active"/)
  assert.match(settings, /selected: popup\.pluginGroup === "active"/)
  assert.match(settings, /selected: popup\.pluginGroup === "disabled"/)
  assert.match(settings, /onClicked: popup\.pluginGroup = "active"/)
  assert.match(settings, /onClicked: popup\.pluginGroup = "disabled"/)
  // One Repeater, model switches on the sub-tab. A `visible` gate on a
  // Repeater does not hide its delegates (they belong to the parent
  // Column), which is why Disabled showed the wrong rows.
  assert.match(settings, /model: popup\.pluginGroup === "active" \? popup\.activePluginList : popup\.disabledPluginList/)
  assert.doesNotMatch(settings, /visible: popup\.pluginGroup === "active"/)
  assert.doesNotMatch(settings, /visible: popup\.pluginGroup === "disabled"/)
  assert.doesNotMatch(settings, /text: "ACTIVE"/)
  assert.doesNotMatch(settings, /text: "DISABLED"/)
  // One shared row component, not two copies of the delegate.
  assert.match(settings, /component PluginRow: Column/)
  assert.match(settings, /delegate: PluginRow \{\}/)
  // The count line sits above the sub-tabs, with the disabled total.
  assert.match(settings, /plugins\.length \+ " plugins · " \+ popup\.activePlugins \+ " active · " \+ \(popup\.plugins\.length - popup\.activePlugins\) \+ " disabled"/)
})

test("the settings window hides tabs and sections for plugins that are not installed", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // hasPlugin: installed and enabled, matched by id or pluginId through
  // baseWidgetId (registry keys can carry a "#n" suffix). A disabled
  // plugin counts as absent: its widget is not on the bar, so its
  // settings are dead.
  assert.match(settings, /function hasPlugin\(id\)/)
  assert.match(settings, /Nyxiri\.baseWidgetId\(p\.id\) === wanted/)
  assert.match(settings, /Nyxiri\.baseWidgetId\(p\.pluginId\) === wanted/)
  assert.match(settings, /p\.enabled !== true/)
  // The probe is only evidence once it has completed successfully. While
  // it is loading, errored, or came back empty, nothing is hidden, so the
  // Workspaces tab never flashes away on first open.
  assert.match(settings, /readonly property bool probeSettled: !popup\.pluginsLoading && popup\.pluginProbeError === "" && popup\.plugins\.length > 0/)
  assert.match(settings, /readonly property bool showWorkspacesTab: !probeSettled \|\| hasPlugin\("pizza\.dirty\.nyxiri-workspaces"\)/)
  assert.match(settings, /readonly property bool showMenuTrigger: !probeSettled \|\| hasPlugin\("pizza\.dirty\.nyxiri-menu"\)/)
  // The sidebar model is conditional: Workspaces only when its plugin is
  // there. Appearance, Monitors, and Plugins are always present.
  assert.match(settings, /readonly property var sidebarTabs:/)
  assert.match(settings, /model: popup\.sidebarTabs/)
  assert.match(settings, /if \(showWorkspacesTab\) tabs\.push\(\{ value: "workspaces", label: "Workspaces" \}\)/)
  // The Menu Trigger section is one wrapped unit, hidden when the menu
  // plugin is not installed (and the probe has settled) or its trigger
  // is not on the bar, with no gap and no leftover header.
  assert.match(settings, /visible: popup\.showMenuTrigger && popup\.bar\.nyxiriMenuAvailable/)
  assert.match(settings, /text: "MENU TRIGGER"/)
  // A tab whose plugin is not installed (or got disabled while the window
  // is open) falls back to Appearance, checked both when the tab changes
  // and when the probe settles.
  assert.match(settings, /function ensureVisibleTab\(\)/)
  assert.match(settings, /if \(tab === "workspaces" && probeSettled && !hasPlugin\("pizza\.dirty\.nyxiri-workspaces"\)\) tab = "appearance"/)
  assert.match(settings, /ensureVisibleTab\(\)/)
  assert.match(settings, /onProbeSettledChanged: ensureVisibleTab\(\)/)
})

test("the settings window has a System tab for the Arch Updates widget", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  const bar = read("Bar.qml")
  // Gating mirrors Workspaces: shown while the probe has not settled, and
  // once settled only when pizza.dirty.arch-updates is installed and enabled.
  assert.match(settings, /readonly property bool showSystemTab: !probeSettled \|\| hasPlugin\("pizza\.dirty\.arch-updates"\)/)
  // Sidebar order: appearance, monitors, workspaces-if-shown,
  // system-if-shown, plugins.
  assert.match(settings, /if \(showSystemTab\) tabs\.push\(\{ value: "system", label: "System Updater" \}\)/)
  assert.ok(
    settings.indexOf('if (showWorkspacesTab) tabs.push({ value: "workspaces", label: "Workspaces" })')
      < settings.indexOf('if (showSystemTab) tabs.push({ value: "system", label: "System Updater" })')
      && settings.indexOf('if (showSystemTab) tabs.push({ value: "system", label: "System Updater" })')
      < settings.indexOf('tabs.push({ value: "plugins", label: "Plugins" })'),
    "system sits between workspaces and plugins in sidebarTabs"
  )
  // A hidden System tab falls back to Appearance, like Workspaces.
  assert.match(settings, /function ensureVisibleTab\(\)/)
  assert.match(settings, /if \(tab === "system" && probeSettled && !hasPlugin\("pizza\.dirty\.arch-updates"\)\) tab = "appearance"/)
  // Helpers mirror workspacesSetting/setWorkspaces, backed by the bar.
  assert.match(settings, /function systemSetting\(name, fallback\)/)
  assert.match(settings, /function setSystem\(patch\)/)
  assert.match(settings, /popup\.bar\.nyxiriSystemSetting\(name, fallback\)/)
  assert.match(settings, /popup\.bar\.writeSystemSettings\(patch\)/)
  // The tab itself, placed between Workspaces and Monitors.
  assert.match(settings, /visible: popup\.tab === "system"\n\s+width: parent\.width\n\s+spacing: Style\.space\(16\)/)
  assert.ok(
    settings.indexOf('visible: popup.tab === "workspaces"')
      < settings.indexOf('visible: popup.tab === "system"')
      && settings.indexOf('visible: popup.tab === "system"')
      < settings.indexOf('visible: popup.tab === "monitors"'),
    "system tab column sits between workspaces and monitors"
  )
  assert.match(settings, /text: "SYSTEM UPDATER"/)
  // Refresh interval: 300-7200s, step 300, default 1800, shown in minutes.
  assert.match(settings, /label: "Refresh interval"/)
  assert.match(settings, /popup\.systemSetting\("refreshIntervalSec", 1800\)/)
  assert.match(settings, /minimum: 300/)
  assert.match(settings, /maximum: 7200/)
  assert.match(settings, /step: 300/)
  assert.match(settings, /\+ " min"/)
  assert.match(settings, /popup\.setSystem\(\{ refreshIntervalSec: value \}\)/)
  // Automatic checks and Always show, both default true, string-"true"
  // coerced like the Workspaces tab's Cycle layout toggle.
  assert.match(settings, /label: "Automatic checks"/)
  assert.match(settings, /popup\.systemSetting\("autoRefresh", true\) === true \|\| popup\.systemSetting\("autoRefresh", true\) === "true"/)
  assert.match(settings, /popup\.setSystem\(\{ autoRefresh: !checked \}\)/)
  assert.match(settings, /Check on the interval and once after startup/)
  assert.match(settings, /Checks run only when the panel is opened/)
  assert.match(settings, /label: "Always show"/)
  assert.match(settings, /popup\.systemSetting\("alwaysShow", true\) === true \|\| popup\.systemSetting\("alwaysShow", true\) === "true"/)
  assert.match(settings, /popup\.setSystem\(\{ alwaysShow: !checked \}\)/)
  assert.match(settings, /Keep the icon visible even when no updates are available/)
  assert.match(settings, /Hide the icon when everything is up to date/)
  // Four source toggles, all default true, all gated on the widget being
  // on the bar.
  for (const [key, label] of [
    ["checkAur", "AUR"],
    ["checkFlatpak", "Flatpak"],
    ["checkMise", "mise"],
    ["checkPlugins", "Plugins & themes"],
  ]) {
    assert.match(settings, new RegExp("label: \"" + label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\""))
    assert.match(settings, new RegExp("popup\\.systemSetting\\(\"" + key + "\", true\\) === true \\|\\| popup\\.systemSetting\\(\"" + key + "\", true\\) === \"true\""))
    assert.match(settings, new RegExp("popup\\.setSystem\\(\\{ " + key + ": !checked \\}\\)"))
  }
  assert.match(settings, /AUR updates from your helper \(yay or paru\)/)
  assert.match(settings, /Flatpak updates/)
  assert.match(settings, /mise dev tools/)
  assert.match(settings, /Git-managed shell plugins and themes/)
  // Not on the bar: the same shape of message as the Workspaces tab.
  assert.match(settings, /text: "Add the Arch Updates widget to the bar to change these\."/)
  assert.match(settings, /visible: !popup\.bar\.nyxiriSystemAvailable/)
  // Bar accessors mirror the workspaces/weather trio, and IPC can open
  // the tab. Workspaces stays out of the validation list (pre-existing
  // quirk, out of scope).
  assert.match(bar, /function nyxiriSystemEntryKey\(\)/)
  assert.match(bar, /Nyxiri\.baseWidgetId\(key\) === "pizza\.dirty\.arch-updates"/)
  assert.match(bar, /function nyxiriSystemSetting\(name, fallback\)/)
  assert.match(bar, /nyxiriSystemAvailable: nyxiriSystemEntryKey\(\) !== ""/)
  assert.match(bar, /function writeSystemSettings\(patch\)/)
  assert.match(bar, /shell\.updateEntryInline\("pizza\.dirty\.arch-updates", next\)/)
  assert.match(bar, /\["appearance", "monitors", "plugins", "system"\]/)
  assert.doesNotMatch(bar, /"workspaces"\]/)
})

test("the settings window has a sidebar, a bat header, and a masked body", () => {
  const settings = read("NyxiriSettingsWindow.qml")
  // Sidebar sections, one per tab.
  assert.match(settings, /id: sidebar/)
  assert.match(settings, /\{ value: "appearance", label: "Appearance" \}/)
  assert.match(settings, /\{ value: "workspaces", label: "Workspaces" \}/)
  assert.match(settings, /\{ value: "plugins", label: "Plugins" \}/)
  // Bat header (nf-md-bat, U+F0B5F) and a close that does not shadow Window.close.
  assert.match(settings, /text: "\\udb82\\udf5f"/)
  assert.match(settings, /function closeSettings\(\)/)
  assert.doesNotMatch(settings, /onActivated: popup\.close\(\)/)
  // Input goes only to the window body.
  assert.match(settings, /mask: Region \{ item: windowBody \}/)
  // The old card file is gone.
  assert.throws(() => read("NyxiriSettings.qml"), /ENOENT/)
})

test("the bar opens settings from the bat, not from right-click or a card", () => {
  const bar = read("Bar.qml")
  assert.match(bar, /NyxiriSettingsWindow \{/)
  assert.match(bar, /component NyxiriBatButton: Item/)
  assert.match(bar, /text: "\\udb82\\udf5f"/)
  assert.match(bar, /onClicked: root\.openNyxiriSettings\(screenName\)/)
  assert.doesNotMatch(bar, /NyxiriSettings \{/)
  assert.doesNotMatch(bar, /nyxiri-right-click/)
  assert.doesNotMatch(bar, /nyxiri-settings-card/)
  assert.doesNotMatch(bar, /acceptedButtons: Qt\.RightButton/)
})

test("the bat button fits inside the bar thickness and its pill follows the right section", () => {
  const bar = read("Bar.qml")
  // The bar is 26 tall horizontal (28 vertical); the old hardcoded 28
  // drew a circle outlining outside the bar. The button's short side is
  // the bar's full thickness on its surface: centered, so it fills the
  // bar exactly and never exceeds it, and BorderSurface draws its border
  // inside the rect. The glyph is the full button size on its short side.
  assert.match(bar, /property int thickness: root\.barSize/)
  assert.match(bar, /thickness: barWindow\.thickness/)
  assert.match(bar, /readonly property int batSize: Math\.max\(Style\.space\(16\), thickness\)/)
  assert.match(bar, /font\.pixelSize: batSize/)
  assert.doesNotMatch(bar, /batSize \* 0\.85/)
  assert.doesNotMatch(bar, /implicitWidth: Style\.space\(28\)/)
  assert.doesNotMatch(bar, /implicitHeight: Style\.space\(28\)/)
  // Foreground, not accent: the accent made the bat harder to see.
  // Pinned to the bat glyph itself, not just any foreground in the file.
  assert.match(bar, /text: "\\udb82\\udf5f"\n\s+color: root\.barForeground/)
  // The bat is inset from the bar's edge, not flush against it.
  assert.match(bar, /anchors\.rightMargin: Style\.space\(16\)/)
  assert.match(bar, /anchors\.bottomMargin: Style\.space\(16\)/)
  // The bat sits last in the right section, so its own pill follows the
  // right section's mode, not the left's: with left mini and right island
  // the old check drew the pill twice (own pill + island pill).
  assert.match(bar, /nyxiriSectionMode\("right"\) !== "island"/)
  assert.doesNotMatch(bar, /nyxiriSectionMode\("left"\) !== "island"/)
  // The bat's ink is wider than its advance (0.938em on a 0.6em advance),
  // so the wing overhangs the Text box and the button is longer than the
  // bar is thick to hold the wingspan; the Text is shifted to centre the
  // ink (left by the overhang, down by the visual-mass offset), and on a
  // vertical bar the glyph rotates 90 degrees so the wingspan runs along
  // the bar's length, with the offsets rotated with it.
  assert.match(bar, /readonly property int batLength: Math\.round\(batSize \* 1\.35\)/)
  assert.match(bar, /implicitWidth: root\.vertical \? batSize : batLength/)
  assert.match(bar, /implicitHeight: root\.vertical \? batLength : batSize/)
  assert.match(bar, /readonly property real inkShiftX: batSize \* 0\.17/)
  assert.match(bar, /readonly property real inkShiftY: batSize \* 0\.05/)
  assert.match(bar, /anchors\.horizontalCenterOffset: root\.vertical \? -inkShiftY : -inkShiftX/)
  assert.match(bar, /anchors\.verticalCenterOffset: root\.vertical \? -inkShiftX : inkShiftY/)
  assert.match(bar, /rotation: root\.vertical \? 90 : 0/)
})
