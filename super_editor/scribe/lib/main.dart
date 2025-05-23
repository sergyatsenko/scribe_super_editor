import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart' as logging;
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:scribe/core/app_theme.dart';
import 'package:scribe/core/theme_provider.dart';
import 'package:scribe/features/editor/domain/document_repository.dart';
import 'package:scribe/features/editor/infrastructure/local_document_repository.dart';
import 'package:scribe/features/editor/ui/editor_screen.dart';
import 'package:scribe/l10n/app_localizations.dart';

void main() {
  // Initialize logging first
  _initLogging();

  // Initialize SuperEditor logging
  initLoggers(Level.FINE, {
    // Enable some key loggers for debugging paste functionality
    // editorKeyLog,
    // editorOpsLog,
    // editorDocLog,
  });

  print('🚀 Starting Scribe app with custom paste functionality');

  runApp(const ScribeApp());
}

void _initLogging() {
  // Configure the logging system with a more reasonable level for debugging
  // Use INFO instead of ALL to reduce noise but keep important diagnostics
  logging.Logger.root.level =
      kDebugMode ? logging.Level.INFO : logging.Level.WARNING;

  // Only log warnings and errors to developer console in debug mode
  logging.Logger.root.onRecord.listen((record) {
    // Skip verbose logs that aren't warnings or errors
    if (kDebugMode && record.level < logging.Level.WARNING) {
      return;
    }

    developer.log(
      record.message,
      time: record.time,
      name: record.loggerName,
      level: record.level.value,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  });
}

class ScribeApp extends StatelessWidget {
  const ScribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('🏗️ Building ScribeApp with providers');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider<DocumentRepository>(
          create: (_) {
            print('📁 Creating LocalDocumentRepository');
            return LocalDocumentRepository();
          },
          dispose: (_, repository) {
            print('🗑️ Disposing LocalDocumentRepository');
            if (repository is LocalDocumentRepository) {
              repository.dispose();
            }
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          print(
              '🎨 Building MaterialApp with theme: ${themeProvider.themeMode}');

          return MaterialApp(
            title: 'Super Editor Scribe',
            theme: AppTheme.lightTheme(),
            darkTheme: AppTheme.darkTheme(),
            themeMode: themeProvider.themeMode,
            home: const EditorScreen(),
            debugShowCheckedModeBanner: false,
            supportedLocales: const [
              Locale('en', ''),
              Locale('es', ''),
            ],
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
