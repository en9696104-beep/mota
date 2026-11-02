# llama_flutter_android 的 Kotlin/JNI 类需要保留（release 混淆保护）
-keep class com.write4me.llama_flutter_android.** { *; }

-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}

-keepclasseswithmembernames class * {
    native <methods>;
}

# ML Kit 文字识别：仅打包中文识别模型包，其他语言识别器类由插件引用但不存在，
# R8 需显式忽略（运行时不会走到这些分支）
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
