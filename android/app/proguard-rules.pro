# WorkManager 2.7.0 / Room 2.2.5：
# Room 通过反射实例化 WorkDatabase_Impl，需要保留无参构造器。
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
