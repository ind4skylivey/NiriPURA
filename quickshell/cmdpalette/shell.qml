// S1B.CMD — standalone Quickshell command palette.
// Launch: qs -c cmdpalette   (toggle: ~/.config/quickshell/cmdpalette/toggle.sh)
// Catalog: commands.toml     runner: run.py
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

    property var commands: []
    property var filtered: []
    property int selected: 0
    property string query: ""
    property string errorText: ""
    property string output: ""
    property string lastName: ""
    property bool running: false
    property bool ready: true
    property bool loaded: commands.length > 0 || errorText.length > 0
    property var pending: null
    property string wantedOutput: Quickshell.env("CP_OUTPUT") || "DP-1"
    property string autoRun: Quickshell.env("CP_AUTORUN") || ""

    readonly property var targetScreen: pickScreen()
    readonly property int screenW: targetScreen ? targetScreen.width : 1920
    readonly property int screenH: targetScreen ? targetScreen.height : 1080
    readonly property bool showOut: output.length > 0 || running
    readonly property int cardW: Math.min(screenW - 60, 820)
    readonly property int cardH: Math.min(screenH - 50, showOut ? 940 : 800)
    readonly property int holeX: Math.max(0, Math.floor((screenW - cardW) / 2))
    readonly property int holeY: Math.max(0, Math.floor((screenH - cardH) / 2))
    readonly property int holeY2: Math.max(0, screenH - holeY - cardH)

    function pickScreen() {
        const s = Quickshell.screens;
        for (let i = 0; i < s.length; i++) if (s[i].name === wantedOutput) return s[i];
        for (let i = 0; i < s.length; i++) if (s[i].name === "DP-1") return s[i];
        return s.length ? s[0] : null;
    }

    function scriptPath(name) {
        let u = Qt.resolvedUrl(name).toString();
        if (u.startsWith("file://")) u = u.slice(7);
        if (u.startsWith("qs:@"))
            u = Quickshell.env("HOME") + "/.config/quickshell/cmdpalette/" + name;
        return u;
    }

    function score(q, c) {
        const hay = (c.name + " " + c.group + " " + c.help + " " + c.id + " " + (c.icon || "")).toLowerCase();
        q = (q || "").trim().toLowerCase();
        if (!q) return 1;
        if (hay.indexOf(q) >= 0) return 200 - hay.indexOf(q);
        const words = q.split(/\s+/);
        if (words.every(w => hay.indexOf(w) >= 0)) return 80;
        let i = 0;
        const t = (c.name + " " + c.group).toLowerCase();
        for (let k = 0; k < t.length && i < q.length; k++) if (t[k] === q[i]) i++;
        return i === q.length ? 20 : 0;
    }

    function rebuild() {
        const q = query;
        let next;
        if (!q.trim()) {
            next = commands.slice();
        } else {
            const scored = [];
            for (const c of commands) {
                const s = score(q, c);
                if (s > 0) scored.push({ c: c, s: s });
            }
            scored.sort((a, b) => b.s - a.s);
            next = scored.map(x => x.c);
        }
        filtered = next;
        if (selected >= next.length) selected = Math.max(0, next.length - 1);
        if (selected < 0) selected = 0;
    }

    function moveSel(delta) {
        if (!filtered.length) return;
        const n = filtered.length;
        selected = (selected + delta + n * 8) % n;
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function current() {
        return (selected >= 0 && selected < filtered.length) ? filtered[selected] : null;
    }

    function requestRun() {
        const c = current();
        if (!c || running) return;
        if (c.confirm || c.danger || c.sudo) {
            pending = c;
            return;
        }
        doRun(c, false);
    }

    function confirmRun() {
        const c = pending;
        if (!c) return;
        pending = null;
        doRun(c, true);
    }

    function cancelPending() {
        pending = null;
    }

    function doRun(c, yes) {
        lastName = c.name;
        output = "";
        running = true;
        const args = ["python3", scriptPath("run.py"), "--run", c.id];
        if (yes) args.push("--yes");
        runner.command = args;
        runner.running = false;
        runner.running = true;
    }

    function onEscape() {
        if (pending) { cancelPending(); return; }
        if (search.text.length) { search.text = ""; return; }
        if (showOut) { output = ""; running = false; return; }
        Qt.quit();
    }

    Process {
        id: loader
        running: true
        command: ["python3", root.scriptPath("run.py"), "--list"]
        stdout: StdioCollector { id: loaderOut }
        stderr: StdioCollector { id: loaderErr }
        onExited: {
            try {
                const d = JSON.parse(loaderOut.text);
                root.commands = d.commands || [];
                root.rebuild();
                const q0 = Quickshell.env("CP_QUERY") || "";
                if (q0) search.text = q0;
                if (root.autoRun.length) {
                    for (let i = 0; i < root.filtered.length; i++) {
                        if (root.filtered[i].id === root.autoRun) {
                            root.selected = i;
                            root.doRun(root.filtered[i], false);
                            break;
                        }
                    }
                }
                if (!root.commands.length && !root.errorText.length)
                    root.errorText = "commands.toml está vacío";
            } catch (e) {
                root.errorText = "No pude leer commands.toml: " + e
                    + (loaderErr.text ? "\n" + loaderErr.text : "");
                console.warn(root.errorText);
            }
        }
    }

    Process {
        id: runner
        stdout: SplitParser {
            onRead: data => { root.output += data + "\n"; }
        }
        stderr: SplitParser {
            onRead: data => { root.output += data + "\n"; }
        }
        onRunningChanged: {
            if (!running) {
                root.running = false;
                if (root.output.length && !root.output.endsWith("\n"))
                    root.output += "\n";
            }
        }
    }

    IpcHandler {
        target: "cmdpalette"
        function close(): void { Qt.quit(); }
    }

    component DimStrip: PanelWindow {
        screen: root.targetScreen
        visible: root.ready
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "cmd-palette-dim"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.5) }
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
    }

    DimStrip {
        anchors { top: true; left: true }
        implicitWidth: root.screenW
        implicitHeight: Math.max(1, root.holeY)
    }
    DimStrip {
        anchors { bottom: true; left: true }
        implicitWidth: root.screenW
        implicitHeight: Math.max(1, root.holeY2)
    }
    DimStrip {
        anchors { top: true; left: true }
        margins { top: root.holeY }
        implicitWidth: Math.max(1, root.holeX)
        implicitHeight: Math.max(1, root.cardH)
    }
    DimStrip {
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
        WlrLayershell.namespace: "cmd-palette"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) {
            card.opacity = 1;
            card.scale = 1;
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

            MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }

            Image {
                anchors.fill: parent
                source: "grid.png"
                fillMode: Image.Tile
                opacity: 0.10
                z: 0
            }
            Image {
                anchors.fill: parent
                source: "scanline.png"
                fillMode: Image.Tile
                opacity: 0.08
                z: 0
            }

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
                height: 2; radius: 1; z: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.pink }
                    GradientStop { position: 0.5; color: root.purple }
                    GradientStop { position: 1.0; color: root.cyan }
                }
            }

            // header
            Item {
                id: header
                z: 2
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                height: 28

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        text: "// S1B.CMD"
                        color: root.pink
                        font { family: root.fontMono; pixelSize: 18; bold: true; letterSpacing: 1.6 }
                    }
                    Text {
                        id: caret
                        text: "▍"
                        color: root.cyan
                        font { family: root.fontMono; pixelSize: 16 }
                        opacity: 1
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 420 }
                            NumberAnimation { to: 1; duration: 420 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "paleta"
                        color: root.dim
                        font { family: root.fontMono; pixelSize: 12 }
                    }
                }

                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: (root.query ? root.filtered.length + " / " : "") + root.commands.length + " cmds"
                    color: root.green
                    font { family: root.fontMono; pixelSize: 12 }
                }
            }

            // search
            Rectangle {
                id: searchBox
                z: 2
                anchors {
                    top: header.bottom; left: parent.left; right: parent.right
                    topMargin: 10; leftMargin: 16; rightMargin: 16
                }
                height: 36; radius: 8
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: search.activeFocus ? root.cyan : Qt.rgba(1, 1, 1, 0.15)

                Text {
                    id: glass
                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    text: ""
                    color: root.cyan
                    font { family: root.fontMono; pixelSize: 14 }
                }
                TextInput {
                    id: search
                    anchors {
                        left: glass.right; leftMargin: 8; right: parent.right; rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    color: root.fg
                    selectionColor: root.purple
                    font { family: root.fontMono; pixelSize: 14 }
                    clip: true
                    focus: true
                    onTextChanged: { root.query = text; root.rebuild(); }
                    Keys.onEscapePressed: root.onEscape()
                    Keys.onDownPressed: root.moveSel(1)
                    Keys.onUpPressed: root.moveSel(-1)
                    Keys.onReturnPressed: {
                        if (root.pending) root.confirmRun();
                        else root.requestRun();
                    }
                    Keys.onEnterPressed: {
                        if (root.pending) root.confirmRun();
                        else root.requestRun();
                    }
                    Text {
                        anchors.fill: parent
                        visible: !search.text.length
                        text: "buscar comando, grupo, acción…"
                        color: root.dim
                        font: search.font
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // confirm banner
            Rectangle {
                id: confirmBar
                z: 2
                anchors {
                    top: searchBox.bottom; left: parent.left; right: parent.right
                    topMargin: root.pending ? 10 : 0; leftMargin: 16; rightMargin: 16
                }
                height: root.pending ? 44 : 0
                visible: height > 0
                radius: 8
                color: Qt.rgba(1, 45 / 255, 120 / 255, 0.18)
                border.width: 1
                border.color: root.pink
                clip: true
                Text {
                    anchors { fill: parent; margins: 10 }
                    text: root.pending
                        ? "⚠  " + root.pending.name + "  ·  Enter confirma, Esc cancela"
                        : ""
                    color: root.peach
                    font { family: root.fontMono; pixelSize: 12; bold: true }
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // list
            ListView {
                id: list
                z: 2
                anchors {
                    top: confirmBar.bottom; left: parent.left; right: parent.right
                    bottom: root.showOut ? resultBox.top : footer.top
                    topMargin: 10; leftMargin: 16; rightMargin: 16; bottomMargin: 8
                }
                clip: true
                model: root.filtered
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.selected

                Text {
                    visible: root.errorText.length > 0
                    anchors.centerIn: parent
                    width: parent.width - 20
                    wrapMode: Text.Wrap
                    text: root.errorText
                    color: root.pink
                    font { family: root.fontMono; pixelSize: 12 }
                }
                Text {
                    visible: root.query.length > 0 && root.filtered.length === 0 && !root.errorText.length
                    anchors.centerIn: parent
                    text: "sin resultados para “" + root.query + "”"
                    color: root.dim
                    font { family: root.fontMono; pixelSize: 13 }
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 52
                    readonly property bool isSel: index === root.selected
                    readonly property bool isDanger: !!modelData.danger

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: row.isSel ? Qt.rgba(0, 0.83, 1, 0.10) : Qt.rgba(1, 1, 1, 0.03)
                        border.width: 1
                        border.color: row.isSel
                            ? (row.isDanger ? root.pink : root.cyan)
                            : Qt.rgba(1, 1, 1, 0.06)

                        Rectangle {
                            visible: row.isSel
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 6 }
                            width: 3; radius: 2
                            color: row.isDanger ? root.pink : root.cyan
                        }

                        // group keycap
                        Rectangle {
                            id: cap
                            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                            width: Math.max(64, capTxt.implicitWidth + 14)
                            height: 20; radius: 4
                            color: Qt.rgba(0, 0, 0, 0.35)
                            border.width: 1
                            border.color: Qt.rgba(208 / 255, 77 / 255, 1, 0.45)
                            Text {
                                id: capTxt
                                anchors.centerIn: parent
                                text: row.modelData.group
                                color: root.purple
                                font { family: root.fontMono; pixelSize: 9; bold: true }
                            }
                        }

                        Text {
                            id: iconTxt
                            anchors { left: cap.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: row.modelData.icon || "󰘳"
                            color: row.isDanger ? root.pink : root.cyan
                            font { family: root.fontMono; pixelSize: 16 }
                            width: 22
                        }

                        Column {
                            anchors {
                                left: iconTxt.right; leftMargin: 8; right: marks.left; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 2
                            Text {
                                text: row.modelData.name
                                color: row.isDanger ? root.pink : root.fg
                                font { family: root.fontMono; pixelSize: 13; bold: row.isSel }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: row.modelData.help
                                color: root.dim
                                font { family: root.fontMono; pixelSize: 10 }
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Row {
                            id: marks
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            Text {
                                visible: !!row.modelData.sudo
                                text: "sudo"
                                color: root.peach
                                font { family: root.fontMono; pixelSize: 9; bold: true }
                            }
                            Text {
                                visible: !!row.modelData.danger
                                text: "peligro"
                                color: root.pink
                                font { family: root.fontMono; pixelSize: 9; bold: true }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selected = row.index;
                                search.forceActiveFocus();
                            }
                            onDoubleClicked: {
                                root.selected = row.index;
                                if (root.pending) root.confirmRun();
                                else root.requestRun();
                            }
                        }
                    }
                }
            }

            // result pane
            Rectangle {
                id: resultBox
                z: 2
                visible: root.showOut
                anchors {
                    left: parent.left; right: parent.right; bottom: footer.top
                    leftMargin: 16; rightMargin: 16; bottomMargin: 6
                }
                height: visible ? Math.max(180, Math.floor(card.height * 0.38)) : 0
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.35)
                border.width: 1
                border.color: Qt.rgba(0, 1, 0.25, 0.28)

                Text {
                    id: outHead
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                    text: "// OUT  " + (root.lastName || "") + (root.running ? "  ·  ejecutando…" : "")
                    color: root.green
                    font { family: root.fontMono; pixelSize: 11; bold: true }
                }

                Flickable {
                    id: outFlick
                    anchors {
                        top: outHead.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                        topMargin: 4; leftMargin: 10; rightMargin: 6; bottomMargin: 8
                    }
                    contentWidth: width
                    contentHeight: outText.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    Text {
                        id: outText
                        width: outFlick.width - 4
                        text: root.output.length ? root.output : (root.running ? "…" : "")
                        color: root.fg
                        font { family: root.fontMono; pixelSize: 11 }
                        wrapMode: Text.WrapAnywhere
                        onTextChanged: {
                            if (outFlick.contentHeight > outFlick.height)
                                outFlick.contentY = outFlick.contentHeight - outFlick.height;
                        }
                    }
                }
            }

            // footer
            Item {
                id: footer
                z: 2
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pending
                        ? "Enter confirma   Esc cancela"
                        : "Enter ejecuta   ↑↓ navega   Esc cierra"
                    color: root.dim
                    font { family: root.fontMono; pixelSize: 10 }
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "edita commands.toml"
                    color: Qt.rgba(0.54, 0.54, 0.64, 0.8)
                    font { family: root.fontMono; pixelSize: 10 }
                }
            }
        }
    }
}
