-keepclasseswithmembernames class * {
    native <methods>;
}

-keep class github.com.maragung.octopus_wallet.OctraNative { *; }

-keep class org.json.** { *; }

-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

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
