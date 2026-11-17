// Keybinds cheatsheet for niri — standalone Quickshell config.
// Launch: qs -c keybinds   (toggle: ~/.config/quickshell/keybinds/toggle.sh)
// Data comes from parse_keybinds.py, which reads ~/.config/niri/modules/keybinds.kdl on every launch.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string fontMono: "JetBrainsMono Nerd Font"
    readonly property color pink: "#ff2d78"
    readonly property color cyan: "#00d4ff"
    readonly property color purple: "#d04dff"
    readonly property color green: "#00ff41"
    readonly property color peach: "#ffb59f"
    readonly property color fg: "#e6e6f0"
    readonly property color dim: "#8a8aa3"

    property var groups: []
    property int total: 0
    property string errorText: ""
    property string query: ""
    property string wantedOutput: Quickshell.env("KB_OUTPUT") || "DP-1"

    readonly property var targetScreen: pickScreen()
    readonly property int screenW: targetScreen ? targetScreen.width : 1920
    readonly property int screenH: targetScreen ? targetScreen.height : 1080
    readonly property int cardW: Math.min(screenW - 60, 1860)
    readonly property int nCols: cardW >= 1700 ? 5 : (cardW >= 1300 ? 4 : 3)
    readonly property var lay: layout(nCols)
    readonly property bool ready: groups.length > 0 || errorText.length > 0

    function pickScreen() {
        const s = Quickshell.screens;
        for (let i = 0; i < s.length; i++) if (s[i].name === wantedOutput) return s[i];
        for (let i = 0; i < s.length; i++) if (s[i].name === "DP-1") return s[i];
        return s.length ? s[0] : null;
    }

    function matches(g, it, q) {
        if (!q) return true;
        const hay = (it.label + " " + g.name + " " + it.action + " " +
                     it.keys.map(k => k.join("+")).join(" ") +
                     (it.disabled ? " desactivado disabled off" : "")).toLowerCase();
        return q.split(/\s+/).every(w => hay.indexOf(w) >= 0);
    }

    // Masonry: drop each filtered group into the currently shortest column.
    function layout(nCols) {
        const q = query.trim().toLowerCase();
        const cols = [], h = [];
        for (let i = 0; i < nCols; i++) { cols.push([]); h.push(0); }
        let shown = 0;
        for (const g of groups) {
            const items = g.items.filter(it => matches(g, it, q));
            if (!items.length) continue;
            shown += items.reduce((a, it) => a + (it.count || it.keys.length), 0);
            let best = 0;
            for (let i = 1; i < nCols; i++) if (h[i] < h[best]) best = i;
            cols[best].push({ name: g.name, color: g.color, items: items });
            h[best] += 1.6 + items.length;
        }
        return { cols: cols, shown: shown };
    }

    Process {
        id: loader
        running: true
        command: ["python3", Qt.resolvedUrl("parse_keybinds.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    root.total = d.total;
                    root.groups = d.groups;
                } catch (e) {
                    root.errorText = "No pude leer keybinds.kdl: " + e;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (this.text.length) { root.errorText = this.text; console.warn(this.text); }
        }
    }

    IpcHandler {
        target: "keybinds"
        function close(): void { Qt.quit(); }
    }

    // Card-sized unanchored overlay (niri centers it). Four dim strips with
    // explicit implicit sizes form a hole around it, so niri only blurs the
    // card and a click outside still closes the cheatsheet.
    readonly property int cardH: Math.max(1, Math.min(root.screenH - 50, header.height + body.contentHeight + 44))
    readonly property int holeX: Math.max(0, Math.floor((root.screenW - root.cardW) / 2))
    readonly property int holeY: Math.max(0, Math.floor((root.screenH - cardH) / 2))
    readonly property int holeY2: Math.max(0, root.screenH - holeY - cardH)

    component DimStrip: PanelWindow {
        screen: root.targetScreen
        visible: root.ready
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "keybinds-cheatsheet-dim"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5) }
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    DimStrip {
        id: dimTop
        anchors { top: true; left: true }
        implicitWidth: root.screenW
        implicitHeight: Math.max(1, root.holeY)
    }
    DimStrip {
        id: dimBottom
        anchors { bottom: true; left: true }
        implicitWidth: root.screenW
        implicitHeight: Math.max(1, root.holeY2)
    }
    DimStrip {
        id: dimLeft
        anchors { top: true; left: true }
        margins { top: root.holeY }
        implicitWidth: Math.max(1, root.holeX)
        implicitHeight: Math.max(1, root.cardH)
    }
    DimStrip {
        id: dimRight
        anchors { top: true; right: true }
        margins { top: root.holeY }
        implicitWidth: Math.max(1, root.screenW - root.holeX - root.cardW)
        implicitHeight: Math.max(1, root.cardH)
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        visible: root.ready
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.cardW
        implicitHeight: root.cardH
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "keybinds-cheatsheet"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) {
            card.opacity = 1;
            card.scale = 1;
            const q = Quickshell.env("KB_QUERY") || "";
            if (q) search.text = q;
            search.forceActiveFocus();
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(10 / 255, 10 / 255, 18 / 255, 0.78)
            border.width: 1
            border.color: Qt.rgba(0, 0.83, 1, 0.35)

            opacity: 0
            scale: 0.97
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // swallow clicks inside the card
            MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }

            // neon top accent line
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
                height: 2; radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.pink }
                    GradientStop { position: 0.5; color: root.purple }
                    GradientStop { position: 1.0; color: root.cyan }
                }
            }

            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                height: 34

                Text {
                    id: title
                    anchors.verticalCenter: parent.verticalCenter
                    text: "<span style='color:" + root.peach + "'>⌨</span>  KEYBINDS <span style='color:" + root.dim + "'>// niri</span>"
                    textFormat: Text.RichText
                    color: root.pink
                    font { family: root.fontMono; pixelSize: 17; bold: true; letterSpacing: 1.5 }
                }

                Rectangle {
                    id: searchBox
                    anchors.centerIn: parent
                    width: Math.min(520, parent.width * 0.4)
                    height: 32; radius: 8
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: search.activeFocus ? root.cyan : Qt.rgba(1, 1, 1, 0.15)
                    Text {
                        id: glass
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: ""; color: root.cyan
                        font { family: root.fontMono; pixelSize: 14 }
                    }
                    TextInput {
                        id: search
                        anchors { left: glass.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        color: root.fg
                        selectionColor: root.purple
                        font { family: root.fontMono; pixelSize: 13 }
                        clip: true
                        onTextChanged: { root.query = text; body.contentY = 0; }
                        Keys.onEscapePressed: { if (text.length) text = ""; else Qt.quit(); }
                        Keys.onDownPressed: body.flick(0, -1200)
                        Keys.onUpPressed: body.flick(0, 1200)
                        Text {
                            anchors.fill: parent
                            visible: !search.text.length
                            text: "buscar atajo, app, tecla…"
                            color: root.dim
                            font: search.font
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: (root.query ? root.lay.shown + " / " : "") + root.total + " atajos   <span style='color:" + root.dim + "'>Esc cierra</span>"
                    textFormat: Text.RichText
                    color: root.green
                    font { family: root.fontMono; pixelSize: 12 }
                }
            }

            Text {
                visible: root.errorText.length > 0
                anchors { top: header.bottom; left: parent.left; margins: 18 }
                text: root.errorText; color: root.pink
                font { family: root.fontMono; pixelSize: 12 }
            }

            Flickable {
                id: body
                anchors { top: header.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                clip: true
                contentHeight: colsRow.height
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: colsRow
                    width: body.width
                    spacing: 12
                    Repeater {
                        model: root.lay.cols
                        Column {
                            id: col
                            required property var modelData
                            width: (colsRow.width - colsRow.spacing * (root.nCols - 1)) / root.nCols
                            spacing: 7
                            Repeater {
                                model: col.modelData
                                Rectangle {
                                    id: grp
                                    required property var modelData
                                    width: col.width
                                    height: grpCol.height + 8
                                    radius: 9
                                    color: Qt.rgba(1, 1, 1, 0.03)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.06)

                                    Column {
                                        id: grpCol
                                        x: 8; y: 4
                                        width: parent.width - 16
                                        spacing: 1
                                        Row {
                                            spacing: 6
                                            height: 18
                                            Rectangle { width: 3; height: 13; radius: 2; color: grp.modelData.color; anchors.verticalCenter: parent.verticalCenter }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: grp.modelData.name.toUpperCase()
                                                color: grp.modelData.color
                                                font { family: root.fontMono; pixelSize: 11; bold: true; letterSpacing: 1 }
                                            }
                                        }
                                        Repeater {
                                            model: grp.modelData.items
                                            Item {
                                                id: rowItem
                                                required property var modelData
                                                width: grpCol.width
                                                height: 16
                                                opacity: rowItem.modelData.disabled ? 0.48 : 1

                                                Text {
                                                    id: icon
                                                    width: 20
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: rowItem.modelData.icon || "›"
                                                    color: rowItem.modelData.color || grp.modelData.color
                                                    horizontalAlignment: Text.AlignHCenter
                                                    font { family: root.fontMono; pixelSize: rowItem.modelData.icon ? 12 : 13; bold: true }
                                                }
                                                Text {
                                                    anchors { left: icon.right; leftMargin: 4; right: keysRow.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                                    text: rowItem.modelData.label
                                                    color: rowItem.modelData.custom ? root.fg : Qt.rgba(0.85, 0.85, 0.92, 0.85)
                                                    elide: Text.ElideRight
                                                    font { family: root.fontMono; pixelSize: 11; bold: rowItem.modelData.custom }
                                                }
                                                Row {
                                                    id: keysRow
                                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                                    spacing: 4
                                                    Text {
                                                        visible: !!rowItem.modelData.disabled
                                                        text: "desactivado"
                                                        color: root.peach
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        font { family: root.fontMono; pixelSize: 8; letterSpacing: 0.4 }
                                                    }
                                                    Repeater {
                                                        model: rowItem.modelData.keys
                                                        Row {
                                                            id: combo
                                                            required property var modelData
                                                            required property int index
                                                            spacing: 2
                                                            Text {
                                                                visible: combo.index > 0
                                                                text: "/"; color: root.dim
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                font { family: root.fontMono; pixelSize: 10 }
                                                            }
                                                            Repeater {
                                                                model: combo.modelData
                                                                Rectangle {
                                                                    id: cap
                                                                    required property string modelData
                                                                    readonly property bool mod: ["Super", "Shift", "Ctrl", "Alt"].indexOf(modelData) >= 0
                                                                    height: 14
                                                                    width: Math.max(14, capText.implicitWidth + 9)
                                                                    radius: 4
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    color: mod ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0.83, 1, 0.12)
                                                                    border.width: 1
                                                                    border.color: mod ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0.83, 1, 0.65)
                                                                    // keycap bottom lip
                                                                    Rectangle {
                                                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2 }
                                                                        height: 1
                                                                        color: Qt.rgba(1, 1, 1, 0.10)
                                                                    }
                                                                    Text {
                                                                        id: capText
                                                                        anchors.centerIn: parent
                                                                        text: cap.modelData
                                                                        color: cap.mod ? Qt.rgba(0.85, 0.85, 0.92, 0.9) : root.cyan
                                                                        font { family: root.fontMono; pixelSize: 9; bold: !cap.mod }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.query.length > 0 && root.lay.shown === 0
                anchors.centerIn: body
                text: "sin resultados para “" + root.query + "”"
                color: root.dim
                font { family: root.fontMono; pixelSize: 14 }
            }
        }
    }
}
