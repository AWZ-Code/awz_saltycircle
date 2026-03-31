Config = Config or {}

Config.Debug = false

Config.VoiceRanges = { 3.0, 8.0, 15.0, 32.0 }

Config.PersistToggleKey = 0x8CC9CD42
Config.EnablePersistentMode = true
Config.PersistentScaleDivisor = 10.0
Config.PersistentCheckSleep = 150

Config.Ptfx = {
    dict = "anm_water",
    name = "ent_anim_ped_water_wade_ripples",
    offset = { x = 0.0, y = 0.0, z = -0.45 },
    rotation = { x = 0.0, y = 0.0, z = 0.0 },
    axis = { x = 0, y = 0, z = 0 },
    useBone = false,
    boneIndex = 21030,
    assetLoadTimeoutMs = 3000,
}

Config.ScaleBaseMeters = 1.0
Config.VisualScaleFactor = 10.0
Config.MinScaleMultiplier = 1.0
Config.MaxScaleMultiplier = 1.0

Config.Ring = {
    afterburnMs = 1600,
    fadeBands = 8,
    fadeStaggerMs = 80,
    fadeLifeMs = 1600,
    startAlpha = 1.0,
}

Config.Wave = {
    slowFactor = 0.25,
    enforceMs = 1000,
    evolutionKeys = {
        "speed", "rate", "frequency", "time", "timescale", "playbackrate",
        "ripple_speed", "ripple_rate", "flow_rate"
    }
}