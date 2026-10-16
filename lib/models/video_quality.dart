class VideoQuality {
  final int height;
  final String label;

  VideoQuality({required this.height, required this.label});

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoQuality &&
          runtimeType == other.runtimeType &&
          height == other.height;

  @override
  int get hashCode => height.hashCode;
}
