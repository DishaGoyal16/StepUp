package com.stepup.trust.store

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Tiny append-only text log (one record per line, fields joined by TAB). Used instead of Room/SQLite so the
 * persistence layer is plain JVM and unit-testable (documented deviation, see KNOWN_LIMITATIONS.md).
 * Records never contain TAB or newline (callers sanitise free text with [clean]).
 */
class AppendLog(val file: File) {
    init {
        file.parentFile?.mkdirs()
    }

    @Synchronized
    fun append(vararg fields: Any?) {
        FileOutputStream(file, true).use { out ->
            out.write((fields.joinToString("\t") { clean(it) } + "\n").toByteArray(Charsets.UTF_8))
            out.flush()
            try { out.fd.sync() } catch (_: IOException) { /* best effort */ }
        }
    }

    @Synchronized
    fun readAll(): List<List<String>> {
        if (!file.exists()) return emptyList()
        return file.readLines(Charsets.UTF_8).filter { it.isNotEmpty() }.map { it.split('\t') }
    }

    /** Atomically replaces the whole file (write temp + rename). */
    @Synchronized
    fun rewrite(rows: List<List<Any?>>) {
        val tmp = File(file.path + ".tmp")
        tmp.writeText(rows.joinToString("") { r -> r.joinToString("\t") { clean(it) } + "\n" }, Charsets.UTF_8)
        if (!tmp.renameTo(file)) {
            file.delete()
            if (!tmp.renameTo(file)) throw IOException("cannot replace ${file.path}")
        }
    }

    @Synchronized
    fun delete() {
        file.delete()
    }

    companion object {
        fun clean(v: Any?): String = (v?.toString() ?: "").replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')
    }
}
