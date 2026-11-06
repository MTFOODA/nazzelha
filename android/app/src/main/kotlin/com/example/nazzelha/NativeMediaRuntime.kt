package com.example.nazzelha

import android.os.Build
import android.system.Os
import android.util.Log
import java.io.File
import java.util.UUID

/** Preparation is shared by activity/service and must not replace active links in two steps. */
internal object NativeMediaRuntime {
    val initializationLock = Any()

    fun executable(binDir: File, nativeDir: File, linkName: String, targetName: String): String? {
        val target = File(nativeDir, targetName)
        if (!target.isFile) return null
        binDir.mkdirs()
        val link = File(binDir, linkName)
        val temporary = File(binDir, ".$linkName-${UUID.randomUUID()}")
        return try {
            if (link.canonicalPath == target.canonicalPath) return link.absolutePath
            try {
                Os.symlink(target.absolutePath, temporary.absolutePath)
                // Atomic replacement repairs stale links after an APK update,
                // without a missing-link window or an EEXIST/copy race.
                Os.rename(temporary.absolutePath, link.absolutePath)
            } catch (error: Exception) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) throw error
                // Older Android permits executing copies in app-owned storage.
                target.copyTo(link, overwrite = true)
                check(link.setExecutable(true, false)) { "Could not make the media tool executable" }
            }
            link.absolutePath
        } catch (error: Exception) {
            Log.e("NazzelhaRuntime", "Could not prepare media executable $linkName", error)
            null
        } finally {
            temporary.delete()
        }
    }
}
