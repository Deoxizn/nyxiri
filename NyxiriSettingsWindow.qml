import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Nyxiri.js" as Nyxiri

// The standalone Nyxiri settings window. A floating layer-shell window with
// a sidebar of sections on the left and the section's options on the right,
// opened from the bat button on the bar or over IPC. It replaces the old
// in-bar settings card (a KeyboardPanel) and the Omarchy menu submenu.
// Every control writes a partial config through bar.writeNyxiri(), so
// persistence and reloading stay in one place.
PanelWindow {
  id: popup

  // `bar` is passed from the bar (KeyboardPanel supplied it; PanelWindow
  // does not). screenName identifies the surface the window was opened for.
  property var bar: null
  property string screenName: ""
  property string initialTab: "bar"

  // A real layer-shell surface, not a popup: it takes keyboard focus
  // natively, so the wordmark and ranges fields just work. Floating: it
  // reserves no bar space, and the mask limits input to the window body
  // so clicks outside it pass through to the windows below.
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "pizza.dirty.nyxiri-settings"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Close is named closeSettings, not close: PanelWindow is a QQuickWindow
  // and already has a close() method, which this must not shadow.
  function closeSettings() {
    if (bar) bar.closeNyxiriSettings()
  }

  readonly property var pill: bar.nyxiri.pill
  readonly property var palette: bar.nyxiriPalette
  readonly property var screenList: Quickshell.screens || []

  // Widget ids currently laid out, deduplicated from BarModel's `id#serial`
  // keys. This is what a per-monitor rule can name.
  readonly property var laidOutIds: {
    var seen = ({})
    var out = []
    var keys = bar.layoutWidgets && bar.layoutWidgets.keys ? bar.layoutWidgets.keys : []
    for (var i = 0; i < keys.length; i++) {
      var id = Nyxiri.baseWidgetId(keys[i])
      if (!id || seen[id]) continue
      seen[id] = true
      out.push(id)
    }
    return out
  }

  readonly property var colorOptions: {
    var roles = Nyxiri.paletteRoles(palette)
    var out = []
    for (var i = 0; i < roles.length; i++) out.push({ value: roles[i], label: roles[i] })
    out.push({ value: "custom", label: "Custom hex…" })
    return out
  }

  property string tab: "bar"
  property string pluginGroup: "active"
  property var plugins: []
  property bool pluginsLoading: false
  property string lastAction: ""
  property string pluginProbeError: ""

  // Whether the plugin probe has completed successfully: only then is the
  // plugins list a reliable picture of what is installed. While it is still
  // loading, or it errored, or it came back empty, the list is not evidence
  // that a plugin is absent, so nothing is hidden.
  readonly property bool probeSettled: !popup.pluginsLoading && popup.pluginProbeError === "" && popup.plugins.length > 0

  // Whether a plugin is installed and enabled, by its id. The probe list
  // carries the plugin id (and pluginId on registry-fallback rows); the
  // registry keys can carry a "#n" suffix, so both are matched through
  // baseWidgetId. A disabled plugin counts as absent: its widget is not on
  // the bar, so its settings are dead, and disabling it hides its tab.
  function hasPlugin(id) {
    var wanted = String(id || "")
    if (!wanted) return false
    for (var i = 0; i < popup.plugins.length; i++) {
      var p = popup.plugins[i]
      if (!p || p.enabled !== true) continue
      if (Nyxiri.baseWidgetId(p.id) === wanted || Nyxiri.baseWidgetId(p.pluginId) === wanted) return true
    }
    return false
  }

  // Tabs and sections for plugins that may not be installed. While the
  // probe has not settled, everything shows (the current behavior), so a
  // tab never flashes away on first open even when its plugin is
  // installed. Once settled, a missing plugin's tab goes.
  readonly property bool showWorkspacesTab: !probeSettled || hasPlugin("pizza.dirty.nyxiri-workspaces")
  readonly property bool showMenuTab: !probeSettled || hasPlugin("pizza.dirty.nyxiri-menu")
  readonly property bool showWeatherTab: !probeSettled || hasPlugin("pizza.dirty.weather")
  readonly property bool showSystemTab: !probeSettled || hasPlugin("pizza.dirty.arch-updates")
  readonly property bool showCalendarTab: !probeSettled || hasPlugin("pizza.dirty.clock")

  // The sidebar's sections, A-Z by label, with a plugin's tab only
  // when it is installed (and the probe has settled). Bar, Monitors,
  // and Plugins are the bar itself and the plugin manager, so they
  // are always present.
  readonly property var sidebarTabs: {
    var tabs = [
      { value: "bar", label: "Bar" }
    ]
    if (showCalendarTab) tabs.push({ value: "calendar", label: "Calendar" })
    if (showMenuTab) tabs.push({ value: "menu", label: "Menu" })
    tabs.push({ value: "monitors", label: "Monitors" })
    tabs.push({ value: "plugins", label: "Plugins" })
    if (showSystemTab) tabs.push({ value: "system", label: "System Updater" })
    if (showWeatherTab) tabs.push({ value: "weather", label: "Weather" })
    if (showWorkspacesTab) tabs.push({ value: "workspaces", label: "Workspaces" })
    return tabs
  }

  // If the current tab is one whose plugin is not installed (or got
  // disabled while the window is open), fall back to Bar so the window
  // never shows a hidden tab's content with no way back. "appearance"
  // is the old Bar tab id, kept as an alias that lands on Bar.
  function ensureVisibleTab() {
    if (tab === "appearance") tab = "bar"
    if (tab === "workspaces" && probeSettled && !hasPlugin("pizza.dirty.nyxiri-workspaces")) tab = "bar"
    if (tab === "menu" && probeSettled && !hasPlugin("pizza.dirty.nyxiri-menu")) tab = "bar"
    if (tab === "weather" && probeSettled && !hasPlugin("pizza.dirty.weather")) tab = "bar"
    if (tab === "system" && probeSettled && !hasPlugin("pizza.dirty.arch-updates")) tab = "bar"
    if (tab === "calendar" && probeSettled && !hasPlugin("pizza.dirty.clock")) tab = "bar"
  }

  // Active plugins first, then disabled, each group alphabetical by name.
  // The probe returns install order, which buries the enabled ones at the
  // bottom of a long list. Re-sorted on every probe refresh (every toggle
  // re-runs the probe, so a flipped row moves to its new group).
  readonly property var sortedPlugins: {
    var list = popup.plugins.slice()
    list.sort(function(a, b) {
      var ae = a.enabled === true ? 0 : 1
      var be = b.enabled === true ? 0 : 1
      if (ae !== be) return ae - be
      var an = String(a.name || a.id || "").toLowerCase()
      var bn = String(b.name || b.id || "").toLowerCase()
      return an < bn ? -1 : an > bn ? 1 : 0
    })
    return list
  }

  readonly property int activePlugins: {
    var n = 0
    for (var i = 0; i < popup.plugins.length; i++) {
      if (popup.plugins[i].enabled === true) n++
    }
    return n
  }

  // The Plugins tab groups the sorted list under Active / Disabled
  // headings, so each group is its own model.
  readonly property var activePluginList: popup.sortedPlugins.filter(function(p) { return p.enabled === true })
  readonly property var disabledPluginList: popup.sortedPlugins.filter(function(p) { return p.enabled !== true })

  // ---------------------------------------------------------------- writes

  function setSection(section, mode) {
    var sections = {}
    sections[section] = mode
    bar.writeNyxiri({ sections: sections })
  }

  function setPill(patch) {
    bar.writeNyxiri({ pill: patch })
  }

  function setMonitor(name, patch) {
    var monitors = {}
    monitors[String(name)] = patch
    bar.writeNyxiri({ monitors: monitors })
  }

  function monitorRule(name) {
    return bar.nyxiriMonitor(String(name))
  }

  function ruleContains(name, id) {
    return monitorRule(name).widgets.list.indexOf(id) !== -1
  }

  function toggleRule(name, id) {
    var rule = monitorRule(name)
    var list = rule.widgets.list.slice()
    var index = list.indexOf(id)
    if (index === -1) list.push(id)
    else list.splice(index, 1)
    setMonitor(name, { widgets: { list: list } })
  }

  function menuSetting(name, fallback) {
    return popup.bar.nyxiriMenuSetting(name, fallback)
  }

  function setMenu(patch) {
    popup.bar.writeMenuSettings(patch)
  }

  function workspacesSetting(name, fallback) {
    return popup.bar.nyxiriWorkspacesSetting(name, fallback)
  }

  function setWorkspaces(patch) {
    popup.bar.writeWorkspacesSettings(patch)
  }

  function weatherSetting(name, fallback) {
    return popup.bar.nyxiriWeatherSetting(name, fallback)
  }

  function setWeather(patch) {
    popup.bar.writeWeatherSettings(patch)
  }

  function systemSetting(name, fallback) {
    return popup.bar.nyxiriSystemSetting(name, fallback)
  }

  function setSystem(patch) {
    popup.bar.writeSystemSettings(patch)
  }

  // ---------------------------------------------------------------- calendar

  // The clock plugin's calendars live in a plain file, not a widget
  // setting: ~/.config/pizza.dirty.clock/calendars.json, a list of
  // {account, name, url|path, color, enabled}. A remote feed has `url`
  // (an iCal/.ics link, https:// or webcal:// — the fetcher refuses
  // plain http); a local file has `path` (a .ics file, ~ expands).
  // The clock widget watches this file and refetches when it changes,
  // so writing it is the whole refresh mechanism. The file is 0600:
  // the links are secret, so the tab masks them like a password field
  // and only reveals one when its eye toggle is tapped.
  readonly property string calendarsPath: (Quickshell.env("HOME") || "") + "/.config/pizza.dirty.clock/calendars.json"
  readonly property string calendarsScript: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/pizza.dirty.nyxiri/scripts/write-calendars.py"
  property var calendars: []
  property var calendarsBeforeSave: []
  property string calendarsStatus: ""
  property string calendarsWriteOutput: ""
  property bool newCalShowLink: false

  function loadCalendars() {
    try {
      var parsed = JSON.parse(String(calendarsFile.text() || "[]"))
      popup.calendars = Array.isArray(parsed) ? parsed : []
    } catch (e) {
      popup.calendars = []
    }
  }

  // The list is one argv to the helper (never a shell string, so secret
  // URLs pass through untouched). The helper validates, writes atomically
  // at 0600, and prints {"status": "ok"} or {"status": "error", ...};
  // its errors never echo a value back, so a link cannot leak into the
  // status line. The list is updated optimistically and restored if the
  // write fails, so the tab never shows a calendar that is not on disk.
  function saveCalendars(list) {
    popup.calendarsBeforeSave = popup.calendars
    popup.calendars = list
    popup.calendarsStatus = ""
    calendarsWrite.command = ["python3", popup.calendarsScript, "--file", popup.calendarsPath, JSON.stringify(list)]
    calendarsWrite.running = true
  }

  function addCalendar() {
    var name = String(newNameField.text || "").trim()
    var link = String(newLinkField.text || "").trim()
    var account = String(newAccountField.text || "").trim() || "Personal"
    if (name === "") { popup.calendarsStatus = "Give the calendar a name."; return }
    if (link === "") { popup.calendarsStatus = "Paste a link or a local file path."; return }
    var entry = { account: account, name: name, color: "#4285f4", enabled: true }
    if (link.indexOf("http://") === 0) {
      popup.calendarsStatus = "Use https:// — the clock refuses plain http links."
      return
    }
    if (link.indexOf("https://") === 0 || link.indexOf("webcal://") === 0) entry.url = link
    else entry.path = link
    var list = popup.calendars.slice()
    list.push(entry)
    popup.saveCalendars(list)
    newNameField.text = ""
    newAccountField.text = ""
    newLinkField.text = ""
    popup.newCalShowLink = false
  }

  function removeCalendar(index) {
    var list = popup.calendars.slice()
    if (index < 0 || index >= list.length) return
    list.splice(index, 1)
    popup.saveCalendars(list)
  }

  function setCalendarEnabled(index, enabled) {
    var list = popup.calendars.slice()
    if (index < 0 || index >= list.length) return
    var entry = {}
    for (var k in list[index]) entry[k] = list[index][k]
    entry.enabled = enabled
    list[index] = entry
    popup.saveCalendars(list)
  }

  // ---------------------------------------------------------------- classic

  // Classic workspaces mode, read from the workspaces plugin's bin/mode.
  // The mode is Hyprland state, not a widget setting, so the card asks the
  // script instead of reading the layout entry. The script runs through
  // bash: pushes land mode 644, so it never runs directly.
  readonly property string classicModeScript: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/pizza.dirty.nyxiri-workspaces/bin/mode"
  property bool classicMode: false
  property bool classicModeKnown: false
  property bool classicSwitching: false

  function refreshClassicMode() {
    if (modeStatus.running) return
    modeStatus.command = ["bash", popup.classicModeScript, "status"]
    modeStatus.running = true
  }

  function switchClassic(classic) {
    if (modeSwitch.running || popup.classicSwitching) return
    popup.classicSwitching = true
    modeSwitch.command = ["bash", popup.classicModeScript, classic ? "classic" : "4.5"]
    modeSwitch.running = true
  }

  // ---------------------------------------------------------------- plugins

  function parsePlugins(text) {
    pluginsLoading = false
    probeWatchdog.running = false
    try {
      var parsed = JSON.parse(String(text || "[]"))
      plugins = Array.isArray(parsed) ? parsed : []
      if (plugins.length === 0) {
        // The probe came back empty (or never found `omarchy`): fall back to
        // the widgets the bar itself has registered, so the tab is never a
        // blank wall when the bar plainly has widgets on it.
        var fallback = pluginsFromRegistry()
        if (fallback.length > 0) {
          plugins = fallback
          lastAction = "Plugin probe came back empty — showing widgets from the bar"
        } else {
          lastAction = "Plugin list came back empty"
        }
      }
    } catch (error) {
      plugins = []
      lastAction = "Could not read the plugin list"
    }
  }

  // Widgets the bar has registered, as plugin-shaped rows. The registry only
  // holds enabled widgets, so enabled/canDisable are fixed; the toggle uses
  // pluginId (the plugin) while Add to bar and inBar use id (the widget).
  function pluginsFromRegistry() {
    var out = []
    var widgets = bar && bar.barWidgetRegistry && bar.barWidgetRegistry.widgets
      ? bar.barWidgetRegistry.widgets : null
    if (!widgets) return out
    for (var key in widgets) {
      var entry = widgets[key]
      if (!entry) continue
      var meta = entry.metadata || {}
      out.push({
        id: String(key),
        pluginId: String(meta.pluginId || key),
        name: String(meta.displayName || key),
        kinds: ["bar-widget"],
        enabled: true,
        canDisable: true,
        firstParty: meta.firstParty === true
      })
    }
    out.sort(function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
    return out
  }

  function useRegistryPlugins(note) {
    var fallback = pluginsFromRegistry()
    if (fallback.length > 0) {
      plugins = fallback
      lastAction = note
      return true
    }
    return false
  }

  function refreshPlugins() {
    pluginsLoading = true
    pluginProbe.running = true
    probeWatchdog.restart()
  }

  function runPluginAction(args, note) {
    lastAction = note
    pluginAction.command = ["omarchy"].concat(args)
    pluginAction.running = true
  }

  function kindList(plugin) {
    return plugin && Array.isArray(plugin.kinds) ? plugin.kinds : []
  }

  function isBarWidget(plugin) {
    return kindList(plugin).indexOf("bar-widget") !== -1 || kindList(plugin).indexOf("menu") !== -1
  }

  function isBarOption(plugin) {
    return kindList(plugin).indexOf("bar") !== -1
  }

  function inBar(plugin) {
    return plugin && laidOutIds.indexOf(String(plugin.id || "")) !== -1
  }

  function setEnabled(plugin, enabled) {
    if (!plugin || plugin.canDisable === false) return
    var pid = String(plugin.pluginId || plugin.id || "")
    if (!pid) return
    runPluginAction(enabled ? ["plugin", "enable", pid] : ["plugin", "disable", pid],
      (enabled ? "Enabled " : "Disabled ") + pid)
  }

  function addToBar(plugin) {
    if (!plugin || !plugin.id) return
    runPluginAction(["bar", "put", plugin.id], "Added " + plugin.id + " to the bar")
  }

  function useAsBar(plugin) {
    if (!plugin || !plugin.id) return
    runPluginAction(["bar", "use", plugin.id], "Now using " + plugin.id + " as the bar")
  }

  function resetBar() {
    runPluginAction(["bar", "reset"], "Returned to the built-in bar")
  }

  // ------------------------------------------------------------------- ui

  onVisibleChanged: {
    if (visible) {
      tab = initialTab
      refreshPlugins()
      refreshClassicMode()
      calendarsFile.reload()
    }
  }
  onInitialTabChanged: if (visible) tab = initialTab
  onTabChanged: {
    if (tab === "plugins" && plugins.length === 0 && !pluginsLoading) refreshPlugins()
    ensureVisibleTab()
    if (tab === "workspaces") refreshClassicMode()
    if (tab === "calendar") calendarsFile.reload()
  }
  // When the probe settles, a tab whose plugin turned out not to be
  // installed (or got disabled while the window is open) is hidden, so
  // move off it. ensureVisibleTab is a no-op while the probe has not
  // settled or the plugin is there.
  onProbeSettledChanged: ensureVisibleTab()

  // This was a PopupCard (xdg-popup) and its text fields never took input:
  // xdg-popups only receive keys after a click routes focus through their
  // parent surface, so the wordmark and image fields showed a blinking
  // cursor and swallowed every key, and no amount of forceActiveFocus
  // fixed it. A PanelWindow is a real layer-shell surface with OnDemand
  // keyboard focus, so the fields take input natively. Escape is scoped
  // to the window while it is visible. The close button remains the
  // pointer path. Shortcut and Process are direct children of the window:
  // PanelWindow's default property is data, so non-visual children are
  // fine here.

  // Section headers: a full window, not a popup card, so they read as
  // headers, not fine print, with room under them before the controls.
  // Section headers are title size with room under them, and a full gap
  // above them too: the space between one section's content and the next
  // header is the tab Column spacing plus this topPadding, so sections
  // read as separate blocks instead of one continuous list.
  component SectionLabel: Text {
    color: Qt.darker(popup.bar.foreground, 1.35)
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    font.letterSpacing: 0.4
    textFormat: Text.PlainText
    topPadding: Style.space(16)
    bottomPadding: Style.spacing.md
  }

  // Sub-headers under a section (Mode, Style, Icon mode, ...): one step
  // smaller than a section header, still bigger than the old caption
  // labels, with room under them too.
  component SubLabel: Text {
    color: Qt.darker(popup.bar.foreground, 1.4)
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    textFormat: Text.PlainText
    bottomPadding: Style.spacing.sm
  }

  component BodyText: Text {
    color: popup.bar.foreground
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
  }

  // A slider with its label on its own line above it. The old card crammed
  // label + slider + value onto one row because it was small; this is a
  // full window, so the label gets its own line and the slider gets the
  // whole width. `value` is bound to the setting, `released` writes it back.
  component SliderRow: Column {
    id: sliderRow
    required property string label
    required property real value
    required property real minimum
    required property real maximum
    required property real step
    property bool integer: false
    required property string valueText
    signal released(real value)

    // The instantiating tab column is full width, so this is too. (body
    // is not in scope here: the component is declared on the window, and
    // body lives inside the window body below it.)
    width: parent.width
    spacing: Style.spacing.xxs

    BodyText {
      text: sliderRow.label
      width: parent.width
    }

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      PanelSlider {
        width: parent.width - sliderValue.width - parent.spacing
        bar: popup.bar
        value: sliderRow.value
        minimum: sliderRow.minimum
        maximum: sliderRow.maximum
        step: sliderRow.step
        integer: sliderRow.integer
        onReleased: function(value) { sliderRow.released(value) }
      }

      BodyText {
        id: sliderValue
        text: sliderRow.valueText
        width: Style.space(40)
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  // Text input in a popup does not take keyboard focus on click by itself:
  // the click selects text but no cursor appears and keys go nowhere, which
  // is exactly what the wordmark field did. Stock panels force focus
  // explicitly (weather Panel startEditingLocation, polkit passwordInput),
  // and they do it deferred: forcing focus synchronously during the press
  // can run before the click has activated the popup window, so it lands
  // nowhere. This defers it the same way, and lets the press through so
  // cursor placement and selection keep working.
  //
  // Two more ways a typed value got lost, which is why the wordmark and
  // image fields were hit or miss:
  //   1. `text:` was bound straight to the saved setting, and the binding
  //      re-evaluates on ANY layout write (a toggle, a slider, another
  //      field's save), snapping in-progress typing back to the last
  //      saved value. So the field owns its text now and only syncs from
  //      `settingText` when the saved value actually changes.
  //   2. `onEditingFinished` only fires on Enter or a clean focus loss;
  //      closing the card (Escape, click-away) destroyed the edit. The
  //      field commits on its own now: 400ms after the last keystroke,
  //      and immediately on Enter or focus loss, so typing sticks
  //      however the card is left. The card is instantiated once per
  //      bar surface and only hidden on close, so the timer survives it.
  component FocusField: TextField {
    signal commit(string value)

    // The saved value, bound by the usage. The field's text is only
    // overwritten from it when it actually changes, so typing is never
    // clobbered by an unrelated layout write.
    property string settingText: ""
    onSettingTextChanged: {
      if (settingText !== text) text = settingText
      lastCommitted = settingText
    }

    property string lastCommitted: ""

    Component.onCompleted: lastCommitted = text

    function commitNow() {
      commitTimer.stop()
      if (text === lastCommitted) return
      lastCommitted = text
      commit(text)
    }

    Timer {
      id: commitTimer
      interval: 400
      onTriggered: commitNow()
    }

    onTextChanged: commitTimer.restart()
    onEditingFinished: commitNow()

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      onPressed: function(mouse) {
        mouse.accepted = false
        var field = parent
        Qt.callLater(function() { field.forceActiveFocus() })
      }
    }
  }

  Shortcut {
    sequence: "Escape"
    enabled: popup.visible
    onActivated: popup.closeSettings()
  }

  Process {
    id: pluginProbe
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.parsePlugins(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.pluginProbeError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      // Always clear loading: a stuck "Loading…" with an empty list was
      // indistinguishable from a failed probe.
      popup.pluginsLoading = false
      probeWatchdog.running = false
      if (exitCode !== 0) {
        var note = popup.pluginProbeError || "omarchy plugin list failed"
        if (popup.plugins.length === 0
          && !popup.useRegistryPlugins(note + " — showing widgets from the bar")) {
          popup.lastAction = note
        }
      }
    }
  }

  // If the probe never answers at all (spawn failure fires no onExited),
  // stop waiting and show what the bar itself knows instead of a stuck
  // "Loading…" and an empty tab.
  Timer {
    id: probeWatchdog
    interval: 8000
    onTriggered: {
      if (!popup.pluginsLoading) return
      popup.pluginsLoading = false
      if (!popup.useRegistryPlugins("Plugin probe timed out — showing widgets from the bar")) {
        popup.lastAction = "Plugin probe timed out and the bar reports no widgets"
      }
    }
  }

  Process {
    id: pluginAction
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) popup.lastAction = "Command failed"
      popup.refreshPlugins()
    }
  }

  // Classic workspaces mode: `bin/mode status` prints "classic" or
  // "4.5". The switch reloads Hyprland (a second or two), so the toggle
  // stays disabled until the status comes back and confirms the new mode.
  Process {
    id: modeStatus
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var mode = String(text || "").trim()
        if (mode === "classic" || mode === "4.5") {
          popup.classicMode = mode === "classic"
          popup.classicModeKnown = true
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Process {
    id: modeSwitch
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      popup.classicSwitching = false
      if (exitCode !== 0) popup.lastAction = "Workspace mode switch failed"
      popup.refreshClassicMode()
    }
  }

  // The clock's calendars file, watched so the tab follows edits made
  // elsewhere (and the clock widget refetches on the same change). The
  // file may not exist yet on a fresh install — the tab then shows an
  // empty list and the first add creates it.
  FileView {
    id: calendarsFile
    path: popup.calendarsPath
    watchChanges: true
    printErrors: false
    onLoaded: popup.loadCalendars()
    onLoadFailed: popup.calendars = []
    onFileChanged: popup.loadCalendars()
  }

  Process {
    id: calendarsWrite
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: popup.calendarsWriteOutput = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var msg = ""
      try {
        var parsed = JSON.parse(popup.calendarsWriteOutput || "{}")
        msg = String(parsed.error || "")
      } catch (e) {}
      if (exitCode !== 0) {
        popup.calendars = popup.calendarsBeforeSave
        popup.calendarsStatus = msg !== "" ? msg : "Could not save calendars"
      } else {
        popup.calendarsStatus = "Saved."
        calendarsFile.reload()
      }
    }
  }

// The window body: a fixed-size surface centered on its screen. The
// PanelWindow itself spans the screen (transparent) and the mask limits
// input to this body, so clicks outside it pass through.
  BorderSurface {
    id: windowBody
    anchors.centerIn: parent
    width: Style.space(880)
    height: Style.space(620)
    radius: Style.cornerRadius
    color: popup.bar.background
    borderSpec: Border.flat(popup.bar.foreground, 1)

    Row {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.md

      // Sidebar: bat header, section rows, close at the bottom.
      Item {
        id: sidebar
        width: Style.space(220)
        height: parent.height

        Column {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.md

          Row {
            spacing: Style.spacing.sm

            Text {
              // nf-md-bat, U+F0B5F, in the bar font (JetBrainsMono Nerd Font).
              text: "\udb82\udf5f"
              color: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.space(52)
              textFormat: Text.PlainText
            }

            Text {
              text: "Nyxiri"
              color: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            text: "Bar, widgets, updates and calendars"
            color: Qt.darker(popup.bar.foreground, 1.4)
            font.family: popup.bar.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Repeater {
            model: popup.sidebarTabs

            delegate: Button {
              required property var modelData
              width: sidebar.width
              text: modelData.label
              selected: popup.tab === modelData.value
              bordered: !selected
              foreground: popup.bar.foreground
              onClicked: popup.tab = modelData.value
            }
          }
        }

        Button {
          id: closeButton
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          text: "Close"
          bordered: true
          foreground: popup.bar.foreground
          onClicked: popup.closeSettings()
        }
      }

      Rectangle {
        id: divider
        width: 1
        height: parent.height
        color: popup.bar.foreground
        opacity: 0.15
      }

      Column {
        id: contentColumn
        width: parent.width - sidebar.width - divider.width - parent.spacing * 2
        height: parent.height
        spacing: Style.spacing.sm


      Item {
        id: viewport
        width: parent.width
        height: parent.height - (noPluginsNote.visible ? noPluginsNote.implicitHeight + contentColumn.spacing : 0)
        clip: true

        Flickable {
          id: scrollArea
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          // A fixed gutter for the scrollbar on the right. Reserving it
          // always (rather than only when overflowing) keeps the layout
          // stable: a width that depends on contentHeight would bind-loop
          // against the body width.
          width: parent.width - Style.space(10)
          contentWidth: width
          contentHeight: body.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          clip: true

          Column {
            id: body
            width: scrollArea.width
            spacing: Style.spacing.lg

            // ------------------------------------------------------------ bar
            Column {
              visible: popup.tab === "bar"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel { text: "BAR" }

              SectionLabel { text: "SECTION PILLS" }

              Repeater {
                model: [
                  { value: "left", label: "Left" },
                  { value: "center", label: "Center" },
                  { value: "right", label: "Right" }
                ]

                delegate: Column {
                  id: sectionRow
                  required property var modelData
                  width: body.width
                  spacing: Style.spacing.xxs

                  BodyText {
                    text: sectionRow.modelData.label
                    width: parent.width
                  }

                  Row {
                    width: parent.width
                    spacing: Style.spacing.xs

                    Repeater {
                      model: [
                        { value: "island", label: "Island", hint: "One pill around the whole section" },
                        { value: "mini", label: "Mini", hint: "One pill per widget" }
                      ]

                      delegate: Button {
                        required property var modelData
                        width: (parent.width - parent.spacing) / 2
                        text: modelData.label
                        tooltipText: modelData.hint
                        selected: popup.bar.nyxiriSectionMode(sectionRow.modelData.value) === modelData.value
                        bordered: !selected
                        foreground: popup.bar.foreground
                        onClicked: popup.setSection(sectionRow.modelData.value, modelData.value)
                      }
                    }
                  }
                }
              }

              SectionLabel { text: "COLOUR" }

              // The swatch is the same height as the dropdown's field and
              // bottom-anchored to it, so it reads as part of the field
              // row instead of floating beside the label above it.
              Item {
                width: body.width
                height: colorDropdown.height

                Dropdown {
                  id: colorDropdown
                  width: parent.width - swatch.width - Style.spacing.sm
                  anchors.left: parent.left
                  anchors.top: parent.top
                  label: "Role"
                  value: popup.pill.color
                  options: popup.colorOptions
                  foreground: popup.bar.foreground
                  fontFamily: popup.bar.fontFamily
                  onChanged: function(value) { popup.setPill({ color: value }) }
                }

                BorderSurface {
                  id: swatch
                  width: Style.space(44)
                  height: Style.spacing.controlHeight
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  radius: Style.cornerRadius
                  color: popup.bar.nyxiriPillColor
                  borderSpec: Border.flat(popup.bar.foreground, 1)
                }
              }

              FocusField {
                visible: popup.pill.color === "custom"
                width: body.width
                settingText: popup.pill.customColor
                placeholderText: "#7aa2f7"
                foreground: popup.bar.foreground
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.body
                onCommit: function(value) {
                  if (Nyxiri.isHexColor(value)) popup.setPill({ customColor: value })
                }
              }

              SectionLabel { text: "PILL SURFACE" }

              Dropdown {
                width: body.width
                label: "Bar surface"
                value: popup.pill.surface
                options: [
                  { value: "theme", label: "Theme background" },
                  { value: "clear", label: "Clear (pills only)" }
                ]
                foreground: popup.bar.foreground
                fontFamily: popup.bar.fontFamily
                onChanged: function(value) { popup.setPill({ surface: value }) }
              }

              SliderRow {
                label: "Background"
                value: popup.pill.surfaceOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                valueText: Math.round(popup.pill.surfaceOpacity * 100) + "%"
                enabled: popup.pill.surface !== "clear"
                onReleased: function(value) { popup.setPill({ surfaceOpacity: value }) }
              }

              SectionLabel { text: "SHAPE" }

              // "Pill opacity" is the Fill level itself, so 100% means a
              // solid pill. A separate master fade once multiplied it, which
              // is why 100% still looked see-through; the master is gone.
              SliderRow {
                label: "Pill opacity"
                value: popup.pill.fillOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                valueText: Math.round(popup.pill.fillOpacity * 100) + "%"
                onReleased: function(value) { popup.setPill({ fillOpacity: value }) }
              }

              SliderRow {
                label: "Border"
                value: popup.pill.borderOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                valueText: Math.round(popup.pill.borderOpacity * 100) + "%"
                onReleased: function(value) { popup.setPill({ borderOpacity: value }) }
              }

              SliderRow {
                label: "Width"
                value: popup.pill.borderWidth
                minimum: 0
                maximum: 4
                step: 1
                integer: true
                valueText: String(popup.pill.borderWidth) + "px"
                onReleased: function(value) { popup.setPill({ borderWidth: value }) }
              }

              SliderRow {
                label: "Padding"
                value: popup.pill.padding
                minimum: 0
                maximum: 24
                step: 1
                integer: true
                valueText: String(popup.pill.padding) + "px"
                onReleased: function(value) { popup.setPill({ padding: value }) }
              }
            }

            // ----------------------------------------------------------- menu
            // The menu trigger's settings belong to a separate plugin
            // (pizza.dirty.nyxiri-menu). The tab only shows when that
            // plugin is installed; the controls only show when its
            // trigger is actually on the bar.
            Column {
              visible: popup.tab === "menu"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel {
                visible: popup.bar.nyxiriMenuAvailable
                text: "MENU TRIGGER"
              }

                // Dropdown popups are clipped by this card's window, so the
                // last option falls off the bottom edge, and their clicks
                // clear the card's focus grab, so picking an option closed
                // the card. Choice rows have neither problem, same as Mode
                // and Style below.
                SubLabel {
                  visible: popup.bar.nyxiriMenuAvailable
                  text: "Icon mode"
                }

                Row {
                  visible: popup.bar.nyxiriMenuAvailable
                  width: body.width
                  spacing: Style.spacing.xs

                  Repeater {
                    model: [
                      { value: "glyph", label: "Glyph" },
                      { value: "image", label: "Image / SVG" },
                      { value: "wordmark", label: "Wordmark" }
                    ]

                    delegate: Button {
                      required property var modelData
                      width: (parent.width - parent.spacing * 2) / 3
                      text: modelData.label
                      selected: popup.menuSetting("iconMode", "glyph") === modelData.value
                      bordered: !selected
                      foreground: popup.bar.foreground
                      onClicked: popup.setMenu({ iconMode: modelData.value })
                    }
                  }
                }

                SubLabel {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                  text: "Glyph"
                }

                Row {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                  width: body.width
                  spacing: Style.spacing.xs

                  Repeater {
                    model: [
                      { value: "omarchy", label: "Omarchy" },
                      { value: "arch", label: "Arch" },
                      { value: "custom", label: "Custom" }
                    ]

                    delegate: Button {
                      required property var modelData
                      width: (parent.width - parent.spacing * 2) / 3
                      text: modelData.label
                      selected: popup.menuSetting("glyph", "omarchy") === modelData.value
                      bordered: !selected
                      foreground: popup.bar.foreground
                      onClicked: popup.setMenu({ glyph: modelData.value })
                    }
                  }
                }

                FocusField {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                    && popup.menuSetting("glyph", "omarchy") === "custom"
                  width: body.width
                  settingText: popup.menuSetting("customGlyph", "")
                  placeholderText: "Glyph"
                  foreground: popup.bar.foreground
                  font.family: popup.bar.fontFamily
                  font.pixelSize: Style.font.body
                  onCommit: function(value) { popup.setMenu({ customGlyph: value }) }
                }

                FocusField {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                    && popup.menuSetting("glyph", "omarchy") === "custom"
                  width: body.width
                  settingText: popup.menuSetting("iconFont", "omarchy")
                  placeholderText: "Font family"
                  foreground: popup.bar.foreground
                  font.family: popup.bar.fontFamily
                  font.pixelSize: Style.font.body
                  onCommit: function(value) { popup.setMenu({ iconFont: value }) }
                }

                FocusField {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "image"
                  width: body.width
                  settingText: popup.menuSetting("iconSource", "")
                  placeholderText: "/path/to/icon.svg"
                  foreground: popup.bar.foreground
                  font.family: popup.bar.fontFamily
                  font.pixelSize: Style.font.body
                  onCommit: function(value) { popup.setMenu({ iconSource: value }) }
                }

                // Wordmark presets are one-tap fills of the same field: the
                // widget renders every wordmark uppercased with wide
                // letterspacing, Shibumi-preview style, so the presets are
                // canned strings, not image assets. Custom text still works.
                SubLabel {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "wordmark"
                  text: "Wordmark"
                }

                Row {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "wordmark"
                  width: body.width
                  spacing: Style.spacing.xs

                  Repeater {
                    model: [
                      { value: "Arch", label: "Arch" },
                      { value: "Hyprland", label: "Hyprland" },
                      { value: "Nyxiri", label: "Nyxiri" },
                      { value: "Omarchy", label: "Omarchy" }
                    ]

                    delegate: Button {
                      required property var modelData
                      width: (parent.width - parent.spacing * 3) / 4
                      text: modelData.label
                      selected: String(popup.menuSetting("wordmark", "Nyxiri")).toUpperCase() === modelData.value.toUpperCase()
                      bordered: !selected
                      foreground: popup.bar.foreground
                      onClicked: popup.setMenu({ wordmark: modelData.value })
                    }
                  }
                }

                FocusField {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "wordmark"
                  width: body.width
                  settingText: popup.menuSetting("wordmark", "Nyxiri")
                  placeholderText: "Nyxiri"
                  foreground: popup.bar.foreground
                  font.family: popup.bar.fontFamily
                  font.pixelSize: Style.font.body
                  onCommit: function(value) { popup.setMenu({ wordmark: value }) }
                }

                Toggle {
                  visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "image"
                  width: body.width
                  label: "Tint image"
                  description: "Recolour the image with the bar foreground"
                  checked: popup.menuSetting("tint", true) === true
                  foreground: popup.bar.foreground
                  onClicked: popup.setMenu({ tint: !checked })
                }

                Toggle {
                  visible: popup.bar.nyxiriMenuAvailable
                  width: body.width
                  label: "Hover opens submenus"
                  description: "Pins this trigger; the menu's own row sets the shared default"
                  checked: popup.menuSetting("hoverOpen", true) !== false
                  foreground: popup.bar.foreground
                  onClicked: popup.setMenu({ hoverOpen: !checked })
                }

                BodyText {
                  visible: !popup.bar.nyxiriMenuAvailable
                  width: body.width
                  text: "Add the Menu widget to the bar to change these."
                  color: Qt.darker(popup.bar.foreground, 1.35)
                  font.pixelSize: Style.font.caption
                }
              }

            // -------------------------------------------------------- weather
            // The weather fork's secondary location is a widget setting;
            // only offer it when pizza.dirty.weather is actually on the bar.
            // A name ("Tucson") or "lat,lon". Empty means no secondary.
            Column {
              visible: popup.tab === "weather"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel {
                visible: popup.bar.nyxiriWeatherAvailable
                text: "WEATHER"
              }

              SubLabel {
                visible: popup.bar.nyxiriWeatherAvailable
                text: "Secondary location"
              }

              FocusField {
                visible: popup.bar.nyxiriWeatherAvailable
                width: body.width
                settingText: popup.weatherSetting("secondaryLocation", "")
                placeholderText: "Tucson"
                foreground: popup.bar.foreground
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.body
                onCommit: function(value) { popup.setWeather({ secondaryLocation: value }) }
              }

              Text {
                visible: popup.bar.nyxiriWeatherAvailable
                width: body.width
                text: "A second city shown under the main forecast. Leave empty for none."
                color: Qt.darker(popup.bar.foreground, 1.4)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              BodyText {
                visible: !popup.bar.nyxiriWeatherAvailable
                width: body.width
                text: "Add the Weather widget to the bar to change these."
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.pixelSize: Style.font.caption
              }
            }

            // ----------------------------------------------------- workspaces
            // The workspaces widget's settings live in its own layout entry;
            // only offer these controls when it is actually on the bar.
            Column {
              visible: popup.tab === "workspaces"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel { text: "WORKSPACES" }

              // Dropdown popups open below the trigger and are clipped by
              // this card's window, so on a short tab the last options fall
              // off the bottom edge. Choice rows have nothing to clip.
              SubLabel {
                visible: popup.bar.nyxiriWorkspacesAvailable
                text: "Mode"
              }

              Row {
                visible: popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                spacing: Style.spacing.xs

                Repeater {
                  model: [
                    { value: "10", label: "Ten" },
                    { value: "5", label: "Five" },
                    { value: "active", label: "Active only" }
                  ]

                  delegate: Button {
                    required property var modelData
                    width: (parent.width - parent.spacing * 2) / 3
                    text: modelData.label
                    selected: popup.workspacesSetting("mode", "10") === modelData.value
                    bordered: !selected
                    foreground: popup.bar.foreground
                    onClicked: popup.setWorkspaces({ mode: modelData.value })
                  }
                }
              }

              // In classic with a range set, the ranges decide how many
              // show, so Ten vs Five is a no-op: the modes are really a
              // 4.5 thing. Without a range, Mode still sets the count.
              Text {
                visible: popup.bar.nyxiriWorkspacesAvailable && popup.classicMode && popup.workspacesSetting("ranges", "") !== ""
                width: body.width
                text: "Modes really only for 4.5"
                color: Qt.darker(popup.bar.foreground, 1.4)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              SubLabel {
                visible: popup.bar.nyxiriWorkspacesAvailable
                text: "Style"
              }

              // Eight styles no longer fit one row, so this one wraps: four
              // on each line.
              Flow {
                visible: popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                spacing: Style.spacing.xs

                Repeater {
                  model: [
                    { value: "numbers", label: "Numbers" },
                    { value: "kanji", label: "Kanji" },
                    { value: "pacman", label: "Pac-Man" },
                    { value: "dots", label: "Dots" },
                    { value: "magic", label: "Magic" },
                    { value: "default", label: "Default" },
                    { value: "aurora", label: "Aurora" },
                    { value: "apps", label: "Apps" }
                  ]

                  delegate: Button {
                    required property var modelData
                    width: (parent.width - parent.spacing * 3) / 4
                    text: modelData.label
                    selected: popup.workspacesSetting("style", "numbers") === modelData.value
                    bordered: !selected
                    foreground: popup.bar.foreground
                    onClicked: popup.setWorkspaces({ style: modelData.value })
                  }
                }
              }

              Toggle {
                visible: popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                label: "Hide empty workspaces"
                description: popup.workspacesSetting("mode", "10") === "active" ? "Does nothing while Mode is Active only" : "Drops workspaces with no windows; the focused one always stays"
                checked: popup.workspacesSetting("hideEmpty", false) === true
                enabled: popup.workspacesSetting("mode", "10") !== "active"
                foreground: popup.bar.foreground
                onClicked: popup.setWorkspaces({ hideEmpty: !checked })
              }

              Toggle {
                visible: popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                label: "Cycle layout on click"
                description: "Clicking the workspace you're already on switches tiling, scrolling, floating. Turn it off if a double-click keeps changing your layout."
                checked: popup.workspacesSetting("cycleLayoutOnClick", true) === true || popup.workspacesSetting("cycleLayoutOnClick", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setWorkspaces({ cycleLayoutOnClick: !checked })
              }

              // Classic workspaces is a Hyprland mode, not a widget setting:
              // the toggle runs the workspaces plugin's bin/mode, which flips
              // the flag and reloads Hyprland. The ranges field pins which
              // workspaces each monitor shows while classic is on.
              Toggle {
                visible: popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                label: "Classic workspaces"
                description: popup.classicSwitching ? "Switching…" : popup.classicMode ? "One global set 1-10, as in Omarchy 4.0.6" : "Omarchy 4.5: each monitor has its own 1-10"
                checked: popup.classicMode
                enabled: popup.classicModeKnown && !popup.classicSwitching
                foreground: popup.bar.foreground
                onClicked: popup.switchClassic(!checked)
              }

              SubLabel {
                visible: popup.bar.nyxiriWorkspacesAvailable && popup.classicMode
                text: "Workspaces per monitor"
              }

              FocusField {
                visible: popup.bar.nyxiriWorkspacesAvailable && popup.classicMode
                width: body.width
                settingText: popup.workspacesSetting("ranges", "")
                placeholderText: "DP-1:1-5,HDMI-A-1:6-10"
                foreground: popup.bar.foreground
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.body
                onCommit: function(value) { popup.setWorkspaces({ ranges: value }) }
              }

              // App icon size only matters for the Apps style, so the slider
              // only shows while that style is picked.
              SliderRow {
                visible: popup.bar.nyxiriWorkspacesAvailable && popup.workspacesSetting("style", "numbers") === "apps"
                label: "App icon size"
                value: popup.workspacesSetting("iconSize", 16)
                minimum: 12
                maximum: 24
                step: 1
                integer: true
                valueText: String(popup.workspacesSetting("iconSize", 16)) + "px"
                onReleased: function(value) { popup.setWorkspaces({ iconSize: value }) }
              }

              BodyText {
                visible: !popup.bar.nyxiriWorkspacesAvailable
                width: body.width
                text: "Add the Nyxiri workspaces widget to the bar to change these."
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.pixelSize: Style.font.caption
              }
            }

            // ------------------------------------------------------------ system
            // The Arch Updates widget's settings live in its own layout entry;
            // only offer these controls when it is actually on the bar. Same
            // keys, types, and defaults as the plugin's own popup, so the
            // two stay in sync.
            Column {
              visible: popup.tab === "system"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel { text: "SYSTEM UPDATER" }

              SubLabel {
                visible: popup.bar.nyxiriSystemAvailable
                text: "Refresh"
              }

              SliderRow {
                visible: popup.bar.nyxiriSystemAvailable
                label: "Refresh interval"
                value: popup.systemSetting("refreshIntervalSec", 1800)
                minimum: 300
                maximum: 7200
                step: 300
                integer: true
                valueText: String(Math.round(popup.systemSetting("refreshIntervalSec", 1800) / 60)) + " min"
                onReleased: function(value) { popup.setSystem({ refreshIntervalSec: value }) }
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "Automatic checks"
                description: popup.systemSetting("autoRefresh", true) === true || popup.systemSetting("autoRefresh", true) === "true" ? "Check on the interval and once after startup" : "Checks run only when the panel is opened"
                checked: popup.systemSetting("autoRefresh", true) === true || popup.systemSetting("autoRefresh", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ autoRefresh: !checked })
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "Always show"
                description: popup.systemSetting("alwaysShow", true) === true || popup.systemSetting("alwaysShow", true) === "true" ? "Keep the icon visible even when no updates are available" : "Hide the icon when everything is up to date"
                checked: popup.systemSetting("alwaysShow", true) === true || popup.systemSetting("alwaysShow", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ alwaysShow: !checked })
              }

              SubLabel {
                visible: popup.bar.nyxiriSystemAvailable
                text: "Sources"
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "AUR"
                description: "AUR updates from your helper (yay or paru)"
                checked: popup.systemSetting("checkAur", true) === true || popup.systemSetting("checkAur", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ checkAur: !checked })
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "Flatpak"
                description: "Flatpak updates"
                checked: popup.systemSetting("checkFlatpak", true) === true || popup.systemSetting("checkFlatpak", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ checkFlatpak: !checked })
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "mise"
                description: "mise dev tools"
                checked: popup.systemSetting("checkMise", true) === true || popup.systemSetting("checkMise", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ checkMise: !checked })
              }

              Toggle {
                visible: popup.bar.nyxiriSystemAvailable
                width: body.width
                label: "Plugins & themes"
                description: "Git-managed shell plugins and themes"
                checked: popup.systemSetting("checkPlugins", true) === true || popup.systemSetting("checkPlugins", true) === "true"
                foreground: popup.bar.foreground
                onClicked: popup.setSystem({ checkPlugins: !checked })
              }

              BodyText {
                visible: !popup.bar.nyxiriSystemAvailable
                width: body.width
                text: "Add the Arch Updates widget to the bar to change these."
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.pixelSize: Style.font.caption
              }
            }

            // ------------------------------------------------------- calendar
            // The clock's calendars, from calendars.json. A remote feed
            // is an iCal/.ics link (https:// or webcal://); a local feed
            // is a .ics file path. Links are secrets, so each row masks
            // its link like a password field until its eye toggle reveals
            // it; a local path is not a secret and shows as-is. Writing
            // the file is the refresh: the clock watches it and refetches.
            Column {
              visible: popup.tab === "calendar"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel { text: "CALENDAR" }

              Text {
                width: body.width
                text: "The clock's calendars. Add an iCal / .ics link or a local .ics file — no need to edit calendars.json by hand."
                color: Qt.darker(popup.bar.foreground, 1.45)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
              }

              BodyText {
                visible: popup.calendars.length === 0
                width: body.width
                text: "No calendars yet. Add one below."
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: popup.calendars

                delegate: Column {
                  id: calRow
                  required property var modelData
                  required property int index
                  property bool showSecret: false
                  width: body.width
                  spacing: Style.spacing.xxs

                  Row {
                    width: parent.width
                    spacing: Style.spacing.sm

                    Rectangle {
                      width: Style.space(12)
                      height: Style.space(12)
                      radius: Style.space(6)
                      color: String(calRow.modelData.color || "#4285f4")
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    BodyText {
                      text: String(calRow.modelData.name || "Calendar")
                      font.bold: true
                      width: parent.width - Style.space(12) - enabledSwitch.width - removeButton.width - parent.spacing * 3
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    ToggleSwitch {
                      id: enabledSwitch
                      anchors.verticalCenter: parent.verticalCenter
                      checked: calRow.modelData.enabled !== false
                      foreground: popup.bar.foreground
                      onToggled: popup.setCalendarEnabled(calRow.index, !(calRow.modelData.enabled !== false))
                    }

                    Button {
                      id: removeButton
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Remove"
                      bordered: true
                      foreground: popup.bar.foreground
                      onClicked: popup.removeCalendar(calRow.index)
                    }
                  }

                  Row {
                    visible: calRow.modelData.url !== undefined && calRow.modelData.url !== null && String(calRow.modelData.url || "") !== ""
                    width: parent.width
                    spacing: Style.spacing.xs

                    // Display only: a Text, not a field. The link shows
                    // as bullets until this row's eye toggle reveals it.
                    Text {
                      width: parent.width - linkEye.width - parent.spacing
                      text: calRow.showSecret ? String(calRow.modelData.url || "") : "••••••••••••"
                      elide: Text.ElideRight
                      color: popup.bar.foreground
                      font.family: popup.bar.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      textFormat: Text.PlainText
                      verticalAlignment: Text.AlignVCenter
                    }

                    Item {
                      id: linkEye
                      width: Style.space(32)
                      height: Style.space(28)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        anchors.centerIn: parent
                        // nf-md-eye / nf-md-eye-off, U+F0208 / U+F0209.
                        text: calRow.showSecret ? "\udb80\ude09" : "\udb80\ude08"
                        color: popup.bar.foreground
                        font.family: popup.bar.fontFamily
                        font.pixelSize: Style.font.body
                        textFormat: Text.PlainText
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: calRow.showSecret = !calRow.showSecret
                      }
                    }
                  }

                  BodyText {
                    visible: (calRow.modelData.url === undefined || calRow.modelData.url === null || String(calRow.modelData.url || "") === "") && calRow.modelData.path !== undefined && calRow.modelData.path !== null && String(calRow.modelData.path || "") !== ""
                    width: parent.width
                    text: String(calRow.modelData.path || "")
                    elide: Text.ElideRight
                    color: Qt.darker(popup.bar.foreground, 1.4)
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              SubLabel { text: "Add a calendar" }

              FocusField {
                id: newNameField
                width: body.width
                placeholderText: "Name"
                foreground: popup.bar.foreground
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.body
              }

              FocusField {
                id: newAccountField
                width: body.width
                placeholderText: "Account (optional, default Personal)"
                foreground: popup.bar.foreground
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.body
              }

              Row {
                width: body.width
                spacing: Style.spacing.xs

                FocusField {
                  id: newLinkField
                  width: parent.width - newLinkEye.width - parent.spacing
                  echoMode: popup.newCalShowLink ? TextInput.Normal : TextInput.Password
                  placeholderText: "https://…/basic.ics or ~/path/to/file.ics"
                  foreground: popup.bar.foreground
                  font.family: popup.bar.fontFamily
                  font.pixelSize: Style.font.body
                }

                Item {
                  id: newLinkEye
                  width: Style.space(32)
                  height: newLinkField.height

                  Text {
                    anchors.centerIn: parent
                    // nf-md-eye / nf-md-eye-off, U+F0208 / U+F0209.
                    text: popup.newCalShowLink ? "\udb80\ude09" : "\udb80\ude08"
                    color: popup.bar.foreground
                    font.family: popup.bar.fontFamily
                    font.pixelSize: Style.font.body
                    textFormat: Text.PlainText
                  }

                  MouseArea {
                    anchors.fill: parent
                    onClicked: popup.newCalShowLink = !popup.newCalShowLink
                  }
                }
              }

              Text {
                width: body.width
                text: "An iCal / .ics link (https:// or webcal://) or a local .ics file path. Links stay hidden unless you tap the eye."
                color: Qt.darker(popup.bar.foreground, 1.4)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
              }

              Button {
                text: "Add calendar"
                bordered: true
                foreground: popup.bar.foreground
                onClicked: popup.addCalendar()
              }

              BodyText {
                visible: popup.calendarsStatus !== ""
                width: body.width
                text: popup.calendarsStatus
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            // -------------------------------------------------------- monitors
            Column {
              visible: popup.tab === "monitors"
              width: parent.width
              spacing: Style.space(16)

              SectionLabel { text: "MONITORS" }

              Text {
                width: body.width
                text: popup.screenList.length === 0
                  ? "No monitors reported yet."
                  : "Turn a monitor's bar off, or limit which widgets it shows. A monitor with no entry shows everything."
                color: Qt.darker(popup.bar.foreground, 1.45)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: popup.screenList

                delegate: Column {
                  id: monitorCard
                  required property var modelData
                  readonly property string monitorName: String(modelData.name || "")
                  readonly property var rule: popup.monitorRule(monitorName)

                  width: body.width
                  spacing: Style.spacing.sm

                  BorderSurface {
                    width: parent.width
                    implicitHeight: monitorHeader.implicitHeight + Style.spacing.md * 2
                    radius: Style.cornerRadius
                    color: Style.normalFill
                    borderSpec: Border.flat(Util.alpha(popup.bar.foreground, 0.18), 1)

                    Row {
                      id: monitorHeader
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.spacing.rowPaddingX
                      anchors.rightMargin: Style.spacing.rowPaddingX
                      spacing: Style.spacing.sm

                      Column {
                        width: parent.width - monitorToggle.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spacing.xxs

                        BodyText {
                          text: monitorCard.monitorName || "Unknown monitor"
                          font.bold: true
                          width: parent.width
                          elide: Text.ElideRight
                        }
                        BodyText {
                          text: monitorCard.rule.enabled ? "Bar shown" : "Bar hidden"
                          color: Qt.darker(popup.bar.foreground, 1.4)
                          font.pixelSize: Style.font.caption
                          width: parent.width
                        }
                      }

                      ToggleSwitch {
                        id: monitorToggle
                        anchors.verticalCenter: parent.verticalCenter
                        checked: monitorCard.rule.enabled
                        foreground: popup.bar.foreground
                        onToggled: popup.setMonitor(monitorCard.monitorName, { enabled: !monitorCard.rule.enabled })
                      }
                    }
                  }

                  Column {
                    width: parent.width
                    spacing: Style.spacing.xxs
                    visible: monitorCard.rule.enabled

                    BodyText { text: "Widgets"; width: parent.width }

                    Dropdown {
                      width: parent.width
                      value: monitorCard.rule.widgets.mode
                      options: [
                        { value: "all", label: "All widgets" },
                        { value: "only", label: "Only listed" },
                        { value: "except", label: "All except listed" }
                      ]
                      foreground: popup.bar.foreground
                      fontFamily: popup.bar.fontFamily
                      onChanged: function(value) {
                        popup.setMonitor(monitorCard.monitorName, { widgets: { mode: value } })
                      }
                    }
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.spacing.xs
                    visible: monitorCard.rule.enabled && monitorCard.rule.widgets.mode !== "all"

                    Repeater {
                      model: popup.laidOutIds

                      delegate: Button {
                        required property string modelData
                        text: Nyxiri.shortWidgetId(modelData)
                        selected: popup.ruleContains(monitorCard.monitorName, modelData)
                        bordered: !selected
                        foreground: popup.bar.foreground
                        fontSize: Style.font.caption
                        onClicked: popup.toggleRule(monitorCard.monitorName, modelData)
                      }
                    }
                  }
                }
              }
            }

            // --------------------------------------------------------- plugins
            Column {
              visible: popup.tab === "plugins"
              width: parent.width
              spacing: Style.space(16)

              Row {
                width: body.width
                spacing: Style.spacing.sm

                SectionLabel {
                  text: "PLUGINS"
                  width: parent.width - refreshButton.width - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                  id: refreshButton
                  text: popup.pluginsLoading ? "Loading…" : "Refresh"
                  bordered: true
                  foreground: popup.bar.foreground
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: popup.refreshPlugins()
                }
              }

              Text {
                visible: popup.lastAction !== ""
                width: body.width
                text: popup.lastAction
                color: Qt.darker(popup.bar.foreground, 1.35)
                font.family: popup.bar.fontFamily
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                elide: Text.ElideRight
              }

              BodyText {
                visible: popup.plugins.length > 0
                width: body.width
                text: popup.plugins.length + " plugins · " + popup.activePlugins + " active · " + (popup.plugins.length - popup.activePlugins) + " disabled"
                color: Qt.darker(popup.bar.foreground, 1.45)
                font.pixelSize: Style.font.caption
              }

              // Active and Disabled are their own sub-tabs now, not one
              // long scroll with both groups stacked: pick a group and
              // only its rows show. Same choice-row buttons as Mode/Style.
              Row {
                width: body.width
                spacing: Style.spacing.xs
                visible: popup.plugins.length > 0

                Button {
                  text: "Active"
                  selected: popup.pluginGroup === "active"
                  bordered: !selected
                  foreground: popup.bar.foreground
                  onClicked: popup.pluginGroup = "active"
                }

                Button {
                  text: "Disabled"
                  selected: popup.pluginGroup === "disabled"
                  bordered: !selected
                  foreground: popup.bar.foreground
                  onClicked: popup.pluginGroup = "disabled"
                }
              }

              BodyText {
                visible: popup.plugins.length > 0 && popup.pluginGroup === "active" && popup.activePluginList.length === 0
                width: body.width
                text: "No active plugins."
                color: Qt.darker(popup.bar.foreground, 1.45)
                font.pixelSize: Style.font.caption
              }

              BodyText {
                visible: popup.plugins.length > 0 && popup.pluginGroup === "disabled" && popup.disabledPluginList.length === 0
                width: body.width
                text: "No disabled plugins."
                color: Qt.darker(popup.bar.foreground, 1.45)
                font.pixelSize: Style.font.caption
              }

              // One row component used by both Repeaters, so a row change
              // lands in both groups.
              component PluginRow: Column {
                required property var modelData
                readonly property bool listed: popup.inBar(modelData)
                // Entries whose kinds are missing or unrecognised still get
                // a row: the tab once showed nothing at all while the list
                // was provably non-empty, because every row hid behind a
                // kinds check. A plugin row is always useful (name, toggle);
                // only "Add to bar" stays widget-gated.
                readonly property bool rowShown: popup.isBarWidget(modelData)
                  || popup.kindList(modelData).length === 0

                width: body.width
                spacing: Style.spacing.xxs

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm
                  visible: rowShown

                  Column {
                    width: parent.width - pluginToggle.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    BodyText {
                      text: String(modelData.name || modelData.id || "")
                      width: parent.width
                      elide: Text.ElideRight
                    }
                    BodyText {
                      text: String(modelData.id || "") + (listed ? " · on the bar" : "")
                      color: Qt.darker(popup.bar.foreground, 1.45)
                      font.pixelSize: Style.font.caption
                      width: parent.width
                      elide: Text.ElideRight
                    }
                  }

                  ToggleSwitch {
                    id: pluginToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: modelData.enabled === true
                    enabled: modelData.canDisable !== false
                    foreground: popup.bar.foreground
                    onToggled: popup.setEnabled(modelData, modelData.enabled !== true)
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  visible: rowShown && modelData.enabled === true && !listed

                  Button {
                    text: "Add to bar"
                    bordered: true
                    foreground: popup.bar.foreground
                    onClicked: popup.addToBar(modelData)
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  visible: popup.isBarOption(modelData)

                  BodyText {
                    text: "Bar option"
                    width: parent.width - useBarButton.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }

                  Button {
                    id: useBarButton
                    text: "Use as bar"
                    bordered: true
                    foreground: popup.bar.foreground
                    onClicked: popup.useAsBar(modelData)
                  }
                }
              }

              // One Repeater with a conditional model: a Repeater's
              // delegates are children of the parent Column, not the
              // Repeater, so `visible` on a Repeater does not hide its
              // delegates. Switching the model swaps the rows, which is
              // why the Disabled sub-tab showed the active list (or
              // nothing) instead of just the disabled plugins.
              Repeater {
                model: popup.pluginGroup === "active" ? popup.activePluginList : popup.disabledPluginList
                delegate: PluginRow {}
              }

              Row {
                width: body.width
                spacing: Style.spacing.xs
                visible: popup.plugins.length > 0

                Button {
                  text: "Back to the built-in bar"
                  bordered: true
                  foreground: popup.bar.foreground
                  onClicked: popup.resetBar()
                }
              }
            }
          }
        }

        // A visible scrollbar for the one shared scroll area: the Plugins
        // tab (and Appearance/Monitors on a short screen) overflows the
        // 430px viewport, and a wheel-only scroll gives no hint there is
        // more. It shows only when the active tab actually overflows, so
        // it serves every tab without taking space on the ones that fit.
        // Upstream has no ScrollBar anywhere, so this is hand-rolled to
        // match the card instead of pulling in QtQuick.Controls.
        Item {
          id: scrollBar
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(10)
          visible: scrollArea.contentHeight > viewport.height

          readonly property real thumbHeight: Math.max(Style.space(28), viewport.height * viewport.height / scrollArea.contentHeight)
          readonly property real thumbY: scrollArea.contentHeight > viewport.height
            ? scrollArea.contentY / (scrollArea.contentHeight - viewport.height) * (viewport.height - thumbHeight)
            : 0

          function scrollTo(y) {
            var maxY = scrollArea.contentHeight - viewport.height
            var ratio = Math.max(0, Math.min(1, (y - thumbHeight / 2) / (viewport.height - thumbHeight)))
            scrollArea.contentY = ratio * maxY
          }

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Style.space(3)
            anchors.rightMargin: Style.space(1)
            color: popup.bar.foreground
            opacity: 0.10
            radius: width / 2
          }

          Rectangle {
            x: Style.space(3)
            y: scrollBar.thumbY
            width: Style.space(6)
            height: scrollBar.thumbHeight
            color: popup.bar.foreground
            opacity: 0.45
            radius: width / 2
          }

          MouseArea {
            anchors.fill: parent
            onPressed: function(mouse) { scrollBar.scrollTo(mouse.y) }
            onPositionChanged: function(mouse) { if (pressed) scrollBar.scrollTo(mouse.y) }
          }
        }
      }

      BodyText {
        id: noPluginsNote
        width: parent.width
        visible: popup.tab === "plugins" && popup.plugins.length === 0 && !popup.pluginsLoading
        text: "No plugins reported. Is `omarchy plugin list` available?"
        color: Qt.darker(popup.bar.foreground, 1.45)
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      }
    }
  }

  // Input goes only to the window body; the rest of the fullscreen surface
  // is transparent to the pointer.
  mask: Region { item: windowBody }
}
