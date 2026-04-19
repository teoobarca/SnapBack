package com.snapback.mobile.db

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class EventLogTest {
    private lateinit var db: AppDatabase
    private lateinit var dao: EventDao

    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.events()
    }

    @After fun teardown() { db.close() }

    @Test fun insertThenRecent() = runBlocking {
        dao.insert(EventRow(timestamp = 1, kind = "attention", detail = "Stop"))
        dao.insert(EventRow(timestamp = 2, kind = "resume", detail = ""))
        val out = dao.recent(10)
        assertEquals(2, out.size)
        assertEquals("resume", out[0].kind)
    }
}
