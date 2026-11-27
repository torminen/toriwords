package com.toriwords.store

import androidx.room.PooledConnection
import androidx.sqlite.SQLITE_DATA_BLOB
import androidx.sqlite.SQLITE_DATA_FLOAT
import androidx.sqlite.SQLITE_DATA_INTEGER
import androidx.sqlite.SQLITE_DATA_NULL
import androidx.sqlite.SQLiteStatement
import com.toriwords.core.ToriId

/**
 * Explicit SQL on a Room connection. Arguments: `ToriId` (16-byte BLOB), `ByteArray`, `String`, `Long`/`Int`, `Double`,
 * `Boolean` (0/1), null; a `Collection` argument expands in place (use with [ph]).
 */
class Sql internal constructor(private val conn: PooledConnection) {
    suspend fun exec(sql: String, vararg args: Any?) {
        conn.usePrepared(sql) { st ->
            bind(st, args)
            st.step()
        }
    }

    suspend fun rows(sql: String, vararg args: Any?): List<Row> = conn.usePrepared(sql) { st ->
        bind(st, args)
        val names = st.getColumnNames()
        val out = ArrayList<Row>()
        while (st.step()) {
            val values = LinkedHashMap<String, Any?>(names.size)
            for (i in names.indices) {
                values[names[i]] = when (st.getColumnType(i)) {
                    SQLITE_DATA_NULL -> null
                    SQLITE_DATA_INTEGER -> st.getLong(i)
                    SQLITE_DATA_FLOAT -> st.getDouble(i)
                    SQLITE_DATA_BLOB -> st.getBlob(i)
                    else -> st.getText(i)
                }
            }
            out.add(Row(values))
        }
        out
    }

    suspend fun row(sql: String, vararg args: Any?): Row? = rows(sql, *args).firstOrNull()

    /** First column of every row as IDs (NULLs skipped). */
    suspend fun ids(sql: String, vararg args: Any?): List<ToriId> = rows(sql, *args).mapNotNull { it.firstId() }

    suspend fun id(sql: String, vararg args: Any?): ToriId? = row(sql, *args)?.firstId()
    suspend fun long(sql: String, vararg args: Any?): Long? = row(sql, *args)?.values?.values?.firstOrNull() as Long?
    suspend fun text(sql: String, vararg args: Any?): String? = row(sql, *args)?.values?.values?.firstOrNull() as String?
    suspend fun bool(sql: String, vararg args: Any?): Boolean = (long(sql, *args) ?: 0L) != 0L

    private fun bind(st: SQLiteStatement, args: Array<out Any?>) {
        var i = 1
        fun one(a: Any?) {
            when (a) {
                null -> st.bindNull(i)
                is ToriId -> st.bindBlob(i, a.bytes)
                is ByteArray -> st.bindBlob(i, a)
                is String -> st.bindText(i, a)
                is Long -> st.bindLong(i, a)
                is Int -> st.bindLong(i, a.toLong())
                is Double -> st.bindDouble(i, a)
                is Boolean -> st.bindLong(i, if (a) 1 else 0)
                else -> throw IllegalArgumentException("cannot bind ${a::class}")
            }
            i++
        }
        for (a in args) if (a is Collection<*>) a.forEach(::one) else one(a)
    }

    companion object {
        /** `(?, ?, …)` for an IN clause of `n` values; an empty list binds one empty BLOB (see [idArgs]). */
        fun ph(n: Int): String = "(" + List(maxOf(n, 1)) { "?" }.joinToString(",") + ")"

        /** IN-clause arguments for [ph]; an empty collection matches nothing. */
        fun idArgs(ids: Collection<ToriId>): List<Any> = if (ids.isEmpty()) listOf(ByteArray(0)) else ids.toList()
    }
}

/** One result row: column name → Long, Double, String, ByteArray or null. */
class Row(val values: Map<String, Any?>) {
    operator fun get(col: String): Any? = values[col]
    fun id(col: String): ToriId? = (values[col] as ByteArray?)?.takeIf { it.size == 16 }?.let(ToriId::fromBytes)
    fun str(col: String): String? = values[col] as String?
    fun long(col: String): Long? = (values[col] as Number?)?.toLong()
    fun int(col: String): Int? = long(col)?.toInt()
    fun double(col: String): Double? = (values[col] as Number?)?.toDouble()
    internal fun firstId(): ToriId? = (values.values.firstOrNull() as ByteArray?)?.takeIf { it.size == 16 }?.let(ToriId::fromBytes)
}
