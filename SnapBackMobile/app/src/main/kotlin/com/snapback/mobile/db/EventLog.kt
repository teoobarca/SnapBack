package com.snapback.mobile.db

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "events")
data class EventRow(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Long,
    val kind: String,
    val detail: String
)

@Dao
interface EventDao {
    @Insert suspend fun insert(row: EventRow): Long

    @Query("SELECT * FROM events ORDER BY id DESC LIMIT :limit")
    suspend fun recent(limit: Int = 50): List<EventRow>

    @Query("DELETE FROM events WHERE id NOT IN (SELECT id FROM events ORDER BY id DESC LIMIT 200)")
    suspend fun trim()
}
