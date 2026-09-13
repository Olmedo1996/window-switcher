pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "WindowModel.js" as WindowModel

// Window Switcher overlay: a list of every open window across all used
// workspaces, with a live preview of the highlighted window on the right.
// Summoned with `omarchy-shell shell toggle diego.window-switcher`.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  // [menu]-surface theme tokens, matching the clipboard/window-list overlays.
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
  property int rowHeight: Math.max(Style.space(52), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int iconSize: Style.space(32)
  property int cardWidth: Math.min(Style.space(1180), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(690), panel.height - Style.gapsOut * 2)

  // ---------- data ----------
  property var windows: []
  property var windowsByAddress: ({})
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

        var record = {
          address: String(tl.address || ""),
          appId: appId,
          classHint: classHint,
          title: String((tl.title || (wl && wl.title) || "")),
          workspaceId: ws.id,
          monitorId: (ws.monitor ? ws.monitor.id : -1),
          pid: ipc ? Number(ipc.pid) : 0,
          at: (ipc && ipc.at && ipc.at.length === 2) ? ipc.at : [0, 0],
          focused: !!(ipc && ipc.focus),
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
    list.sort(function(a, b) {
      if (a.workspaceId !== b.workspaceId) return a.workspaceId - b.workspaceId
      if (a.at[1] !== b.at[1]) return a.at[1] - b.at[1]
      return a.at[0] - b.at[0]
    })

    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      var app = root.resolveApp(w.appId, w.classHint)
      var haystack = (app.name + " " + w.title + " " + w.appId).toLowerCase()
      if (query && haystack.indexOf(query) === -1) continue
      displayModel.append({
        address: w.address,
        appId: w.appId,
        appName: app.name,
        iconName: app.iconName,
        title: w.title,
        activity: WindowModel.activity(w.title, app.name),
        workspaceId: w.workspaceId,
        monitorId: w.monitorId,
        focused: w.focused
      })
    }

    if (displayModel.count === 0) {
      root.selectedIndex = 0
      root.selectedWindow = null
      return
    }

    var index = -1
    if (keep) {
      for (var k = 0; k < displayModel.count; k++) {
        if (displayModel.get(k).address === keep) { index = k; break }
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
  }

  // ---------- lifecycle ----------
  function open(payloadJson) {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.rebuildAppIndex()
    root.filterText = ""
    root.cursorActive = true
    root.selectedIndex = 0
    root.rebuildWindows()

    // Preselect the focused window when it survived filtering.
    var focusedAddress = ""
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).focused) { focusedAddress = displayModel.get(i).address; break }
    }
    if (focusedAddress) {
      for (var j = 0; j < displayModel.count; j++) {
        if (displayModel.get(j).address === focusedAddress) { root.selectedIndex = j; break }
      }
    }
    root.updateSelectedWindow()

    root.opened = true
    pointerGate.reset()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "diego.window-switcher")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function scheduleRefresh() {
    refreshDebounce.restart()
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

  function hyprDispatch(lua) {
    Quickshell.execDetached(["hyprctl", "dispatch", lua])
  }

  function focusWindow(w) {
    if (!w) return
    var address = String(w.address || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    root.dismiss()
    root.hyprDispatch("hl.dsp.focus({ window = \"address:" + address + "\" })")
  }

  function activateSelected() {
    if (root.selectedWindow) root.focusWindow(root.selectedWindow)
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

  PointerMoveGate { id: pointerGate; referenceItem: card }

  Component.onCompleted: root.rebuildAppIndex()

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
            if (root.filterText) {
              root.filterText = ""
              root.selectedIndex = 0
              root.rebuildDisplay()
            } else {
              root.dismiss()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectIndex(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectIndex(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            root.backspaceFilter()
            event.accepted = true
          } else if (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U) {
            root.filterText = ""
            root.selectedIndex = 0
            root.rebuildDisplay()
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                     && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
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
              opacity: root.filterText ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
              width: parent.width - counter.width - parent.spacing
            }

            Text {
              id: counter
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: displayModel.count + (displayModel.count === 1 ? " ventana" : " ventanas")
              color: root.foreground
              opacity: 0.5
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
            width: Math.round(parent.width * 0.44)
            height: parent.height

            ListView {
              id: resultList
              anchors.fill: parent
              anchors.rightMargin: root.contentSpacing
              model: displayModel
              clip: true
              spacing: Style.space(3)
              boundsBehavior: Flickable.StopAtBounds

              section.property: "workspaceId"
              section.criteria: ViewSection.FullString
              section.delegate: Item {
                id: sectionDelegate
                required property string section
                width: ListView.view.width
                height: wsHeader.implicitHeight + Style.space(12)

                Text {
                  id: wsHeader
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(4)
                  textFormat: Text.PlainText
                  text: "Workspace " + sectionDelegate.section
                  color: root.selectedText
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              delegate: Rectangle {
                id: row
                required property int index
                required property string address
                required property string appId
                required property string appName
                required property string iconName
                required property string title
                required property string activity
                required property bool focused

                readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                readonly property var player: root.playerForAddress(row.address)
                readonly property bool hasTrack: player !== null
                                                     && !!(player.trackTitle || player.trackArtist)
                readonly property bool playing: hasTrack && player.isPlaying === true
                readonly property bool audible: !hasTrack && root.windowHasAudio(row.address)

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"

                Rectangle {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(3)
                  height: parent.height * 0.6
                  radius: width / 2
                  color: root.selectedText
                  visible: row.focused
                }

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(7)
                  anchors.bottomMargin: Style.space(7)
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
                      color: Util.alpha(root.selectedText, 0.2)
                      visible: rowIcon.status !== Image.Ready

                      Text {
                        anchors.centerIn: parent
                        text: row.appName.charAt(0).toUpperCase()
                        color: root.selectedText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                    }
                  }

                  Column {
                    width: parent.width - root.iconSize - parent.spacing - badge.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

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
                                           : Util.alpha(root.foreground, 0.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                    }
                  }

                  Item {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.iconSize
                    height: root.iconSize

                    Text {
                      anchors.centerIn: parent
                      visible: row.hasTrack || row.audible
                      text: row.hasTrack ? (row.playing ? "\uDB81\uDFA4" : "\uDB81\uDF82")
                                         : "\uDB80\uDD3E"
                      color: row.hasTrack && row.playing ? root.selectedText
                                                         : Util.alpha(root.foreground, 0.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        cursorShape: Qt.PointingHandCursor
                        enabled: row.hasTrack
                        onClicked: if (row.player) row.player.togglePlaying()
                      }
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
                    root.selectIndex(row.index)
                  }
                  onClicked: function(mouse) {
                    root.selectIndex(row.index)
                    if (mouse.button === Qt.MiddleButton) {
                      root.closeWindow(root.windowsByAddress[row.address])
                    } else {
                      root.focusWindow(root.windowsByAddress[row.address])
                    }
                  }
                }
              }
            }

            // empty / no-match state
            Column {
              anchors.centerIn: parent
              spacing: Style.space(8)
              visible: displayModel.count === 0

              Text {
                text: "\uDB80\uDFC0"
                color: root.selectedText
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.windows.length === 0 ? "No hay ventanas abiertas"
                                                : "Sin resultados para \"" + root.filterText + "\""
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }
            }
          }

          // -------- divider --------
          Rectangle {
            width: Style.normalBorderWidth
            height: parent.height
            color: Util.alpha(root.border, 0.28)
          }

          // -------- right: live preview --------
          Item {
            id: previewPane
            width: parent.width - Math.round(parent.width * 0.44) - Style.normalBorderWidth
            height: parent.height
            clip: true

            readonly property var win: root.selectedWindow
            readonly property var player: win ? root.playerForAddress(win.address) : null
            readonly property bool hasTrack: player !== null
                                               && !!(player.trackTitle || player.trackArtist)
            readonly property bool playing: hasTrack && player.isPlaying === true

            Column {
              anchors.fill: parent
              anchors.leftMargin: root.contentSpacing
              anchors.rightMargin: root.contentSpacing
              anchors.topMargin: root.contentSpacing
              anchors.bottomMargin: root.contentSpacing
              spacing: root.contentSpacing
              visible: previewPane.win !== null

              Item {
                id: previewFrame
                width: parent.width
                height: Math.min(parent.height - info.height - root.contentSpacing,
                                 width / (previewPane.win ? previewPane.win.aspect : (16 / 9)))
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                  anchors.fill: parent
                  radius: root.cornerRadius
                  color: Qt.darker(root.background, 1.15)
                  border.color: root.border
                  border.width: 1
                  clip: true

                  ScreencopyView {
                    anchors.fill: parent
                    anchors.margins: 1
                    captureSource: (root.opened && previewPane.win && previewPane.win.toplevel)
                                   ? previewPane.win.toplevel.wayland : null
                    live: true
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: !previewPane.win || !previewPane.win.toplevel
                    text: "Sin vista previa"
                    color: Util.alpha(root.foreground, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                }
              }

              Column {
                id: info
                width: parent.width
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(10)

                  Item {
                    width: Style.space(44)
                    height: Style.space(44)
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                      id: bigIcon
                      anchors.fill: parent
                      source: previewPane.win ? root.iconSource(previewPane.win.appId) : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                      visible: status === Image.Ready
                    }

                    Rectangle {
                      anchors.fill: parent
                      radius: root.cornerRadius
                      color: Util.alpha(root.selectedText, 0.12)
                      visible: bigIcon.status !== Image.Ready
                    }
                  }

                  Column {
                    width: parent.width - Style.space(44) - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: previewPane.win
                            ? root.resolveApp(previewPane.win.appId, previewPane.win.classHint).name
                            : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: previewPane.win ? previewPane.win.title : ""
                      color: Util.alpha(root.foreground, 0.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      visible: previewPane.hasTrack
                      text: {
                        if (!previewPane.hasTrack) return ""
                        var t = previewPane.player.trackTitle || ""
                        var a = previewPane.player.trackArtist || ""
                        return a && t ? a + " — " + t : (t || a)
                      }
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Util.alpha(root.border, 0.28)
                }

                Row {
                  spacing: Style.space(8)

                  Rectangle {
                    width: Math.max(Style.space(80), focusLabel.width + Style.space(24))
                    height: Style.space(34)
                    radius: root.cornerRadius
                    color: root.selectedText

                    Text {
                      id: focusLabel
                      anchors.centerIn: parent
                      text: "Enfocar"
                      color: root.background
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.activateSelected()
                    }
                  }

                  Rectangle {
                    width: Math.max(Style.space(80), playLabel.width + Style.space(24))
                    height: Style.space(34)
                    radius: root.cornerRadius
                    visible: previewPane.hasTrack
                    color: Util.alpha(root.selectedText, 0.16)
                    border.color: Util.alpha(root.selectedText, 0.5)
                    border.width: 1

                    Text {
                      id: playLabel
                      anchors.centerIn: parent
                      text: previewPane.playing ? "Pausar" : "Reproducir"
                      color: root.selectedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (previewPane.player) previewPane.player.togglePlaying()
                    }
                  }

                  Rectangle {
                    width: Style.space(34)
                    height: Style.space(34)
                    radius: root.cornerRadius
                    color: Util.alpha(root.foreground, 0.1)

                    Text {
                      anchors.centerIn: parent
                      text: "\u26F6"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleFullscreen(previewPane.win)
                    }
                  }

                  Rectangle {
                    width: Style.space(34)
                    height: Style.space(34)
                    radius: root.cornerRadius
                    color: Util.alpha("#ff5555", 0.2)

                    Text {
                      anchors.centerIn: parent
                      text: "\u00D7"
                      color: "#ff5555"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.closeWindow(previewPane.win)
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: "\u2191\u2193 Navegar   Enter Enfocar   Clic medio Cerrar\nEscribe para filtrar   Esc limpiar / cerrar"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  lineHeight: 1.3
                }
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(8)
              visible: previewPane.win === null

              Text {
                text: "\uDB80\uDFC0"
                color: root.selectedText
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: "Selecciona una ventana para verla en vivo"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
              }
            }
          }
        }
      }
    }
  }
}
