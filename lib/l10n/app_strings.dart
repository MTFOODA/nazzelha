import 'package:flutter/widgets.dart';

import '../models/download_task.dart';

/// Lightweight localization for the Nazzelha feature.
///
/// This is intentionally a small, dependency-free string table (English +
/// Arabic) rather than a full `intl`/`.arb` framework. Material's text
/// direction (LTR/RTL) is driven by `flutter_localizations` + the active
/// locale, so Arabic renders right-to-left automatically.
class AppStrings {
  final Locale locale;
  const AppStrings(this.locale);

  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));

  bool get isAr => locale.languageCode == 'ar';

  String _t(String en, String ar) => isAr ? ar : en;

  String text(String english) => isAr ? (_labels[english] ?? english) : english;
  String qualityLabel(int height) =>
      height >= 4320 ? text('Best available') : '${height}p';
  String transferDetails(String speed, String eta) =>
      isAr ? 'السرعة: $speed • المتبقي: $eta' : 'Speed: $speed • ETA: $eta';

  String errorMessage(String raw) {
    final message =
        raw.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    if (message.contains(
        'YouTube is blocking requests from the hosted download service.')) {
      return isAr
          ? 'يوتيوب يمنع طلبات خدمة التنزيل المستضافة لهذا الرابط. استخدم تطبيق Android أو Windows لتنزيله.'
          : 'YouTube is blocking requests from the hosted download service. Use the Android or Windows app for this link.';
    }
    if (isAr && _labels.containsKey(message)) return _labels[message]!;
    final lower = message.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('timeout')) {
      return isAr
          ? 'تعذّر الاتصال بالمنصة. تحقق من الإنترنت وحاول مجددًا.'
          : message;
    }
    if ([
      'facebook did not return',
      'authentication',
      'sign in',
      'login',
      'could not extract',
      'unable to extract',
      'unavailable',
      'no videos',
      'private video',
      'video not found',
      'not available',
      'restricted',
      'session',
      'cookie',
      'cannot parse data'
    ].any(lower.contains)) {
      return isAr
          ? 'الفيديو مغلق من ناشر الفيديو.'
          : 'This video is restricted by its publisher.';
    }
    if (!isAr) return message;
    if (lower.contains('ffmpeg') || lower.contains('merged')) {
      return 'تعذّر دمج ملفات الصوت والفيديو. أعد المحاولة.';
    }
    if (lower.contains('file') ||
        lower.contains('folder') ||
        lower.contains('directory')) {
      return 'تعذّر الوصول إلى الملف أو مجلد الحفظ. راجع المسار والصلاحيات.';
    }
    return 'تعذّر إكمال العملية. راجع الرابط واتصال الإنترنت وحاول مجددًا.';
  }

  static const _labels = <String, String>{
    'The built-in YouTube JavaScript engine could not start. Please restart the app or update to the latest version.':
        'تعذّر تشغيل محرك تنزيل يوتيوب المدمج. أعد تشغيل التطبيق أو حدّثه لآخر إصدار.',
    'The free web edition supports files up to 96 MB. Choose a lower quality or use the app.':
        'نسخة الويب المجانية تدعم الملفات حتى ٩٦ ميجابايت. اختر جودة أقل أو استخدم التطبيق.',
    'The free web edition allows about 4 minutes to prepare a video. Try a lower quality or use the app.':
        'نسخة الويب المجانية تتيح حوالي ٤ دقائق لتجهيز الفيديو. اختر جودة أقل أو استخدم التطبيق.',
    'Please save these videos individually. The browser ZIP limit is 128 MB.':
        'احفظ الفيديوهات منفردة. الحد الأقصى لملف ZIP في المتصفح هو ١٢٨ ميجابايت.',
    'The free download service is waking up. Please try again shortly.':
        'خدمة التحميل المجانية تبدأ التشغيل الآن. حاول مجددًا بعد قليل.',
    'The free service is busy. Please try again shortly.':
        'الخدمة المجانية مشغولة الآن. حاول مجددًا بعد قليل.',
    'The download service is unavailable. Please try again shortly.':
        'خدمة التحميل غير متاحة الآن. حاول مجددًا بعد قليل.',
    'This temporary file expired. Prepare the video again.':
        'انتهت صلاحية الملف المؤقت. جهّز الفيديو مرة أخرى.',
    'Please reconnect to the download service.':
        'أعد الاتصال بخدمة التحميل وحاول مجددًا.',
    'The free web edition supports files up to 256 MB. Choose a lower quality or use the app.':
        'نسخة الويب المجانية تدعم الملفات حتى ٢٥٦ ميجابايت. اختر جودة أقل أو استخدم التطبيق.',
    'The free web edition supports files up to 256 MB. Use the app for larger files.':
        'نسخة الويب المجانية تدعم الملفات حتى ٢٥٦ ميجابايت. استخدم التطبيق للملفات الأكبر.',
    'Temporary storage is full. Please try later or use the app.':
        'التخزين المؤقت ممتلئ. حاول لاحقًا أو استخدم التطبيق.',
    'Temporary storage is full. Please save videos individually or use the app.':
        'التخزين المؤقت ممتلئ. احفظ الفيديوهات منفردة أو استخدم التطبيق.',
    'The download service is being configured. Please try again later.':
        'خدمة التحميل قيد التجهيز. حاول مجددًا لاحقًا.',
    'A download is already running in this browser.':
        'يوجد تحميل جارٍ في هذا المتصفح.',
    'Choose between 1 and 200 prepared videos per ZIP.':
        'اختر من فيديو واحد إلى ٢٠٠ فيديو جاهز لكل ملف ZIP.',
    'Light mode': 'الوضع الفاتح',
    'Dark mode': 'الوضع الداكن',
    'Download a video': 'نزّل فيديو',
    'One link. Your best quality.': 'رابط واحد، وأفضل جودة متاحة.',
    'Paste a link to get started.': 'الصق الرابط وابدأ التحميل.',
    'Platform': 'المنصة',
    'Video link': 'رابط الفيديو',
    'Paste video link': 'الصق رابط الفيديو',
    'Find available qualities': 'عرض الجودات المتاحة',
    'Finding your video…': 'جارٍ البحث عن الفيديو…',
    'Available quality': 'الجودة المتاحة',
    'Best available': 'أفضل جودة متاحة',
    'Video': 'فيديو',
    'Audio': 'صوت',
    'Download video': 'تحميل الفيديو',
    'Download audio': 'تحميل الصوت',
    'Please enter a video URL': 'أدخل رابط الفيديو',
    'URL must start with http:// or https://':
        'أدخل رابطًا يبدأ بـ http:// أو https://',
    'This URL does not match the selected platform.':
        'الرابط لا يطابق المنصة المحددة.',
    'Please select a quality': 'اختر الجودة أولًا',
    'No downloadable qualities were found for this URL.':
        'لا توجد جودات قابلة للتحميل لهذا الرابط.',
    'Unable to extract video information.': 'تعذّر استخراج معلومات الفيديو.',
    'Downloading…': 'جارٍ التحميل…',
    'Download complete': 'اكتمل التحميل',
    'Download failed': 'تعذّر التحميل',
    'Download cancelled': 'تم إلغاء التحميل',
    'Your video is being downloaded': 'جاري تحميل الفيديو بأفضل جودة تختارها',
    'Your audio is being downloaded': 'جاري تحميل الملف الصوتي',
    'Merging audio and video…': 'جارٍ دمج الصوت والفيديو…',
    'Your file is ready.': 'ملفك جاهز.',
    'Saved to': 'تم الحفظ في',
    'Open video': 'فتح الفيديو',
    'Play audio': 'تشغيل الصوت',
    'Download another': 'تحميل رابط آخر',
    'Try again': 'حاول مجددًا',
    'Back to downloads': 'العودة للتحميل',
    'Cancel': 'إلغاء',
    'Quality': 'الجودة',
    'Audio • MP3 192 kbps': 'صوت • MP3 192 كيلوبت/ث',
    'Please enter a YouTube playlist URL containing list=.':
        'أدخل رابط بلاي ليست يوتيوب يحتوي على list=.',
    'Please enter a folder name.': 'أدخل اسم المجلد.',
    'Another operation is running. Please wait.':
        'توجد عملية قيد التنفيذ. انتظر حتى تنتهي.',
    'Preparing your downloads': 'نجهّز لك التحميل',
    'All your media, one place.': 'كل فيديوهاتك، في مكان واحد.',
    'Open folder': 'فتح المجلد',
    'Copy path': 'نسخ المسار',
    'Path copied': 'تم نسخ المسار',
    'Pending': 'في الانتظار',
    'Downloading': 'جارٍ التحميل',
    'Completed': 'اكتمل',
    'Failed': 'فشل',
    'Paused': 'متوقف مؤقتًا',
    'Unavailable': 'غير متاح',
    'Unavailable videos are marked individually; other videos keep downloading.':
        'الفيديو غير المتاح يظهر بحالته، وباقي الفيديوهات تكمل التحميل.',
  };

  // Navigation / shell
  String get navDownload => _t('Download', 'تحميل');
  String get navHome => _t('Nazzelha', 'نزلها');
  String get languageToggle => _t('Language', 'اللغة');

  // Download queue
  String get appTitle => _t('Nazzelha', 'نزلها');
  String get add => _t('Add', 'إضافة');
  String get emptyTitle =>
      _t('Build your download queue', 'ابدأ قائمة التحميل');
  String get emptyBody => _t(
      'Tap + Add to paste a link and start building your queue.',
      'اضغط + إضافة للصق رابط والبدء في بناء قائمتك.');

  // Card
  String get saveAs => _t('Save as', 'حفظ باسم');
  String get optionalFilename => _t('Optional filename', 'اسم الملف (اختياري)');
  String get pasteLink => _t('Paste video link...', 'الصق رابط الفيديو...');
  String get videoMode => _t('Nazzelha Video', 'نزلها فيديو');
  String get audioMode => _t('Nazzelha Audio', 'نزلها صوت');
  String get start => _t('Start', 'ابدأ');
  String get resume => _t('Resume', 'استئناف');
  String get remove => _t('Remove', 'إزالة');

  // Remove confirmation dialog
  String get cancelDialogTitle =>
      _t('Cancel this download?', 'إلغاء هذا التحميل؟');
  String get cancelDialogBody => _t(
      'This task is currently downloading. Removing it will cancel the '
          'download and stop the file from being saved.',
      'هذه المهمة قيد التحميل الآن. ستؤدي إزالتها إلى إلغاء التحميل وعدم حفظ الملف.');
  String get keep => _t('Keep', 'إبقاء');
  String get removeAndCancel => _t('Remove & cancel', 'إزالة وإلغاء');

  String statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return _t('Pending', 'بانتظار');
      case TaskStatus.queued:
        return _t('Queued', 'في الانتظار');
      case TaskStatus.downloading:
        return _t('Downloading', 'جارٍ التحميل');
      case TaskStatus.merging:
        return _t('Merging', 'جارٍ الدمج');
      case TaskStatus.paused:
        return _t('Paused', 'مؤقت');
      case TaskStatus.completed:
        return _t('Completed', 'اكتمل');
      case TaskStatus.failed:
        return _t('Failed', 'فشل');
      case TaskStatus.cancelled:
        return _t('Cancelled', 'أُلغي');
    }
  }

  String platformName(String platform) {
    switch (platform.toLowerCase()) {
      case 'youtube':
        return _t('YouTube', 'يوتيوب');
      case 'facebook':
        return _t('Facebook', 'فيسبوك');
      case 'instagram':
        return _t('Instagram', 'انستغرام');
      case 'tiktok':
        return _t('TikTok', 'تيك توك');
      default:
        return platform;
    }
  }

  /// Localized validation message for a stored error code.
  String validationMessage(String? code, {String? detected, String? selected}) {
    switch (code) {
      case 'busy':
        return _t('Another operation is running. Please wait.',
            'توجد عملية أخرى قيد التنفيذ. انتظر قليلاً.');
      case QueueErrorCodes.invalidUrl:
        return _t('Enter a valid URL (http:// or https://)',
            'أدخل رابطاً صحيحاً (http:// أو https://)');
      case QueueErrorCodes.crossPlatform:
        final detectedName = platformName(detected ?? '');
        final selectedName = platformName(selected ?? '');
        return isAr
            ? 'يبدو هذا الرابط من $detectedName وليس $selectedName.'
            : 'This link looks like a $detectedName URL, not $selectedName.';
      case QueueErrorCodes.platformMismatch:
        return _t('This URL does not match the selected platform.',
            'هذا الرابط لا يطابق المنصة المحددة.');
      default:
        return _t('Invalid input', 'إدخال غير صالح');
    }
  }
}
