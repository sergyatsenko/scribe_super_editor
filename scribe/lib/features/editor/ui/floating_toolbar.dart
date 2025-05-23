import 'dart:math';

import 'package:scribe/features/editor/infrastructure/toolbar_item_selector.dart';
import 'package:scribe/logging.dart';
import 'package:flutter/material.dart';
import 'package:scribe/l10n/app_localizations.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:overlord/follow_the_leader.dart';
import 'package:super_editor/super_editor.dart';

/// Small toolbar that is intended to display near some selected
/// text and offer a few text formatting controls.
///
/// [EditorToolbar] expects to be displayed in a [Stack] where it
/// will position itself based on the given [anchor]. This can be
/// accomplished, for example, by adding [EditorToolbar] to the
/// application [Overlay]. Any other [Stack] should work, too.
class EditorToolbar extends StatefulWidget {
  const EditorToolbar({
    Key? key,
    required this.editorViewportKey,
    required this.editorFocusNode,
    required this.editor,
    required this.document,
    required this.composer,
    required this.anchor,
    required this.closeToolbar,
  }) : super(key: key);

  /// [GlobalKey] that should be attached to a widget that wraps the viewport
  /// area, which keeps the toolbar from appearing outside of the editor area.
  final GlobalKey editorViewportKey;

  /// A [LeaderLink] that should be attached to the boundary of the toolbar
  /// focal area, such as wrapped around the user's selection area.
  ///
  /// The toolbar is positioned relative to this anchor link.
  final LeaderLink anchor;

  /// The [FocusNode] attached to the editor to which this toolbar applies.
  final FocusNode editorFocusNode;

  /// The [editor] is used to alter document content, such as
  /// when the user selects a different block format for a
  /// text blob, e.g., paragraph, header, blockquote, or
  /// to apply styles to text.
  final Editor? editor;

  final Document document;

  /// The [composer] provides access to the user's current
  /// selection within the document, which dictates the
  /// content that is altered by the toolbar's options.
  final DocumentComposer composer;

  /// Delegate that instructs the owner of this [EditorToolbar]
  /// to close the toolbar, such as after submitting a URL
  /// for some text.
  final VoidCallback closeToolbar;

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  late final FollowerAligner _toolbarAligner;
  late FollowerBoundary _screenBoundary;
  late FocusNode _popoverFocusNode;

