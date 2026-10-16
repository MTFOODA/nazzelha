import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../theme/theme_provider.dart';
import '../services/python_service.dart';
import '../models/video_quality.dart';
import 'download_screen.dart';
import '../widgets/custom_dropdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TextEditingController _urlController;
  String _selectedPlatform = 'youtube';
  List<VideoQuality> _availableQualities = [];
  VideoQuality? _selectedQuality;
  bool _isLoadingQualities = false;
  String? _qualitiesError;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _validateUrl() {
    debugPrint('[Submit] Started');
    setState(() {
      _urlError = null;
      _availableQualities = [];
      _selectedQuality = null;
      _qualitiesError = null;
    });

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _urlError = 'Please enter a video URL';
      });
      return;
    }

    if (!url.startsWith('http')) {
      setState(() {
        _urlError = 'URL must start with http:// or https://';
      });
      return;
    }

    // Platform validation
    if (_selectedPlatform == 'youtube') {
      if (!url.contains('youtube.com') && !url.contains('youtu.be')) {
        setState(() {
          _urlError = 'This doesn\'t look like a valid YouTube URL';
        });
        return;
      }
    } else if (_selectedPlatform == 'facebook') {
      if (!url.contains('facebook.com') && !url.contains('fb.watch')) {
        setState(() {
          _urlError = 'This doesn\'t look like a valid Facebook URL';
        });
        return;
      }
    } else if (_selectedPlatform == 'instagram') {
      if (!url.contains('instagram.com') && !url.contains('instagr.am')) {
        setState(() {
          _urlError = 'This doesn\'t look like a valid Instagram URL';
        });
        return;
      }
    } else if (_selectedPlatform == 'tiktok') {
      if (!url.contains('tiktok.com') &&
          !url.contains('vt.tiktok.com') &&
          !url.contains('vm.tiktok.com')) {
        setState(() {
          _urlError = 'This doesn\'t look like a valid TikTok URL';
        });
        return;
      }
    }

    debugPrint('[Submit] URL validated');
    _fetchAvailableQualities(url);
  }

  Future<void> _fetchAvailableQualities(String url) async {
    debugPrint('[Submit] Starting extraction (platform: $_selectedPlatform)');
    setState(() {
      _isLoadingQualities = true;
      _qualitiesError = null;
    });

    List<int>? qualities;
    String? errorMessage;

    try {
      final pythonService = Provider.of<PythonService>(context, listen: false);
      qualities =
          await pythonService.getAvailableQualities(url, _selectedPlatform);
      debugPrint(
          '[Submit] Extraction successful (${qualities.length} formats)');
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
      debugPrint('[Submit] Extraction failed: $errorMessage');
    }

    // Single exit point: whatever happened above (success, empty result,
    // backend error, timeout), the loading state is cleared exactly once so
    // SUBMIT can never remain stuck in its loading state.
    if (!mounted) return;
    setState(() {
      if (qualities != null && qualities.isNotEmpty) {
        _availableQualities = qualities
            .map((height) => VideoQuality(height: height, label: '${height}p'))
            .toList();

        // Select the highest quality by default
        if (_availableQualities.isNotEmpty) {
          _selectedQuality = _availableQualities.last;
        }
        debugPrint(
            '[Submit] Updating quality state (${_availableQualities.length} qualities)');
      } else {
        // Empty formats must never be treated as success.
        _availableQualities = [];
        _selectedQuality = null;
        _qualitiesError = qualities != null
            ? 'No downloadable qualities were found for this URL.'
            : (errorMessage ?? 'Unable to extract video information.');
      }
      _isLoadingQualities = false;
      debugPrint('[Submit] Loading finished');
    });
  }

  void _startDownload({String mode = 'video'}) {
    if (_selectedQuality == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a quality'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DownloadScreen(
          url: _urlController.text.trim(),
          platform: _selectedPlatform,
          quality: _selectedQuality!.height,
          mode: mode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with theme toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            Text(
                              'Nazzelha',
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textDark
                                    : AppColors.textLight,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            themeProvider.isDarkMode
                                ? Icons.light_mode
                                : Icons.dark_mode,
                            size: 24,
                          ),
                          onPressed: () => themeProvider.toggleTheme(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Platform selection
                    Text(
                      'Platform',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? AppColors.textDark : AppColors.textLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CustomDropdown<String>(
                      value: _selectedPlatform,
                      items: const [
                        'youtube',
                        'facebook',
                        'instagram',
                        'tiktok'
                      ],
                      itemLabels: const [
                        'YouTube',
                        'Facebook',
                        'Instagram',
                        'TikTok'
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPlatform = value;
                          _urlError = null;
                          _availableQualities = [];
                          _selectedQuality = null;
                          _qualitiesError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 24),
                    // URL input
                    Text(
                      'Video URL',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? AppColors.textDark : AppColors.textLight,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        hintText:
                            'Paste your $_selectedPlatform video URL here...',
                        errorText: _urlError,
                      ),
                      maxLines: null,
                      onChanged: (_) {
                        if (_urlError != null) {
                          setState(() {
                            _urlError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoadingQualities ? null : _validateUrl,
                        child: _isLoadingQualities
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'YALLA Nazzelha',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Quality selection
                    if (_availableQualities.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Available Quality',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textDark
                                      : AppColors.textLight,
                                ),
                              ),
                              const SizedBox(height: 12),
                              CustomDropdown<VideoQuality>(
                                value: _selectedQuality,
                                items: _availableQualities,
                                itemLabels: _availableQualities
                                    .map((q) => q.label)
                                    .toList(),
                                onChanged: (quality) {
                                  setState(() {
                                    _selectedQuality = quality;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Download button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _startDownload,
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(
                            'Nazzelha Video',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Audio-only download option (button is enabled once a
                      // quality has been resolved; audio mode ignores the
                      // selected height and uses the best audio stream).
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _selectedQuality == null
                              ? null
                              : () => _startDownload(mode: 'audio'),
                          icon: const Icon(Icons.music_note),
                          label: Text(
                            'Nazzelha Audio',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ] else if (_qualitiesError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight.withValues(alpha: 0.1),
                          border: Border.all(color: AppColors.errorLight),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.errorLight,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _qualitiesError!,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: AppColors.errorLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
