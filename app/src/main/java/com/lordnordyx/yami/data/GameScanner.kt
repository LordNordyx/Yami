package com.lordnordyx.yami.data

import java.io.File
import java.nio.charset.Charset
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.ByteBuffer
import java.security.MessageDigest

/** Recognises RPG Maker XP / VX / VX Ace game folders and extracts metadata. */
object GameScanner {

    data class Detected(
        val dir: File,
        val title: String,
        val rgssVersion: Int,
        val engineHint: String,
        val cover: File?,
        val icon: File?,
    )

    private val archiveNames = mapOf(
        "game.rgssad" to 1, "game.rgss2a" to 2, "game.rgss3a" to 3,
    )

    fun isGameDir(dir: File): Boolean {
        if (!dir.isDirectory) return false
        val names = dir.list()?.map { it.lowercase() }?.toSet() ?: return false
        if (names.any { it in archiveNames }) return true
        if ("game.ini" in names || "game.rxproj" in names) {
            return findCaseless(dir, "Data")?.isDirectory == true
        }
        val data = findCaseless(dir, "Data") ?: return false
        return data.list()?.any { it.lowercase().startsWith("scripts.r") } == true
    }

    /** Looks one or two levels deep: archives often wrap the game in a folder. */
    fun locate(root: File, depth: Int = 2): File? {
        if (isGameDir(root)) return root
        if (depth == 0) return null
        root.listFiles()?.filter { it.isDirectory }?.forEach { child ->
            locate(child, depth - 1)?.let { return it }
        }
        return null
    }

    fun detect(dir: File): Detected {
        val ini = findCaseless(dir, "Game.ini")
        val iniMap = ini?.let { parseIni(readText(it)) } ?: emptyMap()
        val title = iniMap["title"]?.takeIf { it.isNotBlank() } ?: dir.name

        val names = dir.list()?.map { it.lowercase() } ?: emptyList()
        var version = names.firstNotNullOfOrNull { archiveNames[it] } ?: 0
        if (version == 0) {
            val lib = iniMap["library"]?.lowercase() ?: ""
            version = when {
                lib.contains("rgss3") -> 3
                lib.contains("rgss2") -> 2
                else -> {
                    val data = findCaseless(dir, "Data")
                    val ext = data?.list()?.firstOrNull { it.lowercase().startsWith("scripts.") }
                        ?.substringAfterLast('.')?.lowercase()
                    when (ext) { "rvdata2" -> 3; "rvdata" -> 2; else -> 1 }
                }
            }
        }

        val hint = when {
            findCaseless(dir, "PBS")?.isDirectory == true -> "Pokémon Essentials"
            findCaseless(dir, "Plugins")?.isDirectory == true &&
                findCaseless(dir, "Data")?.list()?.any { it.lowercase() == "plugin_scripts.rxdata" } == true ->
                "Pokémon Essentials (plugins)"
            findCaseless(dir, "mkxp.json") != null -> "mkxp-z ready"
            else -> when (version) { 1 -> "RPG Maker XP"; 2 -> "RPG Maker VX"; else -> "RPG Maker VX Ace" }
        }

        return Detected(dir, title, version, hint, findCover(dir), findIcon(dir))
    }

    fun idFor(dir: File): String {
        val md = MessageDigest.getInstance("SHA-1")
        return md.digest(dir.absolutePath.toByteArray()).take(6).joinToString("") { "%02x".format(it) }
    }

    private fun findCover(dir: File): File? {
        val titles = findCaseless(dir, "Graphics")?.let { findCaseless(it, "Titles") }
        val imgs = titles?.listFiles()?.filter { it.isFile && it.extension.lowercase() in setOf("png", "jpg", "jpeg") }
            ?.sortedByDescending { it.length() }
        return imgs?.firstOrNull { it.nameWithoutExtension.lowercase().contains("title") } ?: imgs?.firstOrNull()
    }

    private fun findIcon(dir: File): File? {
        listOf("icon.png", "Icon.png", "Game.png").forEach { n -> findCaseless(dir, n)?.let { return it } }
        return findCaseless(dir, "Graphics")?.let { findCaseless(it, "Icons") }
            ?.listFiles()?.firstOrNull { it.extension.lowercase() == "png" }
    }

    fun findCaseless(dir: File, name: String): File? {
        val direct = File(dir, name)
        if (direct.exists()) return direct
        return dir.listFiles()?.firstOrNull { it.name.equals(name, ignoreCase = true) }
    }

    fun parseIni(text: String): Map<String, String> = text.lineSequence()
        .map { it.trim() }
        .filter { it.contains('=') && !it.startsWith(";") && !it.startsWith("[") }
        .associate { line ->
            val k = line.substringBefore('=').trim().lowercase()
            k to line.substringAfter('=').trim()
        }

    /** RPG Maker INIs are UTF-8, Windows-1252 or Shift-JIS depending on author locale. */
    fun readText(f: File): String {
        val bytes = f.readBytes()
        for (cs in listOf("UTF-8", "Shift_JIS", "windows-1252")) {
            try {
                return Charset.forName(cs).newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes)).toString().removePrefix("﻿")
            } catch (_: CharacterCodingException) {
            } catch (_: Exception) {
            }
        }
        return String(bytes, Charsets.ISO_8859_1)
    }
}
