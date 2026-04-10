# Retrofit
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn retrofit2.KotlinExtensions
-dontwarn retrofit2.KotlinExtensions$*

# Gson
-keepclassmembers class com.bizarreelectronics.crm.data.remote.dto.** { *; }
-keep class com.google.gson.** { *; }

# Room — keep database class + all entity classes
-keep class * extends androidx.room.RoomDatabase
-keep class com.bizarreelectronics.crm.data.local.db.entities.** { *; }
-keep class * implements androidx.room.DatabaseConfiguration
-dontwarn androidx.room.paging.**

# Hilt — keep ViewModel constructors
-keep class * { @dagger.hilt.android.lifecycle.HiltViewModel <init>(...); }
-keep class com.bizarreelectronics.crm.di.** { *; }

# OkHttp
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
