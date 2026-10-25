# llama_flutter_android 的 Kotlin/JNI 类需要保留（release 混淆保护）
-keep class com.write4me.llama_flutter_android.** { *; }

-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

-keepclasseswithmembernames class * {
    native <methods>;
}
