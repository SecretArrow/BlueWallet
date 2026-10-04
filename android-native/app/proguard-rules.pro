-keepclasseswithmembernames class * {
    native <methods>;
}

-keep class github.com.maragung.octopus_wallet.OctraNative { *; }

-keep class org.json.** { *; }

-dontwarn okhttp3.**
-dontwarn okio.**
# NOTE: blanket -keep for okhttp3/okio removed for APK size — OkHttp ships
# its own consumer ProGuard rules; R8 keeps everything reachable.

# NOTE: bcprov removed — crypto lives in the native TweetNaCl/PVAC layer.

# SQLCipher ProGuard Rules
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.* { *; }
-keep class net.sqlcipher.database.SupportFactory { *; }
-dontwarn net.sqlcipher.**
-dontwarn net.sqlcipher.database.*

# Room Database
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# Keep native methods for SQLCipher
-keepclasseswithmembernames class * {
    native void <init>(...);
}

# Keep JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep SQLCipher native library
-keep class net.sqlcipher.database.SQLiteDatabase { *; }
-keep class net.sqlcipher.database.SQLiteOpenHelper { *; }
