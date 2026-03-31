local RESOURCE = GetCurrentResourceName()
local TAG = ("[%s] "):format(RESOURCE)

local CFG = Config or {}
local PTFX_CFG = CFG.Ptfx or {}
local RING_CFG = CFG.Ring or {}
local WAVE_CFG = CFG.Wave or {}

local PTFX_DICT = PTFX_CFG.dict or "anm_water"
local PTFX_NAME = PTFX_CFG.name or "ent_anim_ped_water_wade_ripples"
local OFFSET = PTFX_CFG.offset or { x = 0.0, y = 0.0, z = -0.45 }
local ROT = PTFX_CFG.rotation or { x = 0.0, y = 0.0, z = 0.0 }
local AXIS = PTFX_CFG.axis or { x = 0, y = 0, z = 0 }
local USE_BONE = PTFX_CFG.useBone == true
local BONE_INDEX = PTFX_CFG.boneIndex or 21030
local ASSET_LOAD_TIMEOUT_MS = PTFX_CFG.assetLoadTimeoutMs or 3000

local AFTERBURN_MS = RING_CFG.afterburnMs or 1600
local FADE_BANDS = math.max(1, tonumber(RING_CFG.fadeBands) or 8)
local FADE_STAGGER_MS = math.max(0, tonumber(RING_CFG.fadeStaggerMs) or 80)
local FADE_LIFE_MS = math.max(1, tonumber(RING_CFG.fadeLifeMs) or 1600)
local FADE_START_ALPHA = tonumber(RING_CFG.startAlpha) or 1.0

local SCALE_BASE_METERS = tonumber(CFG.ScaleBaseMeters) or 1.0
local VISUAL_SCALE_FACTOR = tonumber(CFG.VisualScaleFactor) or 10.0
local MIN_SCALE_MULTIPLIER = tonumber(CFG.MinScaleMultiplier) or 1.0
local MAX_SCALE_MULTIPLIER = tonumber(CFG.MaxScaleMultiplier) or 1.0

local RANGES = CFG.VoiceRanges or { 3.0, 8.0, 15.0, 32.0 }
table.sort(RANGES, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)

local ENABLE_PERSISTENT_MODE = CFG.EnablePersistentMode ~= false
local PERSIST_TOGGLE_KEY = CFG.PersistToggleKey
local PERSIST_SCALE_DIVISOR = tonumber(CFG.PersistentScaleDivisor) or 10.0
local PERSIST_CHECK_SLEEP = math.max(50, tonumber(CFG.PersistentCheckSleep) or 150)

local WAVE_SLOW_FACTOR = tonumber(WAVE_CFG.slowFactor) or 0.25
local WAVE_EVOLUTION_KEYS = WAVE_CFG.evolutionKeys or {
    "speed", "rate", "frequency", "time", "timescale", "playbackrate",
    "ripple_speed", "ripple_rate", "flow_rate"
}
local WAVE_ENFORCE_MS = math.max(0, tonumber(WAVE_CFG.enforceMs) or 1000)

local currentToken = 0
local lastRange = tonumber(RANGES[1]) or 3.0
local persistMode = false
local persistHandle = false
local bandHandles = {}

local function dprint(msg)
    if CFG.Debug then
        print(("^3[DEBUG]^7 %s"):format(tostring(msg)))
    end
end

local function hasNamedAssetLoaded(dictHash)
    return Citizen.InvokeNative(0x65BB72F29138F5D6, dictHash)
end

local function requestNamedAsset(dictHash)
    Citizen.InvokeNative(0xF2B2353BBC0D4E8F, dictHash)
end

local function usePtfxAsset(dict)
    Citizen.InvokeNative(0xA10DB07FC234DD12, dict)
end

local function doesLoopedExist(handle)
    return handle and Citizen.InvokeNative(0x9DD5AFF561E88F2A, handle)
end

local function removeParticleFx(handle, immediate)
    if handle then
        Citizen.InvokeNative(0x459598F579C98929, handle, immediate or false)
    end
end

