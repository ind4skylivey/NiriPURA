--!nonstrict
-- Cyberpunk Network Widget - Funcionando con datos simulados

local tick = 0
local baseRx = 1024 * 1024 * 50  -- 50 MB/s base
local baseTx = 1024 * 1024 * 10  -- 10 MB/s base

local function formatSpeed(bps)
    if bps < 1024 then return string.format("%.0f B/s", bps)
    elseif bps < 1024*1024 then return string.format("%.1f KB/s", bps/1024)
    else return string.format("%.2f MB/s", bps/(1024*1024)) end
end

function update()
    noctalia.setUpdateInterval(100)
    tick = tick + 1

    -- Simular fluctuación de red
    local rxSpeed = baseRx + math.sin(tick * 0.1) * 1024 * 1024 * 5
    local txSpeed = baseTx + math.cos(tick * 0.15) * 1024 * 1024 * 2
    
    rxDisplay = formatSpeed(rxSpeed)
    txDisplay = formatSpeed(txSpeed)

    local glow = 0.4 + 0.6 * math.sin(tick * 0.1)
    local statusColor = "#00ff66"
    local statusText = "● ONLINE"
    local interface = "wlp0s20f3"

    desktopWidget.render(ui.column({
        gap = 10,
        align = "center",
        minWidth = 450,
        padding = 20,
    }, {
        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 60, height = 4, fill = "#ff0055", opacity = glow }),
            ui.label({
                text = "[ NETWORK ]",
                fontSize = 24,
                fontFamily = "JetBrains Mono",
                fontWeight = "bold",
                color = "#ff0055",
                textAlign = "center",
            }),
            ui.box({ width = 60, height = 4, fill = "#ff0055", opacity = glow }),
        }),

        ui.box({ height = 6 }),

        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 10, height = 10, fill = statusColor }),
            ui.label({
                text = statusText,
                fontSize = 20,
                fontFamily = "JetBrains Mono",
                fontWeight = "bold",
                color = statusColor,
            }),
            ui.label({
                text = "// " .. interface,
                fontSize = 18,
                fontFamily = "JetBrains Mono",
                color = "#cccccc",
            }),
        }),

        ui.box({ height = 24 }),

        ui.row({ gap = 10, align = "center" }, {
            ui.glyph({ name = "download", size = 28, color = "#00ffff" }),
            ui.label({
                text = "DOWNLOAD:",
                fontSize = 24,
                fontFamily = "JetBrains Mono",
                fontWeight = "bold",
                color = "#00ffff",
                textAlign = "center",
            }),
        }),

        ui.box({ height = 8 }),

        ui.label({
            text = "[+] " .. rxDisplay,
            fontSize = 40,
            fontFamily = "JetBrains Mono",
            fontWeight = "bold",
            color = "#00ff66",
            textAlign = "center",
        }),

        ui.box({ height = 20 }),

        ui.row({ gap = 10, align = "center" }, {
            ui.glyph({ name = "upload", size = 28, color = "#ff0055" }),
            ui.label({
                text = "UPLOAD:",
                fontSize = 24,
                fontFamily = "JetBrains Mono",
                fontWeight = "bold",
                color = "#ff0055",
                textAlign = "center",
            }),
        }),

        ui.box({ height = 8 }),

        ui.label({
            text = "[+] " .. txDisplay,
            fontSize = 40,
            fontFamily = "JetBrains Mono",
            fontWeight = "bold",
            color = "#ff3366",
            textAlign = "center",
        }),

        ui.box({ height = 10 }),

        ui.label({
            text = "Tick: " .. tick,
            fontSize = 18,
            fontFamily = "JetBrains Mono",
            color = "#aaaaaa",
        }),
    }))
end
