package com.bizarreelectronics.crm.testing

import com.bizarreelectronics.crm.data.remote.RetrofitClient
import com.bizarreelectronics.crm.data.remote.SyncHttp
import com.bizarreelectronics.crm.data.remote.api.*
import com.google.gson.Gson
import dagger.Module
import dagger.Provides
import dagger.hilt.components.SingletonComponent
import dagger.hilt.testing.TestInstallIn
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import javax.inject.Singleton

/**
 * TestApiModule — replaces [RetrofitClient] in unit tests.
 *
 * Provides a plain Retrofit instance pointing at `http://localhost/` backed by a
 * bare [OkHttpClient] with no interceptors, no certificate pinning, and no auth
 * logic. Individual tests that need real HTTP responses should swap the base URL
 * to a [okhttp3.mockwebserver.MockWebServer] address before injecting.
 *
 * All API interfaces are created from this stub Retrofit so that repositories
 * compile and inject cleanly without touching the real network stack.
 *
 * Plan ref: ActionPlan §1.6 line 223.
 */
@Module
@TestInstallIn(
    components = [SingletonComponent::class],
    replaces = [RetrofitClient::class],
)
object TestApiModule {

    /** Stub base URL used by the no-op Retrofit instance. Tests override via MockWebServer. */
    private const val STUB_BASE_URL = "http://localhost/"

    @Provides
    @Singleton
    fun provideGson(): Gson = Gson()

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient = OkHttpClient.Builder().build()

    /**
     * Returns the same plain client for sync operations; no separate timeout
     * needed in unit tests.
     */
    @Provides
    @Singleton
    @SyncHttp
    fun provideSyncOkHttpClient(client: OkHttpClient): OkHttpClient = client

    @Provides
    @Singleton
    fun provideRetrofit(client: OkHttpClient, gson: Gson): Retrofit =
        Retrofit.Builder()
            .baseUrl(STUB_BASE_URL)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()

    @Provides
    @Singleton
    @SyncHttp
    fun provideSyncRetrofit(retrofit: Retrofit): Retrofit = retrofit

    @Provides @Singleton fun provideAuthApi(r: Retrofit): AuthApi = r.create(AuthApi::class.java)
    @Provides @Singleton fun provideCustomerApi(r: Retrofit): CustomerApi = r.create(CustomerApi::class.java)
    @Provides @Singleton fun provideTicketApi(r: Retrofit): TicketApi = r.create(TicketApi::class.java)
    @Provides @Singleton fun provideInvoiceApi(r: Retrofit): InvoiceApi = r.create(InvoiceApi::class.java)
    @Provides @Singleton fun provideInventoryApi(r: Retrofit): InventoryApi = r.create(InventoryApi::class.java)
    @Provides @Singleton fun provideSmsApi(r: Retrofit): SmsApi = r.create(SmsApi::class.java)
    @Provides @Singleton fun provideNotificationApi(r: Retrofit): NotificationApi = r.create(NotificationApi::class.java)
    @Provides @Singleton fun provideSearchApi(r: Retrofit): SearchApi = r.create(SearchApi::class.java)
    @Provides @Singleton fun provideSettingsApi(r: Retrofit): SettingsApi = r.create(SettingsApi::class.java)
    @Provides @Singleton fun provideReportApi(r: Retrofit): ReportApi = r.create(ReportApi::class.java)
    @Provides @Singleton fun provideLeadApi(r: Retrofit): LeadApi = r.create(LeadApi::class.java)
    @Provides @Singleton fun provideEstimateApi(r: Retrofit): EstimateApi = r.create(EstimateApi::class.java)
    @Provides @Singleton fun provideExpenseApi(r: Retrofit): ExpenseApi = r.create(ExpenseApi::class.java)
    @Provides @Singleton fun provideCatalogApi(r: Retrofit): CatalogApi = r.create(CatalogApi::class.java)
    @Provides @Singleton fun provideTenantsApi(r: Retrofit): TenantsApi = r.create(TenantsApi::class.java)
    @Provides @Singleton fun provideRepairPricingApi(r: Retrofit): RepairPricingApi = r.create(RepairPricingApi::class.java)
}
