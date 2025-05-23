import 'dart:async';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';

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

    if (htmlContent != null && htmlContent.trim().isNotEmpty) {
      print('[PasteService] Processing HTML content...');
      final clipboardData = ClipboardPasteData(
        type: ClipboardDataType.html,
        content: htmlContent,
        plainText: plainTextContent ?? '',
      );
      nodesToInsert = clipboardService.processClipboardPaste(clipboardData);
    } else if (plainTextContent != null && plainTextContent.trim().isNotEmpty) {
      print('[PasteService] Processing plain text content...');
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
      return HorizontalRuleNode(id: newId);
    } else {
      // For other node types, try to preserve as much as possible
      // This is a fallback case
      return ParagraphNode(
        id: newId,
        text: AttributedText('Unsupported content type'),
      );
    }
  }
}
