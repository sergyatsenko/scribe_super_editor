import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

import 'package:scribe/core/theme_provider.dart';
import 'package:scribe/demos/example_editor/_toolbar.dart' as demo_toolbar;
import 'package:scribe/features/clipboard/application/clipboard_service.dart';
import 'package:scribe/features/editor/application/custom_paste_plugin.dart';
import 'package:scribe/features/editor/application/editor_controller.dart';
import 'package:scribe/features/editor/domain/document_repository.dart';
import 'package:scribe/features/editor/ui/editor_toolbar.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _editorController;
  late final FocusNode _editorFocusNode;
  late final ClipboardService _clipboardService;
  late final ScrollController _scrollController;

  // Add a key to force editor rebuilds on demand
  final GlobalKey _editorKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();

  // Add a counter to force rebuilds
  int _editorRebuildCount = 0;

  // Selection layer links for the floating toolbar
  late final SelectionLayerLinks _selectionLayerLinks;

  // Floating toolbar controllers
  final _textFormatBarOverlayController = OverlayPortalController();
  final _textSelectionAnchor = ValueNotifier<Offset?>(null);

  final _imageFormatBarOverlayController = OverlayPortalController();
  final _imageSelectionAnchor = ValueNotifier<Offset?>(null);

  // Document layout key for positioning toolbars
  final GlobalKey _docLayoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _editorController = EditorController(
      documentRepository: context.read<DocumentRepository>(),
    );
    _editorFocusNode = FocusNode();
    _clipboardService = ClipboardService();
    _scrollController = ScrollController();

    _selectionLayerLinks = SelectionLayerLinks();

    _editorFocusNode.addListener(() {
      print(
        '[_EditorScreenState] Editor focus changed: hasFocus = ${_editorFocusNode.hasFocus}',
      );
    });

    _editorController.addListener(_rebuildScreen);

    _editorController.initialize().then((_) {
      if (mounted) {
        setState(() {});
        // Set up selection listener for floating toolbar
        _editorController.composer?.selectionNotifier
            .addListener(_hideOrShowToolbar);
      }
    });

    _scrollController.addListener(_hideOrShowToolbar);
  }

  @override
  void dispose() {
    _editorController.removeListener(_rebuildScreen);
    _editorController.composer?.selectionNotifier
        .removeListener(_hideOrShowToolbar);
    _editorController.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _rebuildScreen() {
    if (mounted) {
      print(
        '[_EditorScreenState] _rebuildScreen called due to _editorController notification.',
      );
      setState(() {});
    }
  }

  DocumentGestureMode get _gestureMode {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return DocumentGestureMode.android;
      case TargetPlatform.iOS:
        return DocumentGestureMode.iOS;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return DocumentGestureMode.mouse;
    }
  }

  bool get _isMobile => _gestureMode != DocumentGestureMode.mouse;

  void _hideOrShowToolbar() {
    if (_gestureMode != DocumentGestureMode.mouse) {
      // We only add our own toolbar when using mouse. On mobile, a bar
      // is rendered for us.
      return;
    }

    final selection = _editorController.composer?.selection;
    if (selection == null) {
      // Nothing is selected. We don't want to show a toolbar
      // in this case.
      _hideEditorToolbar();
      return;
    }
    if (selection.base.nodeId != selection.extent.nodeId) {
      // More than one node is selected. We don't want to show
      // a toolbar in this case.
      _hideEditorToolbar();
      _hideImageToolbar();
      return;
    }
    if (selection.isCollapsed) {
      // We only want to show the toolbar when a span of text
      // is selected. Therefore, we ignore collapsed selections.
      _hideEditorToolbar();
      _hideImageToolbar();
      return;
    }

    final selectedNode =
        _editorController.document?.getNodeById(selection.extent.nodeId);

    if (selectedNode is ImageNode) {
      print("Showing image toolbar");
      // Show the editor's toolbar for image sizing.
      _showImageToolbar();
      _hideEditorToolbar();
      return;
    } else {
      // The currently selected content is not an image. We don't
      // want to show the image toolbar.
      _hideImageToolbar();
    }

    if (selectedNode is TextNode) {
      // Show the editor's toolbar for text styling.
      _showEditorToolbar();
      _hideImageToolbar();
      return;
    } else {
      // The currently selected content is not a paragraph. We don't
      // want to show a toolbar in this case.
      _hideEditorToolbar();
    }
  }

  void _showEditorToolbar() {
    _textFormatBarOverlayController.show();

    // Schedule a callback after this frame to locate the selection
    // bounds on the screen and display the toolbar near the selected
    // text.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final layout = _docLayoutKey.currentState as DocumentLayout?;
      final selection = _editorController.composer?.selection;
      if (layout != null && selection != null) {
        final docBoundingBox =
            layout.getRectForSelection(selection.base, selection.extent);
        if (docBoundingBox != null) {
          final globalOffset =
              layout.getGlobalOffsetFromDocumentOffset(Offset.zero);
          final overlayBoundingBox = docBoundingBox.shift(globalOffset);

          _textSelectionAnchor.value = overlayBoundingBox.topCenter;
        }
      }
    });
  }

  void _hideEditorToolbar() {
    // Null out the selection anchor so that when it re-appears,
    // the bar doesn't momentarily "flash" at its old anchor position.
    _textSelectionAnchor.value = null;

    _textFormatBarOverlayController.hide();

    // Ensure that focus returns to the editor.
    if (FocusManager.instance.primaryFocus != FocusManager.instance.rootScope) {
      _editorFocusNode.requestFocus();
    }
  }

  void _showImageToolbar() {
    // Schedule a callback after this frame to locate the selection
    // bounds on the screen and display the toolbar near the selected
    // text.
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final layout = _docLayoutKey.currentState as DocumentLayout?;
      final selection = _editorController.composer?.selection;
      if (layout != null && selection != null) {
        final docBoundingBox =
            layout.getRectForSelection(selection.base, selection.extent);
        if (docBoundingBox != null) {
          final docBox =
              _docLayoutKey.currentContext!.findRenderObject() as RenderBox;
          final overlayBoundingBox = Rect.fromPoints(
            docBox.localToGlobal(docBoundingBox.topLeft),
            docBox.localToGlobal(docBoundingBox.bottomRight),
          );

          _imageSelectionAnchor.value = overlayBoundingBox.center;
        }
      }
    });

    _imageFormatBarOverlayController.show();
  }

  void _hideImageToolbar() {
    // Null out the selection anchor so that when the bar re-appears,
    // it doesn't momentarily "flash" at its old anchor position.
    _imageSelectionAnchor.value = null;

    _imageFormatBarOverlayController.hide();

    // Ensure that focus returns to the editor.
    if (FocusManager.instance.primaryFocus != FocusManager.instance.rootScope) {
      _editorFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _editorController,
      builder: (context, child) {
        if (!_editorController.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          body: OverlayPortal(
            controller: _textFormatBarOverlayController,
            overlayChildBuilder: _buildFloatingToolbar,
            child: OverlayPortal(
              controller: _imageFormatBarOverlayController,
              overlayChildBuilder: _buildImageToolbar,
              child: Column(
                children: [
                  if (!_editorController.isDistractionFree) ...[
                    _buildAppBar(),
                    EditorToolbar(controller: _editorController),
                  ],
                  Expanded(child: _buildEditor()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      title: const Text('Super Editor Scribe'),
      actions: [
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            return IconButton(
              icon: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
              ),
              onPressed: themeProvider.toggleTheme,
              tooltip: 'Toggle theme',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.save),
          onPressed: _editorController.saveDocument,
          tooltip: 'Save document',
        ),
      ],
    );
  }

  Widget _buildEditor() {
    print(
        '[_EditorScreenState] _buildEditor() called. Rebuild count: $_editorRebuildCount');
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      print('[_EditorScreenState] ❌ Editor components not ready yet');
      return const Center(child: CircularProgressIndicator());
    }

    print('[_EditorScreenState] ✅ Creating SuperEditor with CustomPastePlugin');

    return KeyedSubtree(
      key: _viewportKey,
      child: Container(
        color: _editorController.isDistractionFree
            ? Theme.of(context).colorScheme.surface
            : null,
        child: SuperEditor(
          // Use a combined key of the GlobalKey and rebuild count to force complete rebuilds
          key: ValueKey('$_editorKey-$_editorRebuildCount'),
          editor: editor,
          focusNode: _editorFocusNode,
          scrollController: _scrollController,
          documentLayoutKey: _docLayoutKey,
          selectionLayerLinks: _selectionLayerLinks,
          // Use default component builders - the style for code blocks will be defined in the stylesheet
          componentBuilders: defaultComponentBuilders,
          gestureMode: _gestureMode,
          plugins: {
            // Create a custom paste plugin with a listener to force refresh after paste
            CustomPastePlugin(
              clipboardService: _clipboardService,
              onPasteComplete: () {
                print('[_EditorScreenState] Paste complete callback received');
                // Force an immediate UI rebuild after paste by incrementing the rebuild count
                if (mounted) {
                  setState(() {
                    // Increment the rebuild counter to force a complete widget rebuild
                    _editorRebuildCount++;
                    print(
                        '[_EditorScreenState] Forced rebuild. New count: $_editorRebuildCount');
                  });
                }
              },
            ),
          },
          stylesheet: _buildStylesheet(),
        ),
      ),
    );
  }

  Widget _buildFloatingToolbar(BuildContext context) {
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      return const SizedBox();
    }

    return demo_toolbar.EditorToolbar(
      editorViewportKey: _viewportKey,
      anchor: _selectionLayerLinks.expandedSelectionBoundsLink,
      editorFocusNode: _editorFocusNode,
      editor: editor,
      document: document,
      composer: composer,
      closeToolbar: _hideEditorToolbar,
    );
  }

  Widget _buildImageToolbar(BuildContext context) {
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      return const SizedBox();
    }

    return demo_toolbar.ImageFormatToolbar(
      anchor: _imageSelectionAnchor,
      composer: composer,
      setWidth: (nodeId, width) {
        print("Applying width $width to node $nodeId");
        final node = document.getNodeById(nodeId);
        if (node != null) {
          final currentStyles =
              SingleColumnLayoutComponentStyles.fromMetadata(node);

          editor.execute([
            ChangeSingleColumnLayoutComponentStylesRequest(
              nodeId: nodeId,
              styles: SingleColumnLayoutComponentStyles(
                width: width,
                padding: currentStyles.padding,
              ),
            )
          ]);
        }
      },
      closeToolbar: _hideImageToolbar,
    );
  }

  Stylesheet _buildStylesheet() {
    final theme = Theme.of(context);

    return defaultStylesheet.copyWith(
      addRulesAfter: [
        StyleRule(
          BlockSelector.all,
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.symmetric(
              horizontal: 24,
              vertical: 8,
            ),
            Styles.textStyle: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.6,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header1'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineLarge!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 8,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header2'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.headlineMedium!.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: 8,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('blockquote'),
          (doc, docNode) => {
            Styles.textStyle: theme.textTheme.bodyLarge!.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              fontStyle: FontStyle.italic,
            ),
            Styles.padding: const CascadingPadding.only(
              left: 40,
              right: 24,
              top: 8,
              bottom: 8,
            ),
          },
        ),
        // Enhanced style rule for code blocks
        StyleRule(
          const BlockSelector('code'),
          (doc, docNode) => {
            Styles.padding: const CascadingPadding.only(
              left: 40,
              right: 40,
              top: 16,
              bottom: 16,
            ),
            Styles.textStyle: TextStyle(
              fontFamily: 'Courier New, monospace', // Explicit monospace font
              fontSize: 14.0,
              color: theme.colorScheme.onSurface,
              height: 1.5,
              backgroundColor:
                  theme.colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            // Use supported style properties for code blocks
            Styles.textAlign: TextAlign.left,
            // We'll rely on the background color in the textStyle since paragraphStyle
            // with border and borderRadius isn't directly supported in the stylesheet
          },
        ),
      ],
    );
  }
}
