import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

import 'package:scribe/core/theme_provider.dart';
import 'package:scribe/features/clipboard/application/clipboard_service.dart';
import 'package:scribe/features/editor/application/custom_paste_plugin.dart';
import 'package:scribe/features/editor/application/editor_controller.dart';
import 'package:scribe/features/editor/domain/document_repository.dart';
import 'package:scribe/features/editor/ui/editor_toolbar.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _editorController;
  late final FocusNode _editorFocusNode;
  late final ClipboardService _clipboardService;

  // Add a key to force editor rebuilds on demand
  final GlobalKey _editorKey = GlobalKey();

  // Add a counter to force rebuilds
  int _editorRebuildCount = 0;

  @override
  void initState() {
    super.initState();
    _editorController = EditorController(
      documentRepository: context.read<DocumentRepository>(),
    );
    _editorFocusNode = FocusNode();
    _clipboardService = ClipboardService();

    _editorFocusNode.addListener(() {
      print(
        '[_EditorScreenState] Editor focus changed: hasFocus = ${_editorFocusNode.hasFocus}',
      );
    });

    _editorController.addListener(_rebuildScreen);

    _editorController.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _editorController.removeListener(_rebuildScreen);
    _editorController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _rebuildScreen() {
    if (mounted) {
      print(
        '[_EditorScreenState] _rebuildScreen called due to _editorController notification.',
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, child) {
        if (!_editorController.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          body: Column(
            children: [
              if (!_editorController.isDistractionFree) ...[
                _buildAppBar(),
                EditorToolbar(controller: _editorController),
              ],
              Expanded(child: _buildEditor()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      title: const Text('Super Editor Scribe'),
      actions: [
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return IconButton(
              icon: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              ),
              onPressed: themeProvider.toggleTheme,
              tooltip: 'Toggle theme',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: _editorController.saveDocument,
          tooltip: 'Save document',
        ),
      ],
    );
  }

  Widget _buildEditor() {
    print(
        '[_EditorScreenState] _buildEditor() called. Rebuild count: $_editorRebuildCount');
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: _editorController.isDistractionFree
          ? Theme.of(context).colorScheme.surface
          : null,
      child: SuperEditor(
        // Use a combined key of the GlobalKey and rebuild count to force complete rebuilds
        key: ValueKey('$_editorKey-$_editorRebuildCount'),
        editor: editor,
        focusNode: _editorFocusNode,
        // Use default component builders - the style for code blocks will be defined in the stylesheet
        componentBuilders: defaultComponentBuilders,
        plugins: {
          // Create a custom paste plugin with a listener to force refresh after paste
          CustomPastePlugin(
            clipboardService: _clipboardService,
            onPasteComplete: () {
              print('[_EditorScreenState] Paste complete callback received');
              // Force an immediate UI rebuild after paste by incrementing the rebuild count
              if (mounted) {
                setState(() {
                  // Increment the rebuild counter to force a complete widget rebuild
                  _editorRebuildCount++;
                  print(
                      '[_EditorScreenState] Forced rebuild. New count: $_editorRebuildCount');
                });
              }
            },
          ),
        },
        stylesheet: _buildStylesheet(),
      ),
    );
  }

  Stylesheet _buildStylesheet() {
    final theme = Theme.of(context);

    return defaultStylesheet.copyWith(
      addRulesAfter: [
        StyleRule(
          BlockSelector.all,
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            Styles.textStyle: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.6,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header1'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineLarge!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 8,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header2'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineMedium!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: 8,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('blockquote'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              fontStyle: FontStyle.italic,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 40,
              right: 24,
              top: 8,
              bottom: 8,
            ),
          },
        ),
        // Enhanced style rule for code blocks
        StyleRule(
          const BlockSelector('code'),
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.only(
              left: 40,
              right: 40,
              top: 16,
              bottom: 16,
            ),
            Styles.textStyle: TextStyle(
              fontFamily: 'Courier New, monospace', // Explicit monospace font
              fontSize: 14.0,
              color: theme.colorScheme.onSurface,
              height: 1.5,
              backgroundColor:
                  theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            // Use supported style properties for code blocks
            Styles.textAlign: TextAlign.left,
            // We'll rely on the background color in the textStyle since paragraphStyle
            // with border and borderRadius isn't directly supported in the stylesheet
          },
        ),
      ],
    );
  }
}
