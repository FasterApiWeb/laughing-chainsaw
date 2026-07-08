package com.librering.data.local

import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.RoomDatabase

@Entity(tableName = "heart_rate")
data class HeartRateEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val timestamp: Double,
    val bpm: Double,
    val ibiMs: Int?,
)

@Database(entities = [HeartRateEntity::class], version = 1)
abstract class LibreRingDatabase : RoomDatabase()
