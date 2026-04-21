package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §31.1 — unit coverage for §22.1 WindowSize breakpoint helper.
 */
class WindowSizeTest {

    @Test fun `compact widths classify as Phone`() {
        assertEquals(WindowMode.Phone, widthDpToMode(0))
        assertEquals(WindowMode.Phone, widthDpToMode(360))
        assertEquals(WindowMode.Phone, widthDpToMode(599))
    }

    @Test fun `medium widths classify as Tablet`() {
        assertEquals(WindowMode.Tablet, widthDpToMode(600))
        assertEquals(WindowMode.Tablet, widthDpToMode(720))
        assertEquals(WindowMode.Tablet, widthDpToMode(839))
    }

    @Test fun `expanded widths classify as Desktop`() {
        assertEquals(WindowMode.Desktop, widthDpToMode(840))
        assertEquals(WindowMode.Desktop, widthDpToMode(1024))
        assertEquals(WindowMode.Desktop, widthDpToMode(1920))
    }
}
