import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One-click theme stepper.
//
// The whole plugin is a single bar icon: click it and bin/next-theme.sh walks
// one entry forward through `omarchy theme list` (wrapping at the end) and
// applies it. Scrolling steps backwards, which is the only way to undo an
// overshoot without opening the theme switcher.
//
// The icon is the classic contrast circle — an outlined ring whose right half
// is filled solid. A successful change rotates it a half turn, so the light and
// dark halves trade places. That animation is the only feedback this widget
// gives, which is why a failed change rotates it back rather than leaving a
// flip that claims something happened.
//
// Everything here shares one process with the rest of the bar, so each helper
// runs in its own session under an absolute deadline with its output capped at
// the producer, and is reaped on overflow, supersession and destruction.
Panel {
  id: root
  moduleName: "chyld.next-theme"
  ipcTarget: "chyld.next-theme"

  readonly property int sigTerm: 15
  readonly property int sigKill: 9

  // A theme name is one directory name. The helper caps it at 128 bytes; this
  // is the independent UTF-16 ceiling for whatever reaches the bar.
  readonly property int maxNameChars: 128
  readonly property int maxStdoutChars: 512

  // Half-turn accumulator driving the icon's rotation. Kept at 0/180 rather
  // than incrementing forever so the value stays readable while debugging.
  property int flip: 0
  property string currentTheme: ""
  property bool busy: stepProc.running

  property string stepOutput: ""
  property string currentOutput: ""
  property bool stepAborted: false
  property bool currentAborted: false

  // Resolved from this file's own location, so the plugin keeps working under
  // whatever directory name it was installed as.
  function pluginDir() {
    return String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  }

  function helperCommand(mode) {
    return ["/usr/bin/bash", root.pluginDir() + "bin/next-theme.sh", mode]
  }

  // Absolute paths and a fixed PATH, with only the variables `omarchy theme
  // set` genuinely needs carried through: OMARCHY_PATH locates the stock theme
  // tree, and the Wayland/Hyprland handles let it reload the compositor.
  function processEnvironment() {
    var env = { "HOME": Quickshell.env("HOME"), "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8" }
    var names = ["OMARCHY_PATH", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY",
                 "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CONFIG_HOME", "XDG_STATE_HOME",
                 "XDG_CACHE_HOME", "XDG_DATA_HOME", "USER"]
    for (var i = 0; i < names.length; i++) {
      var value = Quickshell.env(names[i])
      if (value) env[names[i]] = value
    }
    return env
  }

  // tooltipText is a host-owned sink this widget cannot pin to Text.PlainText,
  // and theme names arrive from directory names that `omarchy theme install
  // <git-url>` lets a third party choose. Strip markup, C0/C1 controls and bidi
  // overrides, then cap, before any of it reaches the bar.
  function sanitize(value) {
    var text = String(value === undefined || value === null ? "" : value)
    var out = ""
    for (var i = 0; i < text.length && out.length < root.maxNameChars; i++) {
      var code = text.charCodeAt(i)
      // C0 controls, DEL and the C1 range.
      if (code < 0x20 || (code >= 0x7f && code <= 0x9f)) continue
      // Bidi marks, embeddings, overrides and isolates, which can reorder the
      // rest of the tooltip around the name.
      if (code === 0x200e || code === 0x200f) continue
      if (code >= 0x202a && code <= 0x202e) continue
      if (code >= 0x2066 && code <= 0x2069) continue
      // Markup, because tooltipText reaches a host-owned sink this widget
      // cannot pin to Text.PlainText.
      if (code === 0x26 || code === 0x3c || code === 0x3e) continue
      out += text.charAt(i)
    }
    return out.trim()
  }

  function abortProc(proc, deadlineTimer, killTimer) {
    deadlineTimer.stop()
    if (proc && proc.running) {
      proc.signal(root.sigTerm)
      killTimer.restart()
    } else {
      killTimer.stop()
    }
  }

  // Bound the UTF-16 accumulation independently of the helper's own byte cap,
  // in case the helper itself misbehaves.
  function collect(previous, chunk) {
    if (previous.length + chunk.length > root.maxStdoutChars) return null
    return previous + chunk
  }

  function step(backwards) {
    if (root.busy) return
    root.stepOutput = ""
    root.stepAborted = false
    stepProc.command = root.helperCommand(backwards ? "--prev" : "--next")
    stepProc.running = true
    stepDeadline.restart()
    // Flipped optimistically so the icon responds on the click rather than a
    // second later; onExited rotates it back if the change did not take.
    root.flip = root.flip === 0 ? 180 : 0
  }

  function revertFlip() {
    root.flip = root.flip === 0 ? 180 : 0
  }

  function refreshCurrent() {
    if (currentProc.running) return
    root.currentOutput = ""
    root.currentAborted = false
    currentProc.command = root.helperCommand("--current")
    currentProc.running = true
    currentDeadline.restart()
  }

  // The bar snapshots tooltipText by value in its hover-enter handler, so a
  // name that arrives from an async refresh a moment later never reaches a
  // tooltip that is already on screen. Push it in again if we are still hovered.
  function pushTooltip() {
    if (button.tooltipHovered && root.bar && root.bar.showTooltip)
      root.bar.showTooltip(button, button.tooltipText)
  }

  function setCurrent(name) {
    var clean = root.sanitize(name)
    if (clean === "") return
    root.currentTheme = clean
    root.pushTooltip()
  }

  readonly property string panelFontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refreshCurrent()
  onOpenedChanged: if (opened) refreshCurrent()

  // Reap owned descendants rather than leaving them parented to the bar.
  Component.onDestruction: {
    root.abortProc(stepProc, stepDeadline, stepKill)
    root.abortProc(currentProc, currentDeadline, currentKill)
  }

  // Any theme switch reassigns the palette, whoever triggered it — this
  // widget, the theme switcher, tim.theme-rotate, or `omarchy theme set` in a
  // terminal. That makes it the one signal that catches all of them, so the
  // cached name is never stale by the time anyone hovers.
  Connections {
    target: Color
    function onShellValuesChanged() { root.refreshCurrent() }
    function onBackgroundChanged() { root.refreshCurrent() }
  }

  Process {
    id: currentProc
    clearEnvironment: true
    environment: root.processEnvironment()
    command: []
    running: false
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.currentAborted) return
        var next = root.collect(root.currentOutput, chunk)
        if (next === null) {
          root.currentAborted = true
          root.currentOutput = ""
          root.abortProc(currentProc, currentDeadline, currentKill)
          return
        }
        root.currentOutput = next
      }
    }
    // Never forward a helper's diagnostics into the shared shell log.
    stderr: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    onExited: function(exitCode) {
      currentDeadline.stop()
      if (exitCode === 0 && !root.currentAborted) root.setCurrent(root.currentOutput)
      root.currentOutput = ""
    }
  }

  Process {
    id: stepProc
    clearEnvironment: true
    environment: root.processEnvironment()
    command: []
    running: false
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (root.stepAborted) return
        var next = root.collect(root.stepOutput, chunk)
        if (next === null) {
          root.stepAborted = true
          root.stepOutput = ""
          root.abortProc(stepProc, stepDeadline, stepKill)
          return
        }
        root.stepOutput = next
      }
    }
    stderr: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    onExited: function(exitCode) {
      stepDeadline.stop()
      if (exitCode === 0 && !root.stepAborted && root.stepOutput.trim() !== "") {
        root.setCurrent(root.stepOutput)
      } else {
        // Nothing changed, so undo the optimistic half turn rather than let
        // the icon report a switch that never happened.
        root.revertFlip()
        root.refreshCurrent()
      }
      root.stepOutput = ""
    }
  }

  // Absolute deadlines, with KILL escalation kept alive after the leader exits.
  Timer { id: stepDeadline; interval: 95000; onTriggered: root.abortProc(stepProc, stepDeadline, stepKill) }
  Timer { id: stepKill; interval: 2000; onTriggered: if (stepProc.running) stepProc.signal(root.sigKill) }
  Timer { id: currentDeadline; interval: 25000; onTriggered: root.abortProc(currentProc, currentDeadline, currentKill) }
  Timer { id: currentKill; interval: 2000; onTriggered: if (currentProc.running) currentProc.signal(root.sigKill) }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.iconSlot
    tooltipText: root.currentTheme === "" ? "Next Theme" : "Theme: " + root.currentTheme

    // Only the left button opens the popup. WidgetButton reports right and
    // middle clicks through this same signal, and neither should act.
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }

    // Touchpads emit many small deltas per gesture, so accumulate to whole
    // notches the way the built-in volume and brightness widgets do; without
    // this one two-finger scroll is a burst of theme changes.
    property real wheelAccumulator: 0
    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(button.wheelAccumulator, delta)
      button.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.step(wheel.steps < 0)
    }

    onTooltipHoveredChanged: if (tooltipHovered) root.refreshCurrent()

    iconComponent: Component {
      Item {
        id: glyph

        readonly property color ink: button.foreground
        readonly property real diameter: (Math.min(width, height) - 1) * 0.90
        readonly property real stroke: 1.25

        rotation: root.flip
        Behavior on rotation {
          RotationAnimation {
            duration: 520
            direction: RotationAnimation.Clockwise
            easing.type: Easing.InOutCubic
          }
        }

        Rectangle {
          id: ring
          anchors.centerIn: parent
          width: glyph.diameter
          height: glyph.diameter
          radius: width / 2
          color: "transparent"
          border.color: glyph.ink
          border.width: glyph.stroke
          antialiasing: true
        }

        // The filled half. A clip window over the ring's right side, holding a
        // full disc inset by the stroke width — cheaper and crisper at 16px
        // than an arc path, and it keeps the ring unbroken behind the fill.
        Item {
          x: ring.x + ring.width / 2
          y: ring.y
          width: ring.width / 2
          height: ring.height
          clip: true

          Rectangle {
            x: -(ring.width / 2) + glyph.stroke
            y: glyph.stroke
            width: ring.width - glyph.stroke * 2
            height: ring.height - glyph.stroke * 2
            radius: width / 2
            color: glyph.ink
            antialiasing: true
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(260))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "CURRENT THEME"
          foreground: Color.popups.text
          fontFamily: root.panelFontFamily
        }

        // Popup text reads from the popup palette, not the bar's foreground:
        // a theme whose bar sits on the wallpaper can pair a dark bar
        // foreground with a dark popup surface.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.currentTheme === "" ? "—" : root.currentTheme
          color: Color.popups.text
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        PanelSeparator { foreground: Color.popups.text }

        Row {
          id: actions
          width: parent.width
          spacing: Style.space(8)

          Button {
            width: (actions.width - actions.spacing) / 2
            text: "Previous"
            bordered: true
            foreground: Color.popups.text
            accent: Color.accent
            fontFamily: root.panelFontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.step(true)
          }

          Button {
            width: (actions.width - actions.spacing) / 2
            text: "Next"
            bordered: true
            foreground: Color.popups.text
            accent: Color.accent
            fontFamily: root.panelFontFamily
            fontSize: Style.font.bodySmall
            iconSpinning: root.busy
            onClicked: root.step(false)
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Scroll the icon to step without opening this."
          color: Color.popups.text
          opacity: 0.5
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