  @override
  void initState() {
    super.initState();
    _toolbarAligner = CupertinoPopoverToolbarAligner(widget.editorViewportKey);
    _popoverFocusNode = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenBoundary = WidgetFollowerBoundary(
      boundaryKey: widget.editorViewportKey,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void dispose() {
    _popoverFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if editor, document, or composer is null. If so, don't build the toolbar.
    // This can happen during initial load or if the editor is disposed.
    if (widget.editor == null ||
        widget.composer == null ||
        widget.document == null) {
      appLog.fine(
          "EditorToolbar: Editor, composer, or document is null. Building SizedBox.shrink().");
      return const SizedBox.shrink();
    }

    return BuildInOrder(
      children: [
        FollowerFadeOutBeyondBoundary(
          link: widget.anchor,
          boundary: _screenBoundary,
          child: Follower.withAligner(
            link: widget.anchor,
            aligner: _toolbarAligner,
            boundary: _screenBoundary,
            showWhenUnlinked: false,
            child: SuperEditorPopover(
              popoverFocusNode: _popoverFocusNode,
              editorFocusNode: widget.editorFocusNode,
              child: ToolbarContent(
                editorViewportKey: widget.editorViewportKey,
                editorFocusNode: widget.editorFocusNode,
                editor: widget.editor!,
                document: widget.document,
                composer: widget.composer,
                onLinkApplied: widget.closeToolbar,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// New Reusable Toolbar Content Widget
class ToolbarContent extends StatefulWidget {
  const ToolbarContent({
    Key? key,
    required this.editorViewportKey,
    required this.editorFocusNode,
    required this.editor,
    required this.document,
    required this.composer,
    this.onLinkApplied, // Optional callback for when a link is applied
  }) : super(key: key);

  final GlobalKey editorViewportKey;
  final FocusNode editorFocusNode;
  final Editor editor;
  final Document document;
  final DocumentComposer composer;
  final VoidCallback? onLinkApplied;

  @override
  State<ToolbarContent> createState() => _ToolbarContentState();
}

class _ToolbarContentState extends State<ToolbarContent> {
  bool _showUrlField = false;
  late FocusNode _urlFocusNode;
  ImeAttributedTextEditingController? _urlController;

  @override
  void initState() {
    super.initState();
    _urlFocusNode = FocusNode();
    _urlController = ImeAttributedTextEditingController(
        controller: SingleLineAttributedTextEditingController(_applyLink))
      ..onPerformActionPressed = _onPerformAction
      ..text = AttributedText("https://");
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _urlController!.dispose();
    super.dispose();
  }

  bool _isConvertibleNode() {
    final selection = widget.composer.selection;
    if (selection == null || selection.base.nodeId != selection.extent.nodeId) {
      return false;
    }
    final selectedNode = widget.document.getNodeById(selection.extent.nodeId);
    return selectedNode is ParagraphNode || selectedNode is ListItemNode;
  }

  _TextType _getCurrentTextType() {
    final selectedNode =
        widget.document.getNodeById(widget.composer.selection!.extent.nodeId);
    if (selectedNode is ParagraphNode) {
      final type = selectedNode.getMetadataValue('blockType');
      if (type == header1Attribution) return _TextType.header1;
      if (type == header2Attribution) return _TextType.header2;
      if (type == header3Attribution) return _TextType.header3;
      if (type == blockquoteAttribution) return _TextType.blockquote;
      return _TextType.paragraph;
    } else if (selectedNode is ListItemNode) {
      return selectedNode.type == ListItemType.ordered
          ? _TextType.orderedListItem
          : _TextType.unorderedListItem;
    }
    throw Exception('Alignment does not apply to node of type: $selectedNode');
  }

  TextAlign _getCurrentTextAlignment() {
    final selectedNode =
        widget.document.getNodeById(widget.composer.selection!.extent.nodeId);
    if (selectedNode is ParagraphNode) {
      final align = selectedNode.getMetadataValue('textAlign');
      switch (align) {
        case 'left':
          return TextAlign.left;
        case 'center':
          return TextAlign.center;
        case 'right':
          return TextAlign.right;
        case 'justify':
          return TextAlign.justify;
        default:
          return TextAlign.left;
      }
    }
    throw Exception('Invalid node type: $selectedNode');
  }

  bool _isTextAlignable() {
    final selection = widget.composer.selection;
    if (selection == null || selection.base.nodeId != selection.extent.nodeId) {
      return false;
    }
    final selectedNode = widget.document.getNodeById(selection.extent.nodeId);
    return selectedNode is ParagraphNode;
  }

  void _convertTextToNewType(_TextType? newType) {
    final existingTextType = _getCurrentTextType();
    if (existingTextType == newType) return;

    final selectionExtentNodeId = widget.composer.selection!.extent.nodeId;
    List<EditRequest> requests = [];
    if (_isListItem(existingTextType) && _isListItem(newType)) {
      requests.add(ChangeListItemTypeRequest(
        nodeId: selectionExtentNodeId,
        newType: newType == _TextType.orderedListItem
            ? ListItemType.ordered
            : ListItemType.unordered,
      ));
    } else if (_isListItem(existingTextType) && !_isListItem(newType)) {
      requests.add(ConvertListItemToParagraphRequest(
        nodeId: selectionExtentNodeId,
        paragraphMetadata: {'blockType': _getBlockTypeAttribution(newType)},
      ));
    } else if (!_isListItem(existingTextType) && _isListItem(newType)) {
      requests.add(ConvertParagraphToListItemRequest(
        nodeId: selectionExtentNodeId,
        type: newType == _TextType.orderedListItem
            ? ListItemType.ordered
            : ListItemType.unordered,
      ));
    } else {
      requests.add(ChangeParagraphBlockTypeRequest(
        nodeId: selectionExtentNodeId,
        blockType: _getBlockTypeAttribution(newType),
      ));
    }
    widget.editor.execute(requests);
  }

  bool _isListItem(_TextType? type) {
    return type == _TextType.orderedListItem ||
        type == _TextType.unorderedListItem;
  }

  Attribution? _getBlockTypeAttribution(_TextType? newType) {
    switch (newType) {
      case _TextType.header1:
        return header1Attribution;
      case _TextType.header2:
        return header2Attribution;
      case _TextType.header3:
        return header3Attribution;
      case _TextType.blockquote:
        return blockquoteAttribution;
      case _TextType.paragraph:
      default:
        return null;
    }
  }

  void _toggleBold() {
    widget.editor.execute([
      ToggleTextAttributionsRequest(
          documentRange: widget.composer.selection!,
          attributions: {boldAttribution}),
    ]);
  }

  void _toggleItalics() {
    widget.editor.execute([
      ToggleTextAttributionsRequest(
          documentRange: widget.composer.selection!,
          attributions: {italicsAttribution}),
    ]);
  }

  void _toggleStrikethrough() {
    widget.editor.execute([
      ToggleTextAttributionsRequest(
          documentRange: widget.composer.selection!,
          attributions: {strikethroughAttribution}),
    ]);
  }

  void _toggleSuperscript() {
    widget.editor.execute([
      ToggleTextAttributionsRequest(
          documentRange: widget.composer.selection!,
          attributions: {superscriptAttribution}),
    ]);
  }

  void _toggleSubscript() {
    widget.editor.execute([
      ToggleTextAttributionsRequest(
          documentRange: widget.composer.selection!,
          attributions: {subscriptAttribution}),
    ]);
  }

  bool _isSingleLinkSelected() {
    return _getSelectedLinkSpans().length == 1;
  }

  bool _areMultipleLinksSelected() {
    return _getSelectedLinkSpans().length >= 2;
  }

  Set<AttributionSpan> _getSelectedLinkSpans() {
    final selection = widget.composer.selection;
    if (selection == null) return {};
    final baseOffset = (selection.base.nodePosition as TextPosition).offset;
    final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
    final selectionStart = min(baseOffset, extentOffset);
    final selectionEnd = max(baseOffset, extentOffset);
    final selectionRange = SpanRange(selectionStart, selectionEnd - 1);
    final textNode =
        widget.document.getNodeById(selection.extent.nodeId) as TextNode;
    final text = textNode.text;
    return text.getAttributionSpansInRange(
      attributionFilter: (Attribution attribution) =>
          attribution is LinkAttribution,
      range: selectionRange,
    );
  }

  void _onLinkPressed() {
    final selection = widget.composer.selection;
    if (selection == null) return;
    final baseOffset = (selection.base.nodePosition as TextPosition).offset;
    final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
    final selectionStart = min(baseOffset, extentOffset);
    final selectionEnd = max(baseOffset, extentOffset);
    final selectionRange = SpanRange(selectionStart, selectionEnd - 1);
    final textNode =
        widget.document.getNodeById(selection.extent.nodeId) as TextNode;
    final text = textNode.text;
    final overlappingLinkAttributions = _getSelectedLinkSpans();

    if (overlappingLinkAttributions.length >= 2) return;

    if (overlappingLinkAttributions.isNotEmpty) {
      final overlappingLinkSpan = overlappingLinkAttributions.first;
      final isLinkSelectionOnTrailingEdge =
          (overlappingLinkSpan.start >= selectionRange.start &&
                  overlappingLinkSpan.start <= selectionRange.end) ||
              (overlappingLinkSpan.end >= selectionRange.start &&
                  overlappingLinkSpan.end <= selectionRange.end);
      if (isLinkSelectionOnTrailingEdge) {
        text.removeAttribution(overlappingLinkSpan.attribution, selectionRange);
      } else {
        text.removeAttribution(
            overlappingLinkSpan.attribution, overlappingLinkSpan.range);
      }
    } else {
      setState(() {
        _showUrlField = true;
        _urlFocusNode.requestFocus();
      });
    }
  }

  void _applyLink() {
    final url = _urlController!.text.toPlainText(includePlaceholders: false);
    final selection = widget.composer.selection;
    if (selection == null) return;

    final baseOffset = (selection.base.nodePosition as TextPosition).offset;
    final extentOffset = (selection.extent.nodePosition as TextPosition).offset;
    final selectionStart = min(baseOffset, extentOffset);
    final selectionEnd = max(baseOffset, extentOffset);
    final selectionRange =
        TextRange(start: selectionStart, end: selectionEnd - 1);
    final textNode =
        widget.document.getNodeById(selection.extent.nodeId) as TextNode;
    final text = textNode.text;
    final trimmedRange = _trimTextRangeWhitespace(text, selectionRange);
    final linkAttribution = LinkAttribution.fromUri(Uri.parse(url));

    widget.editor.execute([
      AddTextAttributionsRequest(
        documentRange: DocumentRange(
          start: DocumentPosition(
              nodeId: textNode.id,
              nodePosition: TextNodePosition(offset: trimmedRange.start)),
          end: DocumentPosition(
              nodeId: textNode.id,
              nodePosition: TextNodePosition(offset: trimmedRange.end)),
        ),
        attributions: {linkAttribution},
      ),
    ]);

    _urlController!.clearTextAndSelection();
    setState(() {
      _showUrlField = false;
      _urlFocusNode.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild);
    });
    widget.onLinkApplied?.call(); // Call the callback if provided
  }

  SpanRange _trimTextRangeWhitespace(AttributedText text, TextRange range) {
    int startOffset = range.start;
    int endOffset = range.end;
    final plainText = text.toPlainText();
    while (startOffset < range.end && plainText[startOffset] == ' ')
      startOffset += 1;
    while (endOffset > startOffset && plainText[endOffset] == ' ')
      endOffset -= 1;
    return SpanRange(startOffset, endOffset + 1);
  }

  void _changeAlignment(TextAlign? newAlignment) {
    if (newAlignment == null) return;
    widget.editor.execute([
      ChangeParagraphAlignmentRequest(
          nodeId: widget.composer.selection!.extent.nodeId,
          alignment: newAlignment),
    ]);
  }

  String _getTextTypeName(_TextType textType) {
    // Assuming AppLocalizations is available in the context where this widget is used.
    // For a truly self-contained widget, consider passing these localized strings as parameters
    // or using a static localization lookup if appropriate for your app structure.
    final localizations = AppLocalizations.of(context)!;
    switch (textType) {
      case _TextType.header1:
        return localizations.labelHeader1;
      case _TextType.header2:
        return localizations.labelHeader2;
      case _TextType.header3:
        return localizations.labelHeader3;
      case _TextType.paragraph:
        return localizations.labelParagraph;
      case _TextType.blockquote:
        return localizations.labelBlockquote;
      case _TextType.orderedListItem:
        return localizations.labelOrderedListItem;
      case _TextType.unorderedListItem:
        return localizations.labelUnorderedListItem;
    }
  }

  void _onPerformAction(TextInputAction action) {
    if (action == TextInputAction.done) _applyLink();
  }

  void _onBlockTypeSelected(SuperEditorDemoTextItem? selectedItem) {
    if (selectedItem != null) {
      setState(() {
        _convertTextToNewType(
            _TextType.values.firstWhere((e) => e.name == selectedItem.id));
      });
    }
  }

  void _onAlignmentSelected(SuperEditorDemoIconItem? selectedItem) {
    if (selectedItem != null) {
      setState(() {
        _changeAlignment(
            TextAlign.values.firstWhere((e) => e.name == selectedItem.id));
      });
    }
  }

  Widget _buildActualToolbar() {
    // Wrap the toolbar content with a Material widget for consistent styling.
    return Material(
      shape: const StadiumBorder(),
      elevation: 5,
      clipBehavior: Clip.hardEdge,
      // Constrain the maximum width of the toolbar.
      // This allows the SingleChildScrollView to know its bounds.
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
        child: SizedBox(
          height: 40,
          // Enable horizontal scrolling for the toolbar items.
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black,
                  Colors.black,
                  Colors.transparent
                ],
                stops: [0.0, 0.05, 0.95, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Use a Row to layout the toolbar items horizontally.
              // mainAxisSize.min ensures the Row takes up only necessary space if content is smaller than max width.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isConvertibleNode()) ...[
                    Tooltip(
                        message:
                            AppLocalizations.of(context)!.labelTextBlockType,
                        child: _buildBlockTypeSelector()),
                    _buildVerticalDivider(),
                  ],
                  Center(
                      child: IconButton(
                          onPressed: _toggleBold,
                          icon: const Icon(Icons.format_bold),
                          splashRadius: 16,
                          tooltip: AppLocalizations.of(context)!.labelBold)),
                  Center(
                      child: IconButton(
                          onPressed: _toggleItalics,
                          icon: const Icon(Icons.format_italic),
                          splashRadius: 16,
                          tooltip: AppLocalizations.of(context)!.labelItalics)),
                  Center(
                      child: IconButton(
                          onPressed: _toggleStrikethrough,
                          icon: const Icon(Icons.strikethrough_s),
                          splashRadius: 16,
                          tooltip: AppLocalizations.of(context)!
                              .labelStrikethrough)),
                  Center(
                      child: IconButton(
                          onPressed: _toggleSuperscript,
                          icon: const Icon(Icons.superscript),
                          splashRadius: 16,
                          tooltip:
                              AppLocalizations.of(context)!.labelSuperscript)),
                  Center(
                      child: IconButton(
                          onPressed: _toggleSubscript,
                          icon: const Icon(Icons.subscript),
                          splashRadius: 16,
                          tooltip:
                              AppLocalizations.of(context)!.labelSubscript)),
                  Center(
                      child: IconButton(
                          onPressed: _areMultipleLinksSelected()
                              ? null
                              : _onLinkPressed,
                          icon: const Icon(Icons.link),
                          color: _isSingleLinkSelected()
                              ? const Color(0xFF007AFF)
                              : IconTheme.of(context).color,
                          splashRadius: 16,
                          tooltip: AppLocalizations.of(context)!.labelLink)),
                  if (_isTextAlignable())
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _buildVerticalDivider(),
                      Tooltip(
                          message:
                              AppLocalizations.of(context)!.labelTextAlignment,
                          child: _buildAlignmentSelector())
                    ]),
                  _buildVerticalDivider(),
                  Center(
                      child: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_vert),
                          splashRadius: 16,
                          tooltip:
                              AppLocalizations.of(context)!.labelMoreOptions)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlignmentSelector() {
    final alignment = _getCurrentTextAlignment();
    return SuperEditorDemoIconItemSelector(
      parentFocusNode: widget.editorFocusNode,
      boundaryKey: widget.editorViewportKey,
      value: SuperEditorDemoIconItem(
          id: alignment.name, icon: _buildTextAlignIcon(alignment)),
      items: [
        TextAlign.left,
        TextAlign.center,
        TextAlign.right,
        TextAlign.justify
      ]
          .map((alignment) => SuperEditorDemoIconItem(
              icon: _buildTextAlignIcon(alignment), id: alignment.name))
          .toList(),
      onSelected: _onAlignmentSelected,
    );
  }

  Widget _buildBlockTypeSelector() {
    final currentBlockType = _getCurrentTextType();
    return SuperEditorDemoTextItemSelector(
      parentFocusNode: widget.editorFocusNode,
      boundaryKey: widget.editorViewportKey,
      id: SuperEditorDemoTextItem(
          id: currentBlockType.name, label: _getTextTypeName(currentBlockType)),
      items: _TextType.values
          .map((blockType) => SuperEditorDemoTextItem(
              id: blockType.name, label: _getTextTypeName(blockType)))
          .toList(),
      onSelected: _onBlockTypeSelected,
    );
  }

  Widget _buildUrlField() {
    return Material(
      shape: const StadiumBorder(),
      elevation: 5,
      clipBehavior: Clip.hardEdge,
      child: Container(
        width: 400,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: SuperTextField(
              focusNode: _urlFocusNode,
              textController: _urlController,
              minLines: 1,
              maxLines: 1,
              inputSource: TextInputSource.ime,
              hintBehavior: HintBehavior.displayHintUntilTextEntered,
              hintBuilder: (context) => const Text("enter a url...",
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
              textStyleBuilder: (_) =>
                  const TextStyle(color: Colors.black, fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _urlFocusNode.unfocus();
                _showUrlField = false;
                _urlController!.clearTextAndSelection();
              });
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(width: 1, color: Colors.grey.shade300);
  }

  IconData _buildTextAlignIcon(TextAlign align) {
    switch (align) {
      case TextAlign.left:
      case TextAlign.start:
        return Icons.format_align_left;
      case TextAlign.center:
        return Icons.format_align_center;
      case TextAlign.right:
      case TextAlign.end:
        return Icons.format_align_right;
      case TextAlign.justify:
        return Icons.format_align_justify;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editor == null ||
        widget.composer == null ||
        widget.document == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActualToolbar(),
        if (_showUrlField) ...[
          const SizedBox(height: 8),
          _buildUrlField(),
        ],
      ],
    );
  }
}

enum _TextType {
  header1,
  header2,
  header3,
  paragraph,
  blockquote,
  orderedListItem,
  unorderedListItem,
}

/// Small toolbar that is intended to display over an image and
/// offer controls to expand or contract the size of the image.
///
/// [ImageFormatToolbar] expects to be displayed in a [Stack] where it
/// will position itself based on the given [anchor]. This can be
/// accomplished, for example, by adding [ImageFormatToolbar] to the
/// application [Overlay]. Any other [Stack] should work, too.
class ImageFormatToolbar extends StatefulWidget {
  const ImageFormatToolbar({
    Key? key,
    required this.anchor,
    required this.composer,
    required this.setWidth,
    required this.closeToolbar,
  }) : super(key: key);

  /// [ImageFormatToolbar] displays itself horizontally centered and
  /// slightly above the given [anchor] value.
  ///
  /// [anchor] is a [ValueNotifier] so that [ImageFormatToolbar] can
  /// reposition itself as the [Offset] value changes.
  final ValueNotifier<Offset?> anchor;

  /// The [composer] provides access to the user's current
  /// selection within the document, which dictates the
  /// content that is altered by the toolbar's options.
  final DocumentComposer composer;

  /// Callback that should update the width of the component with
  /// the given [nodeId] to match the given [width].
  final void Function(String nodeId, double? width) setWidth;

  /// Delegate that instructs the owner of this [ImageFormatToolbar]
  /// to close the toolbar.
  final VoidCallback closeToolbar;

  @override
  State<ImageFormatToolbar> createState() => _ImageFormatToolbarState();
}

class _ImageFormatToolbarState extends State<ImageFormatToolbar> {
  AppLocalizations get appLocalizations => AppLocalizations.of(context)!;
  void _makeImageConfined() {
    widget.setWidth(widget.composer.selection!.extent.nodeId, null);
  }

  void _makeImageFullBleed() {
    widget.setWidth(widget.composer.selection!.extent.nodeId, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    return _PositionedToolbar(
      anchor: widget.anchor,
      composer: widget.composer,
      child: ValueListenableBuilder<DocumentSelection?>(
        valueListenable: widget.composer.selectionNotifier,
        builder: (context, selection, child) {
          appLog.fine("Building image toolbar. Selection: $selection");
          if (selection == null) {
            return const SizedBox();
          }
          if (selection.extent.nodePosition
              is! UpstreamDownstreamNodePosition) {
            return const SizedBox();
          }
          return _buildToolbar();
        },
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      shape: const StadiumBorder(),
      elevation: 5,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: IconButton(
                  onPressed: _makeImageConfined,
                  icon: const Icon(Icons.photo_size_select_large),
                  splashRadius: 16,
                  tooltip: appLocalizations.labelLimitedWidth,
                ),
              ),
              Center(
                child: IconButton(
                  onPressed: _makeImageFullBleed,
                  icon: const Icon(Icons.photo_size_select_actual),
                  splashRadius: 16,
                  tooltip: appLocalizations.labelFullWidth,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionedToolbar extends StatelessWidget {
  const _PositionedToolbar({
    Key? key,
    required this.anchor,
    required this.composer,
    required this.child,
  }) : super(key: key);

  final ValueNotifier<Offset?> anchor;
  final DocumentComposer composer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: anchor,
      builder: (context, offset, _) {
        appLog.fine(
            "(Re)Building _PositionedToolbar widget due to anchor change");
        if (offset == null || composer.selection == null) {
          appLog.fine("Anchor is null. Building an empty box.");
          return const SizedBox();
        }
        appLog.fine("Anchor is non-null: $offset, child: $child");
        return SizedBox.expand(
          child: Stack(
            children: [
              Positioned(
                left: offset.dx,
                top: offset.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -1.4),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SingleLineAttributedTextEditingController
    extends AttributedTextEditingController {
  SingleLineAttributedTextEditingController(this.onSubmit);
  final VoidCallback onSubmit;

  @override
  void insertNewline() {
    onSubmit();
  }
}
