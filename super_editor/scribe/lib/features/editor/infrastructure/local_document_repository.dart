import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:super_editor/super_editor.dart';

import 'package:scribe/features/editor/domain/document_repository.dart';

class LocalDocumentRepository implements DocumentRepository {
  static const String _documentFileName = 'document.json';
  Timer? _autoSaveTimer;
  final _documentController = StreamController<Document>.broadcast();

  @override
  Future<Document?> loadDocument() async {
    try {
      final file = await _getDocumentFile();
      if (!await file.exists()) {
        return _createDefaultDocument();
      }

      // Simple JSON deserialization - would need proper implementation
      return _createDefaultDocument();
    } catch (e) {
      return _createDefaultDocument();
    }
  }

  @override
  Future<void> saveDocument(Document document) async {
    try {
      final file = await _getDocumentFile();
      // Simple JSON serialization - would need proper implementation
      final jsonData = {'nodes': <Map<String, dynamic>>[]};
      final jsonString = json.encode(jsonData);

      await file.writeAsString(jsonString);
      _documentController.add(document);
    } catch (e) {
      // Handle save error silently for now
    }
  }

  @override
  Future<void> autoSave(Document document) async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 5), () {
      saveDocument(document);
    });
  }

  @override
  Stream<Document> watchDocument() {
    return _documentController.stream;
  }

  Future<File> _getDocumentFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_documentFileName');
  }

  Document _createDefaultDocument() {
    return MutableDocument(
      nodes: [
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText('Welcome to Super Editor Scribe'),
        ),
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText('Start typing to create your document...'),
        ),
      ],
    );
  }

  void dispose() {
    _autoSaveTimer?.cancel();
    _documentController.close();
  }
}
