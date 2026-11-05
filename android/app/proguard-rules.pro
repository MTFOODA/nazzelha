# Chaquopy calls these methods by name from Python, outside R8's call graph.
# Preserve both the contract and its anonymous service/activity implementations.
-keep interface com.example.nazzelha.ProgressSink { *; }
-keep class * implements com.example.nazzelha.ProgressSink {
    public void send(java.lang.String);
    public boolean isCancelled();
}
