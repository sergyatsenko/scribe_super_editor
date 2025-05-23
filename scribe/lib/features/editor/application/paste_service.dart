import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_markdown/super_editor_markdown.dart';

import '../../clipboard/application/clipboard_service.dart';

/// Service that provides rich text and markdown paste functionality.
///
/// This service extracts the core paste logic so it can be shared between
/// keyboard shortcuts (CustomPastePlugin) and context menu operations.
class PasteService {
  PasteService({required this.clipboardService});

  final ClipboardService clipboardService;

  /// Handles rich text and markdown paste operation.
  ///
  /// Returns true if content was successfully pasted, false otherwise.
  Future<bool> handlePaste({
    required MutableDocument document,
    required MutableDocumentComposer composer,
    DocumentPosition? pastePosition,
  }) async {
    print('[PasteService] 🚀 handlePaste() started');

    // Get clipboard content
    final reader = await SystemClipboard.instance?.read();
    if (reader == null) {
      print('[PasteService] Clipboard reader is null.');
      return false;
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
                  '[PasteService] Error reading plain text alongside HTML: $e');
            }
          }
        }
      } catch (e) {
        print('[PasteService] Error reading HTML from reader item: $e');
      }
    }

    // If HTML wasn't found or was empty via super_clipboard, try direct Clipboard.getData.
    if (htmlContent == null || htmlContent.trim().isEmpty) {
      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        final clipboardText = clipboardData?.text;
        if (clipboardText != null) {
          if (clipboardText.trim().isNotEmpty) {
            if (clipboardText.trim().startsWith('<') &&
                clipboardText.trim().endsWith('>')) {
              htmlContent = clipboardText; // Assume it's HTML
            } else {
              // It's plain text
              if (plainTextContent == null || plainTextContent.trim().isEmpty) {
                plainTextContent = clipboardText;
              }
            }
          }
        }
      } catch (e) {
        print('[PasteService] Error reading from Clipboard.getData: $e');
      }
    }

    // Final attempt to get plain text if still missing
    if (plainTextContent == null || plainTextContent.trim().isEmpty) {
      if (reader.canProvide(Formats.plainText)) {
        try {
          final plainTextItem = reader.items.firstWhere(
            (item) => item.canProvide(Formats.plainText),
          );
          plainTextContent = await plainTextItem.readValue(Formats.plainText);
        } catch (e) {
          print(
              '[PasteService] Error reading plain text from reader item (final attempt): $e');
        }
      }
    }

    if ((htmlContent == null || htmlContent.trim().isEmpty) &&
        (plainTextContent == null || plainTextContent.trim().isEmpty)) {
      print('[PasteService] No usable content found on clipboard.');
      return false;
    }

    // Determine paste position
    final currentSelection = composer.selection;
    DocumentPosition actualPastePosition;

    if (pastePosition != null) {
      actualPastePosition = pastePosition;
    } else if (currentSelection != null) {
      actualPastePosition = currentSelection.extent;
    } else {
      print('[PasteService] No selection or paste position available.');
      return false;
    }

    // Process clipboard content using ClipboardService
    List<DocumentNode> nodesToInsert = [];

    // 1. Try HTML first if available
    if (htmlContent != null && htmlContent.trim().isNotEmpty) {
      print('[PasteService] Processing HTML content...');
      final clipboardData = ClipboardPasteData(
        type: ClipboardDataType.html,
        content: htmlContent,
        plainText: plainTextContent ?? '',
      );
      nodesToInsert = clipboardService.processClipboardPaste(clipboardData);
    }

    // 2. If HTML processing yielded no nodes or HTML wasn't available, try Markdown from plain text
    if (nodesToInsert.isEmpty &&
        (plainTextContent != null && plainTextContent.trim().isNotEmpty)) {
      print(
          '[PasteService] HTML processing yielded no nodes or HTML not available. Trying Markdown from plain text.');

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
                      '[PasteService] Node type: ${node.runtimeType}, metadata: ${node.metadata}');
                  final nodeCopy = _createNodeWithNewId(node);
                  markdownNodes.add(nodeCopy);
                }
              }
            }

            if (markdownNodes.isNotEmpty) {
              nodesToInsert = markdownNodes;
              print('[PasteService] Successfully parsed Markdown content.');
            } else {
              print(
                  '[PasteService] Markdown parsing resulted in empty document. Falling back to plain text processing.');
            }
          } catch (e) {
            print(
                '[PasteService] Error processing markdown with super_editor_markdown: $e');
          }
        } else {
          // Not markdown - will fall through to plain text processing
          print(
              '[PasteService] Content doesn\'t appear to be markdown. Processing as plain text.');
        }
      } catch (e) {
        print(
            '[PasteService] Error parsing Markdown: $e. Falling back to plain text processing.');
        // Fallback to plain text processing will happen in the next block if nodesToInsert is still empty
      }
    }

    // 3. If Markdown also failed/not applicable (nodesToInsert is still empty), and plain text is available, process as plain text.
    if (nodesToInsert.isEmpty &&
        (plainTextContent != null && plainTextContent.trim().isNotEmpty)) {
      print(
          '[PasteService] Markdown processing failed or not applicable. Processing as plain text.');
      final clipboardData = ClipboardPasteData(
        type: ClipboardDataType.plainText,
        content: plainTextContent,
        plainText: plainTextContent,
      );
      nodesToInsert = clipboardService.processClipboardPaste(clipboardData);
    }

    if (nodesToInsert.isEmpty) {
      print('[PasteService] No nodes to insert after processing.');
      return false;
    }

    print(
        '[PasteService] Inserting ${nodesToInsert.length} nodes into document...');

    // Insert nodes into document
    await _insertNodesIntoDocument(
      document: document,
      composer: composer,
      nodesToInsert: nodesToInsert,
      pastePosition: actualPastePosition,
    );

    print('[PasteService] ✅ Paste operation completed successfully');
    return true;
  }

  /// Inserts the processed nodes into the document at the specified position.
  Future<void> _insertNodesIntoDocument({
    required MutableDocument document,
    required MutableDocumentComposer composer,
    required List<DocumentNode> nodesToInsert,
    required DocumentPosition pastePosition,
  }) async {
    final currentSelection = composer.selection;
    if (currentSelection == null) {
      print('[PasteService] No selection found, cannot paste.');
      return;
    }

    // Clear selection before modifying document to avoid invalid references
    composer.clearSelection();

    if (currentSelection.isCollapsed) {
      // For collapsed selection, insert nodes at the current position
      final nodeIndex = document.getNodeIndexById(pastePosition.nodeId);

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
  }

  /// Creates a new node with a unique ID based on the given node.
  /// Handles special markdown elements like horizontal rules, lists, and code blocks.
  DocumentNode _createNodeWithNewId(DocumentNode originalNode) {
    final newId = Editor.createNodeId();

    if (originalNode is ParagraphNode) {
      return ParagraphNode(
        id: newId,
        text: originalNode.text,
        metadata: Map<String, dynamic>.from(originalNode.metadata),
      );
    } else if (originalNode is ListItemNode) {
      return ListItemNode(
        id: newId,
        itemType: originalNode.type,
        text: originalNode.text,
        indent: originalNode.indent,
      );
    } else if (originalNode is HorizontalRuleNode) {
      return HorizontalRuleNode(
        id: newId,
        metadata: Map<String, dynamic>.from(originalNode.metadata),
      );
    } else if (originalNode is ImageNode) {
      return ImageNode(
        id: newId,
        imageUrl: originalNode.imageUrl,
        altText: originalNode.altText,
        metadata: Map<String, dynamic>.from(originalNode.metadata),
      );
    } else if (originalNode.getMetadataValue('blockType') ==
        const NamedAttribution('task')) {
      // Create a task node (checkbox item)
      if (originalNode is ParagraphNode) {
        return ParagraphNode(
          id: newId,
          text: originalNode.text,
          metadata: {
            'blockType': const NamedAttribution('task'),
            if (originalNode.metadata.containsKey('checked'))
              'checked': originalNode.metadata['checked'],
          },
        );
      }
    } else if (originalNode.getMetadataValue('blockType') ==
            const NamedAttribution('code') ||
        originalNode.getMetadataValue('blockType')?.id == 'code') {
      if (originalNode is ParagraphNode) {
        // For code blocks, ensure we properly format them and preserve language information
        String? language;
        if (originalNode.metadata.containsKey('language')) {
          final langValue = originalNode.metadata['language'];
          language = langValue != null ? langValue.toString() : null;
        }

        print(
            '[PasteService] Processing code block with content: "${originalNode.text.toPlainText().substring(0, math.min(20, originalNode.text.toPlainText().length))}..."');
        if (language != null) {
          print('[PasteService] Code language: $language');
        }

        // Create a new node with proper formatting for code blocks
        return ParagraphNode(
          id: newId,
          text: originalNode.text,
          metadata: {
            'blockType': const NamedAttribution('code'),
            if (language != null) 'language': language,
            'textAlign': TextAlign.left,
          },
        );
      }
    } else if (originalNode is TextNode) {
      return ParagraphNode(id: newId, text: originalNode.text);
    }

    // For any other node type, create a generic paragraph with the node's string representation
    print('[PasteService] Unhandled node type: ${originalNode.runtimeType}');
    return ParagraphNode(
      id: newId,
      text: AttributedText('Unsupported content type'),
    );
  }

  /// Manually extracts code blocks from markdown text
  /// This is used as a fallback when the standard markdown parser doesn't handle code blocks properly
  List<DocumentNode> _extractCodeBlocksManually(String markdownText) {
    final List<DocumentNode> nodes = [];
    final lines = markdownText.split('\n');

    print(
        '[PasteService] Manually extracting code blocks from markdown: ${markdownText.length} characters');

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
          print('[PasteService] Found code block with language: $language');
        } else {
          print(
              '[PasteService] Found code block without language specification');
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
              '[PasteService] Code block content preview: "${codeText.substring(0, math.min(20, codeText.length))}..."');

          // Create the code block with proper styling that matches our stylesheet
          final codeNode = ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(codeText),
            metadata: {
              'blockType': const NamedAttribution('code'),
              if (language != null && language.isNotEmpty) 'language': language,
              'textAlign': TextAlign.left,
            },
          );
          nodes.add(codeNode);
          print('[PasteService] Added code block node to result');
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
        '[PasteService] Manual extraction complete. Generated ${nodes.length} nodes');
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
