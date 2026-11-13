package com.stepup.trust.export

/** Minimal RFC-4180 CSV writer/reader. Pure Kotlin. */
object Csv {
    fun escape(v: Any?): String {
        val s = when (v) {
            null -> ""
            is Double -> if (v.isNaN()) "" else trimDouble(v)
            is Float -> if (v.isNaN()) "" else trimDouble(v.toDouble())
            else -> v.toString()
        }
        return if (s.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) "\"" + s.replace("\"", "\"\"") + "\"" else s
    }

    private fun trimDouble(d: Double): String {
        if (d.isInfinite()) return if (d > 0) "Infinity" else "-Infinity"
        val s = "%.6f".format(java.util.Locale.ROOT, d)
        return s.trimEnd('0').trimEnd('.').ifEmpty { "0" }
    }

    fun row(vararg cells: Any?): String = cells.joinToString(",") { escape(it) }
    fun row(cells: List<Any?>): String = cells.joinToString(",") { escape(it) }

    /** Parses one CSV document into rows (supports quoted fields with commas/newlines/double quotes). */
    fun parse(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val cur = StringBuilder()
        var inQuotes = false
        var i = 0
        var fieldStarted = false
        while (i < text.length) {
            val c = text[i]
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < text.length && text[i + 1] == '"') { cur.append('"'); i++ } else inQuotes = false
                } else cur.append(c)
            } else when (c) {
                '"' -> { inQuotes = true; fieldStarted = true }
                ',' -> { row.add(cur.toString()); cur.setLength(0); fieldStarted = true }
                '\r' -> {}
                '\n' -> {
                    if (fieldStarted || cur.isNotEmpty() || row.isNotEmpty()) { row.add(cur.toString()); rows.add(row) }
                    row = mutableListOf(); cur.setLength(0); fieldStarted = false
                }
                else -> { cur.append(c); fieldStarted = true }
            }
            i++
        }
        if (fieldStarted || cur.isNotEmpty() || row.isNotEmpty()) { row.add(cur.toString()); rows.add(row) }
        return rows
    }
}
