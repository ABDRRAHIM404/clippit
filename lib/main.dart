import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/db_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final dbService = DbService();
  bool dbInitialized = false;
  String? initError;

  try {
    await dbService.initialize();
    dbInitialized = true;
  } catch (e) {
    initError = e.toString();
  }

  runApp(ClippitApp(
    dbService: dbService,
    initialized: dbInitialized,
    error: initError,
  ));
}

class ClippitApp extends StatelessWidget {
  final DbService dbService;
  final bool initialized;
  final String? error;

  const ClippitApp({
    super.key,
    required this.dbService,
    required this.initialized,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clippit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: initialized
          ? HomeScreen(dbService: dbService)
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to initialize local database',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error ?? 'Unknown error occurred.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
