enum TranslationMode {
  offline,
  online;

  String get label => this == offline ? '离线' : '在线';
}
