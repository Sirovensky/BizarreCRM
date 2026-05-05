package com.bizarreelectronics.crm.data.local.prefs

/**
 * §3.17 L607-L608 — A named saved dashboard layout.
 *
 * Instances are immutable value objects; use [copy] to derive modified versions.
 * Serialised to/from JSON via the companion helpers so no Gson dependency is
 * required in the prefs layer (plain string operations only).
 *
 * @property name        User-chosen label (e.g. "Morning", "End of day").
 * @property tileOrder   Ordered tile-ID list for this layout. Empty = role default.
 * @property hiddenTiles Set of tile IDs hidden in this layout.
 */
data class SavedDashboard(
    val name: String,
    val tileOrder: List<String> = emptyList(),
    val hiddenTiles: Set<String> = emptySet(),
) {
    companion object {
        /**
         * Serialize a [SavedDashboard] to a compact JSON object string.
         * Format: `{"n":"<name>","o":["id1","id2"],"h":["id3"]}`
         */
        fun serialize(d: SavedDashboard): String {
            val orderJson = d.tileOrder.joinToString(",") { "\"$it\"" }
            val hiddenJson = d.hiddenTiles.joinToString(",") { "\"$it\"" }
            val escapedName = d.name.replace("\"", "\\\"")
            return "{\"n\":\"$escapedName\",\"o\":[$orderJson],\"h\":[$hiddenJson]}"
        }

        /**
         * Deserialize a single [SavedDashboard] from the compact JSON produced by
         * [serialize]. Returns null on any parse failure.
         */
        fun deserialize(json: String): SavedDashboard? = runCatching {
            val nameMatch = Regex("\"n\":\"((?:[^\"\\\\]|\\\\.)*)\"").find(json)
            val name = nameMatch?.groupValues?.getOrNull(1)?.replace("\\\"", "\"") ?: return null

            fun parseArray(key: String): List<String> {
                val arrayMatch = Regex("\"$key\":\\[([^\\]]*)\\]").find(json)
                val inner = arrayMatch?.groupValues?.getOrNull(1) ?: return emptyList()
                return inner.split(",")
                    .map { it.trim().removeSurrounding("\"") }
                    .filter { it.isNotBlank() }
            }

            SavedDashboard(
                name = name,
                tileOrder = parseArray("o"),
                hiddenTiles = parseArray("h").toSet(),
            )
        }.getOrNull()

        /**
         * Serialize a list of [SavedDashboard] to a JSON array string.
         * Returns `"[]"` for an empty list.
         */
        fun serializeList(list: List<SavedDashboard>): String =
            "[${list.joinToString(",") { serialize(it) }}]"

        /**
         * Deserialize a JSON array string produced by [serializeList].
         * Returns an empty list on any parse failure.
         */
        fun deserializeList(json: String): List<SavedDashboard> = runCatching {
            // Split top-level JSON objects inside the array. Works for the compact
            // format produced by serialize() because objects don't contain nested arrays.
            val trimmed = json.trim().removeSurrounding("[", "]").trim()
            if (trimmed.isEmpty()) return emptyList()

            // Walk character-by-character to split on top-level commas between objects.
            val objects = mutableListOf<String>()
            var depth = 0
            val current = StringBuilder()
            for (ch in trimmed) {
                when {
                    ch == '{' -> { depth++; current.append(ch) }
                    ch == '}' -> { depth--; current.append(ch); if (depth == 0) { objects.add(current.toString()); current.clear() } }
                    ch == ',' && depth == 0 -> { /* separator between objects, skip */ }
                    else -> current.append(ch)
                }
            }

            objects.mapNotNull { deserialize(it) }
        }.getOrDefault(emptyList())
    }
}
