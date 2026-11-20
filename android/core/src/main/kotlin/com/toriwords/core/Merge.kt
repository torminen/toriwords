package com.toriwords.core

/** Author rank of a field write: 1 for a direct user action, 0 for anything automatic. */
enum class AuthorRank(val wire: Int) {
    AUTOMATIC(0), USER(1);

    companion object {
        fun fromWire(value: Int): AuthorRank? = entries.firstOrNull { it.wire == value }
    }
}

/** A synced field value with its clock `c` and rank `u`. */
data class FieldVersion<V>(val value: V, val clock: HlcTimestamp, val rank: AuthorRank) {

    /** `(u, c)` order: rank first, then clock. */
    fun winsOver(other: FieldVersion<V>): Boolean =
        if (rank != other.rank) rank > other.rank else clock > other.clock

    companion object {
        /** The only conflict rule: remote wins only if it beats local. */
        fun <V> merge(local: FieldVersion<V>, remote: FieldVersion<V>): FieldVersion<V> =
            if (remote.winsOver(local)) remote else local
    }
}

/** A synced record. `fields` holds only the fields present (a partial push carries a subset). */
data class Envelope<V>(
    val id: ToriId,
    val type: String,
    val schema: Int,
    val owner: ToriId?,
    val deleted: Boolean,
    val mergedInto: ToriId?,
    val fields: Map<String, FieldVersion<V>>,
) {
    companion object {
        /**
         * Envelope merge: deleted = OR; mergedInto non-null beats null, smaller ID wins; fields per field (unknown kept,
         * disjoint unioned); a tombstone drops all field values; schema = max. Commutative.
         */
        fun <V> merge(local: Envelope<V>, remote: Envelope<V>): Envelope<V> {
            val deleted = local.deleted || remote.deleted
            val into = listOfNotNull(local.mergedInto, remote.mergedInto).minOrNull()
            val fields = if (deleted) {
                emptyMap()
            } else {
                val out = LinkedHashMap(local.fields)
                for ((name, r) in remote.fields) out[name] = out[name]?.let { FieldVersion.merge(it, r) } ?: r
                out
            }
            return Envelope(local.id, local.type, maxOf(local.schema, remote.schema), local.owner, deleted, into, fields)
        }
    }
}
