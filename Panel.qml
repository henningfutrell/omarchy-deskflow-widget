import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "deskflow"
  ipcTarget: "deskflow"
  manageIpc: false

  // Material "monitor-share" from the theme's Nerd Font, like Bluetooth/Network.
  readonly property string glyph: "󱒃"

  // "header" is the on/off switch; "rows" walks the action list below it.
  property string focusSection: "header"
  property int rowIndex: 0
  property bool cursorActive: false

  readonly property var rows: ["autostart", "settings"]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool inputError: deskflow.active && (deskflow.connectionState === "input-error" || deskflow.connectionState === "server-error")
  readonly property color barIconColor: deskflow.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && deskflow.installed

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) {
        focusSection = "rows"
        rowIndex = 0
      }
      return
    }
    if (dy < 0 && rowIndex === 0) {
      focusSection = "header"
      return
    }
    rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + dy))
  }

  function setRowCursor(index) {
    cursorActive = true
    focusSection = "rows"
    rowIndex = index
  }

  function activateRow(name) {
    if (name === "autostart") deskflow.toggleAutostart()
    else if (name === "settings") {
      deskflow.openSettings()
      root.close()
    }
  }

  function activateCursor() {
    if (focusSection === "header") toggleRunning()
    else activateRow(rows[rowIndex])
  }

  function toggleRunning() {
    if (deskflow.installed && !deskflow.busy) deskflow.toggleRunning()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    rowIndex = 0
    deskflow.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

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
    function status(): string { return deskflow.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: root.barIconColor
    active: root.inputError
    tooltipText: "Deskflow " + deskflow.mode + ": " + deskflow.statusText
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.toggleRunning()
        else if (t === "r" || t === "R") deskflow.refresh()
        else if (t === "a" || t === "A") deskflow.toggleAutostart()
        else if (t === "s" || t === "S") root.activateRow("settings")
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          // The hero's trailingControl resolves `root` to PanelHero, so panel
          // state is reached through `header`.
          readonly property bool ringVisible: root.headerHasCursor
          function focusHero() {
            root.cursorActive = true
            root.focusSection = "header"
          }

          PanelHero {
            id: hero
            width: parent.width
            title: "Deskflow"
            meta: deskflow.installed ? deskflow.statusText : "Deskflow is not installed"
            detail: (deskflow.isServer ? "Server" : "Client") + (deskflow.screenName !== "" ? " · " + deskflow.screenName : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: deskflow.connected ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.glyph
                color: root.inputError ? root.urgent : root.foreground
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
                  text: (deskflow.active ? "Stop Deskflow " : "Start Deskflow ") + deskflow.mode
                  fontFamily: hero.fontFamily
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: deskflow.lastError !== "" || root.inputError
          width: parent.width
          text: deskflow.lastError !== "" ? deskflow.lastError
                : deskflow.isServer ? "Deskflow server failed. Open Pair / settings to check the screen layout."
                : "Deskflow can't inject input. Check that hypr-kdeconnect-portal is running."
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          visible: deskflow.isServer && deskflow.active
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CLIENTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            visible: deskflow.clients.length === 0
            width: parent.width
            text: "No clients connected."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            model: deskflow.clients
            RowLayout {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "󰍹"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                Layout.leftMargin: Style.space(10)
              }

              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: modelData
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          ActionRow {
            rowIndex: 0
            glyph: "󰐥"
            title: "Start on login"
            subtitle: (deskflow.isServer ? "Server" : "Client") + (deskflow.autostart ? " starts with your session" : " starts only when switched on")
            trailing: Component {
              ToggleSwitch {
                checked: deskflow.autostart
                busy: deskflow.busy
                interactive: false
                foreground: root.foreground
              }
            }
          }

          ActionRow {
            rowIndex: 1
            glyph: "󰒓"
            title: "Pair / settings"
            subtitle: deskflow.isServer ? "Open Deskflow to arrange screens and trust clients"
                                 : "Open Deskflow to set the server and trust its fingerprint"
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property int rowIndex: 0
    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property Component trailing: null

    width: parent.width
    hasCursor: root.cursorActive && root.focusSection === "rows" && root.rowIndex === rowIndex
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: deskflow.installed ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: deskflow.installed && !deskflow.busy
      onEntered: root.setRowCursor(actionRow.rowIndex)
      onClicked: root.activateRow(root.rows[actionRow.rowIndex])
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
