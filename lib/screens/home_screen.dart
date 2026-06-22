import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/clip_history_entry.dart';
import '../services/db_service.dart';

class HomeScreen extends StatefulWidget {
  final DbService dbService;

  const HomeScreen({super.key, required this.dbService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<ClipHistoryEntry> _historyList = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _historyList = widget.dbService.getAllHistory();
    });
  }

  Future<void> _handleUrlSubmit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a YouTube link')),
      );
      return;
    }
    
    setState(() => _isProcessing = true);
    // Future integration flow goes here
    _urlController.clear();
    setState(() => _isProcessing = false);
  }

  Future<void> _pickLocalFile() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File picker click (ready for Phase 2 integration)')),
    );
  }

  Future<void> _deleteHistoryItem(String id) async {
    await widget.dbService.deleteHistoryEntry(id);
    _loadHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clip deleted and storage cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        // YouTube URL Input Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.link, color: AppColors.accentNeon, size: 24),
                    const SizedBox(width: 8),
                    const Text(
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
                    onPressed: _isProcessing ? null : _handleUrlSubmit,
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Start AI Analysis'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Local File Upload Card
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
