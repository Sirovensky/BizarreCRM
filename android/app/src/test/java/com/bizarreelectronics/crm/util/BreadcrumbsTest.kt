package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for the §32.5 breadcrumb ring buffer. Pure-JVM.
 */
class BreadcrumbsTest {

    @Test fun `recent returns oldest first`() {
        val crumbs = Breadcrumbs()
        crumbs.log("nav", "first")
        crumbs.log("tap", "second")
        crumbs.log("sync", "third")

        val out = crumbs.recent()
        assertEquals(3, out.size)
        assertTrue("first should appear before second", out[0].contains("first"))
        assertTrue(out[1].contains("second"))
        assertTrue(out[2].contains("third"))
    }

    @Test fun `blank message is dropped`() {
        val crumbs = Breadcrumbs()
        crumbs.log("nav", "")
        crumbs.log("nav", "   ")
        assertEquals(0, crumbs.recent().size)
    }

    @Test fun `ring caps at 50 entries`() {
        val crumbs = Breadcrumbs()
        for (i in 1..70) {
            crumbs.log("loop", "msg-$i")
        }
        val out = crumbs.recent()
        assertEquals(50, out.size)
        // First entry surviving should be msg-21 (70 - 50 + 1).
        assertTrue("oldest surviving entry should be msg-21", out.first().contains("msg-21"))
        assertTrue("newest entry should be msg-70", out.last().contains("msg-70"))
    }

    @Test fun `clear empties the ring`() {
        val crumbs = Breadcrumbs()
        crumbs.log("nav", "x")
        crumbs.log("nav", "y")
        crumbs.clear()
        assertEquals(0, crumbs.recent().size)
    }

    @Test fun `category is preserved in formatted line`() {
        val crumbs = Breadcrumbs()
        crumbs.log(Breadcrumbs.CAT_NAV, "/dashboard")
        crumbs.log(Breadcrumbs.CAT_PUSH, "type=ticket_assigned")
        val out = crumbs.recent()
        assertTrue(out[0].contains("[nav] /dashboard"))
        assertTrue(out[1].contains("[push] type=ticket_assigned"))
    }
}
