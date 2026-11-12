import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Nyxiri.js" as Nyxiri

// The in-bar Nyxiri settings card. Instantiated once per bar surface and
// opened on the focused monitor; every control writes a partial config through
// bar.writeNyxiri(), so persistence and reloading stay in one place.
PopupCard {
  id: popup

  // `bar` and `open` come from PopupCard. screenName identifies the surface
  // this card belongs to.
  property string screenName: ""
  property string initialTab: "appearance"

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

  property string tab: "appearance"
  property var plugins: []
  property bool pluginsLoading: false
  property string lastAction: ""
  property string pluginProbeError: ""

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

  onOpenChanged: {
    if (open) {
      tab = initialTab
      refreshPlugins()
    }
  }
  onInitialTabChanged: if (open) tab = initialTab
  onTabChanged: if (tab === "widgets" && plugins.length === 0 && !pluginsLoading) refreshPlugins()

  // PopupCard does not consume keys, so Escape is scoped to the card while it
  // is open. The close button remains the pointer path. NOTE: Shortcut (and
  // Process) must NOT be direct children of PopupCard: its default property
  // is the visual contentItem list, and a QQuickShortcut there fails the
  // whole file ("Cannot assign object of type QQuickShortcut to list
  // property contentItem"), which makes NyxiriSettings unavailable and the
  // bar falls back to omarchy.bar. They live inside the content Column
  // below instead, where Item.data accepts non-visual children.
  contentWidth: fittedContentWidth(Style.space(440))
  contentHeight: fittedContentHeight(column.implicitHeight, Style.space(620))

  component SectionLabel: Text {
    color: Qt.darker(popup.bar.foreground, 1.35)
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.4
    textFormat: Text.PlainText
  }

  component BodyText: Text {
    color: popup.bar.foreground
    font.family: popup.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
  }

  // Text input in a popup does not take keyboard focus on click by itself:
  // the click selects text but no cursor appears and keys go nowhere, which
  // is exactly what the wordmark field did. Stock panels force focus
  // explicitly (weather Panel startEditingLocation, polkit passwordInput),
  // and they do it deferred: forcing focus synchronously during the press
  // can run before the click has activated the popup window, so it lands
  // nowhere. This defers it the same way, and lets the press through so
  // cursor placement and selection keep working.
  component FocusField: TextField {
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

  Column {
    id: column
    width: parent.width
    spacing: Style.spacing.md

    Shortcut {
      sequence: "Escape"
      enabled: popup.open
      onActivated: popup.close()
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
        popup.probeWatchdog.running = false
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

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Column {
        width: parent.width - closeButton.width - parent.spacing
        spacing: Style.spacing.xxs

        Text {
          text: "Nyxiri"
          color: popup.bar.foreground
          font.family: popup.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          textFormat: Text.PlainText
        }
        Text {
          text: "Bar appearance, monitor rules and widgets"
          color: Qt.darker(popup.bar.foreground, 1.4)
          font.family: popup.bar.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Button {
        id: closeButton
        text: "Close"
        bordered: true
        foreground: popup.bar.foreground
        onClicked: popup.close()
      }
    }

    Row {
      width: parent.width
      spacing: Style.spacing.xs

      Repeater {
        model: [
          { value: "appearance", label: "Appearance" },
          { value: "monitors", label: "Monitors" },
          { value: "workspaces", label: "Workspaces" },
          { value: "widgets", label: "Widgets" }
        ]

        delegate: Button {
          required property var modelData
          text: modelData.label
          selected: popup.tab === modelData.value
          bordered: !selected
          foreground: popup.bar.foreground
          onClicked: popup.tab = modelData.value
        }
      }
    }

    Item {
      id: viewport
      width: parent.width
      height: Math.min(body.implicitHeight, Style.space(430))
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

          // ------------------------------------------------------ appearance
          Column {
            visible: popup.tab === "appearance"
            width: parent.width
            spacing: Style.spacing.sm

            SectionLabel { text: "SECTION PILLS" }

            Repeater {
              model: [
                { value: "left", label: "Left" },
                { value: "center", label: "Center" },
                { value: "right", label: "Right" }
              ]

              delegate: Row {
                id: sectionRow
                required property var modelData
                width: body.width
                spacing: Style.spacing.xs

                BodyText {
                  text: modelData.label
                  width: Style.space(72)
                }

                Repeater {
                  model: [
                    { value: "island", label: "Island", hint: "One pill around the whole section" },
                    { value: "mini", label: "Mini", hint: "One pill per widget" }
                  ]

                  delegate: Button {
                    required property var modelData
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

            SectionLabel { text: "COLOUR" }

            Row {
              width: body.width
              spacing: Style.spacing.sm

              Dropdown {
                id: colorDropdown
                width: parent.width - swatch.width - parent.spacing
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
                radius: Style.cornerRadius
                color: popup.bar.nyxiriPillColor
                borderSpec: Border.flat(popup.bar.foreground, 1)
              }
            }

            FocusField {
              visible: popup.pill.color === "custom"
              width: body.width
              text: popup.pill.customColor
              placeholderText: "#7aa2f7"
              foreground: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.body
              onEditingFinished: {
                if (Nyxiri.isHexColor(text)) popup.setPill({ customColor: text })
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

            Row {
              width: body.width
              spacing: Style.spacing.sm
              enabled: popup.pill.surface !== "clear"
              BodyText { text: "Background"; width: Style.space(76) }
              PanelSlider {
                width: parent.width - Style.space(76) - surfaceValue.width - parent.spacing * 2
                bar: popup.bar
                value: popup.pill.surfaceOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                onReleased: function(value) { popup.setPill({ surfaceOpacity: value }) }
              }
              BodyText {
                id: surfaceValue
                text: Math.round(popup.pill.surfaceOpacity * 100) + "%"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            SectionLabel { text: "SHAPE" }

            // "Pill opacity" is the Fill level itself, so 100% means a
            // solid pill. A separate master fade once multiplied it, which
            // is why 100% still looked see-through; the master is gone.
            Row {
              width: body.width
              spacing: Style.spacing.sm
              BodyText { text: "Pill opacity"; width: Style.space(76) }
              PanelSlider {
                id: fillSlider
                width: parent.width - Style.space(76) - valueText.width - parent.spacing * 2
                bar: popup.bar
                value: popup.pill.fillOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                onReleased: function(value) { popup.setPill({ fillOpacity: value }) }
              }
              BodyText {
                id: valueText
                text: Math.round(popup.pill.fillOpacity * 100) + "%"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            Row {
              width: body.width
              spacing: Style.spacing.sm
              BodyText { text: "Border"; width: Style.space(76) }
              PanelSlider {
                width: parent.width - Style.space(76) - borderValue.width - parent.spacing * 2
                bar: popup.bar
                value: popup.pill.borderOpacity
                minimum: 0
                maximum: 1
                step: 0.05
                onReleased: function(value) { popup.setPill({ borderOpacity: value }) }
              }
              BodyText {
                id: borderValue
                text: Math.round(popup.pill.borderOpacity * 100) + "%"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            Row {
              width: body.width
              spacing: Style.spacing.sm
              BodyText { text: "Width"; width: Style.space(76) }
              PanelSlider {
                width: parent.width - Style.space(76) - widthValue.width - parent.spacing * 2
                bar: popup.bar
                value: popup.pill.borderWidth
                minimum: 0
                maximum: 4
                step: 1
                integer: true
                onReleased: function(value) { popup.setPill({ borderWidth: value }) }
              }
              BodyText {
                id: widthValue
                text: String(popup.pill.borderWidth) + "px"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            Row {
              width: body.width
              spacing: Style.spacing.sm
              BodyText { text: "Padding"; width: Style.space(76) }
              PanelSlider {
                width: parent.width - Style.space(76) - paddingValue.width - parent.spacing * 2
                bar: popup.bar
                value: popup.pill.padding
                minimum: 0
                maximum: 24
                step: 1
                integer: true
                onReleased: function(value) { popup.setPill({ padding: value }) }
              }
              BodyText {
                id: paddingValue
                text: String(popup.pill.padding) + "px"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            // The menu fork's trigger is a separate plugin; only offer these
            // controls when it is actually on the bar.
            SectionLabel {
              visible: popup.bar.nyxiriMenuAvailable
              text: "MENU TRIGGER"
            }

            Dropdown {
              visible: popup.bar.nyxiriMenuAvailable
              width: body.width
              label: "Icon mode"
              value: popup.menuSetting("iconMode", "glyph")
              options: [
                { value: "glyph", label: "Glyph" },
                { value: "image", label: "Image / SVG" },
                { value: "wordmark", label: "Wordmark" }
              ]
              foreground: popup.bar.foreground
              fontFamily: popup.bar.fontFamily
              onChanged: function(value) { popup.setMenu({ iconMode: value }) }
            }

            Dropdown {
              visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
              width: body.width
              label: "Glyph"
              value: popup.menuSetting("glyph", "omarchy")
              options: [
                { value: "omarchy", label: "Omarchy" },
                { value: "arch", label: "Arch" },
                { value: "custom", label: "Custom Nerd Font glyph" }
              ]
              foreground: popup.bar.foreground
              fontFamily: popup.bar.fontFamily
              onChanged: function(value) { popup.setMenu({ glyph: value }) }
            }

            FocusField {
              visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                && popup.menuSetting("glyph", "omarchy") === "custom"
              width: body.width
              text: popup.menuSetting("customGlyph", "")
              placeholderText: "Glyph"
              foreground: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.body
              onEditingFinished: popup.setMenu({ customGlyph: text })
            }

            FocusField {
              visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "glyph"
                && popup.menuSetting("glyph", "omarchy") === "custom"
              width: body.width
              text: popup.menuSetting("iconFont", "omarchy")
              placeholderText: "Font family"
              foreground: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.body
              onEditingFinished: popup.setMenu({ iconFont: text })
            }

            FocusField {
              visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "image"
              width: body.width
              text: popup.menuSetting("iconSource", "")
              placeholderText: "/path/to/icon.svg"
              foreground: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.body
              onEditingFinished: popup.setMenu({ iconSource: text })
            }

            FocusField {
              visible: popup.bar.nyxiriMenuAvailable && popup.menuSetting("iconMode", "glyph") === "wordmark"
              width: body.width
              text: popup.menuSetting("wordmark", "Nyxiri")
              placeholderText: "Nyxiri"
              foreground: popup.bar.foreground
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.body
              onEditingFinished: popup.setMenu({ wordmark: text })
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
          }

          // ----------------------------------------------------- workspaces
          // The workspaces widget's settings live in its own layout entry;
          // only offer these controls when it is actually on the bar.
          Column {
            visible: popup.tab === "workspaces"
            width: parent.width
            spacing: Style.spacing.sm

            SectionLabel { text: "WORKSPACES" }

            // Dropdown popups open below the trigger and are clipped by
            // this card's window, so on a short tab the last options fall
            // off the bottom edge. Choice rows have nothing to clip.
            Text {
              visible: popup.bar.nyxiriWorkspacesAvailable
              text: "Mode"
              color: Qt.darker(popup.bar.foreground, 1.4)
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
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

            Text {
              visible: popup.bar.nyxiriWorkspacesAvailable
              text: "Style"
              color: Qt.darker(popup.bar.foreground, 1.4)
              font.family: popup.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
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
              description: "Drops workspaces with no windows; the focused one always stays"
              checked: popup.workspacesSetting("hideEmpty", false) === true
              foreground: popup.bar.foreground
              onClicked: popup.setWorkspaces({ hideEmpty: !checked })
            }

            // App icon size only matters for the Apps style, so the slider
            // only shows while that style is picked.
            Row {
              visible: popup.bar.nyxiriWorkspacesAvailable && popup.workspacesSetting("style", "numbers") === "apps"
              width: body.width
              spacing: Style.spacing.sm
              BodyText { text: "App icon size"; width: Style.space(76) }
              PanelSlider {
                width: parent.width - Style.space(76) - iconSizeValue.width - parent.spacing * 2
                bar: popup.bar
                value: popup.workspacesSetting("iconSize", 16)
                minimum: 12
                maximum: 24
                step: 1
                integer: true
                onReleased: function(value) { popup.setWorkspaces({ iconSize: value }) }
              }
              BodyText {
                id: iconSizeValue
                text: String(popup.workspacesSetting("iconSize", 16)) + "px"
                width: Style.space(40)
                horizontalAlignment: Text.AlignRight
              }
            }

            BodyText {
              visible: !popup.bar.nyxiriWorkspacesAvailable
              width: body.width
              text: "Add the Nyxiri workspaces widget to the bar to change these."
              color: Qt.darker(popup.bar.foreground, 1.35)
              font.pixelSize: Style.font.caption
            }
          }

          // -------------------------------------------------------- monitors
          Column {
            visible: popup.tab === "monitors"
            width: parent.width
            spacing: Style.spacing.sm

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
                spacing: Style.spacing.xs

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

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  visible: monitorCard.rule.enabled

                  BodyText { text: "Widgets"; width: Style.space(72) }

                  Dropdown {
                    width: parent.width - Style.space(72) - parent.spacing
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
                      text: Nyxiri.baseWidgetId(modelData)
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

          // --------------------------------------------------------- widgets
          Column {
            visible: popup.tab === "widgets"
            width: parent.width
            spacing: Style.spacing.sm

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
              text: popup.plugins.length + " plugins · " + popup.activePlugins + " active"
              color: Qt.darker(popup.bar.foreground, 1.45)
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: popup.sortedPlugins

              delegate: Column {
                id: pluginRow
                required property var modelData
                readonly property bool listed: popup.inBar(modelData)
                // Entries whose kinds are missing or unrecognised still get
                // a row: the tab once showed nothing at all while the list
                // was provably non-empty, because every row hid behind a
                // kinds check. A plugin row is always useful (name, toggle);
                // only "Add to bar" stays widget-gated.
                readonly property bool rowShown: popup.isBarWidget(pluginRow.modelData)
                  || popup.kindList(pluginRow.modelData).length === 0

                width: body.width
                spacing: Style.spacing.xxs

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm
                  visible: pluginRow.rowShown

                  Column {
                    width: parent.width - pluginToggle.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    BodyText {
                      text: String(pluginRow.modelData.name || pluginRow.modelData.id || "")
                      width: parent.width
                      elide: Text.ElideRight
                    }
                    BodyText {
                      text: String(pluginRow.modelData.id || "") + (pluginRow.listed ? " · on the bar" : "")
                      color: Qt.darker(popup.bar.foreground, 1.45)
                      font.pixelSize: Style.font.caption
                      width: parent.width
                      elide: Text.ElideRight
                    }
                  }

                  ToggleSwitch {
                    id: pluginToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: pluginRow.modelData.enabled === true
                    enabled: pluginRow.modelData.canDisable !== false
                    foreground: popup.bar.foreground
                    onToggled: popup.setEnabled(pluginRow.modelData, pluginRow.modelData.enabled !== true)
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  visible: pluginRow.rowShown && pluginRow.modelData.enabled === true && !pluginRow.listed

                  Button {
                    text: "Add to bar"
                    bordered: true
                    foreground: popup.bar.foreground
                    onClicked: popup.addToBar(pluginRow.modelData)
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.spacing.xs
                  visible: popup.isBarOption(pluginRow.modelData)

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
                    onClicked: popup.useAsBar(pluginRow.modelData)
                  }
                }
              }
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

      // A visible scrollbar for the one shared scroll area: the Widgets
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
      width: parent.width
      visible: popup.tab === "widgets" && popup.plugins.length === 0 && !popup.pluginsLoading
      text: "No plugins reported. Is `omarchy plugin list` available?"
      color: Qt.darker(popup.bar.foreground, 1.45)
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
