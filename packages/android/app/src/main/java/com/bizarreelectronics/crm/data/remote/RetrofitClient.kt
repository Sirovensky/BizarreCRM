package com.bizarreelectronics.crm.data.remote

import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.*
import com.bizarreelectronics.crm.data.remote.interceptors.AuthInterceptor
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

/**
 * Interceptor that dynamically rewrites the base URL on every request
 * based on the server URL stored in AuthPreferences.
 * This allows the user to configure the server IP at runtime.
 */
class DynamicBaseUrlInterceptor(private val authPreferences: AuthPreferences) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
        val originalRequest = chain.request()
        val serverUrl = authPreferences.serverUrl

        if (serverUrl.isNullOrBlank()) {
            return chain.proceed(originalRequest)
        }

        val newBaseUrl = "$serverUrl/api/v1/".toHttpUrlOrNull() ?: return chain.proceed(originalRequest)

        // Replace the placeholder base URL with the real one
        val newUrl = originalRequest.url.newBuilder()
            .scheme(newBaseUrl.scheme)
            .host(newBaseUrl.host)
            .port(newBaseUrl.port)
            .build()

        val newRequest = originalRequest.newBuilder()
            .url(newUrl)
            .build()

        return chain.proceed(newRequest)
    }
}

@Module
@InstallIn(SingletonComponent::class)
object RetrofitClient {

    @Provides
    @Singleton
    fun provideGson(): Gson = GsonBuilder()
        .setLenient()
        // Don't auto-convert field names — we use @SerializedName explicitly where needed
        // This preserves camelCase Kotlin fields while matching snake_case JSON via annotations
        .create()

    @Provides
    @Singleton
    fun provideAuthInterceptor(
        authPreferences: AuthPreferences,
        gson: Gson,
    ): AuthInterceptor = AuthInterceptor(authPreferences, gson)

    @Provides
    @Singleton
    fun provideDynamicBaseUrlInterceptor(
        authPreferences: AuthPreferences,
    ): DynamicBaseUrlInterceptor = DynamicBaseUrlInterceptor(authPreferences)

    @Provides
    @Singleton
    fun provideLoggingInterceptor(): HttpLoggingInterceptor {
        return HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BODY
                    else HttpLoggingInterceptor.Level.NONE
        }
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
    ): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .addInterceptor(dynamicBaseUrlInterceptor)
            .addInterceptor(authInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)

        // In debug builds, trust all SSL certificates (for self-signed certs on LAN)
        if (BuildConfig.DEBUG) {
            val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
            })
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, trustAllCerts, SecureRandom())
            builder.sslSocketFactory(sslContext.socketFactory, trustAllCerts[0] as X509TrustManager)
            builder.hostnameVerifier { _, _ -> true }
        }

        return builder.build()
    }

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient, gson: Gson): Retrofit {
        // Use a placeholder base URL — the DynamicBaseUrlInterceptor rewrites it
        return Retrofit.Builder()
            .baseUrl("http://localhost/api/v1/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    // --- API interface providers ---
    @Provides @Singleton fun provideAuthApi(retrofit: Retrofit): AuthApi = retrofit.create(AuthApi::class.java)
    @Provides @Singleton fun provideTicketApi(retrofit: Retrofit): TicketApi = retrofit.create(TicketApi::class.java)
    @Provides @Singleton fun provideCustomerApi(retrofit: Retrofit): CustomerApi = retrofit.create(CustomerApi::class.java)
    @Provides @Singleton fun provideInventoryApi(retrofit: Retrofit): InventoryApi = retrofit.create(InventoryApi::class.java)
    @Provides @Singleton fun provideInvoiceApi(retrofit: Retrofit): InvoiceApi = retrofit.create(InvoiceApi::class.java)
    @Provides @Singleton fun provideSmsApi(retrofit: Retrofit): SmsApi = retrofit.create(SmsApi::class.java)
    @Provides @Singleton fun provideSearchApi(retrofit: Retrofit): SearchApi = retrofit.create(SearchApi::class.java)
    @Provides @Singleton fun provideNotificationApi(retrofit: Retrofit): NotificationApi = retrofit.create(NotificationApi::class.java)
    @Provides @Singleton fun provideReportApi(retrofit: Retrofit): ReportApi = retrofit.create(ReportApi::class.java)
    @Provides @Singleton fun provideSettingsApi(retrofit: Retrofit): SettingsApi = retrofit.create(SettingsApi::class.java)
    @Provides @Singleton fun provideCatalogApi(retrofit: Retrofit): CatalogApi = retrofit.create(CatalogApi::class.java)
    @Provides @Singleton fun provideRepairPricingApi(retrofit: Retrofit): RepairPricingApi = retrofit.create(RepairPricingApi::class.java)
}
