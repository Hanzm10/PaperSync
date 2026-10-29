# WorkManager, which ML Kit uses to download models, opens its Room database
# by looking up the generated WorkDatabase_Impl class by name. R8 cannot see
# that use, so in a release build it removed the class and the app crashed on
# start with "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
