enum AppEdition { windows, android, iosWeb }

class AppRelease {
  static const version = '1.1.2';
  static const developer = 'Mohamed Fooda';
  static final github = Uri.parse('https://github.com/MTFOODA');
  static final linkedin =
      Uri.parse('https://www.linkedin.com/in/mohamed-fooda-08b00132a/');
  static final website =
      Uri.parse('https://nazzelha.mohamed-fooda-mtf.workers.dev/');
  static Uri url(AppEdition edition) => switch (edition) {
        AppEdition.windows => Uri.parse(
            'https://github.com/MTFOODA/nazzelha/releases/latest/download/Nazzelha-Windows-x64.zip'),
        AppEdition.android => Uri.parse(
            'https://github.com/MTFOODA/nazzelha/releases/latest/download/Nazzelha-Android.apk'),
        AppEdition.iosWeb => website,
      };
}
