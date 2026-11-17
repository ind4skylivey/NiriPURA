// ASUS vertical desktop panels — standalone Quickshell config.
// Launch: qs -c asus-panels   (toggle: ~/.config/quickshell/asus-panels/toggle.sh)
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
    readonly property color glass: Qt.rgba(10 / 255, 10 / 255, 18 / 255, 0.78)

    property string wantedOutput: Quickshell.env("ASUS_OUTPUT") || "DP-2"
    readonly property var targetScreen: pickScreen()
    readonly property int screenW: targetScreen ? targetScreen.width : 1080
    readonly property int screenH: targetScreen ? targetScreen.height : 1920
    readonly property int marginX: 18
    readonly property int marginTop: 18
    readonly property int marginBottom: 18
    readonly property int gap: 14
    readonly property int cardW: Math.max(320, screenW - marginX * 2)
    readonly property int innerH: Math.max(200, screenH - marginTop - marginBottom - gap)
    // DL.STREAM crece con su contenido (min 150, tope 45%); EMU.DECK toma el resto
    property real dlContentH: 0
    readonly property int dlMinH: 150
    readonly property int dlMaxH: Math.floor(innerH * 0.45)
    readonly property int dlH: Math.round(Math.max(dlMinH, Math.min(dlMaxH, dlContentH + 64)))
    readonly property int emuH: innerH - dlH

    property var systems: []
    property int totalGames: 0
    property string scanError: ""
    property string scanStatus: "escaneando biblioteca…"
    property bool scanReady: false
    property string query: ""
    property int sysIndex: 0          // 0 = ALL
    property var emuOverride: ({})    // systemId -> label
    property var dl: ({
        qbittorrent: { ok: false, reason: "pending", message: "consultando…", items: [], totals: { count: 0, down_text: "—", up_text: "—" } },
        nicotine: { ok: false, reason: "pending", message: "consultando…", items: [], totals: { count: 0 } }
    })

    readonly property var currentSystem: (sysIndex > 0 && sysIndex <= systems.length) ? systems[sysIndex - 1] : null
    readonly property var visibleGames: buildGames()
    readonly property var currentEmus: currentSystem ? (currentSystem.emulators || []) : []
    readonly property string currentEmuLabel: currentSystem ? (emuOverride[currentSystem.id] || currentSystem.default_emulator || "") : ""

    function pickScreen() {
        const s = Quickshell.screens;
        for (let i = 0; i < s.length; i++) if (s[i].name === wantedOutput) return s[i];
        for (let i = 0; i < s.length; i++) if (s[i].name === "DP-2") return s[i];
        return s.length ? s[0] : null;
    }

    function fileUrl(p) {
        if (!p) return "";
        return "file://" + encodeURI(p);
    }

    function here(name) {
        return Qt.resolvedUrl(name).toString().replace(/^file:\/\//, "");
    }

    function buildGames() {
        const q = query.trim().toLowerCase();
        const words = q ? q.split(/\s+/) : [];
        let list = [];
        if (currentSystem) {
            list = currentSystem.games || [];
        } else {
            for (const s of systems) list = list.concat(s.games || []);
        }
        if (!words.length) return list;
        return list.filter(g => {
            const hay = ((g.name || "") + " " + (g.system || "") + " " + (g.path || "")).toLowerCase();
            return words.every(w => hay.indexOf(w) >= 0);
        });
    }

    function sysColor(i) {
        const c = [root.pink, root.cyan, root.purple, root.green, root.peach];
        return c[i % c.length];
    }

    function launch(game, emuLabel) {
        if (!game || !game.path) return;
        const sys = game.system || (currentSystem ? currentSystem.id : "");
        const emu = emuLabel || (sys && root.emuOverride[sys]) || (currentSystem && currentSystem.id === sys ? root.currentEmuLabel : "") || "";
        launcher.command = ["python3", here("launch_game.py"), "--system", sys, "--rom", game.path, "--emulator", emu];
        launcher.running = false;
        launcher.running = true;
    }

    function setEmu(sysId, label) {
        const next = Object.assign({}, root.emuOverride);
        next[sysId] = label;
        root.emuOverride = next;
    }

    Process {
        id: scanner
        running: true
        command: ["python3", here("scan_esde.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    if (d.error) {
                        root.scanError = d.error;
                        root.scanStatus = "error";
                    } else {
                        root.systems = d.systems || [];
                        root.totalGames = d.total_games || 0;
                        root.scanError = "";
                        root.scanStatus = "";
                    }
                } catch (e) {
                    root.scanError = "No pude leer la biblioteca: " + e;
                }
                root.scanReady = true;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (this.text.length) console.warn(this.text);
        }
    }

    Process {
        id: dlProc
        running: false
        command: ["python3", here("fetch_downloads.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    root.dl = d;
                } catch (e) {
                    console.warn("downloads parse", e);
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!dlProc.running)
                dlProc.running = true;
        }
    }

    Process { id: launcher; running: false }

    IpcHandler {
        target: "asus-panels"
        function close(): void { Qt.quit(); }
    }

    // ------------------------------------------------------------------
    // Shared visual pieces
    // ------------------------------------------------------------------
    component NeonFrame: Item {
        id: frame
        anchors.fill: parent
        property color accent: root.cyan
        // corner brackets
        Repeater {
            model: 4
            Item {
                required property int index
                width: 18; height: 18
                x: index % 2 === 0 ? 6 : parent.width - 24
                y: index < 2 ? 6 : parent.height - 24
                Rectangle { width: 18; height: 2; color: frame.accent; anchors.top: parent.top; anchors.left: index % 2 === 0 ? parent.left : undefined; anchors.right: index % 2 === 1 ? parent.right : undefined }
                Rectangle { width: 2; height: 18; color: frame.accent; anchors.left: index % 2 === 0 ? parent.left : undefined; anchors.right: index % 2 === 1 ? parent.right : undefined; anchors.top: index < 2 ? parent.top : undefined; anchors.bottom: index >= 2 ? parent.bottom : undefined }
            }
        }
    }

    component TextureOverlay: Item {
        anchors.fill: parent
        clip: true
        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("grid.png")
            fillMode: Image.Tile
            opacity: 0.22
            smooth: false
        }
        Image {
            id: scans
            anchors.fill: parent
            source: Qt.resolvedUrl("scanline.png")
            fillMode: Image.Tile
            opacity: 0.16
            smooth: false
            SequentialAnimation on opacity {
                running: true
                loops: Animation.Infinite
                NumberAnimation { to: 0.26; duration: 1800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.10; duration: 1800; easing.type: Easing.InOutSine }
            }
        }
    }

    component GlitchHeader: Item {
        id: gh
        property string tag: "// EMU.DECK"
        property color accent: root.pink
        property string sub: ""
        width: parent.width
        height: 28

        Text {
            id: ghostA
            text: gh.tag
            color: root.cyan
            opacity: 0.35
            font { family: root.fontMono; pixelSize: 16; bold: true; letterSpacing: 1.6 }
            x: 2; y: 1
        }
        Text {
            id: ghostB
            text: gh.tag
            color: root.pink
            opacity: 0.28
            font { family: root.fontMono; pixelSize: 16; bold: true; letterSpacing: 1.6 }
            x: -1; y: -1
        }
        Text {
            id: title
            text: gh.tag
            color: gh.accent
            font { family: root.fontMono; pixelSize: 16; bold: true; letterSpacing: 1.6 }
        }
        Rectangle {
            id: caret
            width: 8; height: 14
            anchors.verticalCenter: title.verticalCenter
            x: title.x + title.width + 6
            color: gh.accent
            SequentialAnimation on opacity {
                running: true
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 280 }
                PauseAnimation { duration: 200 }
                NumberAnimation { to: 1; duration: 80 }
                PauseAnimation { duration: 420 }
            }
        }
        Timer {
            interval: 4200
            running: true
            repeat: true
            onTriggered: {
                ghostA.x = Math.random() > 0.5 ? 3 : -2;
                ghostB.x = Math.random() > 0.5 ? -2 : 2;
                glitchOff.start();
            }
        }
        Timer {
            id: glitchOff
            interval: 90
            onTriggered: { ghostA.x = 2; ghostB.x = -1; }
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: gh.sub
            color: root.dim
            font { family: root.fontMono; pixelSize: 11 }
        }
    }

    component Keycap: Rectangle {
        id: cap
        property string label: ""
        property bool active: false
        property bool enabledCap: true
        property color accent: root.cyan
        signal clicked()
        height: 26
        width: Math.max(36, capLab.implicitWidth + 16)
        radius: 6
        color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.05)
        border.width: 1
        border.color: active ? accent : Qt.rgba(1, 1, 1, 0.14)
        opacity: enabledCap ? 1 : 0.4
        scale: capMouse.containsMouse ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        // keycap top highlight
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 2 }
            height: 8; radius: 4
            color: Qt.rgba(1, 1, 1, cap.active ? 0.10 : 0.06)
        }
        Text {
            id: capLab
            anchors.centerIn: parent
            text: cap.label
            color: cap.active ? cap.accent : root.fg
            font { family: root.fontMono; pixelSize: 10; bold: cap.active }
        }
        MouseArea {
            id: capMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cap.clicked()
        }
        // glow when hovered / active
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: 8
            z: -1
            color: "transparent"
            border.width: 2
            border.color: capMouse.containsMouse || cap.active ? Qt.rgba(accent.r, accent.g, accent.b, 0.35) : "transparent"
        }
    }

    component NeonBar: Item {
        id: bar
        property real progress: 0
        property bool animate: true
        height: 8
        Rectangle {
            anchors.fill: parent
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }
        Rectangle {
            id: fill
            width: Math.max(0, Math.min(1, bar.progress)) * parent.width
            height: parent.height
            radius: 4
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.pink }
                GradientStop { position: 0.5; color: root.purple }
                GradientStop { position: 1.0; color: root.cyan }
            }
            Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
            Rectangle {
                id: shine
                visible: bar.animate && bar.progress > 0 && bar.progress < 0.999
                width: 36; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.40) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on x {
                    running: shine.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -40; to: Math.max(40, fill.width); duration: 1500; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    component GlassCard: Rectangle {
        radius: 12
        color: root.glass
        border.width: 1
        border.color: Qt.rgba(0, 0.83, 1, 0.35)
        clip: true

        // gradient accent line
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
            height: 2; radius: 1; z: 80
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.pink }
                GradientStop { position: 0.5; color: root.purple }
                GradientStop { position: 1.0; color: root.cyan }
            }
        }
        TextureOverlay { z: 0; anchors.fill: parent }
        NeonFrame { z: 70; accent: Qt.rgba(0, 0.83, 1, 0.55) }
    }

    // ------------------------------------------------------------------
    // EMU.DECK  (top)
    // ------------------------------------------------------------------
    PanelWindow {
        id: emuWin
        screen: root.targetScreen
        visible: true
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.emuH
        color: "transparent"
        anchors { top: true; left: true; right: true }
        margins { top: root.marginTop; left: root.marginX; right: root.marginX }
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "asus-panels"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        GlassCard {
            id: emuCard
            anchors.fill: parent

            MouseArea {
                anchors.fill: parent
                onClicked: search.forceActiveFocus()
            }

            GlitchHeader {
                id: emuHead
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 12; leftMargin: 16; rightMargin: 16 }
                tag: "// EMU.DECK"
                accent: root.pink
                sub: root.scanReady ? (root.visibleGames.length + " / " + root.totalGames + " juegos") : "boot…"
            }

            // search
            Rectangle {
                id: searchBox
                anchors { top: emuHead.bottom; topMargin: 10; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                height: 30; radius: 8
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: 1
                border.color: search.activeFocus ? root.cyan : Qt.rgba(1, 1, 1, 0.15)
                z: 20
                Text {
                    id: glassIco
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    text: ""; color: root.cyan
                    font { family: root.fontMono; pixelSize: 13 }
                }
                TextInput {
                    id: search
                    anchors { left: glassIco.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: root.fg
                    selectionColor: root.purple
                    font { family: root.fontMono; pixelSize: 12 }
                    clip: true
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: { if (text.length) text = ""; else search.focus = false; }
                    Text {
                        anchors.fill: parent
                        visible: !search.text.length
                        text: "buscar juego, consola…"
                        color: root.dim
                        font: search.font
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // system chips (wrap so every console stays visible)
            Flow {
                id: sysFlick
                anchors { top: searchBox.bottom; topMargin: 8; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                spacing: 6
                Keycap {
                    label: "ALL"
                    active: root.sysIndex === 0
                    accent: root.peach
                    onClicked: root.sysIndex = 0
                }
                Repeater {
                    model: root.systems
                    Keycap {
                        required property var modelData
                        required property int index
                        label: (modelData.id || "").toUpperCase() + " " + modelData.count
                        active: root.sysIndex === index + 1
                        accent: root.sysColor(index)
                        onClicked: root.sysIndex = index + 1
                    }
                }
            }

            // emulator chips for the selected system
            Flickable {
                id: emuFlick
                visible: root.currentSystem !== null
                anchors { top: sysFlick.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                height: visible ? 28 : 0
                contentWidth: emuRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                Row {
                    id: emuRow
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "EMU"
                        color: root.dim
                        font { family: root.fontMono; pixelSize: 9; letterSpacing: 1 }
                    }
                    Repeater {
                        model: root.currentEmus
                        Keycap {
                            required property var modelData
                            label: modelData.label
                            enabledCap: modelData.available
                            active: root.currentEmuLabel === modelData.label
                            accent: modelData.available ? root.green : root.pink
                            onClicked: if (root.currentSystem) root.setEmu(root.currentSystem.id, modelData.label)
                        }
                    }
                }
            }

            Text {
                id: emuErr
                visible: root.scanError.length > 0
                anchors { top: emuFlick.bottom; topMargin: 12; left: parent.left; leftMargin: 20 }
                text: root.scanError
                color: root.pink
                font { family: root.fontMono; pixelSize: 11 }
                wrapMode: Text.Wrap
                width: parent.width - 40
            }

            Text {
                visible: !root.scanReady && !root.scanError.length
                anchors.centerIn: parent
                text: root.scanStatus
                color: root.cyan
                font { family: root.fontMono; pixelSize: 13 }
            }

            GridView {
                id: grid
                anchors {
                    top: emuFlick.bottom; topMargin: 8
                    left: parent.left; right: parent.right; bottom: emuFoot.top
                    leftMargin: 14; rightMargin: 8; bottomMargin: 4
                }
                visible: root.scanReady
                clip: true
                cellWidth: Math.floor(width / 3)
                cellHeight: 270
                model: root.visibleGames
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 10
                        color: Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.07 : 0.03)
                        border.width: 1
                        border.color: tileMouse.containsMouse ? root.cyan : Qt.rgba(1, 1, 1, 0.08)
                        scale: tileMouse.containsMouse ? 1.03 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        // hover glow
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: 12
                            z: -1
                            color: "transparent"
                            border.width: 2
                            border.color: tileMouse.containsMouse ? Qt.rgba(0, 0.83, 1, 0.45) : "transparent"
                        }

                        Item {
                            id: art
                            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 7 }
                            height: parent.height - 62

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Qt.rgba(8 / 255, 8 / 255, 18 / 255, 0.9)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#1a1024" }
                                    GradientStop { position: 1.0; color: "#0a0a14" }
                                }
                                clip: true

                                Text {
                                    visible: !coverImg.status || coverImg.status !== Image.Ready
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: (cell.modelData.name || "?").split(" ").slice(0, 4).join("\n")
                                    color: root.peach
                                    font { family: root.fontMono; pixelSize: 12; bold: true }
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    opacity: 0.85
                                }
                                Image {
                                    id: coverImg
                                    anchors.fill: parent
                                    source: cell.modelData.cover ? root.fileUrl(cell.modelData.cover) : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: true
                                    visible: status === Image.Ready
                                }
                            }
                        }

                        Text {
                            id: gname
                            anchors { top: art.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                            text: (cell.modelData.favorite ? "★ " : "") + (cell.modelData.name || "")
                            color: cell.modelData.favorite ? root.peach : root.fg
                            font { family: root.fontMono; pixelSize: 11; bold: true }
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Text {
                            anchors { top: gname.bottom; topMargin: 1; left: parent.left; leftMargin: 8 }
                            text: (cell.modelData.system || "").toUpperCase()
                            color: root.dim
                            font { family: root.fontMono; pixelSize: 9; letterSpacing: 1 }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.launch(cell.modelData, "")
                        }
                    }
                }
            }

            Text {
                visible: root.scanReady && root.visibleGames.length === 0 && !root.scanError.length
                anchors.centerIn: parent
                text: root.query.length ? "sin resultados para “" + root.query + "”" : "sin juegos en este sistema"
                color: root.dim
                font { family: root.fontMono; pixelSize: 13 }
                z: 30
            }

            Rectangle {
                id: emuFoot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 26
                color: Qt.rgba(10 / 255, 10 / 255, 18 / 255, 0.82)
                Text {
                    anchors.fill: parent
                    anchors.margins: 4
                    text: "S1B // DP-2   clic lanza · chips EMU cambian el emulador   <span style='color:" + root.dim + "'>no escribe ES-DE</span>"
                    textFormat: Text.RichText
                    color: root.dim
                    font { family: root.fontMono; pixelSize: 9 }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // DL.STREAM  (bottom)
    // ------------------------------------------------------------------
    PanelWindow {
        id: dlWin
        screen: root.targetScreen
        visible: true
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.dlH
        color: "transparent"
        anchors { bottom: true; left: true; right: true }
        margins { bottom: root.marginBottom; left: root.marginX; right: root.marginX }
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "asus-panels"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        GlassCard {
            id: dlCard
            anchors.fill: parent

            GlitchHeader {
                id: dlHead
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 12; leftMargin: 16; rightMargin: 16 }
                tag: "// DL.STREAM"
                accent: root.cyan
                sub: (root.dl.qbittorrent && root.dl.qbittorrent.ok ? root.dl.qbittorrent.totals.down_text : "qBit off") + "   " + (root.dl.nicotine && root.dl.nicotine.ok ? (root.dl.nicotine.totals.count + " nic") : "nic off")
            }

            // scroll indicator (solo si hay overflow)
            Rectangle {
                z: 60
                visible: dlFlick.contentHeight > dlFlick.height + 1
                x: parent.width - 7
                y: dlFlick.y + dlFlick.visibleArea.yPosition * dlFlick.height
                width: 3; radius: 1.5
                height: Math.max(18, dlFlick.visibleArea.heightRatio * dlFlick.height)
                color: root.cyan
                opacity: 0.75
            }

            Flickable {
                id: dlFlick
                anchors { top: dlHead.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 14; rightMargin: 10; bottomMargin: 10 }
                clip: true
                contentHeight: dlCol.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: dlCol
                    width: dlFlick.width - 4
                    onHeightChanged: root.dlContentH = height
                    Component.onCompleted: root.dlContentH = height
                    spacing: 10

                    // ---- qBittorrent ----
                    Rectangle {
                        width: parent.width
                        height: qbitCol.height + 12
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)

                        Column {
                            id: qbitCol
                            width: parent.width - 16
                            x: 8; y: 6
                            spacing: 6

                            Row {
                                spacing: 8
                                width: parent.width
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: (root.dl.qbittorrent && root.dl.qbittorrent.ok) ? root.green : root.pink
                                    SequentialAnimation on opacity {
                                        running: true
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 700 }
                                        NumberAnimation { to: 1; duration: 700 }
                                    }
                                }
                                Text {
                                    text: "QBIT"
                                    color: root.peach
                                    font { family: root.fontMono; pixelSize: 11; bold: true; letterSpacing: 1.2 }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.dl.qbittorrent && root.dl.qbittorrent.ok
                                          ? (root.dl.qbittorrent.totals.count + " activas  ↓ " + root.dl.qbittorrent.totals.down_text + "  ↑ " + root.dl.qbittorrent.totals.up_text)
                                          : "NO CONECTADO"
                                    color: root.dl.qbittorrent && root.dl.qbittorrent.ok ? root.green : root.pink
                                    font { family: root.fontMono; pixelSize: 10 }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: !(root.dl.qbittorrent && root.dl.qbittorrent.ok)
                                width: parent.width
                                text: (root.dl.qbittorrent && root.dl.qbittorrent.message) || "sin datos"
                                color: root.dim
                                wrapMode: Text.WordWrap
                                font { family: root.fontMono; pixelSize: 10 }
                            }
                            Text {
                                visible: root.dl.qbittorrent && root.dl.qbittorrent.ok && root.dl.qbittorrent.items.length === 0
                                text: "sin descargas activas"
                                color: root.dim
                                font { family: root.fontMono; pixelSize: 10 }
                            }

                            Repeater {
                                model: (root.dl.qbittorrent && root.dl.qbittorrent.items) ? root.dl.qbittorrent.items : []
                                Column {
                                    required property var modelData
                                    width: qbitCol.width
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        text: modelData.name || ""
                                        color: root.fg
                                        elide: Text.ElideMiddle
                                        font { family: root.fontMono; pixelSize: 11 }
                                    }
                                    NeonBar { width: parent.width; progress: modelData.progress || 0; animate: (modelData.speed || 0) > 0 }
                                    Text {
                                        width: parent.width
                                        text: Math.round((modelData.progress || 0) * 100) + "%   " + (modelData.speed_text || "—") + "   ETA " + (modelData.eta_text || "—") + "   queda " + (modelData.left_text || "—")
                                        color: root.dim
                                        font { family: root.fontMono; pixelSize: 9 }
                                    }
                                }
                            }
                        }
                    }

                    // ---- Nicotine+ ----
                    Rectangle {
                        width: parent.width
                        height: nicCol.height + 12
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.06)

                        Column {
                            id: nicCol
                            width: parent.width - 16
                            x: 8; y: 6
                            spacing: 6

                            Row {
                                spacing: 8
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: (root.dl.nicotine && root.dl.nicotine.running) ? root.green : root.pink
                                    SequentialAnimation on opacity {
                                        running: true
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 800 }
                                        NumberAnimation { to: 1; duration: 800 }
                                    }
                                }
                                Text {
                                    text: "NICOTINE+"
                                    color: root.purple
                                    font { family: root.fontMono; pixelSize: 11; bold: true; letterSpacing: 1.2 }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.dl.nicotine && root.dl.nicotine.running
                                          ? (root.dl.nicotine.totals.count + " activas")
                                          : "NO CONECTADO"
                                    color: root.dl.nicotine && root.dl.nicotine.running ? root.green : root.pink
                                    font { family: root.fontMono; pixelSize: 10 }
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: !!(root.dl.nicotine && root.dl.nicotine.message)
                                width: parent.width
                                text: (root.dl.nicotine && root.dl.nicotine.message) || ""
                                color: root.dim
                                wrapMode: Text.WordWrap
                                font { family: root.fontMono; pixelSize: 10 }
                            }

                            Repeater {
                                model: (root.dl.nicotine && root.dl.nicotine.items) ? root.dl.nicotine.items : []
                                Column {
                                    required property var modelData
                                    width: nicCol.width
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        text: modelData.name || ""
                                        color: root.fg
                                        elide: Text.ElideMiddle
                                        font { family: root.fontMono; pixelSize: 11 }
                                    }
                                    NeonBar { width: parent.width; progress: modelData.progress || 0; animate: false }
                                    Text {
                                        width: parent.width
                                        text: Math.round((modelData.progress || 0) * 100) + "%   " + (modelData.state || "") + "   queda " + (modelData.left_text || "—")
                                        color: root.dim
                                        font { family: root.fontMono; pixelSize: 9 }
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
