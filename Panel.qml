import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "deskflow"
  ipcTarget: "deskflow"
  manageIpc: false

  // Material "monitor-share" from the theme's Nerd Font, like Bluetooth/Network.
  readonly property string glyph: "󱒃"
  readonly property var directions: ["above", "below", "left", "right"]

  // The keyboard cursor walks a flat list of whatever rows are on screen;
  // `placeIndex` picks among the direction chips on the "place" row.
  property int focusIndex: 0
  property int placeIndex: 0
  property bool cursorActive: false

  readonly property var focusItems: buildFocusItems()
  readonly property var focusedItem: focusItems.length > 0 ? focusItems[Math.max(0, Math.min(focusIndex, focusItems.length - 1))] : null
  readonly property string focusedKind: cursorActive && focusedItem ? focusedItem.kind : ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: deskflow.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string errorText: deskflow.lastError !== "" ? deskflow.lastError
    : deskflow.connectionState === "input-error" ? "Deskflow can't inject input. Check that hypr-kdeconnect-portal is running."
    : deskflow.failing && deskflow.coreError !== "" ? deskflow.coreError
    : ""

  function buildFocusItems() {
    var items = [{ kind: "header" }]
    if (!deskflow.isServer) items.push({ kind: "server-field" })
    if (deskflow.pendingFingerprint !== "") items.push({ kind: "trust" })
    if (deskflow.isServer && deskflow.unknownClient !== "") items.push({ kind: "place" })
    if (deskflow.isServer) {
      for (var i = 0; i < deskflow.layout.length; i++) items.push({ kind: "screen", name: deskflow.layout[i].name })
    }
    items.push({ kind: "mode" })
    items.push({ kind: "autostart" })
    return items
  }

  function focusIndexOf(kind, name) {
    for (var i = 0; i < focusItems.length; i++) {
      if (focusItems[i].kind === kind && (name === undefined || focusItems[i].name === name)) return i
    }
    return -1
  }

  function hasCursor(kind, name) {
    return focusedKind === kind && (name === undefined || (focusedItem && focusedItem.name === name))
  }

  function setCursor(kind, name) {
    var index = focusIndexOf(kind, name)
    if (index < 0) return
    cursorActive = true
    focusIndex = index
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (focusedKind === "place" && dx !== 0) {
      placeIndex = Math.max(0, Math.min(directions.length - 1, placeIndex + dx))
      return
    }
    if (dy !== 0) focusIndex = Math.max(0, Math.min(focusItems.length - 1, focusIndex + dy))
  }

  function activateCursor() {
    var kind = focusedKind
    if (kind === "header") toggleRunning()
    else if (kind === "server-field") serverField.forceActiveFocus()
    else if (kind === "trust") deskflow.trustPending()
    else if (kind === "place") deskflow.addScreen(deskflow.unknownClient, directions[placeIndex])
    else if (kind === "mode") deskflow.toggleMode()
    else if (kind === "autostart") deskflow.toggleAutostart()
  }

  function removeCursor() {
    if (focusedKind === "screen") deskflow.removeScreen(focusedItem.name)
  }

  function toggleRunning() {
    if (deskflow.installed && !deskflow.busy) deskflow.toggleRunning()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusIndex = 0
    placeIndex = 0
    deskflow.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onFocusItemsChanged: if (focusIndex >= focusItems.length) focusIndex = Math.max(0, focusItems.length - 1)

  Service {
    id: deskflow
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): string { deskflow.start(); return "ok" }
    function stop(): string { deskflow.stop(); return "ok" }
    function toggleRunning(): string { root.toggleRunning(); return "ok" }
    function refresh(): string { deskflow.refresh(); return "ok" }
    function status(): string { return deskflow.mode + ": " + deskflow.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: root.barIconColor
    active: deskflow.failing
    tooltipText: "Deskflow: " + deskflow.statusText
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleRunning()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onDeleteRequested: root.removeCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.toggleRunning()
        else if (t === "r" || t === "R") deskflow.refresh()
        else if (t === "m" || t === "M") deskflow.toggleMode()
        else if (t === "a" || t === "A") deskflow.toggleAutostart()
        else if (t === "x" || t === "X") root.removeCursor()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, so panel
            // state is reached through `header`.
            readonly property bool ringVisible: root.hasCursor("header") && deskflow.installed
            function focusHero() { root.setCursor("header") }

            PanelHero {
              id: hero
              width: parent.width
              title: "Deskflow"
              meta: deskflow.installed ? deskflow.statusText : "Install deskflow to use this widget"
              detail: deskflow.isServer ? "Server" : "Client"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: deskflow.connected ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: root.glyph
                  color: deskflow.failing ? root.urgent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: deskflow.installed
                  checked: deskflow.active
                  busy: deskflow.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: deskflow.active ? "Stop Deskflow" : "Start Deskflow"
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Client: where to connect.
          Column {
            visible: !deskflow.isServer
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "SERVER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: serverField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Server name or IP address"
              hasCursor: root.hasCursor("server-field")
              text: deskflow.host
              onActiveFocusChanged: if (activeFocus) root.setCursor("server-field")
              onAccepted: {
                if (text.trim() !== deskflow.host) deskflow.setServer(text)
                keyCatcher.forceActiveFocus()
              }
              Keys.onEscapePressed: {
                text = deskflow.host
                keyCatcher.forceActiveFocus()
              }
            }
          }

          // Either side: a peer whose fingerprint we don't trust yet.
          Column {
            visible: deskflow.pendingFingerprint !== ""
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: deskflow.isServer ? "NEW CLIENT" : "NEW SERVER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ActionRow {
              kind: "trust"
              glyph: "󰒘"
              title: deskflow.isServer ? "Trust this client" : "Trust this server"
              subtitle: "Only if it matches the fingerprint shown on the other machine"
              onActivated: deskflow.trustPending()
            }

            FingerprintText { text: Model.formatFingerprint(deskflow.pendingFingerprint) }
          }

          // Server: a trusted client that isn't in the layout yet.
          Column {
            visible: deskflow.isServer && deskflow.unknownClient !== ""
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "PLACE " + deskflow.unknownClient.toUpperCase()
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.directions
                PlaceChip {
                  required property var modelData
                  required property int index
                  direction: modelData
                  chipIndex: index
                  width: (parent.width - Style.space(6) * 3) / 4
                }
              }
            }
          }

          // Server: the screen layout.
          Column {
            visible: deskflow.isServer
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "CLIENTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: deskflow.layout.length === 0
              width: parent.width
              text: "Start Deskflow and connect a client to place it here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: deskflow.layout
              ActionRow {
                required property var modelData
                kind: "screen"
                name: modelData.name
                glyph: Model.directionGlyph(modelData.direction)
                title: modelData.name
                subtitle: Model.directionLabel(modelData.direction)
                  + (deskflow.clients.indexOf(modelData.name) >= 0 ? " · connected" : "")
                trailing: Component {
                  PanelActionButton {
                    iconText: "󰆴"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: !deskflow.busy
                    onClicked: deskflow.removeScreen(modelData.name)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            ActionRow {
              kind: "mode"
              glyph: deskflow.isServer ? "󰍹" : "󰌌"
              title: deskflow.isServer ? "Switch to client" : "Switch to server"
              subtitle: deskflow.isServer ? "Use another machine's keyboard and mouse" : "Share this keyboard and mouse"
              onActivated: deskflow.toggleMode()
              trailing: Component {
                Text {
                  text: "󰓡"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                }
              }
            }

            ActionRow {
              kind: "autostart"
              glyph: "󰐥"
              title: "Start on login"
              subtitle: deskflow.autostart ? "Starts with your session" : "Starts only when switched on"
              onActivated: deskflow.toggleAutostart()
              trailing: Component {
                ToggleSwitch {
                  checked: deskflow.autostart
                  busy: deskflow.busy
                  interactive: false
                  foreground: root.foreground
                }
              }
            }
          }

          // What the other machine should see when it asks to trust this one.
          Column {
            visible: deskflow.fingerprint !== ""
            width: parent.width
            spacing: Style.spacing.labelGap

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "This machine · " + deskflow.screenName
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            FingerprintText { text: Model.formatFingerprint(deskflow.fingerprint) }
          }
        }
      }
    }
  }

  component FingerprintText: Text {
    textFormat: Text.PlainText
    width: parent.width
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component PlaceChip: CursorSurface {
    id: chip
    property string direction: ""
    property int chipIndex: 0

    hasCursor: root.hasCursor("place") && root.placeIndex === chipIndex
    foreground: root.foreground
    implicitHeight: chipColumn.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !deskflow.busy
      onEntered: {
        root.setCursor("place")
        root.placeIndex = chip.chipIndex
      }
      onClicked: deskflow.addScreen(deskflow.unknownClient, chip.direction)
    }

    Column {
      id: chipColumn
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Model.directionGlyph(chip.direction)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: chip.direction.charAt(0).toUpperCase() + chip.direction.substring(1)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string kind: ""
    property string name: ""
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property Component trailing: null
    signal activated()

    width: parent.width
    hasCursor: root.hasCursor(kind, name !== "" ? name : undefined)
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: deskflow.installed ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: deskflow.installed && !deskflow.busy
      onEntered: root.setCursor(actionRow.kind, actionRow.name !== "" ? actionRow.name : undefined)
      onClicked: actionRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Loader {
        active: actionRow.trailing !== null
        sourceComponent: actionRow.trailing
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
