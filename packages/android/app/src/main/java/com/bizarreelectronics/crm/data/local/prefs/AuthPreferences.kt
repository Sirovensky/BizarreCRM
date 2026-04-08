package com.bizarreelectronics.crm.data.local.prefs

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthPreferences @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "auth_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    /**
     * Emits Unit each time [clear] is called (e.g. after a failed token refresh).
     * Observe this in UI to redirect the user back to the login screen.
     * replay=0 so late subscribers don't get a stale event.
     */
    private val _authCleared = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val authCleared: SharedFlow<Unit> = _authCleared.asSharedFlow()

    var accessToken: String?
        get() = prefs.getString("access_token", null)
        set(value) = prefs.edit().putString("access_token", value).apply()

    var userId: Long
        get() = prefs.getLong("user_id", 0)
        set(value) = prefs.edit().putLong("user_id", value).apply()

    var username: String?
        get() = prefs.getString("username", null)
        set(value) = prefs.edit().putString("username", value).apply()

    var userRole: String?
        get() = prefs.getString("user_role", null)
        set(value) = prefs.edit().putString("user_role", value).apply()

    var userFirstName: String?
        get() = prefs.getString("user_first_name", null)
        set(value) = prefs.edit().putString("user_first_name", value).apply()

    var userLastName: String?
        get() = prefs.getString("user_last_name", null)
        set(value) = prefs.edit().putString("user_last_name", value).apply()

    var serverUrl: String?
        get() = prefs.getString("server_url", null)
        set(value) = prefs.edit().putString("server_url", value).apply()

    var storeName: String?
        get() = prefs.getString("store_name", null)
        set(value) = prefs.edit().putString("store_name", value).apply()

    var refreshToken: String?
        get() = prefs.getString("refresh_token", null)
        set(value) = prefs.edit().putString("refresh_token", value).apply()

    val isLoggedIn: Boolean
        get() = accessToken != null

    fun clear() {
        prefs.edit().clear().apply()
        _authCleared.tryEmit(Unit)
    }

    fun saveUser(token: String, refreshToken: String?, id: Long, username: String, firstName: String?, lastName: String?, role: String) {
        prefs.edit()
            .putString("access_token", token)
            .putString("refresh_token", refreshToken)
            .putLong("user_id", id)
            .putString("username", username)
            .putString("user_first_name", firstName)
            .putString("user_last_name", lastName)
            .putString("user_role", role)
            .apply()
    }
}
