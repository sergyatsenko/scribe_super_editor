import 'package:super_editor/super_editor.dart';
import 'paste_service.dart';

/// Creates a custom request handler that intercepts PasteEditorRequest and uses
/// our rich text/markdown paste logic instead of the default paste behavior.
EditRequestHandler createCustomPasteRequestHandler(
  PasteService pasteService, {
  VoidCallback? onPasteComplete,
}) {
  return (Editor editor, EditRequest request) {
    if (request is PasteEditorRequest) {
      // Intercept the paste request and use our custom paste logic
      return CustomPasteEditorCommand(
        pasteService: pasteService,
        pastePosition: request.pastePosition,
        onPasteComplete: onPasteComplete,
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
    this.onPasteComplete,
  });

  final PasteService pasteService;
  final DocumentPosition pastePosition;
  final VoidCallback? onPasteComplete;

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
      return;
    }

    // Context menu paste was successful - now trigger UI refresh
    // Use the same multi-phase refresh logic as CustomPastePlugin
    print(
        '[CustomPasteEditorCommand] Paste successful, triggering UI refresh...');

    // Schedule UI refresh using the same timing as CustomPastePlugin
    _scheduleUIRefresh();
  }

  /// Schedules UI refresh using the same multi-phase approach as CustomPastePlugin
  void _scheduleUIRefresh() async {
    // PHASE 1: Immediate callback
    if (onPasteComplete != null) {
      onPasteComplete!();
    }

    // PHASE 2: Allow Flutter to process the first round of changes
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // PHASE 3: Second refresh callback
    if (onPasteComplete != null) {
      onPasteComplete!();
    }

    // PHASE 4: Final refresh with longer delay
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // PHASE 5: Final callback to ensure UI is updated
    if (onPasteComplete != null) {
      onPasteComplete!();

      // One final delay to allow setState to propagate
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    print('[CustomPasteEditorCommand] UI refresh sequence completed');
  }
}
