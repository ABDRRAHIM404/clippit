import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../models/clip_history_entry.dart';
import '../models/clip_suggestion.dart';
import '../services/db_service.dart';
import '../services/youtube_service.dart';
import '../services/gemini_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/face_tracking_service.dart';
import '../services/storage_service.dart';
import '../controllers/clipper_controller.dart';
import 'processing_screen.dart';
import 'highlights_screen.dart';
import 'edit_screen.dart';
import 'export_screen.dart';

class HomeScreen extends StatefulWidget {
  final DbService dbService;

  const HomeScreen({super.key, required this.dbService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  List<ClipHistoryEntry> _historyList = [];
  String _savedApiKey = '';
  String _savedModelName = 'gemini-1.5-flash'; // Default configured model name
  bool _obscureKey = true;
  bool _isProcessing = false;
  
  ClipperController? _clipperController;
  ClipSuggestion? _selectedSuggestionForEdit;

  final List<String> _availableModels = [
    'gemini-1.5-flash', // Safest, universally supported free-tier fallback
    'gemini-2.5-flash', // Bleeding-edge 2026 high-speed reasoning model
    'gemini-1.5-pro'    // Deep reasoning model
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadSavedSettings();
  }

  // Load saved API key & Model configurations from local device preferences
  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedApiKey = prefs.getString('gemini_api_key') ?? '';
      _savedModelName = prefs.getString('gemini_model_name') ?? 'gemini-1.5-flash';
      _apiKeyController.text = _savedApiKey;
      _initClipperController();
    });
  }

  // Persists the Gemini settings locally
  Future<void> _saveSettings(String key, String modelName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    await prefs.setString('gemini_model_name', modelName);
    
    setState(() {
      _savedApiKey = key.trim();
      _savedModelName = modelName;
      _initClipperController();
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings successfully saved locally!'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // Initializes our state controller only if an API key exists
  void _initClipperController() {
    if (_savedApiKey.isNotEmpty) {
      _clipperController = ClipperController(
        youtubeService: YouTubeService(),
        geminiService: GeminiService(
          apiKey: _savedApiKey,
          analysisModelName: _savedModelName,
          transcriptionModelName: _savedModelName, // 🌟 Match user selected model for transcription!
        ),
        ffmpegService: FFmpegService(),
        captionService: CaptionService(),
        faceTrackingService: FaceTrackingService(),
        storageService: StorageService(),
        dbService: widget.dbService,
      )..addListener(_onControllerStateChanged);
    }
  }

  void _onControllerStateChanged() {
    if (mounted) {
      setState(() {
        _loadHistory(); // reload clips if compilation succeeds
      });
    }
  }

  void _loadHistory() {
    setState(() {
      _historyList = widget.dbService.getAllHistory();
    });
  }

  Future<void> _handleUrlSubmit() async {
    if (_savedApiKey.isEmpty || _clipperController == null) {
      _showApiKeyWarning();
      return;
    }

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a YouTube link')),
      );
      return;
    }
    
    // Trigger download & Pass 1 AI Analysis inside the State Machine
    await _clipperController!.processYouTubeInput(url);
    _urlController.clear();
  }

  Future<void> _pickLocalFile() async {
    if (_savedApiKey.isEmpty || _clipperController == null) {
      _showApiKeyWarning();
      return;
    }

    // Launch Android's native picker intent
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      final file = File(video.path);
      final displayName = video.name;
      
      // Trigger Hashing & Pass 1 AI Analysis inside the State Machine
      await _clipperController!.processLocalFileInput(file, displayName);
    }
  }

  void _showApiKeyWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: AppColors.warning),
            SizedBox(width: 8),
            Text('API Key Required'),
          ],
        ),
        content: const Text(
          'Please enter your Gemini API Key in the Settings panel before starting analysis.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openSettingsBottomSheet();
            },
            child: const Text('Configure Key', style: TextStyle(color: AppColors.primaryLight)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHistoryItem(String id) async {
    await widget.dbService.deleteHistoryEntry(id);
    _loadHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clip deleted and storage cleared')),
      );
    }
  }

  // Opens settings panel to manage Keys and choose models dynamically
  void _openSettingsBottomSheet() {
    String localSelectedModel = _savedModelName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                top: 24,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Icon(Icons.settings, color: AppColors.primaryLight, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Clippit Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Gemini API Key',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      hintText: 'Paste AI Studio Key (AIzaSy...)',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          setModalState(() {
                            _obscureKey = !_obscureKey;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // MODEL SELECTION DROPDOWN
                  const Text(
                    'AI Highlight Model',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: DropdownButton<String>(
                      value: localSelectedModel,
                      isExpanded: true,
                      underline: const SizedBox(),
                      dropdownColor: AppColors.surface,
                      items: _availableModels.map((String model) {
                        return DropdownMenuItem<String>(
                          value: model,
                          child: Text(
                            model,
                            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? val) {
                        if (val != null) {
                          setModalState(() {
                            localSelectedModel = val;
                          });
                        }
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  const Text(
                    'Your API key and model choices are stored 100% locally on your phone filesystem and are only used to talk directly to Gemini APIs.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.3),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _saveSettings(_apiKeyController.text, localSelectedModel);
                        Navigator.pop(context);
                      },
                      child: const Text('Save & Close'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _clipperController?.removeListener(_onControllerStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🌟 STATE-BASED ROUTING LOGIC
    if (_clipperController != null) {
      final status = _clipperController!.status;
      
      // A. Show Processing Overlay for any background pipeline state
      if (status == PipelineStatus.downloading ||
          status == PipelineStatus.hashing ||
          status == PipelineStatus.analyzingPass1 ||
          status == PipelineStatus.trimming ||
          status == PipelineStatus.trackingFaces ||
          status == PipelineStatus.transcribingPass2 ||
          status == PipelineStatus.renderingFinal) {
        return ProcessingScreen(
          statusMessage: _clipperController!.statusMessage,
          progress: _clipperController!.progress,
          onCancel: () => _clipperController!.reset(),
        );
      }

      // B. Show Highlights Panel when suggestions have loaded
      if (status == PipelineStatus.showingHighlights && _selectedSuggestionForEdit == null) {
        return HighlightsScreen(
          suggestions: _clipperController!.suggestions,
          sourceTitle: _clipperController!.activeSourceTitle,
          onClipSelected: (clip) {
            setState(() {
              _selectedSuggestionForEdit = clip;
            });
          },
        );
      }

      // C. Transition to Sliders Fine-Tuning screen (With background asset downloader safe loading!)
      if (_selectedSuggestionForEdit != null && status == PipelineStatus.showingHighlights) {
        if (_clipperController!.processedSourceFile == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.accentNeon),
                  SizedBox(height: 24),
                  Text(
                    'Preparing video assets...',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Fetching high-speed stream preview from YouTube...',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        return EditScreen(
          sourceVideoFile: _clipperController!.processedSourceFile!,
          initialSuggestion: _selectedSuggestionForEdit!,
          onExportTriggered: ({
            required double startSeconds,
            required double endSeconds,
            required bool enableCrop,
            required bool enableCaptions,
            required String selectedLanguage,
          }) {
            setState(() {
              _selectedSuggestionForEdit = null;
            });
            _clipperController!.renderAndExportClip(
              startSeconds: startSeconds,
              endSeconds: endSeconds,
              enableCrop: enableCrop,
              enableCaptions: enableCaptions,
              selectedLanguage: selectedLanguage,
            );
          },
        );
      }

      // D. Show the Video Player Export/Share Sheet on successful rendering
      if (status == PipelineStatus.completed) {
        final File? file = _clipperController!.processedSourceFile;
        return ExportScreen(
          renderedClipFile: file!,
          clipTitle: _clipperController!.activeSourceTitle,
          onReturnHome: () {
            _clipperController!.reset();
          },
        );
      }

      // E. Show Error sheets in case of API failure
      if (status == PipelineStatus.error) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'An error occurred in the pipeline',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _clipperController!.errorMessage ?? 'Unknown error occurred.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _clipperController!.reset(),
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    // Default: Show Core Slogan/Inputs Dashboard (PipelineStatus.idle)
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_filter, color: AppColors.primaryLight, size: 28),
            const SizedBox(width: 8),
            Text(
              'CLIPPIT',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w900,
                fontSize: 24,
                letterSpacing: 1.5,
                foreground: Paint()
                  ..shader = const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.accentNeon],
                  ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.textPrimary),
            onPressed: _openSettingsBottomSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildSloganSection(),
            const SizedBox(height: 28),
            _buildInputTabs(),
            const SizedBox(height: 32),
            _buildHistoryHeader(),
            const SizedBox(height: 16),
            _buildHistoryList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSloganSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Instant Highlight Clipper',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Let Gemini find and render viral moments from YouTube links or local video files.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildInputTabs() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.link, color: AppColors.accentNeon, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Paste YouTube URL',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _urlController,
                  enabled: !_isProcessing,
                  decoration: const InputDecoration(
                    hintText: 'https://www.youtube.com/watch?v=...',
                    prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _handleUrlSubmit,
                    child: const Text('Start AI Analysis'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _pickLocalFile,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.upload_file, color: AppColors.primaryLight, size: 32),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Upload Local Video File',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Analyze directly from local storage',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Saved Highlight Clips',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        if (_historyList.isNotEmpty)
          Text(
            '${_historyList.length} clips',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
      ],
    );
  }

  Widget _buildHistoryList() {
    if (_historyList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.video_collection_outlined, size: 48, color: AppColors.textMuted.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text(
              'No clips created yet',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            const Text(
              'Analyze a video to generate clips.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _historyList.length,
      itemBuilder: (context, index) {
        final item = _historyList[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Card(
            child: ListTile(
              leading: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.play_circle_fill, color: AppColors.textSecondary, size: 32),
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'Source: ${item.sourcePathOrUrl.length > 24 ? "${item.sourcePathOrUrl.substring(0, 24)}..." : item.sourcePathOrUrl}\nDuration: ${(item.endTime - item.startTime).toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _deleteHistoryItem(item.id),
              ),
            ),
          ),
        );
      },
    );
  }
}
