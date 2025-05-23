import 'package:super_editor/super_editor.dart';

abstract class DocumentRepository {
  Future<Document?> loadDocument();
  Future<void> saveDocument(Document document);
  Future<void> autoSave(Document document);
  Stream<Document> watchDocument();
}