local function ensurePtfxLoaded(dict)
    local dictHash = GetHashKey(dict)
    if not hasNamedAssetLoaded(dictHash) then
        requestNamedAsset(dictHash)
        local startedAt = GetGameTimer()
        while not hasNamedAssetLoaded(dictHash) do
            if GetGameTimer() - startedAt > ASSET_LOAD_TIMEOUT_MS then
                dprint(("%sTimeout caricamento asset PTFX: %s"):format(TAG, dict))
                return false
            end
            Wait(0)
        end
    end

    usePtfxAsset(dict)
    return true
end

local function setAlpha(handle, alpha)
    if handle and SetParticleFxLoopedAlpha then
        SetParticleFxLoopedAlpha(handle, alpha)
    end
end

local function applyWaveSlow(handle)
    if not handle or not SetParticleFxLoopedEvolution then
        return
    end

    for _, key in ipairs(WAVE_EVOLUTION_KEYS) do
        SetParticleFxLoopedEvolution(handle, key, WAVE_SLOW_FACTOR, false)
    end
end

local function getRangeClampBounds()
    local first = tonumber(RANGES[1]) or 3.0
    local last = tonumber(RANGES[#RANGES]) or first
    local minClamp = (first * VISUAL_SCALE_FACTOR / SCALE_BASE_METERS) * MIN_SCALE_MULTIPLIER
    local maxClamp = (last * VISUAL_SCALE_FACTOR / SCALE_BASE_METERS) * MAX_SCALE_MULTIPLIER
    return minClamp, maxClamp
end

local function scaleForRange(rangeMeters, isPersistent)
    local range = tonumber(rangeMeters) or 0.0
    local persistentFactor = isPersistent and (1.0 / PERSIST_SCALE_DIVISOR) or 1.0

    for _, configuredRange in ipairs(RANGES) do
        if range == configuredRange then
            return (configuredRange * VISUAL_SCALE_FACTOR / SCALE_BASE_METERS) * persistentFactor
        end
    end

    local scale = (range * VISUAL_SCALE_FACTOR / SCALE_BASE_METERS) * persistentFactor
    local minClamp, maxClamp = getRangeClampBounds()
    minClamp = minClamp * persistentFactor
    maxClamp = maxClamp * persistentFactor

    if scale < minClamp then scale = minClamp end
    if scale > maxClamp then scale = maxClamp end

    return scale
end

local function clearBandHandles()
    for i = #bandHandles, 1, -1 do
        local entry = bandHandles[i]
        if entry and doesLoopedExist(entry.h) then
            removeParticleFx(entry.h, false)
        end
        bandHandles[i] = nil
    end
end

local function stopPersistent()
    if doesLoopedExist(persistHandle) then
        removeParticleFx(persistHandle, false)
    end
    persistHandle = false
end

local function stopCurrent()
    currentToken = currentToken + 1
    clearBandHandles()
end

local function startLoopedOnPed(ped, scale)
    if USE_BONE then
        return Citizen.InvokeNative(
            0x9C56621462FFE7A6,
            PTFX_NAME, ped,
            OFFSET.x, OFFSET.y, OFFSET.z,
            ROT.x, ROT.y, ROT.z,
            BONE_INDEX, scale, AXIS.x, AXIS.y, AXIS.z
        )
    end

    return Citizen.InvokeNative(
        0x8F90AB32E1944BDE,
        PTFX_NAME, ped,
        OFFSET.x, OFFSET.y, OFFSET.z,
        ROT.x, ROT.y, ROT.z,
        scale, AXIS.x, AXIS.y, AXIS.z
    )
end

local function createBand(ped, scale)
    local handle = startLoopedOnPed(ped, scale)
    if handle then
        applyWaveSlow(handle)
        setAlpha(handle, FADE_START_ALPHA)
        bandHandles[#bandHandles + 1] = {
            h = handle,
            born = GetGameTimer(),
            life = FADE_LIFE_MS,
        }
    end
end

local function runFadeManager(token)
    CreateThread(function()
        while token == currentToken do
            local now = GetGameTimer()
            local alive = 0

            for i = #bandHandles, 1, -1 do
                local entry = bandHandles[i]
                local handle = entry and entry.h

                if doesLoopedExist(handle) then
                    local age = now - entry.born
                    local progress = age / entry.life
                    if progress >= 1.0 then
                        removeParticleFx(handle, false)
                        table.remove(bandHandles, i)
                    else
                        setAlpha(handle, 1.0 - progress)
                        alive = alive + 1
                    end
                else
                    table.remove(bandHandles, i)
                end
            end

            if alive == 0 then
                break
            end

            Wait(0)
        end
    end)

    if WAVE_ENFORCE_MS > 0 then
        CreateThread(function()
            while token == currentToken and #bandHandles > 0 do
                for i = #bandHandles, 1, -1 do
                    local handle = bandHandles[i] and bandHandles[i].h
                    if doesLoopedExist(handle) then
                        applyWaveSlow(handle)
                    else
                        table.remove(bandHandles, i)
                    end
                end
                Wait(WAVE_ENFORCE_MS)
            end
        end)
    end
end

local function playVoiceRing(rangeMeters)
    lastRange = tonumber(rangeMeters) or lastRange
    local finalScale = scaleForRange(lastRange, false)

    stopCurrent()
    if not ensurePtfxLoaded(PTFX_DICT) then
        return
    end

    local myToken = currentToken
    local ped = PlayerPedId()

    for i = 1, FADE_BANDS do
        local fraction = i / FADE_BANDS
        local scale = finalScale * fraction
        local delay = FADE_STAGGER_MS * (i - 1)

        CreateThread(function()
            local startAt = GetGameTimer() + delay
            while GetGameTimer() < startAt do
                if myToken ~= currentToken then
                    return
                end
                Wait(0)
            end

            if myToken ~= currentToken then
                return
            end

            createBand(ped, scale)
        end)
    end

    runFadeManager(myToken)

    local totalDuration = (FADE_STAGGER_MS * (FADE_BANDS - 1)) + FADE_LIFE_MS
    local timeout = math.max(AFTERBURN_MS, totalDuration + 50)

    dprint(("%sRing avviato | range=%.1f | scale=%.3f | bands=%d"):format(TAG, lastRange, finalScale, FADE_BANDS))

    CreateThread(function()
        local startedAt = GetGameTimer()
        while GetGameTimer() - startedAt < timeout do
            if myToken ~= currentToken then
                return
            end
            Wait(0)
        end

        if myToken == currentToken then
            stopCurrent()
            dprint(TAG .. "Ring terminato")
        end
    end)
end

local function startPersistentForRange(rangeMeters)
    if not ENABLE_PERSISTENT_MODE then
        return
    end

    if not ensurePtfxLoaded(PTFX_DICT) then
        return
    end

    stopPersistent()

    local ped = PlayerPedId()
    local finalScale = scaleForRange(rangeMeters, true)
    persistHandle = startLoopedOnPed(ped, finalScale)

    if persistHandle then
        applyWaveSlow(persistHandle)
        setAlpha(persistHandle, 1.0)
        dprint(("%sPersistente ON | range=%.1f | scale=%.3f"):format(TAG, rangeMeters, finalScale))
    end
end

if ENABLE_PERSISTENT_MODE and PERSIST_TOGGLE_KEY then
    CreateThread(function()
        while true do
            if Citizen.InvokeNative(0x91AEF906BCA88877, 0, PERSIST_TOGGLE_KEY) then
                persistMode = not persistMode

                if persistMode then
                    startPersistentForRange(lastRange)
                else
                    stopPersistent()
                    dprint(TAG .. "Persistente OFF")
                end

                Wait(250)
            else
                Wait(PERSIST_CHECK_SLEEP)
            end
        end
    end)
end

RegisterNetEvent('SaltyChat_VoiceRangeChanged', function(range)
    playVoiceRing(range)

    if persistMode then
        startPersistentForRange(lastRange)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    stopPersistent()
    stopCurrent()
end)
