package com.lordnordyx.yami.engine

import android.content.Context
import com.lordnordyx.yami.BuildConfig
import com.lordnordyx.yami.data.GameRepository
import java.io.File

/** Copies bundled shaders and Ruby runtime scripts to real files the engine can open. */
object RuntimeAssets {

    data class ShaderInfo(val id: String, val title: String, val file: File, val builtIn: Boolean)

    class Installed(val dir: File, private val userShaders: File) {
        fun script(name: String) = File(dir, "scripts/$name")
        fun shader(id: String): File? {
            if (id.isBlank() || id == "none") return null
            val builtIn = File(dir, "shaders/$id.frag")
            if (builtIn.exists()) return builtIn
            return userShaders.listFiles()?.firstOrNull { it.nameWithoutExtension == id }
        }
    }

    fun install(context: Context, repo: GameRepository): Installed {
        val dir = repo.runtimeDir
        val stamp = File(dir, ".version")
        val want = "${BuildConfig.VERSION_CODE}-${context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime}"
        if (!stamp.exists() || stamp.readText() != want) {
            for (sub in listOf("shaders", "scripts")) {
                val out = File(dir, sub).apply { deleteRecursively(); mkdirs() }
                context.assets.list("yami/$sub")?.forEach { name ->
                    context.assets.open("yami/$sub/$name").use { i -> File(out, name).outputStream().use { i.copyTo(it) } }
                }
            }
            stamp.writeText(want)
        }
        return Installed(dir, repo.userShaderDir)
    }

    fun shaders(context: Context, repo: GameRepository): List<ShaderInfo> {
        val rt = install(context, repo)
        val builtIn = File(rt.dir, "shaders").listFiles()?.sortedBy { it.name }?.map {
            ShaderInfo(it.nameWithoutExtension, describe(it), it, true)
        } ?: emptyList()
        val user = repo.userShaderDir.listFiles()?.filter { it.extension in setOf("frag", "glsl", "fsh") }
            ?.map { ShaderInfo(it.nameWithoutExtension, describe(it), it, false) } ?: emptyList()
        return builtIn + user
    }

    /** First line of a shader is "// Yami post shader: Title — description". */
    private fun describe(f: File): String {
        val first = runCatching { f.bufferedReader().use { it.readLine() } }.getOrNull() ?: return f.nameWithoutExtension
        return first.substringAfter("shader:", f.nameWithoutExtension).trim()
    }
}
