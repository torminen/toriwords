package com.toriwords.store

import android.content.Context
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.deferredTransaction
import androidx.room.immediateTransaction
import androidx.room.useReaderConnection
import androidx.room.useWriterConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers

/**
 * Owner of `user.sqlite`. All writes go through [write], which stamps clocks, fills the outbox and runs the post-write
 * maintenance (canonical IDs, duplicate merge, Card creation, replay) in the same transaction. Every public method is one
 * transaction.
 */
class ToriStore private constructor(val database: ToriDatabase, private val clock: () -> Long) {

    /** One write transaction with clock stamping and post-write maintenance. */
    internal suspend fun <T> write(body: suspend (Tx) -> T): T = database.useWriterConnection { t ->
        t.immediateTransaction {
            val tx = Tx.begin(Sql(this), clock())
            val result = body(tx)
            tx.finish()
            result
        }
    }

    /** A write transaction without clocks or maintenance (sync bookkeeping). */
    internal suspend fun <T> writeRaw(body: suspend (Sql) -> T): T =
        database.useWriterConnection { t -> t.immediateTransaction { body(Sql(this)) } }

    /** Read-only access for queries, one consistent snapshot. */
    suspend fun <T> read(body: suspend (StoreReader) -> T): T =
        database.useReaderConnection { t -> t.deferredTransaction { body(StoreReader(Sql(this))) } }

    fun close() = database.close()

    companion object {
        val NEW_WORDS_PER_DAY_RANGE = 0..50

        /** `now` returns Unix ms; injectable for tests. */
        fun open(context: Context, name: String = "user.sqlite", now: () -> Long = System::currentTimeMillis): ToriStore =
            ToriStore(configure(Room.databaseBuilder<ToriDatabase>(context, name)), now)

        fun inMemory(context: Context, now: () -> Long = System::currentTimeMillis): ToriStore =
            ToriStore(configure(Room.inMemoryDatabaseBuilder<ToriDatabase>(context)), now)

        private fun configure(b: RoomDatabase.Builder<ToriDatabase>): ToriDatabase = b
            .setDriver(BundledSQLiteDriver())
            .setQueryCoroutineContext(Dispatchers.IO)
            .addCallback(ToriDatabase.Create)
            .build()
    }
}

/** Read-only query surface (queries live in extensions). `sql` is for diagnostics and tests. */
class StoreReader internal constructor(val sql: Sql)
