package com.bizarreelectronics.crm.lint

import com.android.tools.lint.client.api.IssueRegistry
import com.android.tools.lint.client.api.Vendor
import com.android.tools.lint.detector.api.CURRENT_API
import com.android.tools.lint.detector.api.Issue

/**
 * Registers all custom lint issues for the Bizarre Electronics CRM Android app.
 *
 * Loaded via the service-loader file at:
 * META-INF/services/com.android.tools.lint.client.api.IssueRegistry
 *
 * The JAR manifest attribute `Lint-Registry-v2` also points here so that
 * both lookup mechanisms agree.
 */
class CrmIssueRegistry : IssueRegistry() {

    override val api: Int = CURRENT_API

    override val issues: List<Issue> = listOf(
        StatefulObjectSingletonDetector.ISSUE,
        GlobalScopeLaunchDetector.ISSUE,
        // §20.1 — Retrofit/OkHttp/ApiClient banned outside data/remote/ and di/.
        RetrofitOutsideRemoteDetector.ISSUE,
    )

    override val vendor: Vendor = Vendor(
        vendorName = "Bizarre Electronics",
        identifier = "com.bizarreelectronics.crm",
    )
}
