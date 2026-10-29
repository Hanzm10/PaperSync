# WorkManager, which ML Kit uses to download models, opens its Room database
# by looking up the generated WorkDatabase_Impl class by name. R8 cannot see
# that use, so in a release build it removed the class and the app crashed on
# start with "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# ML Kit finds its model downloader and other parts by name at runtime.
# Keep them whole so the release shrinker cannot break the model download.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
