import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
// Import for DocumentKeyboardAction typedef and ExecutionInstruction enum.
import 'package:super_editor/src/default_editor/document_hardware_keyboard/document_input_keyboard.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';
import 'dart:async';

import '../../clipboard/application/clipboard_service.dart';

/// A plugin that handles paste actions for the editor.
///
/// This plugin listens for paste intents and then uses the [ClipboardService]
/// to fetch and process clipboard data, inserting it into the document.
class CustomPastePlugin extends SuperEditorPlugin {
  CustomPastePlugin({required this.clipboardService, this.onPasteComplete});

  final ClipboardService? clipboardService;

  /// Optional callback that's invoked after a paste operation completes
  /// This can be used to force a UI refresh in the parent widget
  final VoidCallback? onPasteComplete;

  @override
  List<DocumentKeyboardAction> get keyboardActions => [
        _handlePasteKeyboardAction, // Assign the function directly
      ];

  // This function now matches the DocumentKeyboardAction typedef.
  // It's a method of the class, so it has access to 'this' (e.g., _handlePaste).
  ExecutionInstruction _handlePasteKeyboardAction({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    print('[CustomPastePlugin] Key event received: ${keyEvent.runtimeType}');

    if (keyEvent is! KeyDownEvent) {
      // Only interested in key down events for shortcuts
      print('[CustomPastePlugin] Not a KeyDownEvent, continuing execution');
      return ExecutionInstruction.continueExecution;
    }

    // Standard paste shortcuts: Ctrl+V (Windows/Linux), Cmd+V (macOS)
    final isPasteShortcut = (HardwareKeyboard.instance.isControlPressed &&
            keyEvent.logicalKey == LogicalKeyboardKey.keyV) ||
        (HardwareKeyboard.instance.isMetaPressed &&
            keyEvent.logicalKey == LogicalKeyboardKey.keyV);

    print(
        '[CustomPastePlugin] Key: ${keyEvent.logicalKey}, Ctrl: ${HardwareKeyboard.instance.isControlPressed}, Meta: ${HardwareKeyboard.instance.isMetaPressed}, isPasteShortcut: $isPasteShortcut');

    if (isPasteShortcut) {
      print('[CustomPastePlugin] ✅ PASTE SHORTCUT DETECTED! Handling paste...');
      _handlePaste(editContext); // 'this' is implicitly available
      return ExecutionInstruction
          .haltExecution; // Indicate that the event was handled
    }

    print('[CustomPastePlugin] Not a paste shortcut, continuing execution');
    return ExecutionInstruction
        .continueExecution; // Event not handled by this action
  }

  /// Handles the paste operation by getting data from the clipboard
  /// and inserting it into the document.
  Future<void> _handlePaste(SuperEditorContext editContext) async {
    print('[CustomPastePlugin] 🚀 _handlePaste() started');

    if (clipboardService == null) {
      print('[CustomPastePlugin] ❌ clipboardService is null!');
      return;
    }

    print('[CustomPastePlugin] ✅ clipboardService is available');

    final document = editContext.document;
    final composer = editContext.composer;

    if (document is! MutableDocument || composer is! MutableDocumentComposer) {
      print('[CustomPastePlugin] ❌ Document or composer type mismatch');
      return;
    }

    print(
        '[CustomPastePlugin] ✅ Document and composer are valid, calling _processClipboardContent');

    // We need the original selection for _processClipboardContent
    // DO NOT clear selection yet - the paste handler needs it

    // Process and insert clipboard content
    await _processClipboardContent(document, composer, editContext);

    // PHASE 1: Execute immediate focus and selection changes
    editContext.editorFocusNode.requestFocus();

    // Clear selection AFTER content processing to ensure document in stable state
    composer.clearSelection();

    // We need to avoid explicitly setting a selection right after paste
    // as it can cause styling errors with SingleColumnLayoutSelectionStyler
    // Instead, we'll just ensure the editor has focus and let it handle
    // selection internally

    // Do not attempt to create a new selection, which causes the null error
    // The editor will handle cursor placement automatically

    // PHASE 2: Add delays and additional UI-triggering operations
    // Allow Flutter to process the first round of changes
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // PHASE 3: Just focus the editor and make sure it redraws
    editContext.editorFocusNode.requestFocus();

    // We'll skip directly manipulating the selection again to avoid potential issues

    // PHASE 4: Final refresh operations with longer delay
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Ensure editor still has focus at the end
    if (!editContext.editorFocusNode.hasFocus) {
      editContext.editorFocusNode.requestFocus();
    }

    // PHASE 5: Notify parent to trigger higher-level UI refresh
    if (onPasteComplete != null) {
      onPasteComplete!();

      // One final delay to allow setState to propagate
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Handles the actual clipboard content processing and node insertion
  Future<void> _processClipboardContent(
    MutableDocument document,
    MutableDocumentComposer composer,
    SuperEditorContext editContext,
  ) async {
    // Get clipboard content
    final reader = await SystemClipboard.instance?.read();
    if (reader == null) {
      print('[CustomPastePlugin] Clipboard reader is null.');
      return;
    }

    String? htmlContent;
    String? plainTextContent;

    // Try to get HTML first, and if successful, also try to get plain text for fallback.
    if (reader.canProvide(Formats.htmlText)) {
      try {
        final htmlItem = reader.items.firstWhere(
          (item) => item.canProvide(Formats.htmlText),
        );
        htmlContent = await htmlItem.readValue(Formats.htmlText);
        if (htmlContent != null && htmlContent.isNotEmpty) {
          // If HTML is found, also try to get plain text from any item, as it might be a better source than generated from HTML.
          if (reader.canProvide(Formats.plainText)) {
            try {
              final plainTextItemForHtml = reader.items.firstWhere(
                (item) => item.canProvide(Formats.plainText),
              );
              plainTextContent = await plainTextItemForHtml.readValue(
                Formats.plainText,
              );
            } catch (e) {
              print(
                '[CustomPastePlugin] Error reading plain text alongside HTML: $e',
              );
            }
          }
        }
      } catch (e) {
        print('[CustomPastePlugin] Error reading HTML from reader item: $e');
      }
    }

    // If HTML wasn't found or was empty via super_clipboard, try direct Clipboard.getData.
    // Also, ensure plainTextContent is fetched if not already available.
    if (htmlContent == null || htmlContent.trim().isEmpty) {
      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        // More explicit null safety check to satisfy analyzer
        final clipboardText = clipboardData?.text;
        if (clipboardText != null) {
          // Now clipboardText is guaranteed to be non-null
          if (clipboardText.trim().isNotEmpty) {
            if (clipboardText.trim().startsWith('<') &&
                clipboardText.trim().endsWith('>')) {
              htmlContent = clipboardText; // Assume it's HTML
              // If plainTextContent is still null, it might be this text itself if it's not truly HTML, or we need to fetch it.
            } else {
              // It's plain text
              if (plainTextContent == null || plainTextContent.trim().isEmpty) {
                plainTextContent = clipboardText;
              }
            }
          }
        }
      } catch (e) {
        print('[CustomPastePlugin] Error reading from Clipboard.getData: $e');
      }
    }

    // Final attempt to get plain text if still missing and HTML was found (but plain text part failed)
    // or if HTML was not found at all.
    if (plainTextContent == null || plainTextContent.trim().isEmpty) {
      if (reader.canProvide(Formats.plainText)) {
        try {
          final plainTextItem = reader.items.firstWhere(
            (item) => item.canProvide(Formats.plainText),
          );
          plainTextContent = await plainTextItem.readValue(Formats.plainText);
        } catch (e) {
          print(
            '[CustomPastePlugin] Error reading plain text from reader item (final attempt): $e',
          );
        }
      }
    }

    if ((htmlContent == null || htmlContent.trim().isEmpty) &&
        (plainTextContent == null || plainTextContent.trim().isEmpty)) {
      print('[CustomPastePlugin] No usable content found on clipboard.');
      return;
    }

    List<DocumentNode> nodesToInsert = [];

    // 1. Try HTML if available
    if (htmlContent != null && htmlContent.trim().isNotEmpty) {
      print('[CustomPastePlugin] Processing HTML content.');
      String cleanedHtml = htmlContent; // Make a mutable copy
      // Apply original cleaning rules from the plugin
      cleanedHtml = cleanedHtml.replaceAll(RegExp(r'</?meta[^>]*>'), '');
      cleanedHtml = cleanedHtml.replaceAll(
        RegExp(r'</?style[^>]*>.*?</style>', dotAll: true),
        '',
      );
      cleanedHtml = cleanedHtml.replaceAll(
        RegExp(r'<\?xml[^>]*>'),
        '',
      ); // Escaped '?'
      cleanedHtml = cleanedHtml.replaceAll(
        RegExp(r'<!--.*?-->', dotAll: true),
        '',
      );
      if (!cleanedHtml.contains('<html') && !cleanedHtml.contains('<body')) {
        cleanedHtml = '<html><body>$cleanedHtml</body></html>';
      }

      nodesToInsert = clipboardService!.processClipboardPaste(
        ClipboardPasteData(
          type: ClipboardDataType.html,
          content: cleanedHtml,
          plainText: plainTextContent ??
              '', // Provide original plain text as fallback reference
        ),
      );
    }

    // 2. If HTML processing yielded no nodes or HTML wasn't available, try Markdown from plain text
    if (nodesToInsert.isEmpty &&
        (plainTextContent != null && plainTextContent.trim().isNotEmpty)) {
      print(
        '[CustomPastePlugin] HTML processing yielded no nodes or HTML not available. Trying Markdown from plain text.',
      );
      try {
        // Check if the content looks like markdown (has # headers, *, etc.)
        final bool looksLikeMarkdown = _looksLikeMarkdown(plainTextContent);

        // Special handling for code fences - more robust check for code blocks
        final bool containsCodeFences =
            RegExp(r'```[\w]*\n[\s\S]*?```').hasMatch(plainTextContent);

        if (looksLikeMarkdown || containsCodeFences) {
          // Use the super_editor_markdown package to parse the markdown string
          try {
            // Convert the markdown text to a SuperEditor Document
            final Document markdownDocument =
                deserializeMarkdownToDocument(plainTextContent);

            // Now extract all nodes from the document
            List<DocumentNode> markdownNodes = [];

            // Special handling for code blocks if the standard markdown parsing doesn't work
            if (containsCodeFences && markdownDocument.nodeCount == 0) {
              markdownNodes = _extractCodeBlocksManually(plainTextContent);
            } else {
              for (int i = 0; i < markdownDocument.nodeCount; i++) {
                // Create a copy of each node with a new ID to avoid conflicts
                final node = markdownDocument.getNodeAt(i);
                // Only process non-null nodes
                if (node != null) {
                  print(
                      '[CustomPastePlugin] Node type: ${node.runtimeType}, metadata: ${node.metadata}');
                  final nodeCopy = _createNodeWithNewId(node);
                  markdownNodes.add(nodeCopy);
                }
              }
            }

            if (markdownNodes.isNotEmpty) {
              nodesToInsert = markdownNodes;
              print(
                  '[CustomPastePlugin] Successfully parsed Markdown content.');
            } else {
              print(
                '[CustomPastePlugin] Markdown parsing resulted in empty document. Falling back to plain text processing.',
              );
            }
          } catch (e) {
            print(
                '[CustomPastePlugin] Error processing markdown with super_editor_markdown: $e');
          }
        } else {
          // Not markdown - will fall through to plain text processing
          print(
            '[CustomPastePlugin] Content doesn\'t appear to be markdown. Processing as plain text.',
          );
        }
      } catch (e) {
        print(
          '[CustomPastePlugin] Error parsing Markdown: $e. Falling back to plain text processing.',
        );
        // Fallback to plain text processing will happen in the next block if nodesToInsert is still empty
      }
    }

    // 3. If Markdown also failed/not applicable (nodesToInsert is still empty), and plain text is available, process as plain text.
    if (nodesToInsert.isEmpty &&
        (plainTextContent != null && plainTextContent.trim().isNotEmpty)) {
      print(
        '[CustomPastePlugin] Markdown processing failed or not applicable. Processing as plain text.',
      );
      nodesToInsert = clipboardService!.processClipboardPaste(
        ClipboardPasteData(
          type: ClipboardDataType.plainText,
          content: plainTextContent,
          plainText: plainTextContent,
        ),
      );
    }

    if (nodesToInsert.isEmpty) {
      print(
        '[CustomPastePlugin] No nodes to insert after all processing attempts.',
      );
      return;
    }

    // --- Existing node insertion logic ---
    // This part should be the original logic from lines 270-366 of CustomPastePlugin
    // It handles inserting or replacing content based on current selection.
    final currentSelection = composer.selection;
    if (currentSelection == null) {
      print('[CustomPastePlugin] No selection found, cannot paste.');
      return;
    }

    // Clear selection before modifying document to avoid invalid references
    // This follows best practices from the existing implementation
    composer.clearSelection();

    if (currentSelection.isCollapsed) {
      // For collapsed selection, insert nodes at the current position
      final nodeIndex = document.getNodeIndexById(
        currentSelection.extent.nodeId,
      );

      // Insert after the current node
      for (var i = 0; i < nodesToInsert.length; i++) {
        final node = nodesToInsert[i];
        // Ensure we don't have duplicate node IDs
        if (document.getNodeById(node.id) != null) {
          // If this node ID already exists, assign a new ID
          final nodeWithNewId = _createNodeWithNewId(node);
          document.insertNodeAt(nodeIndex + 1 + i, nodeWithNewId);
        } else {
          document.insertNodeAt(nodeIndex + 1 + i, node);
        }
      }
    } else {
      // For expanded selection, replace the selected content
      final baseNodeId = currentSelection.base.nodeId;
      final extentNodeId = currentSelection.extent.nodeId;
      final baseNodeIndex = document.getNodeIndexById(baseNodeId);
      final extentNodeIndex = document.getNodeIndexById(extentNodeId);

      if (baseNodeIndex < 0 || extentNodeIndex < 0) {
        return;
      }

      // Determine the affected range (handle both forward and backward selections)
      final startIndex =
          baseNodeIndex < extentNodeIndex ? baseNodeIndex : extentNodeIndex;
      final endIndex =
          baseNodeIndex < extentNodeIndex ? extentNodeIndex : baseNodeIndex;

      // Calculate how many nodes to delete
      final nodesToDelete = endIndex - startIndex + 1;

      // Delete the selected nodes
      for (var i = 0; i < nodesToDelete; i++) {
        // Always delete at the same index because each deletion shifts the indices
        document.deleteNodeAt(startIndex);
      }

      // Now insert the new nodes at the start position
      for (var i = 0; i < nodesToInsert.length; i++) {
        final node = nodesToInsert[i];
        // Ensure we don't have duplicate node IDs
        if (document.getNodeById(node.id) != null) {
          // If this node ID already exists, assign a new ID
          final nodeWithNewId = _createNodeWithNewId(node);
          document.insertNodeAt(startIndex + i, nodeWithNewId);
        } else {
          document.insertNodeAt(startIndex + i, node);
        }
      }
    }
    // Selection update after paste is handled by _handlePaste method's phases.
  }

  /// Creates a new node with a unique ID based on the given node
  /// Handles special markdown elements like horizontal rules, lists, and code blocks
  DocumentNode _createNodeWithNewId(DocumentNode node) {
    // Handle paragraph nodes (most common)
    if (node is ParagraphNode) {
      return ParagraphNode(
        id: Editor.createNodeId(),
        text: node.text,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // Handle horizontal rule nodes
    else if (node is HorizontalRuleNode) {
      return HorizontalRuleNode(
        id: Editor.createNodeId(),
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // Handle list items
    else if (node is ListItemNode) {
      return ListItemNode(
        id: Editor.createNodeId(),
        itemType: node.type,
        text: node.text,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // Handle image nodes
    else if (node is ImageNode) {
      return ImageNode(
        id: Editor.createNodeId(),
        imageUrl: node.imageUrl,
        altText: node.altText,
        metadata: Map<String, dynamic>.from(node.metadata),
      );
    }
    // Handle task nodes
    else if (node.getMetadataValue('blockType') ==
        const NamedAttribution('task')) {
      // Create a task node (checkbox item)
      if (node is ParagraphNode) {
        return ParagraphNode(
          id: Editor.createNodeId(),
          text: node.text,
          metadata: {
            'blockType': const NamedAttribution('task'),
            if (node.metadata.containsKey('checked'))
              'checked': node.metadata['checked'],
          },
        );
      }
    }
    // Handle code blocks - improved handling with better attribution
    else if (node.getMetadataValue('blockType') ==
            const NamedAttribution('code') ||
        node.getMetadataValue('blockType')?.id == 'code') {
      if (node is ParagraphNode) {
        // For code blocks, ensure we properly format them and preserve language information
        String? language;
        if (node.metadata.containsKey('language')) {
          final langValue = node.metadata['language'];
          // Cast to String if not null
          language = langValue != null ? langValue.toString() : null;
        }

        // Print more detailed debugging information about the code block
        print(
            '[CustomPastePlugin] Processing code block with content: "${node.text.text.substring(0, math.min(20, node.text.text.length))}..."');
        if (language != null) {
          print('[CustomPastePlugin] Code language: $language');
        }

        // Create a new node with proper formatting for code blocks
        return ParagraphNode(
          id: Editor.createNodeId(),
          text: node.text,
          metadata: {
            'blockType': const NamedAttribution('code'),
            if (language != null) 'language': language,
            // Ensure proper text alignment
            'textAlign': TextAlign.left,
          },
        );
      }
    }
    // Handle any other text nodes by converting to paragraph
    else if (node is TextNode) {
      return ParagraphNode(id: Editor.createNodeId(), text: node.text);
    }

    // For any other node type, create a generic paragraph with the node's string representation
    print('[CustomPastePlugin] Unhandled node type: ${node.runtimeType}');
    return ParagraphNode(
        id: Editor.createNodeId(), text: AttributedText(node.toString()));
  }

  /// Manually extracts code blocks from markdown text
  /// This is used as a fallback when the standard markdown parser doesn't handle code blocks properly
  List<DocumentNode> _extractCodeBlocksManually(String markdownText) {
    final List<DocumentNode> nodes = [];
    final lines = markdownText.split('\n');

    // Debug output for the entire input text
    print(
        '[CustomPastePlugin] Manually extracting code blocks from markdown: ${markdownText.length} characters');

    // Process the lines to extract code blocks
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      // Check for code fence start
      if (line.startsWith('```')) {
        // Extract language if specified (e.g., ```dart)
        String? language;
        if (line.length > 3) {
          language = line.substring(3).trim();
          if (language.isEmpty) language = null;
        }

        if (language != null) {
          print(
              '[CustomPastePlugin] Found code block with language: $language');
        } else {
          print(
              '[CustomPastePlugin] Found code block without language specification');
        }

        // Collect all lines until the closing code fence
        final codeLines = <String>[];
        int j = i + 1;
        bool foundClosingFence = false;

        while (j < lines.length) {
          if (lines[j].trim() == '```') {
            foundClosingFence = true;
            break;
          }
          codeLines.add(lines[j]);
          j++;
        }

        // Create a code block node - only if we have content
        if (codeLines.isNotEmpty) {
          final codeText = codeLines.join('\n');
          print(
              '[CustomPastePlugin] Code block content preview: "${codeText.substring(0, math.min(20, codeText.length))}..."');

          // Create the code block with proper styling that matches our stylesheet
          final codeNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(codeText),
            metadata: {
              'blockType': const NamedAttribution('code'),
              if (language != null && language.isNotEmpty) 'language': language,
              // Set textAlign as a TextAlign object, not a NamedAttribution
              'textAlign': TextAlign.left,
            },
          );
          nodes.add(codeNode);
          print('[CustomPastePlugin] Added code block node to result');
        }

        // Skip to after the closing fence or to the end if no closing fence
        i = foundClosingFence ? j + 1 : j;
      } else {
        // Regular line - add as paragraph
        if (line.isNotEmpty) {
          final paragraphNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(line),
          );
          nodes.add(paragraphNode);
        }
        i++;
      }
    }

    print(
        '[CustomPastePlugin] Manual extraction complete. Generated ${nodes.length} nodes');
    return nodes;
  }

  /// Checks if text content appears to be Markdown
  /// Returns true if the content contains common Markdown syntax
  bool _looksLikeMarkdown(String text) {
    if (text.isEmpty) return false;

    // Check for common Markdown patterns
    final commonMarkdownPatterns = [
      RegExp(r'^```'), // Code fence start
      RegExp(r'```$'), // Code fence end
      RegExp(r'^#+\s'), // Headers
      RegExp(r'\*\*.*?\*\*'), // Bold
      RegExp(r'__.*?__'), // Bold
      RegExp(r'\*[^\*]+?\*'), // Italic
      RegExp(r'_[^_]+?_'), // Italic
      RegExp(r'~~.*?~~'), // Strikethrough
      RegExp(r'^>\s'), // Blockquote
      RegExp(r'^-\s'), // Unordered list
      RegExp(r'^\*\s'), // Unordered list
      RegExp(r'^\+\s'), // Unordered list
      RegExp(r'^\d+\.\s'), // Ordered list
      RegExp(r'^\[.*?\]\(.*?\)'), // Links
      RegExp(r'^!\[.*?\]\(.*?\)'), // Images
      RegExp(r'^---$'), // Horizontal rule
      RegExp(r'^\*\*\*$'), // Horizontal rule
      RegExp(r'^___$'), // Horizontal rule
    ];

    final lines = text.split('\n');

    // Check each line against markdown patterns
    for (final line in lines) {
      for (final pattern in commonMarkdownPatterns) {
        if (pattern.hasMatch(line)) {
          return true;
        }
      }
    }

    // Additional special case: If we have multiple lines starting with # at different levels,
    // it's very likely to be markdown
    bool hasHeader1 = false;
    bool hasHeader2 = false;
    for (final line in lines) {
      if (line.trim().startsWith('# ')) hasHeader1 = true;
      if (line.trim().startsWith('## ')) hasHeader2 = true;
    }
    if (hasHeader1 && hasHeader2) return true;

    return false;
  }
}
