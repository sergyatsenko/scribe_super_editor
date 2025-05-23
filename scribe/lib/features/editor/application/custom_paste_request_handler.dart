import 'package:super_editor/super_editor.dart';
import 'paste_service.dart';

/// Creates a custom request handler that intercepts PasteEditorRequest and uses
/// our rich text/markdown paste logic instead of the default paste behavior.
EditRequestHandler createCustomPasteRequestHandler(PasteService pasteService) {
  return (Editor editor, EditRequest request) {
    if (request is PasteEditorRequest) {
      // Intercept the paste request and use our custom paste logic
      return CustomPasteEditorCommand(
        pasteService: pasteService,
        pastePosition: request.pastePosition,
      );
    }

    // For other requests, return null to let other handlers process them
    return null;
  };
}

/// Custom paste command that uses PasteService for rich text/markdown pasting.
class CustomPasteEditorCommand extends EditCommand {
  CustomPasteEditorCommand({
    required this.pasteService,
    required this.pastePosition,
  });

  final PasteService pasteService;
  final DocumentPosition pastePosition;

  @override
  HistoryBehavior get historyBehavior => HistoryBehavior.undoable;

  @override
  void execute(EditContext context, CommandExecutor executor) async {
    final document = context.document;
    final composer = context.find<MutableDocumentComposer>(Editor.composerKey);

    if (document is! MutableDocument) {
      print(
          '[CustomPasteEditorCommand] Document is not MutableDocument, falling back to default');
      // Fallback to default paste behavior if types don't match
      executor.executeCommand(
        PasteEditorCommand(
          content: '', // Will be fetched by default command
          pastePosition: pastePosition,
        ),
      );
      return;
    }

    print(
        '[CustomPasteEditorCommand] Using custom paste logic for context menu paste');

    // Use our PasteService for rich text/markdown pasting
    final success = await pasteService.handlePaste(
      document: document,
      composer: composer,
      pastePosition: pastePosition,
    );

    if (!success) {
      print(
          '[CustomPasteEditorCommand] Custom paste failed, falling back to default');
      // If custom paste fails, fall back to default paste behavior
      executor.executeCommand(
        PasteEditorCommand(
          content: '', // Will be fetched by default command
          pastePosition: pastePosition,
        ),
      );
    }
  }
}
