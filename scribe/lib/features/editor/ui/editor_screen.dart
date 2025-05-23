import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_editor/super_editor.dart';

import 'package:scribe/core/theme_provider.dart';
import 'package:scribe/features/editor/ui/floating_toolbar.dart'
    as ftb; // Renamed to avoid conflict with local ToolbarContent
import 'package:scribe/features/clipboard/application/clipboard_service.dart';
import 'package:scribe/features/editor/application/custom_paste_plugin.dart';
import 'package:scribe/features/editor/application/paste_service.dart';
import 'package:scribe/features/editor/application/custom_paste_request_handler.dart';
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
  late final PasteService _pasteService;
  late final ScrollController _scrollController;

  // Add a key to force editor rebuilds on demand
  final GlobalKey _editorKey = GlobalKey();
  final GlobalKey _viewportKey = GlobalKey();

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

    // Initialize services
    _clipboardService = ClipboardService();
    _pasteService = PasteService(clipboardService: _clipboardService);

    // Create custom request handler for rich text/markdown paste
    final customPasteRequestHandler = createCustomPasteRequestHandler(
      _pasteService,
      onPasteComplete: () {
        print(
            '[_EditorScreenState] Context menu paste complete callback received');
        // Force an immediate UI rebuild after paste
        if (mounted) {
          setState(() {
            print(
                '[_EditorScreenState] Forced rebuild after context menu paste');
          });
        }
      },
    );

    _editorController = EditorController(
      documentRepository: context.read<DocumentRepository>(),
      customRequestHandlers: [customPasteRequestHandler],
    );
    _editorFocusNode = FocusNode();
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
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  void _hideOrShowToolbar() {
    if (_isIOS) {
      // On iOS, the fixed/keyboard-aware toolbar is handled by _buildIOSFixedToolbar
      // and its visibility is controlled within that widget based on focus/keyboard state.
      // The desktop floating toolbar should not be shown.
      _hideEditorToolbar(); // Ensure desktop toolbar is hidden if it was somehow shown
      _hideImageToolbar(); // Ensure desktop image toolbar is hidden
      return;
    }

    // Original logic for desktop (mouse mode)
    if (_gestureMode == DocumentGestureMode.mouse) {
      _hideOrShowDesktopToolbar();
    }
    // Android and other non-iOS mobile platforms can use default behavior or have their own logic.
    // For now, this means no explicit toolbar for them from this method.
  }

  void _hideOrShowDesktopToolbar() {
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
    // Schedule the show() call to avoid calling it during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFormatBarOverlayController.show();
      }
    });

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

    // Schedule the hide() call to avoid calling it during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _textFormatBarOverlayController.hide();
      }
    });

    // Ensure that focus returns to the editor.
    if (FocusManager.instance.primaryFocus != FocusManager.instance.rootScope) {
      _editorFocusNode.requestFocus();
    }
  }

  void _showImageToolbar() {
    // Schedule the show() call to avoid calling it during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _imageFormatBarOverlayController.show();
      }
    });

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
  }

  void _hideImageToolbar() {
    // Null out the selection anchor so that when the bar re-appears,
    // it doesn't momentarily "flash" at its old anchor position.
    _imageSelectionAnchor.value = null;

    // Schedule the hide() call to avoid calling it during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _imageFormatBarOverlayController.hide();
      }
    });

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

        // For iOS, the main layout will be wrapped in a Stack to include the fixed/keyboard-aware toolbar.
        // The desktop floating toolbar is handled by OverlayPortal as before.
        Widget mainContent = _buildLayout();
        if (_isIOS) {
          mainContent = Stack(
            children: [
              mainContent, // The main editor layout
              _buildIOSFixedToolbar(), // The new iOS toolbar
            ],
          );
        }

        return Scaffold(
          body: OverlayPortal(
            controller: _textFormatBarOverlayController,
            overlayChildBuilder:
                _buildFloatingToolbar, // This is for desktop/non-iOS
            child: OverlayPortal(
              controller: _imageFormatBarOverlayController,
              overlayChildBuilder:
                  _buildImageToolbar, // This is for desktop/non-iOS
              child:
                  mainContent, // mainContent now includes the Stack for iOS if applicable
            ),
          ),
        );
      },
    );
  }

  Widget _buildLayout() {
    // Simplified: Always build the editor area. iOS toolbar is handled by the Stack in `build()`.
    // Desktop/other platforms show the EditorToolbar if not distraction-free.
    return Column(
      children: [
        if (!_editorController.isDistractionFree) ...[
          _buildAppBar(),
          if (!_isIOS) // Only show EditorToolbar for non-iOS platforms
            EditorToolbar(controller: _editorController),
        ],
        Expanded(child: _buildEditor()),
      ],
    );
  }

  Widget _buildIOSFixedToolbar() {
    if (!_editorController.isInitialized || _editorController.editor == null) {
      return const SizedBox.shrink();
    }
    return KeyboardHeightBuilder(
      builder: (context, keyboardHeight) {
        // For positioning, MediaQuery.of(context).viewInsets.bottom is often more reliable
        // as it directly reflects the space taken by system UI like the keyboard.
        final double actualKeyboardOffset =
            MediaQuery.of(context).viewInsets.bottom;

        // Always show the toolbar on iOS (per user request)
        return Positioned(
          left: 0,
          right: 0,
          bottom: actualKeyboardOffset, // Use viewInsets.bottom for positioning
          child: ftb.ToolbarContent(
            editorViewportKey: _viewportKey,
            editorFocusNode: _editorFocusNode,
            editor: _editorController.editor!,
            document: _editorController.document!,
            composer: _editorController.composer!,
            isFullWidth: true, // Enable full-width mobile styling
          ),
        );
      },
    );
  }

  Widget _buildKeyboardAwareToolbar() {
    // Use SuperEditor's KeyboardHeightBuilder for proper keyboard detection
    return KeyboardHeightBuilder(
      builder: (context, keyboardHeight) {
        return Padding(
          // Add padding that takes up the height of the software keyboard so
          // that the toolbar sits just above the keyboard.
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: EditorToolbar(controller: _editorController),
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
    print('[_EditorScreenState] _buildEditor() called');
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      print('[_EditorScreenState] ❌ Editor components not ready yet');
      return const Center(child: CircularProgressIndicator());
    }

    print('[_EditorScreenState] ✅ Creating SuperEditor with CustomPastePlugin');

    Widget superEditorWidget = SuperEditor(
      key: _editorKey,
      editor: editor,
      focusNode: _editorFocusNode,
      scrollController: _scrollController,
      documentLayoutKey: _docLayoutKey,
      selectionLayerLinks: _selectionLayerLinks,
      componentBuilders: defaultComponentBuilders,
      gestureMode: _gestureMode,
      plugins: {
        CustomPastePlugin(
          clipboardService: _clipboardService,
          onPasteComplete: () {
            print('[_EditorScreenState] Paste complete callback received');
            if (mounted) {
              setState(() {
                print('[_EditorScreenState] Forced rebuild after paste');
              });
            }
          },
        ),
      },
      stylesheet: _buildStylesheet(),
    );

    // Determine padding for iOS
    if (_isIOS) {
      return KeyboardHeightBuilder(
        builder: (context, keyboardHeight) {
          // When keyboard is hidden, add padding for the fixed toolbar at the bottom.
          // Toolbar height is 40, add a bit more for breathing room.
          final double bottomPadding = (keyboardHeight == 0) ? 50.0 : 0.0;

          return Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: KeyedSubtree(
              key:
                  _viewportKey, // Assuming _viewportKey is still relevant for the editor area
              child: Container(
                color: _editorController.isDistractionFree
                    ? Theme.of(context).colorScheme.surface
                    : null,
                child: superEditorWidget,
              ),
            ),
          );
        },
      );
    } else {
      // For non-iOS platforms, use the existing structure
      return KeyedSubtree(
        key: _viewportKey,
        child: Container(
          color: _editorController.isDistractionFree
              ? Theme.of(context).colorScheme.surface
              : null,
          child: superEditorWidget,
        ),
      );
    }
  }

  Widget _buildFloatingToolbar(BuildContext context) {
    final editor = _editorController.editor;
    final document = _editorController.document;
    final composer = _editorController.composer;

    if (editor == null || document == null || composer == null) {
      return const SizedBox();
    }

    return ftb.EditorToolbar(
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

    return ftb.ImageFormatToolbar(
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
