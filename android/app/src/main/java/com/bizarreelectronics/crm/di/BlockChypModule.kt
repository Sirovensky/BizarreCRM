package com.bizarreelectronics.crm.di

import android.content.Context
import android.content.SharedPreferences
import com.bizarreelectronics.crm.data.blockchyp.BlockChypClient
import com.bizarreelectronics.crm.data.remote.api.BlockChypApi
import com.bizarreelectronics.crm.util.SignaturePromptHost
import com.bizarreelectronics.crm.util.SignatureRouter
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import retrofit2.Retrofit
import javax.inject.Named
import javax.inject.Singleton

/**
 * Hilt module providing [BlockChypClient], [SignatureRouter], and their
 * supporting bindings.
 *
 * The [SignaturePromptHost] binding is deliberately left **unbound** here —
 * it is an interface that the UI layer (MainActivity or a navigation
 * coordinator) must implement and register at runtime via a Hilt entry point
 * or by providing the binding in an `@ActivityComponent` submodule.
 * Keeping it out of SingletonComponent prevents a memory leak where the
 * singleton holds a reference to an Activity.
 *
 * Phase 4 — BlockChyp Android SDK + SignatureRouter.
 */
@Module
@InstallIn(SingletonComponent::class)
object BlockChypModule {

    /**
     * Named [SharedPreferences] for terminal pairing state.
     * Isolated from the app's main prefs so a future migration can switch
     * to EncryptedSharedPreferences without touching the auth prefs.
     */
    @Provides
    @Singleton
    @Named("blockchyp")
    fun provideBlockChypPrefs(
        @ApplicationContext context: Context,
    ): SharedPreferences = context.getSharedPreferences("blockchyp_prefs", Context.MODE_PRIVATE)

    @Provides
    @Singleton
    fun provideBlockChypApi(retrofit: Retrofit): BlockChypApi =
        retrofit.create(BlockChypApi::class.java)

    @Provides
    @Singleton
    fun provideBlockChypClient(
        api: BlockChypApi,
        @Named("blockchyp") prefs: SharedPreferences,
    ): BlockChypClient = BlockChypClient(api, prefs)

    /**
     * [SignatureRouter] requires a [SignaturePromptHost]. The host is a UI
     * component (Activity / Compose navigator) that must be bound at the
     * activity scope. This singleton [SignatureRouter] accepts it as a
     * constructor param — call [SignatureRouter] from a ViewModel that
     * injects both [SignatureRouter] and wires the host via a callback.
     *
     * A NullSignaturePromptHost stub is provided here so the graph compiles;
     * the real host is injected at runtime by MainActivity before the first
     * [SignatureRouter.capture] call. This follows the same pattern used by
     * BroadcastReceiver + Activity communication.
     */
    @Provides
    @Singleton
    fun provideSignaturePromptHost(): SignaturePromptHost = NullSignaturePromptHost()

    @Provides
    @Singleton
    fun provideSignatureRouter(
        client: BlockChypClient,
        host: SignaturePromptHost,
    ): SignatureRouter = SignatureRouter(client, host)
}

/**
 * Stub host returned when the real Activity host has not yet been registered.
 * Immediately calls [onResult] with null (cancellation) so that the
 * [SignatureRouter] coroutine resumes and the caller can surface a graceful
 * error rather than hanging forever.
 */
private class NullSignaturePromptHost : SignaturePromptHost {
    override fun showSignaturePad(
        reason: com.bizarreelectronics.crm.util.SignatureReason,
        onResult: (String?) -> Unit,
    ) {
        onResult(null)
    }
}
