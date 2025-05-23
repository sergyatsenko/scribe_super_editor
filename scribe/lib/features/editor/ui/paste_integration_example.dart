import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:scribe/features/clipboard/application/clipboard_service.dart';
import 'package:scribe/features/editor/application/custom_paste_plugin.dart';

/// Example showing how to integrate custom paste functionality with SuperEditor
///
/// This is a minimal example that demonstrates the key integration points
/// mentioned in the comprehensive guide.
class PasteIntegrationExample extends StatefulWidget {
  const PasteIntegrationExample({super.key});

  @override
  State<PasteIntegrationExample> createState() =>
      _PasteIntegrationExampleState();
}

class _PasteIntegrationExampleState extends State<PasteIntegrationExample> {
  late final MutableDocument _document;
  late final MutableDocumentComposer _composer;
  late final Editor _editor;
  late final ClipboardService _clipboardService;
  late final FocusNode _editorFocusNode;

  @override
  void initState() {
    super.initState();

    // Step 1: Initialize your document and composer
    _document = MutableDocument(nodes: [
      ParagraphNode(
        id: Editor.createNodeId(),
        text: AttributedText('Start typing or paste content here...'),
      ),
    ]);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document,
      composer: _composer,
    );

    // Step 2: Initialize clipboard service
    _clipboardService = ClipboardService();
    _editorFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editorFocusNode.dispose();
    super.dispose();
  }

  void _refreshEditor() {
    // Optional: Force UI refresh after paste operations
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paste Integration Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste Testing Instructions:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                        '• Copy rich text from a website and paste it here'),
                    const Text('• Copy markdown content and paste it'),
                    const Text(
                        '• Try pasting code blocks with syntax highlighting'),
                    const Text(
                        '• Use Ctrl+V (Windows/Linux) or Cmd+V (macOS) to paste'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Editor
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SuperEditor(
                  editor: _editor,
                  focusNode: _editorFocusNode,
                  stylesheet: _buildStylesheet(),

                  // Step 3: Add the custom paste plugin
                  plugins: {
                    CustomPastePlugin(
                      clipboardService: _clipboardService,
                      onPasteComplete:
                          _refreshEditor, // Optional: refresh UI after paste
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stylesheet _buildStylesheet() {
    final theme = Theme.of(context);

    return defaultStylesheet.copyWith(
      addRulesAfter: [
        // Basic paragraph styling
        StyleRule(
          BlockSelector.all,
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            Styles.textStyle: theme.textTheme.bodyLarge!,
          },
        ),

        // Header styling
        StyleRule(
          const BlockSelector('header1'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineLarge!,
            Styles.padding: const CascadingPadding.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 8,
            ),
          },
        ),

        StyleRule(
          const BlockSelector('header2'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineMedium!,
            Styles.padding: const CascadingPadding.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 6,
            ),
          },
        ),

        // Code block styling
        StyleRule(
          const BlockSelector('code'),
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.all(16),
            Styles.textStyle: TextStyle(
              fontFamily: 'Courier New, monospace',
              fontSize: 14.0,
              color: theme.colorScheme.onSurfaceVariant,
              backgroundColor:
                  theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            Styles.textAlign: TextAlign.left,
          },
        ),

        // Blockquote styling
        StyleRule(
          const BlockSelector('blockquote'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.bodyLarge!.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface.withOpacity(0.8),
            ),
            Styles.padding: const CascadingPadding.only(
              left: 32,
              right: 16,
              top: 8,
              bottom: 8,
            ),
          },
        ),
      ],
    );
  }
}

/// Key Integration Points Summary:
/// 
/// 1. **Dependencies Required** (already in your pubspec.yaml):
///    - super_editor
///    - super_editor_markdown
///    - super_clipboard
///    - html
/// 
/// 2. **Core Files** (already implemented in your app):
///    - ClipboardService: Processes clipboard data
///    - HtmlToDocumentConverter: Converts HTML to SuperEditor nodes
///    - CustomPastePlugin: Handles paste keyboard shortcuts and processing
/// 
/// 3. **Integration Steps**:
///    - Initialize ClipboardService
///    - Add CustomPastePlugin to SuperEditor's plugins
///    - Optional: Add onPasteComplete callback for UI refresh
/// 
/// 4. **Platform Permissions** (now configured):
///    - Android: READ_EXTERNAL_STORAGE permission
///    - macOS: com.apple.security.files.user-selected.read-only entitlement
/// 
/// 5. **Testing**:
///    - Copy content from PASTE_TESTING.md
///    - Try rich content from web browsers
///    - Test with various markdown formats
///    - Check console output for debugging info 