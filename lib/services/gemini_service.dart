import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // 🌟 Added for safe MediaType parsing!
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/clip_suggestion.dart';

class GeminiService {
  final String apiKey;
  final String analysisModelName;       // e.g. 'gemini-1.5-pro' or 'gemini-2.5-flash'
  final String transcriptionModelName;  // e.g. 'gemini-1.5-flash'
  
  late final GenerativeModel _model;
  late final GenerativeModel _transcribeModel;

  GeminiService({
    required this.apiKey,
    this.analysisModelName = 'gemini-1.5-pro',
    this.transcriptionModelName = 'gemini-1.5-flash',
  }) {
    // 1. Configure Pass 1 Model with JSON schema constraints
    _model = GenerativeModel(
      model: analysisModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'highlights': Schema.array(
              items: Schema.object(
                properties: {
                  'start_time_seconds': Schema.number(),
                  'end_time_seconds': Schema.number(),
                  'title': Schema.string(),
                  'reason': Schema.string(),
                  'virality_score': Schema.integer(),
                },
                requiredProperties: ['start_time_seconds', 'end_time_seconds', 'title', 'reason', 'virality_score'],
              ),
            ),
          },
          requiredProperties: ['highlights'],
        ),
      ),
    );

    // 2. Configure Pass 2 Model with JSON schema constraints
    _transcribeModel = GenerativeModel(
      model: transcriptionModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'segments': Schema.array(
              items: Schema.object(
                properties: {
                  'start_time_ms': Schema.integer(),
                  'end_time_ms': Schema.integer(),
                  'text': Schema.string(),
                  'keywords': Schema.array(items: Schema.string()),
                },
                requiredProperties: ['start_time_ms', 'end_time_ms', 'text', 'keywords'],
              ),
            ),
          },
          requiredProperties: ['segments'],
        ),
      ),
    );
  }

  /// Pass 1: Analysis (Analyze full video upload and return structured suggestions)
  Future<List<ClipSuggestion>> analyzeVideoFile(File videoFile, {Function(String status)? onStatusUpdate}) async {
    onStatusUpdate?.call('Uploading video to Gemini Cloud Storage...');
    final uploadResponse = await _uploadToFilesApi(videoFile);
    final String fileUri = uploadResponse['fileUri'] ?? '';
    final String apiName = uploadResponse['apiName'] ?? '';

    try {
      onStatusUpdate?.call('Analyzing visual contents (polling until active)...');
      await _pollFileStatus(fileUri);

      onStatusUpdate?.call('Generating highlights using ${analysisModelName}...');
      
      // Use built-in FilePart instead of custom sealed class extension
      final filePart = FilePart(Uri.parse(fileUri));
      
      final response = await _model.generateContent([
        Content.multi([
          filePart,
          TextPart('Analyze this video and return the top viral highlights. Keep recommended duration strictly between 60 and 75 seconds.')
        ])
      ]);

      if (response.text == null) {
        throw Exception('Received empty text response from Gemini analysis.');
      }

      final Map<String, dynamic> parsed = jsonDecode(response.text!);
      final List<dynamic> highlightsJson = parsed['highlights'];
      return highlightsJson.map((x) => ClipSuggestion.fromJson(x)).toList();
    } finally {
      // Always cleanup cloud file to avoid hitting the 20GB free storage limit
      onStatusUpdate?.call('Cleaning up temporary cloud storage files...');
      await _deleteFileFromApi(apiName);
    }
  }

  /// Pass 2: Clip Subtitle Transcription
  Future<Map<String, dynamic>> transcribeClipSegment(File trimmedClip, {Function(String status)? onStatusUpdate}) async {
    onStatusUpdate?.call('Uploading clip to Gemini...');
    final uploadResponse = await _uploadToFilesApi(trimmedClip);
    final String fileUri = uploadResponse['fileUri'] ?? '';
    final String apiName = uploadResponse['apiName'] ?? '';

    try {
      onStatusUpdate?.call('Processing audio timeline (polling active state)...');
      await _pollFileStatus(fileUri);

      onStatusUpdate?.call('Transcribing relative audio streams...');
      
      // Use built-in FilePart instead of custom sealed class extension
      final filePart = FilePart(Uri.parse(fileUri));
      
      final response = await _transcribeModel.generateContent([
        Content.multi([
          filePart,
          TextPart('Transcribe this exact clip segment. Output start and end times in relative milliseconds from the absolute beginning (0:00). Identify 1-3 highly expressive keywords per segment to emphasize.')
        ])
      ]);

      if (response.text == null) {
        throw Exception('Failed to generate transcription text.');
      }

      return jsonDecode(response.text!);
    } finally {
      onStatusUpdate?.call('Cleaning up cloud clip data...');
      await _deleteFileFromApi(apiName);
    }
  }

  /// REST Implementation of the Gemini File API (Upload under 2GB limit)
  Future<Map<String, String>> _uploadToFilesApi(File file) async {
    final uploadUrl = Uri.parse(
      'https://generativelanguage.googleapis.com/upload/v1beta/files?key=$apiKey',
    );

    final request = http.MultipartRequest('POST', uploadUrl);
    
    // 1. Add headers
    request.headers['X-Goog-Upload-Protocol'] = 'multipart';
    
    // 2. Add metadata part
    final metadataJson = jsonEncode({
      'file': {
        'displayName': file.path.split('/').last,
      }
    });
    
    request.files.add(
      http.MultipartFile.fromString(
        'metadata',
        metadataJson,
        contentType: MediaType('application', 'json'), // 🌟 Fixed runtime type mismatch!
      ),
    );

    // 3. Add raw file part
    final stream = http.ByteStream(file.openRead());
    final length = await file.length();
    final multipartFile = http.MultipartFile(
      'file',
      stream,
      length,
      filename: file.path.split('/').last,
    );
    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Gemini File Upload Failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    return {
      'fileUri': data['file']['uri'] as String,
      'apiName': data['file']['name'] as String, // Name syntax: "files/abc123xyz"
    };
  }

  /// Polls the file endpoint until state changes to 'ACTIVE'
  Future<void> _pollFileStatus(String fileUri) async {
    final url = Uri.parse('$fileUri?key=$apiKey');
    
    while (true) {
      final response = await http.get(url);
      if (response.statusCode != 200) {
        throw Exception('Failed to poll file status: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final String state = data['state'] ?? 'PROCESSING';

      if (state == 'ACTIVE') {
        break; // File is successfully parsed and ready for prompt operations
      } else if (state == 'FAILED') {
        throw Exception('Gemini Cloud Video processing failed on server.');
      }

      // Backoff delay before checking again
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  /// Deletes file from Gemini Storage server after completing execution
  Future<void> _deleteFileFromApi(String apiName) async {
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/$apiName?key=$apiKey');
    try {
      final response = await http.delete(url);
      if (response.statusCode != 200) {
        print('Warning: Cloud file deletion failed: ${response.body}');
      }
    } catch (e) {
      print('Warning: Error during cloud deletion: $e');
    }
  }
}
