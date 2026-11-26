package com.lordnordyx.yami.data

import kotlinx.serialization.Serializable

@Serializable
enum class WidescreenMode(val label: String, val blurb: String) {
    OFF("Original", "Native 4:3 picture, as the developer made it"),
    FULL("Widescreen", "Resizes the game screen; scripts lay out to the new width"),
    PANORAMIC("Panoramic", "Map fills the screen, menus and UI stay at original width, centered"),
}

@Serializable
enum class AspectPreset(val label: String, val ratio: Float) {
    DEVICE("Match device", 0f),
    R16_10("16:10", 16f / 10f),
    R16_9("16:9", 16f / 9f),
    R20_9("20:9", 20f / 9f),
}

/** Values match mkxp-z's smoothScaling enum (etc.h). */
@Serializable
enum class ScalingFilter(val code: Int, val label: String) {
    NEAREST(0, "Nearest (sharp pixels)"),
    BILINEAR(1, "Bilinear"),
    BICUBIC(2, "Bicubic"),
    LANCZOS3(3, "Lanczos3"),
    XBRZ(4, "xBRZ (pixel-art upscaler)"),
}

@Serializable
enum class TurboMode(val label: String) {
    FRAMERATE("Raise frame rate"),
    FRAMESKIP("Skip frames"),
    HYBRID("Frame rate + skip"),
}

@Serializable
enum class ScreenFit(val label: String) {
    FIT("Fit (keep aspect)"),
    INTEGER("Integer scale"),
    STRETCH("Stretch to fill"),
}

@Serializable
enum class ControllerProfile(val label: String) {
    AUTO("Auto-detect"),
    XBOX("Xbox / generic (A = confirm)"),
    NINTENDO("Nintendo (B position = confirm)"),
    PLAYSTATION("PlayStation (✕ = confirm)"),
}

@Serializable
data class GameSettings(
    // Display
    val widescreen: WidescreenMode = WidescreenMode.OFF,
    val aspect: AspectPreset = AspectPreset.DEVICE,
    val fit: ScreenFit = ScreenFit.FIT,
    val scaling: ScalingFilter = ScalingFilter.BICUBIC,
    val xbrzFactor: Int = 2,
    val bicubicSharpness: Int = 100,
    val shader: String = "none",
    val shaderIntensity: Float = 1f,
    val internalResolution: Float = 1f,
    val hiresTextures: Boolean = false,
    val hiresTextureScale: Float = 2f,
    val vsync: Boolean = true,
    val fixedFramerate: Int = 0,
    val frameSkip: Boolean = false,
    val showEngineFps: Boolean = false,
    // Overlays
    val showInfo: Boolean = false,
    val showTouchControls: Boolean = true,
    val touchOpacity: Float = 0.55f,
    // Speed
    val turboMode: TurboMode = TurboMode.FRAMERATE,
    val turboSpeed: Int = 3,
    val turboToggle: Boolean = true,
    // Performance
    val mapCache: Boolean = true,
    val mapCacheMb: Int = 192,
    /** Experimental: rewrites tileset ids per map; opt-in only. */
    val optimizedMaps: Boolean = false,
    val warmGraphics: Boolean = false,
    // Audio
    val soundFont: String = "",
    val midiReverb: Boolean = true,
    val midiChorus: Boolean = false,
    // Input
    val controllerProfile: ControllerProfile = ControllerProfile.AUTO,
    val autofireRateHz: Int = 12,
    val vibration: Boolean = true,
    // Compatibility
    val rgssVersionOverride: Int = 0,
    val fontScale: Float = 0f,
    val redirectSaves: Boolean = true,
)

@Serializable
data class OptimizeReport(
    val at: Long = 0,
    val archiveExtracted: Boolean = false,
    val indexedFiles: Int = 0,
    val maps: Int = 0,
    val mapBytes: Long = 0,
    val optimizedTilesets: Int = 0,
    val mapVariants: Int = 0,
    val savedPixels: Long = 0,
    val missingRefs: Int = 0,
    val note: String = "",
)

@Serializable
data class Game(
    val id: String,
    val title: String,
    val path: String,
    val rgssVersion: Int = 1,
    val engineHint: String = "",
    val iconPath: String? = null,
    val coverPath: String? = null,
    val addedAt: Long = System.currentTimeMillis(),
    val lastPlayed: Long = 0,
    val playTimeSec: Long = 0,
    val launches: Int = 0,
    val favorite: Boolean = false,
    val inPlace: Boolean = false,
    val tags: List<String> = emptyList(),
    val useGlobalSettings: Boolean = true,
    val settings: GameSettings = GameSettings(),
    val optimize: OptimizeReport? = null,
)

@Serializable
data class AppSettings(
    /** Bumped when defaults change in a way stored settings must follow (see GameRepository.migrate).
     *  Files written before this field existed decode as 1. */
    val schema: Int = 1,
    val libraryView: LibraryView = LibraryView.COVERS,
    val sort: LibrarySort = LibrarySort.RECENT,
    val hideFromGallery: Boolean = true,
    val rtpPaths: List<String> = emptyList(),
    val defaultSoundFont: String = "",
    val defaults: GameSettings = GameSettings(),
    val accent: Long = 0xFF7C5CFF,
    val amoled: Boolean = true,
    val optimizeOnImport: Boolean = true,
    val haptics: Boolean = true,
) {
    companion object { const val SCHEMA = 2 }
}

@Serializable enum class LibraryView { COVERS, GRID, LIST }
@Serializable enum class LibrarySort(val label: String) {
    RECENT("Recently played"), TITLE("Title"), ADDED("Recently added"), PLAYTIME("Play time")
}
