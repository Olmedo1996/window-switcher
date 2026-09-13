pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "WindowModel.js" as WindowModel

// Window Switcher overlay: every open window across all used workspaces, with
// a still/live preview of the highlighted window and icon-only, keyboard
// reachable controls. Summoned with `omarchy-shell shell toggle diego.window-switcher`.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/diego.window-switcher"

  // ---------- settings (read from settings.json on each open) ----------
  property string previewMode: "still"        // still | live | off
  property bool groupByWorkspace: true
  property string rowDensity: "comfortable"   // comfortable | compact
  property string sortMode: "workspace"       // workspace | recency | app
  property bool terminalActivity: true

  // ---------- state ----------
  property bool opened: false
  property bool pendingOpen: false
  property string filterText: ""
  property int selectedIndex: 0
  property string zone: "list"                // list | controls
  property int controlIndex: 0
  property bool cursorActive: false
  property string captureState: "loading"     // loading | ready | error | off

  // [menu]-surface theme tokens.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  readonly property int rowHeight: rowDensity === "compact" ? Style.space(40) : Style.space(52)
  readonly property int iconSize: rowDensity === "compact" ? Style.space(24) : Style.space(30)
  property int cardWidth: Math.min(Style.space(1120), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(660), panel.height - Style.gapsOut * 2)

  // ---------- data ----------
  property var windows: []
  property var windowsByAddress: ({})
  property var terminalInfo: ({})
  property var selectedWindow: null
  property var appIndex: ({})

  ListModel { id: displayModel }

  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var audioStreams: {
    var out = []
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isStream && n.audio
          && (n.isSink === true || String(n.type || "").indexOf("Output") !== -1))
        out.push(n)
    }
    return out
  }
  PwObjectTracker { objects: root.audioStreams }

  // Reusable icon-only button.
  component IconButton: Rectangle {
    id: button
    property string glyph: ""
    property bool destructive: false
    property bool emphasised: false
    signal activated()

    implicitWidth: Style.space(32)
    implicitHeight: Style.space(32)
    radius: root.cornerRadius
    opacity: enabled ? (button.hovered ? 1.0 : 0.88) : 0.35
    color: destructive
           ? Util.alpha(Color.urgent, button.hovered ? 0.22 : 0.12)
           : Util.alpha(root.foreground, button.hovered ? 0.18 : 0.08)
    border.width: button.emphasised ? 0 : 1
    border.color: destructive
                  ? Util.alpha(Color.urgent, 0.5)
                  : Util.alpha(root.border, 0.4)

    readonly property bool hovered: buttonMouse.containsMouse

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: button.destructive ? Color.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.activated()
    }
  }

  // ---------- app library ----------
  function rebuildAppIndex() {
    var index = ({})
    var values = DesktopEntries.applications ? DesktopEntries.applications.values : []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || !entry.id || entry.noDisplay) continue
      var record = { name: String(entry.name || entry.id), icon: String(entry.icon || "") }
      var idKey = WindowModel.normalizeId(entry.id)
      if (index[idKey] === undefined) index[idKey] = record
      var nameKey = WindowModel.key(entry.name)
      if (nameKey && index[nameKey] === undefined) index[nameKey] = record
    }
    root.appIndex = index
  }

  function entryFor(appId) {
    if (!appId) return null
    var idKey = WindowModel.normalizeId(appId)
    if (root.appIndex[idKey]) return root.appIndex[idKey]
    var nameKey = WindowModel.key(appId)
    if (nameKey && root.appIndex[nameKey]) return root.appIndex[nameKey]
    return null
  }

  function resolveApp(appId, classHint) {
    var entry = root.entryFor(appId) || root.entryFor(classHint)
    if (entry)
      return { name: entry.name, iconName: entry.icon || appId || classHint || "" }
    var raw = appId || classHint || ""
    return { name: WindowModel.fallbackName(raw), iconName: raw }
  }

  function iconSource(iconName) {
    var name = String(iconName || "")
    if (!name) return ""
    return Quickshell.iconPath(name, true) || ""
  }

  // ---------- media / audio ----------
  function playerForAddress(address) {
    var w = root.windowsByAddress[address]
    if (!w) return null
    var app = WindowModel.key(w.appId || w.classHint)
    if (!app) return null
    for (var i = 0; i < root.mprisPlayers.length; i++) {
      var p = root.mprisPlayers[i]
      var key = WindowModel.key(p.desktopEntry || p.identity
                        || String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, ""))
      if (!key) continue
      if (key === app || key.indexOf(app) !== -1 || app.indexOf(key) !== -1) return p
    }
    return null
  }

  function windowHasAudio(address) {
    var w = root.windowsByAddress[address]
    if (!w) return false
    var pid = w.pid
    var app = WindowModel.key(w.appId)
    for (var i = 0; i < root.audioStreams.length; i++) {
      var n = root.audioStreams[i]
      var props = (n.ready && n.properties) ? n.properties : {}
      if (pid && Number(props["application.process.id"]) === pid) return true
      var label = WindowModel.key(props["application.name"] || n.description || n.name || "")
      if (app && label
          && (label === app || label.indexOf(app) !== -1 || app.indexOf(label) !== -1))
        return true
    }
    return false
  }

  // ---------- window collection ----------
  function pad4(value) {
    var s = String(value)
    while (s.length < 4) s = "0" + s
    return s
  }

  function windowActivity(w, app) {
    if (root.terminalActivity && WindowModel.isTerminal(w.appId || w.classHint)) {
      var info = root.terminalInfo[w.address]
      if (info && (info.cwd || info.cmd)) {
        var enriched = WindowModel.terminalActivity(info.cwd, info.cmd, root.home, "")
        if (enriched) return enriched
      }
    }
    return WindowModel.activity(w.title, app.name)
  }

  function rebuildWindows() {
    var list = []
    var map = ({})
    var workspaces = Hyprland.workspaces ? Hyprland.workspaces.values : []

    for (var i = 0; i < workspaces.length; i++) {
      var ws = workspaces[i]
      if (!ws || ws.id <= 0) continue // skip special workspaces
      var toplevels = ws.toplevels ? ws.toplevels.values : []
      for (var j = 0; j < toplevels.length; j++) {
        var tl = toplevels[j]
        var wl = tl ? tl.wayland : null
        var ipc = tl ? tl.lastIpcObject : null
        var classHint = ipc ? String(ipc["class"] || "") : ""
        var appId = (wl && wl.appId) || classHint || ""
        var size = (ipc && ipc.size && ipc.size.length === 2) ? ipc.size : null
        var focusHistory = (ipc && ipc.focusHistoryID !== undefined)
                           ? Number(ipc.focusHistoryID) : 9999

        var record = {
          address: String(tl.address || ""),
          appId: appId,
          classHint: classHint,
          title: String((tl.title || (wl && wl.title) || "")),
          workspaceId: ws.id,
          monitorId: (ws.monitor ? ws.monitor.id : -1),
          pid: ipc ? Number(ipc.pid) : 0,
          at: (ipc && ipc.at && ipc.at.length === 2) ? ipc.at : [0, 0],
          focusHistory: focusHistory,
          focused: focusHistory === 0,
          aspect: (size && size[0] > 0 && size[1] > 0) ? (size[0] / size[1]) : (16 / 9),
          toplevel: tl
        }
        list.push(record)
        map[record.address] = record
      }
    }

    root.windows = list
    root.windowsByAddress = map
    root.rebuildDisplay()
  }

  function currentAddress() {
    if (displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count)
      return displayModel.get(root.selectedIndex).address
    return ""
  }

  function rebuildDisplay() {
    var keep = root.currentAddress()
    var query = root.filterText.toLowerCase()
    displayModel.clear()

    var list = root.windows.slice(0)
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var app = root.resolveApp(w.appId, w.classHint)
      w._app = app
      w._activity = root.windowActivity(w, app)
    }

    list.sort(function(a, b) {
      if (root.groupByWorkspace && a.workspaceId !== b.workspaceId)
        return a.workspaceId - b.workspaceId
      if (root.sortMode === "app") {
        var byName = a._app.name.localeCompare(b._app.name)
        if (byName !== 0) return byName
      } else if (root.sortMode === "recency") {
        if (a.focusHistory !== b.focusHistory) return a.focusHistory - b.focusHistory
      }
      if (a.at[1] !== b.at[1]) return a.at[1] - b.at[1]
      return a.at[0] - b.at[0]
    })

    for (var k = 0; k < list.length; k++) {
      var item = list[k]
      var appRef = item._app
      var haystack = (appRef.name + " " + item.title + " " + item.appId).toLowerCase()
      if (query && haystack.indexOf(query) === -1) continue
      displayModel.append({
        address: item.address,
        appId: item.appId,
        appName: appRef.name,
        iconName: appRef.iconName,
        title: item.title,
        activity: item._activity,
        workspaceId: item.workspaceId,
        monitorId: item.monitorId,
        focused: item.focused
      })
    }

    if (displayModel.count === 0) {
      root.selectedIndex = 0
      root.selectedWindow = null
      return
    }

    var index = -1
    if (keep) {
      for (var m = 0; m < displayModel.count; m++) {
        if (displayModel.get(m).address === keep) { index = m; break }
      }
    }
    if (index < 0) index = Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
    root.selectedIndex = index
    root.updateSelectedWindow()
  }

  function updateSelectedWindow() {
    if (displayModel.count === 0) {
      root.selectedWindow = null
      return
    }
    var index = Math.max(0, Math.min(root.selectedIndex, displayModel.count - 1))
    root.selectedIndex = index
    var row = displayModel.get(index)
    root.selectedWindow = root.windowsByAddress[row.address] || null
    root.clampControl()
    Qt.callLater(function() { resultList.positionViewAtIndex(index, ListView.Contain) })
  }

  function selectFocused() {
    if (displayModel.count === 0) { root.updateSelectedWindow(); return }
    var address = ""
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).focused) { address = displayModel.get(i).address; break }
    }
    if (address) {
      for (var j = 0; j < displayModel.count; j++) {
        if (displayModel.get(j).address === address) { root.selectedIndex = j; break }
      }
    }
    root.updateSelectedWindow()
  }

  // ---------- controls (fullscreen + close, icon-only) ----------
  readonly property var controls: {
    var list = []
    if (!root.selectedWindow) return list
    list.push({ id: "fullscreen" })
    list.push({ id: "close" })
    return list
  }
  onControlsChanged: root.clampControl()

  function clampControl() {
    if (root.controls.length === 0) { root.controlIndex = 0; return }
    root.controlIndex = Math.max(0, Math.min(root.controlIndex, root.controls.length - 1))
  }

  function activateControl() {
    if (root.controls.length === 0) return
    var control = root.controls[Math.max(0, Math.min(root.controlIndex, root.controls.length - 1))]
    if (control.id === "fullscreen") root.focusAndFullscreen(root.selectedWindow)
    else if (control.id === "close") root.closeWindow(root.selectedWindow)
  }

  // ---------- lifecycle ----------
  function open(payloadJson) {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.rebuildAppIndex()
    root.filterText = ""
    root.cursorActive = true
    root.zone = "list"
    root.controlIndex = 0
    root.captureState = root.previewMode === "off" ? "off" : "loading"
    root.selectedIndex = 0
    root.rebuildWindows()
    root.selectFocused()

    root.pendingOpen = true
    settingsProbe.running = true
    if (root.terminalActivity) {
      // Wait for the cwd/command scan so terminal rows do not visibly change
      // from the window title to the enriched text after the overlay is up.
      openGuard.restart()
      terminalScan.running = true
    } else {
      root.finalizeOpen()
    }
  }

  function finalizeOpen() {
    if (!root.pendingOpen) return
    root.pendingOpen = false
    openGuard.stop()
    root.selectFocused()
    root.opened = true
    pointerGate.reset()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.pendingOpen = false
  }

  function dismiss() {
    root.opened = false
    root.pendingOpen = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "diego.window-switcher")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function scheduleRefresh() {
    refreshDebounce.restart()
    if (root.terminalActivity) terminalDebounce.restart()
  }

  // ---------- navigation / actions ----------
  function select(delta) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    root.updateSelectedWindow()
  }

  function selectIndex(index) {
    if (displayModel.count === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    root.updateSelectedWindow()
  }

  // Dispatch first, then hide: with keepLoaded false the plugin instance is
  // destroyed by shell.hide(), so any root.* call afterwards would fail.
  function dispatchFocus(w) {
    var address = String(w.address || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    Quickshell.execDetached(["hyprctl", "dispatch",
      "hl.dsp.focus({ window = \"address:" + address + "\" })"])
  }

  function focusWindow(w) {
    if (!w) return
    root.dispatchFocus(w)
    root.dismiss()
  }

  function activateSelected() {
    if (root.selectedWindow) root.focusWindow(root.selectedWindow)
  }

  function focusAndFullscreen(w) {
    if (!w) return
    root.toggleFullscreen(w)
    root.focusWindow(w)
  }

  function closeWindow(w) {
    if (!w || !w.toplevel) return
    var wl = w.toplevel.wayland
    if (wl && typeof wl.close === "function") wl.close()
    else if (typeof w.toplevel.close === "function") w.toplevel.close()
    root.scheduleRefresh()
  }

  function toggleFullscreen(w) {
    if (!w || !w.toplevel) return
    var wl = w.toplevel.wayland
    if (wl && wl.fullscreen !== undefined) wl.fullscreen = !wl.fullscreen
    else if (w.toplevel.fullscreen !== undefined) w.toplevel.fullscreen = !w.toplevel.fullscreen
    root.scheduleRefresh()
  }

  function appendFilter(text) {
    root.filterText = root.filterText + text
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function backspaceFilter() {
    if (root.filterText.length === 0) return
    root.filterText = root.filterText.slice(0, -1)
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  // ---------- reactive refresh while open ----------
  Timer {
    id: refreshDebounce
    interval: 160
    onTriggered: if (root.opened) root.rebuildWindows()
  }

  Timer {
    id: terminalDebounce
    interval: 700
    onTriggered: if (root.opened && root.terminalActivity) terminalScan.running = true
  }

  // Bounds the wait for the terminal scan so a slow /proc read never delays
  // the overlay indefinitely.
  Timer {
    id: openGuard
    interval: 450
    onTriggered: root.finalizeOpen()
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { if (root.opened) root.scheduleRefresh() }
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { if (root.opened) root.scheduleRefresh() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildAppIndex() }
  }

  // ---------- settings probe ----------
  Process {
    id: settingsProbe
    command: ["sh", "-c",
      'f="$HOME/.config/omarchy/plugins/diego.window-switcher/settings.json"; ' +
      '[ -f "$f" ] && [ ! -L "$f" ] && exec timeout 2 head -c 65536 -- "$f"']
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var s = JSON.parse(String(text))
          if (s.preview === "still" || s.preview === "live" || s.preview === "off")
            root.previewMode = s.preview
          if (typeof s.groupByWorkspace === "boolean") root.groupByWorkspace = s.groupByWorkspace
          if (s.rowDensity === "comfortable" || s.rowDensity === "compact")
            root.rowDensity = s.rowDensity
          if (s.sort === "workspace" || s.sort === "recency" || s.sort === "app")
            root.sortMode = s.sort
          if (typeof s.terminalActivity === "boolean") root.terminalActivity = s.terminalActivity
        } catch (e) {}
        root.captureState = root.previewMode === "off" ? "off" : "loading"
        if (root.opened) root.rebuildDisplay()
      }
    }
  }

  // ---------- terminal enrichment (cwd + foreground command) ----------
  Process {
    id: terminalScan
    command: ["bash", root.pluginDir + "/window-scan.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = ({})
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i]) continue
          var parts = lines[i].split("\t")
          if (parts.length < 3) continue
          map[parts[0]] = { cwd: parts[1], cmd: parts[2] }
        }
        root.terminalInfo = map
        if (root.pendingOpen) root.finalizeOpen()
        else if (root.opened) root.rebuildDisplay()
      }
    }
  }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  Component.onCompleted: {
    root.rebuildAppIndex()
    console.log("diego.window-switcher loaded")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "diego-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.zone === "controls") {
              root.zone = "list"
            } else if (root.filterText) {
              root.filterText = ""
              root.selectedIndex = 0
              root.rebuildDisplay()
            } else {
              root.dismiss()
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.zone = root.zone === "list" ? "controls" : "list"
            if (root.zone === "controls") root.controlIndex = 0
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Right) {
            if (root.zone === "list") {
              if (root.controls.length > 0) { root.zone = "controls"; root.controlIndex = 0 }
            } else {
              root.controlIndex = (root.controlIndex + 1) % root.controls.length
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Left) {
            if (root.zone === "controls") {
              if (root.controlIndex <= 0) root.zone = "list"
              else root.controlIndex--
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Up) {
            if (root.zone === "list") root.select(-1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Down) {
            if (root.zone === "list") root.select(1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_PageUp) {
            if (root.zone === "list") root.select(-6)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_PageDown) {
            if (root.zone === "list") root.select(6)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Home) {
            if (root.zone === "list") root.selectIndex(0)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_End) {
            if (root.zone === "list") root.selectIndex(displayModel.count - 1)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.zone === "controls") root.activateControl()
            else root.activateSelected()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Space && root.zone === "list") {
            var w = root.selectedWindow
            var player = w ? root.playerForAddress(w.address) : null
            if (player && (player.trackTitle || player.trackArtist)) {
              player.togglePlaying()
              event.accepted = true
              return
            }
          }
          if (event.key === Qt.Key_Backspace) {
            root.zone = "list"
            root.backspaceFilter()
            event.accepted = true
            return
          }
          if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) {
            root.zone = "list"
            root.filterText = ""
            root.selectedIndex = 0
            root.rebuildDisplay()
            event.accepted = true
            return
          }
          if (event.text && event.text.length === 1
              && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
              && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.zone = "list"
            root.appendFilter(event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ---------------- header / search ----------------
        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText || "Buscar ventanas..."
              color: root.foreground
              opacity: root.filterText ? 1 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
              width: parent.width - counter.width - parent.spacing
            }

            Text {
              id: counter
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: displayModel.count + (displayModel.count === 1 ? " ventana" : " ventanas")
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------------- body ----------------
        Row {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          spacing: 0

          // -------- left: window list --------
          Item {
            width: Math.round(parent.width * 0.46)
            height: parent.height

            ListView {
              id: resultList
              anchors.fill: parent
              anchors.rightMargin: root.contentSpacing
              model: displayModel
              clip: true
              spacing: Style.space(2)
              boundsBehavior: Flickable.StopAtBounds
              section.property: root.groupByWorkspace ? "workspaceId" : ""
              section.criteria: ViewSection.FullString
              section.delegate: Item {
                id: sectionDelegate
                required property string section
                width: ListView.view.width
                height: wsLabel.implicitHeight + Style.space(12)

                Text {
                  id: wsLabel
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(3)
                  textFormat: Text.PlainText
                  text: sectionDelegate.section
                  color: root.selectedText
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Rectangle {
                  anchors.left: wsLabel.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: wsLabel.verticalCenter
                  width: Math.max(0, sectionDelegate.width - wsLabel.width - Style.space(8))
                  height: 1
                  color: Util.alpha(root.border, 0.25)
                }
              }

              delegate: Rectangle {
                id: row
                required property int index
                required property string address
                required property string appName
                required property string iconName
                required property string activity
                required property bool focused

                readonly property bool hasCursor: index === root.selectedIndex

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(3)
                  height: parent.height * 0.55
                  radius: width / 2
                  color: row.focused ? root.selectedText : "transparent"
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(6)
                  anchors.bottomMargin: Style.space(6)
                  spacing: Style.space(10)

                  Item {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                      id: rowIcon
                      anchors.fill: parent
                      source: root.iconSource(row.iconName)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                      visible: status === Image.Ready
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: root.cornerRadius
                      color: Util.alpha(root.selectedText, 0.18)
                      visible: rowIcon.status !== Image.Ready

                      Text {
                        anchors.centerIn: parent
                        text: row.appName.charAt(0).toUpperCase()
                        color: root.selectedText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                      }
                    }
                  }

                  Column {
                    width: parent.width - root.iconSize - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: row.appName
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: row.activity || "—"
                      color: row.hasCursor ? Util.alpha(root.selectedText, 0.75)
                                           : Util.alpha(root.foreground, 0.55)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                  onPositionChanged: function(mouse) {
                    if (!pointerGate.moved(row, mouse)) return
                    root.zone = "list"
                    root.selectIndex(row.index)
                  }
                  onClicked: function(mouse) {
                    root.zone = "list"
                    root.selectIndex(row.index)
                    if (mouse.button === Qt.MiddleButton)
                      root.closeWindow(root.windowsByAddress[row.address])
                    else
                      root.focusWindow(root.windowsByAddress[row.address])
                  }
                }
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(6)
              visible: displayModel.count === 0

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.windows.length === 0 ? "No hay ventanas abiertas"
                                                : "Sin resultados para \"" + root.filterText + "\""
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }
          }

          // -------- divider --------
          Rectangle {
            width: Style.normalBorderWidth
            height: parent.height
            color: Util.alpha(root.border, 0.22)
          }

          // -------- right: detail (top, fixed) + preview (bottom) --------
          Item {
            id: previewPane
            width: parent.width - Math.round(parent.width * 0.46) - Style.normalBorderWidth
            height: parent.height
            clip: true

            readonly property var win: root.selectedWindow
            readonly property var app: win ? root.resolveApp(win.appId, win.classHint) : null
            readonly property var player: win ? root.playerForAddress(win.address) : null
            readonly property bool hasTrack: player !== null
                                               && !!(player.trackTitle || player.trackArtist)
            readonly property bool playing: hasTrack && player.isPlaying === true
            readonly property bool audible: win !== null && !hasTrack
                                              && root.windowHasAudio(win.address)

            Column {
              id: rightColumn
              anchors.fill: parent
              anchors.leftMargin: root.contentSpacing
              anchors.rightMargin: root.contentSpacing
              anchors.topMargin: root.contentSpacing
              anchors.bottomMargin: root.contentSpacing
              spacing: root.contentSpacing

              // -------- detail + media (fixed height, no layout jumps) --------
              Column {
                id: detailBlock
                width: parent.width
                spacing: 0
                visible: previewPane.win !== null

                Row {
                  width: parent.width
                  height: Style.space(46)
                  spacing: Style.space(10)

                  Item {
                    width: Style.space(46)
                    height: Style.space(46)
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                      id: detailIcon
                      anchors.fill: parent
                      source: previewPane.app ? root.iconSource(previewPane.app.iconName) : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                      visible: status === Image.Ready
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: root.cornerRadius
                      color: Util.alpha(root.selectedText, 0.12)
                      visible: detailIcon.status !== Image.Ready

                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: previewPane.app ? previewPane.app.name.charAt(0).toUpperCase() : ""
                        color: root.selectedText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }
                    }
                  }

                  Column {
                    width: parent.width - Style.space(46) - parent.spacing
                            - headerButtons.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: previewPane.app ? previewPane.app.name : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: previewPane.win ? previewPane.win.title : ""
                      color: Util.alpha(root.foreground, 0.65)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }
                  }

                  Row {
                    id: headerButtons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    IconButton {
                      glyph: "\u26F6"
                      onActivated: root.focusAndFullscreen(previewPane.win)
                    }

                    IconButton {
                      glyph: "\u00D7"
                      destructive: true
                      onActivated: root.closeWindow(previewPane.win)
                    }
                  }
                }

                // Media transport: always reserved so switching windows never
                // changes the detail height.
                Item {
                  width: parent.width
                  height: Style.space(38)
                  opacity: previewPane.hasTrack ? 1 : 0
                  enabled: previewPane.hasTrack

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    IconButton {
                      glyph: "\uDB81\uDCAE"
                      enabled: previewPane.player ? previewPane.player.canGoPrevious : false
                      onActivated: if (previewPane.player) previewPane.player.previous()
                    }

                    IconButton {
                      glyph: previewPane.playing ? "\uDB80\uDFE4" : "\uDB81\uDC0A"
                      onActivated: if (previewPane.player) previewPane.player.togglePlaying()
                    }

                    IconButton {
                      glyph: "\uDB81\uDCAD"
                      enabled: previewPane.player ? previewPane.player.canGoNext : false
                      onActivated: if (previewPane.player) previewPane.player.next()
                    }

                    Text {
                      visible: previewPane.hasTrack
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(implicitWidth, previewPane.width - Style.space(160))
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: {
                        if (!previewPane.hasTrack) return ""
                        var title = previewPane.player.trackTitle || ""
                        var artist = previewPane.player.trackArtist || ""
                        return artist && title ? artist + " — " + title : (title || artist)
                      }
                      color: Util.alpha(root.foreground, 0.75)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              // -------- preview (fills the rest) --------
              Item {
                id: previewArea
                width: parent.width
                height: parent.height - detailBlock.height - rightColumn.spacing

                readonly property real capAspect: {
                  if (captureView.sourceSize
                      && captureView.sourceSize.width > 0
                      && captureView.sourceSize.height > 0)
                    return captureView.sourceSize.width / captureView.sourceSize.height
                  return previewPane.win ? previewPane.win.aspect : (16 / 9)
                }

                Item {
                  anchors.centerIn: parent
                  readonly property real maxW: parent.width
                  readonly property real maxH: parent.height
                  readonly property real aspect: previewArea.capAspect
                  width: Math.min(maxW, maxH * aspect)
                  height: width / aspect

                  Rectangle {
                    anchors.fill: parent
                    radius: root.cornerRadius
                    // Opaque so a window we cannot capture never reveals the
                    // desktop behind the overlay.
                    color: Util.alpha(root.background, 1.0)
                    border.color: Util.alpha(root.border, 0.5)
                    border.width: 1
                    clip: true

                    ScreencopyView {
                      id: captureView
                      anchors.fill: parent
                      anchors.margins: 1
                      visible: root.previewMode !== "off" && hasContent
                      live: root.previewMode === "live"
                      paintCursor: false
                      captureSource: (root.opened && root.previewMode !== "off"
                                      && previewPane.win && previewPane.win.toplevel)
                                     ? previewPane.win.toplevel.wayland : null
                      opacity: hasContent ? 1 : 0
                      Behavior on opacity { NumberAnimation { duration: 150 } }

                      onCaptureSourceChanged: {
                        if (!root.opened) return
                        if (root.previewMode === "off" || !previewPane.win) {
                          root.captureState = root.previewMode === "off" ? "off" : "loading"
                          captureTimeout.stop()
                          return
                        }
                        root.captureState = "loading"
                        captureTimeout.restart()
                      }

                      onHasContentChanged: {
                        if (hasContent) {
                          root.captureState = "ready"
                          captureTimeout.stop()
                        }
                      }

                      onStopped: {
                        if (!hasContent) {
                          root.captureState = "error"
                          captureTimeout.stop()
                        }
                      }
                    }

                    Column {
                      anchors.centerIn: parent
                      width: parent.width - Style.space(24)
                      spacing: Style.space(6)
                      visible: root.previewMode === "off"
                               || previewPane.win === null
                               || root.captureState !== "ready"

                      Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Util.alpha(root.foreground, 0.65)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        text: {
                          if (root.previewMode === "off") return "Vista previa desactivada"
                          if (!previewPane.win) return "Selecciona una ventana"
                          if (root.captureState === "error")
                            return "No se puede previsualizar esta ventana\n(permiso o superficie protegida)"
                          return "Cargando vista previa…"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ---------------- footer ----------------
        Text {
          width: parent.width
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          text: "\u2191\u2193 navegar   \u2192 controles   Enter enfocar   Espacio pausar   Esc cerrar"
          color: root.foreground
          opacity: 0.4
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Timer {
    id: captureTimeout
    interval: 1200
    onTriggered: if (!captureView.hasContent) root.captureState = "error"
  }
}
