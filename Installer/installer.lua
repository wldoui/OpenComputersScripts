-- ================================================================
-- OPEN SPACE CONTROL
-- GitHub Bootstrap Installer
--
-- Minecraft 1.12.2
-- OpenComputers 1.8.9a
--
-- SOURCE:
-- https://github.com/wldoui/OpenComputersScripts/tree/main/Space/oc_space_control
--
-- INSTALLS:
--   /boot.lua
--   /api_inspector.lua
--   /apps/*
--   /data/*
--   /drivers/*
--   /lib/*
--
-- REQUIREMENTS:
--   Internet Card
--   writable filesystem
--
-- USAGE:
--   install.lua
-- ================================================================

local component = require("component")
local computer = require("computer")
local term = require("term")
local filesystem = require("filesystem")

local internet = nil

-- ================================================================
-- CONFIG
-- ================================================================

local API_BASE =
    "https://api.github.com/repos/wldoui/OpenComputersScripts/contents/Space/oc_space_control"

local RAW_BASE =
    "https://raw.githubusercontent.com/wldoui/OpenComputersScripts/main/Space/oc_space_control"

local INSTALL_ROOT = "/"

local VERSION_FILE = "/.open_space_control"

-- Files/directories we expect from the repository.
local EXPECTED = {
    "boot.lua",
    "api_inspector.lua",
    "apps",
    "data",
    "drivers",
    "lib"
}

-- ================================================================
-- UI
-- ================================================================

local function line()
    print("------------------------------------------------------------")
end

local function title()
    term.clear()

    print("============================================================")
    print("              OPEN SPACE CONTROL INSTALLER")
    print("============================================================")
    print("")
    print("Repository:")
    print("wldoui/OpenComputersScripts")
    print("")
    print("Path:")
    print("Space/oc_space_control")
    print("")
end

local function ok(message)
    print("[OK] " .. message)
end

local function warn(message)
    print("[WARN] " .. message)
end

local function fail(message)
    print("[ERROR] " .. message)
end

-- ================================================================
-- INTERNET
-- ================================================================

local function findInternet()
    if component.isAvailable("internet") then
        local address = component.list("internet")()

        if address then
            local success, proxy = pcall(component.proxy, address)

            if success and proxy then
                internet = proxy
                return true
            end
        end
    end

    return false
end

-- ================================================================
-- HTTP GET
-- ================================================================

local function httpGet(url)
    if not internet then
        return nil, "Internet component unavailable"
    end

    local success, handle = pcall(internet.request, url)

    if not success then
        return nil, tostring(handle)
    end

    if not handle then
        return nil, "internet.request returned nil"
    end

    local chunks = {}

    while true do
        local successRead, data = pcall(handle.read, handle, 4096)

        if not successRead then
            return nil, tostring(data)
        end

        if not data then
            break
        end

        chunks[#chunks + 1] = data
    end

    pcall(handle.close, handle)

    return table.concat(chunks)
end

-- ================================================================
-- JSON
-- ================================================================

local serialization = nil

do
    local success, result = pcall(require, "serialization")

    if success then
        serialization = result
    end
end

local function decodeJSON(data)
    if not serialization then
        return nil, "serialization library unavailable"
    end

    local success, result = pcall(serialization.unserialize, data)

    if not success then
        return nil, tostring(result)
    end

    return result
end

-- ================================================================
-- FILESYSTEM
-- ================================================================

local function ensureDirectory(path)
    if filesystem.exists(path) then
        if filesystem.isDirectory(path) then
            return true
        end

        return false, "Path exists but is not a directory: " .. path
    end

    local success, err = pcall(filesystem.makeDirectory, path)

    if not success then
        return false, tostring(err)
    end

    return filesystem.exists(path)
end

local function writeFile(path, data)
    local directory = filesystem.path(path)

    local success, err = ensureDirectory(directory)

    if not success then
        return false, err
    end

    local handle, openError = io.open(path, "w")

    if not handle then
        return false, tostring(openError)
    end

    local writeSuccess, writeError =
        pcall(function()
            handle:write(data)
        end)

    handle:close()

    if not writeSuccess then
        return false, tostring(writeError)
    end

    return true
end

-- ================================================================
-- DIRECTORY CREATION
-- ================================================================

local function createBaseDirectories()
    print("Creating directory structure...")
    print("")

    local directories = {
        "/apps",
        "/data",
        "/drivers",
        "/lib"
    }

    for _, directory in ipairs(directories) do
        local success, err = ensureDirectory(directory)

        if success then
            ok(directory)
        else
            fail(directory .. " -> " .. tostring(err))
            return false
        end
    end

    print("")

    return true
end

-- ================================================================
-- GITHUB DIRECTORY LISTING
-- ================================================================

local function getDirectory(path)
    local url = API_BASE

    if path and path ~= "" then
        url = url .. "/" .. path
    end

    local data, err = httpGet(url)

    if not data then
        return nil, err
    end

    local decoded, decodeError = decodeJSON(data)

    if not decoded then
        return nil, decodeError
    end

    return decoded
end

-- ================================================================
-- FILE DOWNLOAD
-- ================================================================

local function downloadFile(relativePath)
    local url = RAW_BASE .. "/" .. relativePath

    print("")
    print("Downloading:")
    print("  " .. relativePath)

    local data, err = httpGet(url)

    if not data then
        fail(relativePath)
        print("  " .. tostring(err))
        return false
    end

    local destination = "/" .. relativePath

    local success, writeError =
        writeFile(destination, data)

    if not success then
        fail(relativePath)
        print("  " .. tostring(writeError))
        return false
    end

    ok(relativePath)

    return true
end

-- ================================================================
-- RECURSIVE REPOSITORY INSTALL
-- ================================================================

local installedFiles = 0
local failedFiles = 0

local function installDirectory(relativePath)
    local entries, err = getDirectory(relativePath)

    if not entries then
        fail("Cannot read GitHub directory: " ..
            tostring(relativePath))

        print("Reason: " .. tostring(err))

        return false
    end

    if type(entries) ~= "table" then
        fail("GitHub returned invalid directory data")

        return false
    end

    for _, entry in ipairs(entries) do

        if entry.type == "dir" then

            local childPath

            if relativePath == "" then
                childPath = entry.name
            else
                childPath =
                    relativePath .. "/" .. entry.name
            end

            local localDirectory =
                "/" .. childPath

            local success, directoryError =
                ensureDirectory(localDirectory)

            if not success then
                fail(
                    "Cannot create " ..
                    localDirectory ..
                    ": " ..
                    tostring(directoryError)
                )

                return false
            end

            print("")
            print("[DIR] " .. localDirectory)

            local recursiveSuccess =
                installDirectory(childPath)

            if not recursiveSuccess then
                return false
            end

        elseif entry.type == "file" then

            local childPath

            if relativePath == "" then
                childPath = entry.name
            else
                childPath =
                    relativePath .. "/" .. entry.name
            end

            if downloadFile(childPath) then
                installedFiles =
                    installedFiles + 1
            else
                failedFiles =
                    failedFiles + 1
            end
        end
    end

    return true
end

-- ================================================================
-- VERSION INFORMATION
-- ================================================================

local function writeVersionFile()
    local content =
        "OPEN SPACE CONTROL\n" ..
        "Repository: wldoui/OpenComputersScripts\n" ..
        "Path: Space/oc_space_control\n" ..
        "Branch: main\n" ..
        "Installed: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"

    writeFile(VERSION_FILE, content)
end

-- ================================================================
-- VERIFY INSTALLATION
-- ================================================================

local function verifyInstallation()
    print("")
    line()
    print("VERIFYING INSTALLATION")
    line()
    print("")

    local requiredFiles = {
        "/boot.lua",
        "/api_inspector.lua"
    }

    local requiredDirectories = {
        "/apps",
        "/data",
        "/drivers",
        "/lib"
    }

    local valid = true

    for _, path in ipairs(requiredFiles) do
        if filesystem.exists(path) then
            ok(path)
        else
            fail(path .. " is missing")
            valid = false
        end
    end

    for _, path in ipairs(requiredDirectories) do
        if filesystem.exists(path) and filesystem.isDirectory(path) then
            ok(path)
        else
            fail(path .. " is missing")
            valid = false
        end
    end

    return valid
end

-- ================================================================
-- MAIN
-- ================================================================

local function main()

    title()

    -- ------------------------------------------------------------
    -- Filesystem
    -- ------------------------------------------------------------

    print("Checking filesystem...")

    if not filesystem.isReadOnly() then
        ok("Filesystem is writable")
    else
        fail("Filesystem is READ-ONLY")
        print("")
        print("Install OpenOS onto a writable disk first.")
        return
    end

    print("")

    -- ------------------------------------------------------------
    -- Internet
    -- ------------------------------------------------------------

    print("Checking Internet Card...")

    if findInternet() then
        ok("Internet Card detected")
    else
        fail("Internet Card not detected")
        print("")
        print("Install an Internet Card into the computer.")
        print("Then connect it to the computer/network as required.")
        return
    end

    print("")

    -- ------------------------------------------------------------
    -- GitHub connection
    -- ------------------------------------------------------------

    print("Testing GitHub connection...")
    print("")

    local testData, testError =
        httpGet(API_BASE)

    if not testData then
        fail("GitHub connection failed")
        print("")
        print(tostring(testError))
        return
    end

    ok("GitHub reachable")

    -- Make sure response can actually be decoded.
    local decoded, decodeError =
        decodeJSON(testData)

    if not decoded then
        fail("GitHub API response could not be parsed")
        print("")
        print(tostring(decodeError))
        return
    end

    ok("GitHub API response valid")

    print("")

    -- ------------------------------------------------------------
    -- Directories
    -- ------------------------------------------------------------

    if not createBaseDirectories() then
        return
    end

    -- ------------------------------------------------------------
    -- Installation
    -- ------------------------------------------------------------

    line()
    print("DOWNLOADING OPEN SPACE CONTROL")
    line()
    print("")

    print("Source:")
    print(API_BASE)
    print("")

    local success =
        installDirectory("")

    if not success then
        print("")
        fail("Installation encountered a fatal error")
        return
    end

    -- ------------------------------------------------------------
    -- Version
    -- ------------------------------------------------------------

    writeVersionFile()

    -- ------------------------------------------------------------
    -- Verification
    -- ------------------------------------------------------------

    local verified =
        verifyInstallation()

    print("")
    line()
    print("INSTALLATION RESULT")
    line()
    print("")

    print("Files installed: " .. tostring(installedFiles))
    print("Files failed:    " .. tostring(failedFiles))
    print("")

    if not verified or failedFiles > 0 then
        fail("Installation is incomplete.")
        print("")
        print("DO NOT start OPEN SPACE CONTROL yet.")
        return
    end

    print("============================================================")
    print(" INSTALLATION COMPLETE")
    print("============================================================")
    print("")
    print("Installed:")
    print("  /boot.lua")
    print("  /api_inspector.lua")
    print("  /apps/")
    print("  /data/")
    print("  /drivers/")
    print("  /lib/")
    print("")
    print("Run:")
    print("")
    print("  boot.lua")
    print("")
    print("or:")
    print("")
    print("  /boot.lua")
    print("")

    -- ------------------------------------------------------------
    -- Ask whether to start
    -- ------------------------------------------------------------

    term.write("Start OPEN SPACE CONTROL now? [Y/n] ")

    local answer = term.read()

    if answer then
        answer =
            answer:gsub("%s+", ""):lower()
    else
        answer = ""
    end

    if answer == "" or answer == "y" or answer == "yes" then

        print("")
        print("Starting OPEN SPACE CONTROL...")
        print("")

        local successBoot, bootError =
            pcall(dofile, "/boot.lua")

        if not successBoot then
            print("")
            fail("boot.lua crashed")
            print(tostring(bootError))
        end

    else

        print("")
        print("Installation finished.")
        print("Run /boot.lua when ready.")
    end
end

main()