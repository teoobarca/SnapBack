package com.snapback.mobile.ui

import org.junit.Assert.*
import org.junit.Test

class OemDetectionTest {
    @Test fun detectSamsung() { assertEquals(Oem.Samsung, Oem.fromManufacturer("samsung")) }
    @Test fun detectXiaomi() { assertEquals(Oem.Xiaomi, Oem.fromManufacturer("Xiaomi")) }
    @Test fun detectRedmi() { assertEquals(Oem.Xiaomi, Oem.fromManufacturer("Redmi")) }
    @Test fun detectOneplus() { assertEquals(Oem.OnePlus, Oem.fromManufacturer("OnePlus")) }
    @Test fun detectGeneric() { assertEquals(Oem.Generic, Oem.fromManufacturer("Pixel")) }
}
