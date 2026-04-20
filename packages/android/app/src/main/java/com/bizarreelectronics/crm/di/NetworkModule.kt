package com.bizarreelectronics.crm.di

import com.google.gson.Gson
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /**
     * Provides a singleton [Gson] instance for use across the app.
     * AND-032: centralises Gson so callers (e.g. WebSocketService) do not
     * instantiate a new Gson on every message, avoiding unnecessary allocation
     * and enabling future serialisation configuration in one place.
     */
    @Provides
    @Singleton
    fun provideGson(): Gson = Gson()
}
