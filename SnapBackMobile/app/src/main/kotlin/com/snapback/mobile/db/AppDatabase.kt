package com.snapback.mobile.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(entities = [EventRow::class], version = 1)
abstract class AppDatabase : RoomDatabase() {
    abstract fun events(): EventDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        fun get(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext, AppDatabase::class.java, "snapback.db"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
