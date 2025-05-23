import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import 'package:scribe/features/editor/domain/document_repository.dart';

class EditorController extends ChangeNotifier {
  EditorController({required this.documentRepository});

  final DocumentRepository documentRepository;

  Editor? _editor;
  MutableDocument? _document;
  MutableDocumentComposer? _composer;

  // Explicitly typed listener field, matching the typedef in super_editor
  late final DocumentChangeListener _docListener;

  Editor? get editor => _editor;
  MutableDocument? get document => _document;
  MutableDocumentComposer? get composer => _composer;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isDistractionFree = false;
  bool get isDistractionFree => _isDistractionFree;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final loadedDocument = await documentRepository.loadDocument();
    _document = loadedDocument as MutableDocument? ??
        MutableDocument(
          nodes: [
            ParagraphNode(
              id: Editor.createNodeId(),
              text: AttributedText('Welcome to Super Editor Scribe'),
            ),
          ],
        );

    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document!,
      composer: _composer!,
    );

    // Initialize the listener, ensuring the signature matches DocumentChangeListener
    _docListener = (DocumentChangeLog changeLog) {
      print(
        '[EditorController] _docListener CALLED. ChangeLog details: ${changeLog.changes.length} changes.',
      );
      if (_document != null) {
        documentRepository.autoSave(_document!);
      }

      // Re-create the editor instance to ensure SuperEditor gets a fresh one.
      // This is a more drastic measure to see if the Editor instance itself was stale.
      if (_document != null && _composer != null && _isInitialized) {
        print(
          '[EditorController] Re-creating editor instance due to document change.',
        );
        _editor = createDefaultDocumentEditor(
          document: _document!,
          composer: _composer!,
        );
      }

      notifyListeners(); // Notify listeners AFTER potential editor re-creation
    };

    // Listen to document changes using super_editor's Document.addListener API.
    _document!.addListener(_docListener);

    _isInitialized = true;
    notifyListeners();
  }

  void toggleDistractionFree() {
    _isDistractionFree = !_isDistractionFree;
    notifyListeners();
  }

  void formatBold() {
    if (_editor == null || _composer?.selection == null) return;
    _editor!.execute([
      ToggleTextAttributionsRequest(
        documentRange: _composer!.selection!,
        attributions: {boldAttribution},
      ),
    ]);
  }

  void formatItalic() {
    if (_editor == null || _composer?.selection == null) return;
    _editor!.execute([
      ToggleTextAttributionsRequest(
        documentRange: _composer!.selection!,
        attributions: {italicsAttribution},
      ),
    ]);
  }

  void formatUnderline() {
    if (_editor == null || _composer?.selection == null) return;
    _editor!.execute([
      ToggleTextAttributionsRequest(
        documentRange: _composer!.selection!,
        attributions: {underlineAttribution},
      ),
    ]);
  }

  void formatHeader1() {
    final selection = _composer?.selection;
    if (_editor == null || selection == null) return;

    _editor!.execute([
      ChangeParagraphBlockTypeRequest(
        nodeId: selection.extent.nodeId,
        blockType: header1Attribution,
      ),
    ]);
  }

  void formatHeader2() {
    final selection = _composer?.selection;
    if (_editor == null || selection == null) return;

    _editor!.execute([
      ChangeParagraphBlockTypeRequest(
        nodeId: selection.extent.nodeId,
        blockType: header2Attribution,
      ),
    ]);
  }

  void insertLink(String url, String text) {
    if (_editor == null || _composer?.selection == null) return;

    // Simple text insertion for now - link functionality will be added later
    _editor!.execute([
      InsertTextRequest(
        documentPosition: _composer!.selection!.extent,
        textToInsert: text,
        attributions: {LinkAttribution(url)},
      ),
    ]);
  }

  Future<void> saveDocument() async {
    if (_document != null) {
      await documentRepository.saveDocument(_document!);
    }
  }

  @override
  void dispose() {
    // Remove the DocumentChangeListener using super_editor's Document.removeListener API.
    if (_document != null) {
      // Ensure _document was initialized before trying to remove listener
      _document!.removeListener(_docListener);
    }
    super.dispose();
  }
}
