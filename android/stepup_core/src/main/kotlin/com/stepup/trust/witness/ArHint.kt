package com.stepup.trust.witness

enum class ArType { IN_VEHICLE, ON_BICYCLE, ON_FOOT, WALKING, RUNNING, STILL, TILTING, UNKNOWN }

/** One Activity Recognition update, timestamped (UTC ms mapped from the AR event's elapsed-realtime stamp). */
data class ArEvent(val tsMs: Long, val type: ArType, val confidence: Int)

/**
 * Activity Recognition as a HINT THAT MAY ONLY DOWNGRADE (v2 §L2.3).
 *
 * * Qualifying update: IN_VEHICLE (or ON_BICYCLE when [rejectBicycle]) with confidence >= [minConfidence].
 * * Hysteresis: [consecutive] qualifying updates in a row confirm an episode (avoids flapping).
 * * AR can take 15-45 s to react, so a confirmed episode is applied RETROACTIVELY with a +-[marginMs] margin.
 * * "WALKING" never upgrades anything; it is only exposed so E2 can open a walking session.
 */
class ArVehicleTracker(
    private val minConfidence: Int = 65,
    private val consecutive: Int = 2,
    private val marginMs: Long = 45_000L,
    private val rejectBicycle: Boolean = true,
) {
    private data class Episode(var startMs: Long, var endMs: Long, val bicycle: Boolean)

    private val episodes = mutableListOf<Episode>()
    private var runStart = -1L
    private var runCount = 0
    private var runBicycle = false
    private var activeEpisode: Episode? = null

    fun reset() {
        episodes.clear(); runStart = -1; runCount = 0; activeEpisode = null
    }

    fun onEvent(e: ArEvent) {
        val qualifies = e.confidence >= minConfidence &&
            (e.type == ArType.IN_VEHICLE || (rejectBicycle && e.type == ArType.ON_BICYCLE))
        if (!qualifies) {
            // An observed change of state ends the episode; until then the vehicle state is held (updates can be sparse).
            activeEpisode?.let { it.endMs = maxOf(it.endMs, e.tsMs) }
            runStart = -1; runCount = 0; activeEpisode = null
            return
        }
        val bike = e.type == ArType.ON_BICYCLE
        if (runCount == 0 || bike != runBicycle) { runStart = e.tsMs; runCount = 1; runBicycle = bike; activeEpisode = null }
        else runCount++
        val ep = activeEpisode
        if (ep != null) { ep.endMs = maxOf(ep.endMs, e.tsMs); return }
        if (runCount >= consecutive) {
            val created = Episode(runStart, e.tsMs, bike)
            episodes += created
            activeEpisode = created
        }
    }

    /** @return null if no vehicle/bicycle episode overlaps [startMs, endMs) (with margin); else "IN_VEHICLE"/"ON_BICYCLE". */
    fun reasonFor(startMs: Long, endMs: Long): String? {
        for (ep in episodes) {
            if (ep.startMs - marginMs < endMs && ep.endMs + marginMs >= startMs) {
                return if (ep.bicycle) "ON_BICYCLE" else "IN_VEHICLE"
            }
        }
        return null
    }

    val confirmedEpisodes: Int get() = episodes.size
}
