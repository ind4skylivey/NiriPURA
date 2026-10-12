--!nonstrict
-- Cyberpunk Network Service v5 - Using noctalia.http with callbacks

local UPDATE_INTERVAL = 5000
local interface = nil
local lastRx = 0
local lastTx = 0
local lastTime = 0

local function detectInterface(callback)
    -- Find default route interface from /proc/net/route
    noctalia.http({ url = "file:///proc/net/route" }, function(res)
        if res.ok and res.body then
            for line in res.body:gmatch("[^\r\n]+") do
                -- Line format: Iface  Destination  Gateway  Flags  RefCnt  Use  Metric  Mask  MTU  Window  IRTT
                -- We want the line where Destination is 00000000 (default route)
                local iface = line:match("^(%w+)%s+00000000")
                if iface and iface ~= "lo" then
                    interface = iface
                    callback(true)
                    return
                end
            end
        end
        -- Could not detect, use fallback
        interface = "enp5s0"
        callback(false)
    end)
end

local function formatSpeed(bps)
    if bps < 0 then bps = 0 end
    if bps < 1024 then return string.format("%.0f B/s", bps)
    elseif bps < 1024*1024 then return string.format("%.1f KB/s", bps/1024)
    else return string.format("%.2f MB/s", bps/(1024*1024)) end
end

local function formatTotal(b)
    if b < 1024 then return string.format("%.0f B", b)
    elseif b < 1024*1024 then return string.format("%.1f KB", b/1024)
    elseif b < 1024*1024*1024 then return string.format("%.2f MB", b/(1024*1024))
    else return string.format("%.2f GB", b/(1024*1024*1024)) end
end

local function fetchStats(rx, tx)
    local connected = (rx + tx) > 0
    local now = os.time()

    if lastTime == 0 then
        lastRx = rx
        lastTx = tx
        lastTime = now
        noctalia.state.set("network.status", connected and "connected" or "disconnected")
        noctalia.state.set("network.interface", interface)
        noctalia.state.set("network.total_rx", formatTotal(rx))
        noctalia.state.set("network.total_tx", formatTotal(tx))
        noctalia.state.set("network.rx_display", "0 B/s")
        noctalia.state.set("network.tx_display", "0 B/s")
        noctalia.state.set("network.tick", now)
        return
    end

    local dt = now - lastTime
    if dt > 0 then
        local rxSpeed = math.max(0, (rx - lastRx) / dt)
        local txSpeed = math.max(0, (tx - lastTx) / dt)
        noctalia.state.set("network.rx_display", formatSpeed(rxSpeed))
        noctalia.state.set("network.tx_display", formatSpeed(txSpeed))
    end

    lastRx = rx
    lastTx = tx
    lastTime = now

    noctalia.state.set("network.status", connected and "connected" or "disconnected")
    noctalia.state.set("network.interface", interface)
    noctalia.state.set("network.total_rx", formatTotal(rx))
    noctalia.state.set("network.total_tx", formatTotal(tx))
    noctalia.state.set("network.tick", now)
end

local function readStats()
    local rxUrl = "file:///sys/class/net/" .. interface .. "/statistics/rx_bytes"
    local txUrl = "file:///sys/class/net/" .. interface .. "/statistics/tx_bytes"

    -- Read rx first, then tx
    noctalia.http({ url = rxUrl }, function(rxRes)
        local rx = 0
        if rxRes.ok then
            rx = tonumber(rxRes.body) or 0
        end

        -- Then read tx
        noctalia.http({ url = txUrl }, function(txRes)
            local tx = 0
            if txRes.ok then
                tx = tonumber(txRes.body) or 0
            end

            -- Calculate and store stats
            fetchStats(rx, tx)
        end)
    end)
end

function update()
    noctalia.setUpdateInterval(UPDATE_INTERVAL)
    if interface then
        readStats()
    end
end

-- Detect interface, then start polling
detectInterface(function(detected)
    if detected then
        print("[cyberpunk-network] Detected interface: " .. interface)
    else
        print("[cyberpunk-network] Using fallback interface: " .. interface)
    end
    -- Initial read after detection
    if interface then
        readStats()
    end
end)
