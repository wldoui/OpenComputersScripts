local component = require("component")
local event = require("event")
local computer = require("computer")

local gpu = component.gpu

local WIDTH = 160
local HEIGHT = 50

gpu.setResolution(WIDTH, HEIGHT)

local selected = 1
local running = true
local batteries = {}

local function clear()
    gpu.fill(1, 1, WIDTH, HEIGHT, " ")
end

local function text(x, y, value)
    gpu.set(x, y, tostring(value))
end

local function center(y, value)
    value = tostring(value)

    local x = math.floor((WIDTH - #value) / 2) + 1

    if x < 1 then
        x = 1
    end

    gpu.set(x, y, value)
end

local function separator(y, char)
    char = char or "-"

    gpu.fill(1, y, WIDTH, 1, char)
end

local function formatNumber(number)
    number = math.floor(number or 0)

    local result = tostring(number)

    while true do
        local newResult, count =
            result:gsub("^(-?%d+)(%d%d%d)", "%1 %2")

        result = newResult

        if count == 0 then
            break
        end
    end

    return result
end

local function formatPercent(current, maximum)
    if not maximum or maximum <= 0 then
        return 0
    end

    return current / maximum * 100
end

local function getModeName(mode)
    if mode == 0 then
        return "INPUT"
    elseif mode == 1 then
        return "BUFFER"
    elseif mode == 2 then
        return "OUTPUT"
    end

    return "UNKNOWN"
end

local function getBatteryComponents()
    local result = {}

    for address, componentType in component.list("ntm_energy_storage") do
        local proxy = component.proxy(address)

        table.insert(result, {
            address = address,
            proxy = proxy
        })
    end

    return result
end

local function scan()
    batteries = getBatteryComponents()

    if selected > #batteries then
        selected = #batteries
    end

    if selected < 1 then
        selected = 1
    end
end

local function getBatteryData(battery)
    local proxy = battery.proxy

    local energyInfo = nil
    local modeInfo = nil
    local packInfo = nil

    pcall(function()
        energyInfo = {proxy.getEnergyInfo()}
    end)

    pcall(function()
        modeInfo = {proxy.getModeInfo()}
    end)

    pcall(function()
        packInfo = {proxy.getPackInfo()}
    end)

    local data = {
        current = 0,
        maximum = 0,
        delta = 0,

        modeLow = 0,
        modeHigh = 0,
        priority = 0,

        batteryName = "UNKNOWN",
        chargeRate = 0,
        dischargeRate = 0
    }

    if energyInfo then
        data.current = energyInfo[1] or 0
        data.maximum = energyInfo[2] or 0
        data.delta = energyInfo[3] or 0
    end

    if modeInfo then
        data.modeLow = modeInfo[1] or 0
        data.modeHigh = modeInfo[2] or 0
        data.priority = modeInfo[3] or 0
    end

    if packInfo then
        data.batteryName = packInfo[1] or "EMPTY"
        data.chargeRate = packInfo[2] or 0
        data.dischargeRate = packInfo[3] or 0
    end

    return data
end

local function drawHeader()
    center(
        1,
        "HBM CE ENERGY CONTROL SYSTEM"
    )

    separator(2, "=")

    text(3, 3, "160x50")
    text(130, 3, "OpenComputers / HBM CE")
end

local function drawTotal()
    local totalCurrent = 0
    local totalMaximum = 0
    local totalDelta = 0

    for _, battery in ipairs(batteries) do
        local data = getBatteryData(battery)

        totalCurrent = totalCurrent + data.current
        totalMaximum = totalMaximum + data.maximum
        totalDelta = totalDelta + data.delta
    end

    local percent =
        formatPercent(totalCurrent, totalMaximum)

    text(3, 5, "TOTAL ENERGY")

    text(
        3,
        6,
        formatNumber(totalCurrent)
        .. " / "
        .. formatNumber(totalMaximum)
        .. " HE"
    )

    text(
        55,
        6,
        string.format("%.2f%%", percent)
    )

    local sign = ""

    if totalDelta > 0 then
        sign = "+"
    elseif totalDelta < 0 then
        sign = ""
    end

    text(
        85,
        6,
        sign .. formatNumber(totalDelta) .. " HE/s"
    )

    separator(8)
end

local function drawBatteryList()
    text(3, 9, "ID")
    text(8, 9, "ADDRESS")
    text(47, 9, "ENERGY")
    text(73, 9, "MAX")
    text(99, 9, "PERCENT")
    text(114, 9, "DELTA HE/s")
    text(132, 9, "MODE")

    separator(10)

    local y = 11

    for i, battery in ipairs(batteries) do

        if y > 35 then
            break
        end

        local data = getBatteryData(battery)

        local percent =
            formatPercent(data.current, data.maximum)

        local mode =
            getModeName(data.modeLow)

        local marker = " "

        if i == selected then
            marker = ">"
        end

        text(1, y, marker .. string.format("%02d", i))

        text(
            8,
            y,
            string.sub(battery.address, 1, 34)
        )

        text(
            47,
            y,
            formatNumber(data.current)
        )

        text(
            73,
            y,
            formatNumber(data.maximum)
        )

        text(
            99,
            y,
            string.format("%.1f%%", percent)
        )

        text(
            114,
            y,
            string.format("%+10s",
                formatNumber(data.delta)
            )
        )

        text(
            132,
            y,
            mode
        )

        y = y + 1
    end

    separator(37)
end

local function drawSelected()
    if #batteries == 0 then
        text(
            3,
            39,
            "NO NTM ENERGY STORAGE COMPONENTS FOUND."
        )

        text(
            3,
            41,
            "Connect an HBM energy storage block to the OpenComputers network."
        )

        return
    end

    local battery = batteries[selected]
    local data = getBatteryData(battery)

    text(
        3,
        39,
        "SELECTED BATTERY #" .. selected
    )

    text(
        3,
        40,
        "Address: " .. battery.address
    )

    text(
        3,
        42,
        "Energy: "
        .. formatNumber(data.current)
        .. " / "
        .. formatNumber(data.maximum)
        .. " HE"
    )

    text(
        3,
        43,
        "Flow: "
        .. string.format("%+d", data.delta)
        .. " HE/s"
    )

    text(
        55,
        42,
        "Mode LOW: "
        .. getModeName(data.modeLow)
    )

    text(
        55,
        43,
        "Mode HIGH: "
        .. getModeName(data.modeHigh)
    )

    text(
        105,
        42,
        "Priority: "
        .. tostring(data.priority)
    )

    text(
        105,
        43,
        "Battery: "
        .. tostring(data.batteryName)
    )

    text(
        3,
        45,
        "Charge: "
        .. tostring(data.chargeRate)
        .. " HE/t"
    )

    text(
        55,
        45,
        "Discharge: "
        .. tostring(data.dischargeRate)
        .. " HE/t"
    )
end

local function drawControls()
    separator(47)

    text(
        3,
        48,
        "[R] RESCAN"
    )

    text(
        25,
        48,
        "[1-9] SELECT"
    )

    text(
        50,
        48,
        "[I] INPUT"
    )

    text(
        70,
        48,
        "[B] BUFFER"
    )

    text(
        92,
        48,
        "[O] OUTPUT"
    )

    text(
        115,
        48,
        "[P] PRIORITY"
    )

    text(
        145,
        48,
        "[Q] QUIT"
    )
end

local function draw()
    clear()

    drawHeader()
    drawTotal()
    drawBatteryList()
    drawSelected()
    drawControls()
end

local function setMode(mode)
    if not batteries[selected] then
        return
    end

    local proxy = batteries[selected].proxy

    pcall(function()
        proxy.setModeLow(mode)
        proxy.setModeHigh(mode)
    end)
end

local function cyclePriority()
    if not batteries[selected] then
        return
    end

    local proxy = batteries[selected].proxy
    local data = getBatteryData(batteries[selected])

    local newPriority =
        (data.priority + 1) % 3

    pcall(function()
        proxy.setPriority(newPriority)
    end)
end

scan()

local lastUpdate = 0

while running do

    local currentTime = computer.uptime()

    if currentTime - lastUpdate >= 0.5 then
        scan()
        draw()
        lastUpdate = currentTime
    end

    local eventName, _, char, code =
        event.pull(0.1)

    if eventName == "key_down" then

        if char then

            local key = string.char(char)

            if key == "q" or key == "Q" then
                running = false

            elseif key == "r" or key == "R" then
                scan()

            elseif key >= "1" and key <= "9" then
                local number = tonumber(key)

                if number and number <= #batteries then
                    selected = number
                end

            elseif key == "i" or key == "I" then
                setMode(0)

            elseif key == "b" or key == "B" then
                setMode(1)

            elseif key == "o" or key == "O" then
                setMode(2)

            elseif key == "p" or key == "P" then
                cyclePriority()
            end
        end
    end
end

clear()
center(25, "ENERGY CONTROL SYSTEM STOPPED")