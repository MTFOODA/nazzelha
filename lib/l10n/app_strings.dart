import 'package:flutter/widgets.dart';

import '../models/download_task.dart';

/// Lightweight localization for the Nazzelha Sawa feature.
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

  // Navigation / shell
  String get navDownload => _t('Download', 'تحميل');
  String get navSawa => _t('Nazzelha Sawa', 'نزلها سوا');
  String get languageToggle => _t('Language', 'اللغة');

  // Sawa screen
  String get sawaTitle => _t('Nazzelha Sawa', 'نزلها سوا');
  String get add => _t('Add', 'إضافة');
  String get emptyTitle =>
      _t('Build your download queue', 'ابدأ قائمة التحميل');
  String get emptyBody => _t(
      'Tap + Add to paste a link and start building your queue.',
      'اضغط + إضافة للصق رابط والبدء في بناء قائمتك.');

  // Card
  String get saveAs => _t('Save as', 'حفظ باسم');
  String get optionalFilename =>
      _t('Optional filename', 'اسم الملف (اختياري)');
  String get pasteLink => _t('Paste video link...', 'الصق رابط الفيديو...');
  String get videoMode => _t('Nazzelha Video', 'نزلها فيديو');
  String get audioMode => _t('Nazzelha Audio', 'نزلها صوت');
  String get start => _t('Start', 'ابدأ');
  String get resume => _t('Resume', 'استئناف');
  String get remove => _t('Remove', 'إزالة');

  // Remove confirmation dialog
  String get cancelDialogTitle => _t('Cancel this download?', 'إلغاء هذا التحميل؟');
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
