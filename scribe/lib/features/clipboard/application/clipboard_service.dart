import 'package:html/parser.dart' show parse;
import 'package:super_editor/super_editor.dart';
import 'package:scribe/features/clipboard/application/html_to_document_converter.dart';

class ClipboardService {
  List<DocumentNode> processClipboardPaste(ClipboardPasteData data) {
    if (data.content.isEmpty) {
      return [];
    }

    switch (data.type) {
      case ClipboardDataType.html:
        final nodes = _convertHtmlToNodes(data.content);
        return nodes;
      case ClipboardDataType.plainText:
        final nodes = _convertPlainTextToNodes(data.content);
        return nodes;
    }
  }

  List<DocumentNode> _convertHtmlToNodes(String htmlContent) {
    try {
      final document = parse(htmlContent);
      final converter = HtmlToDocumentConverter();
      final nodes = converter.convert(document);

      if (nodes.isEmpty) {
        return _convertPlainTextToNodes(htmlContent);
      }

      return nodes;
    } catch (e) {
      // Fall back to plain text if HTML parsing fails
      return _convertPlainTextToNodes(htmlContent);
    }
  }

  List<DocumentNode> _convertPlainTextToNodes(String plainText) {
    final lines = plainText.split('\n');

    final nodes = lines
        .map(
          (line) => ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(line.trim()),
          ),
        )
        .toList();

    return nodes;
  }
}

enum ClipboardDataType { plainText, html }

class ClipboardPasteData {
  const ClipboardPasteData({
    required this.type,
    required this.content,
    required this.plainText,
  });

  final ClipboardDataType type;
  final String content;
  final String plainText;
}
