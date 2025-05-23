import 'package:html/dom.dart' as html;
import 'package:super_editor/super_editor.dart';

class HtmlToDocumentConverter {
  List<DocumentNode> convert(html.Document document) {
    final nodes = <DocumentNode>[];

    final body = document.body;
    if (body != null) {
      if (body.children.isEmpty) {
        // If there are no child elements but there is text content,
        // process the body itself as a paragraph
        final bodyText = body.text;
        if (bodyText.isNotEmpty) {
          final convertedNodes = _convertElement(body);
          nodes.addAll(convertedNodes);
        }
      } else {
        // Process each child element
        for (final element in body.children) {
          final convertedNodes = _convertElement(element);
          nodes.addAll(convertedNodes);
        }
      }
    }

    // If no nodes were created, create a default paragraph
    if (nodes.isEmpty) {
      nodes.add(
        ParagraphNode(
          id: Editor.createNodeId(),
          text: AttributedText(document.body?.text ?? document.outerHtml),
        ),
      );
    }

    return nodes;
  }

  List<DocumentNode> _convertElement(html.Element element) {
    // Process elements based on their type
    final tagName = element.localName?.toLowerCase();
    
    // Handle special case for div and span that might contain rich text
    // but shouldn't be treated as paragraphs directly if they contain block elements
    if (tagName == 'div' || tagName == 'span') {
      // Check if this div/span contains any block elements
      final hasBlockChildren = element.children.any((child) => _isBlockElement(child.localName));
      
      if (hasBlockChildren) {
        // Process each child element separately to preserve structure
        final nodes = <DocumentNode>[];
        for (final child in element.children) {
          nodes.addAll(_convertElement(child));
        }
        return nodes;
      } else {
        // No block children, treat as a paragraph with potential styling
        return [_convertParagraph(element)];
      }
    }
    
    // Handle standard HTML elements
    switch (tagName) {
      case 'p':
        return [_convertParagraph(element)];
      case 'h1':
        return [_convertHeading(element, 1)];
      case 'h2':
        return [_convertHeading(element, 2)];
      case 'h3':
        return [_convertHeading(element, 3)];
      case 'h4':
        return [_convertHeading(element, 4)];
      case 'h5':
        return [_convertHeading(element, 5)];
      case 'h6':
        return [_convertHeading(element, 6)];
      case 'blockquote':
        return [_convertBlockquote(element)];
      case 'ul':
        return _convertUnorderedList(element);
      case 'ol':
        return _convertOrderedList(element);
      case 'br':
        // Handle single line breaks
        return [ParagraphNode(id: Editor.createNodeId(), text: AttributedText(''))];
      default:
        // For unknown elements, check if they contain block elements
        if (element.children.isNotEmpty && 
            element.children.any((child) => _isBlockElement(child.localName))) {
          // Process children separately
          final nodes = <DocumentNode>[];
          for (final child in element.children) {
            nodes.addAll(_convertElement(child));
          }
          return nodes;
        } else {
          // Otherwise convert as paragraph
          return [_convertParagraph(element)];
        }
    }
  }

  ParagraphNode _convertParagraph(html.Element element) {
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: _extractAttributedText(element),
    );
  }

  ParagraphNode _convertHeading(html.Element element, int level) {
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: _extractAttributedText(element),
      metadata: {'blockType': _getHeaderAttribution(level)},
    );
  }

  ParagraphNode _convertBlockquote(html.Element element) {
    return ParagraphNode(
      id: Editor.createNodeId(),
      text: _extractAttributedText(element),
      metadata: {'blockType': blockquoteAttribution},
    );
  }

  List<DocumentNode> _convertUnorderedList(html.Element element) {
    final nodes = <DocumentNode>[];

    for (final listItem in element.querySelectorAll('li')) {
      nodes.add(
        ListItemNode(
          id: Editor.createNodeId(),
          itemType: ListItemType.unordered,
          text: _extractAttributedText(listItem),
        ),
      );
    }

    return nodes;
  }

  List<DocumentNode> _convertOrderedList(html.Element element) {
    final nodes = <DocumentNode>[];

    for (final listItem in element.querySelectorAll('li')) {
      nodes.add(
        ListItemNode(
          id: Editor.createNodeId(),
          itemType: ListItemType.ordered,
          text: _extractAttributedText(listItem),
        ),
      );
    }

    return nodes;
  }

  AttributedText _extractAttributedText(html.Element element) {
    final textBuffer = StringBuffer();
    final attributions = <SpanMarker>[];
    
    // If there's an existing style on the element itself, capture it
    final selfAttribution = _getAttributionForElement(element);
    final startOffset = 0;
    
    _processNode(element, textBuffer, attributions, 0);
    
    // If the element has a style and there's content, apply the style
    if (selfAttribution != null && textBuffer.length > 0) {
      attributions.add(
        SpanMarker(
          attribution: selfAttribution,
          offset: startOffset,
          markerType: SpanMarkerType.start,
        ),
      );
      attributions.add(
        SpanMarker(
          attribution: selfAttribution,
          offset: textBuffer.length - 1,
          markerType: SpanMarkerType.end,
        ),
      );
    }

    final result = AttributedText(
      textBuffer.toString(),
      AttributedSpans(attributions: attributions),
    );
    
    return result;
  }

  int _processNode(
    html.Node node,
    StringBuffer textBuffer,
    List<SpanMarker> attributions,
    int currentOffset,
  ) {
    if (node is html.Text) {
      final text = node.text;
      if (text.isNotEmpty) {
        textBuffer.write(text);
        return currentOffset + text.length;
      }
      return currentOffset;
    }

    if (node is html.Element) {
      final startOffset = currentOffset;
      var endOffset = currentOffset;
      
      // Handle special cases for line breaks
      if (node.localName == 'br') {
        textBuffer.write('\n');
        return currentOffset + 1;
      }
      
      // Process all child nodes
      for (final child in node.nodes) {
        endOffset = _processNode(child, textBuffer, attributions, endOffset);
      }
      
      // If no content was added but this is a block element, add a newline
      if (endOffset == startOffset && _isBlockElement(node.localName)) {
        textBuffer.write('\n');
        endOffset++;
      }
      
      // Apply styling based on element type
      final attribution = _getAttributionForElement(node);
      if (attribution != null && endOffset > startOffset) {
        attributions.addAll([
          SpanMarker(
            attribution: attribution,
            offset: startOffset,
            markerType: SpanMarkerType.start,
          ),
          SpanMarker(
            attribution: attribution,
            offset: endOffset - 1,
            markerType: SpanMarkerType.end,
          ),
        ]);
      }
      
      // Add newlines after block elements
      if (_isBlockElement(node.localName) && !textBuffer.toString().endsWith('\n')) {
        textBuffer.write('\n');
        endOffset++;
      }

      return endOffset;
    }

    return currentOffset;
  }

  bool _isBlockElement(String? tagName) {
    if (tagName == null) return false;
    
    const blockElements = [
      'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'ul', 'ol', 'li', 'blockquote', 'pre', 'hr',
      'table', 'tr', 'th', 'td'
    ];
    
    return blockElements.contains(tagName.toLowerCase());
  }
  
  Attribution? _getAttributionForElement(html.Element element) {
    final tagName = element.localName?.toLowerCase();
    final style = element.attributes['style'] ?? '';
    
    // More comprehensive check for inline styles
    // Bold detection
    if (style.contains('font-weight:') && 
        (style.contains('bold') || style.contains('700') || style.contains('800') || style.contains('900'))) {
      return boldAttribution;
    }
    
    // Italic detection
    if (style.contains('font-style:') && style.contains('italic')) {
      return italicsAttribution;
    }
    
    // Underline detection - more comprehensive pattern matching
    if (style.contains('text-decoration') && 
        (style.contains('underline') || style.contains('line-through'))) {
      return underlineAttribution;
    }
    
    // Check for tag-based attributions
    switch (tagName) {
      case 'b':
      case 'strong':
        return boldAttribution;
      case 'i':
      case 'em':
        return italicsAttribution;
      case 'u':
      case 'ins':
        return underlineAttribution;
      case 'strike':
      case 'del':
      case 's':
        // If super_editor supports strikethrough, we would add it here
        return null;
      case 'a':
        final href = element.attributes['href'];
        if (href != null) {
          return LinkAttribution(href);
        }
        return null;
      case 'span':
        // For spans, more comprehensive class checking
        final className = element.className.toLowerCase();
        
        // Check various CSS class patterns used by rich text editors
        if (className.contains('bold') || 
            className.contains('font-weight-bold') || 
            className.contains('fw-bold')) {
          return boldAttribution;
        } 
        
        if (className.contains('italic') || 
            className.contains('font-style-italic') || 
            className.contains('font-italic')) {
          return italicsAttribution;
        } 
        
        if (className.contains('underline') || 
            className.contains('text-decoration-underline')) {
          return underlineAttribution;
        }
        
        // Also check data attributes that might indicate formatting
        final dataStyle = element.attributes['data-style'] ?? '';
        if (dataStyle.contains('bold')) return boldAttribution;
        if (dataStyle.contains('italic')) return italicsAttribution;
        if (dataStyle.contains('underline')) return underlineAttribution;
        
        return null;
      default:
        return null;
    }
  }

  Attribution _getHeaderAttribution(int level) {
    switch (level) {
      case 1:
        return header1Attribution;
      case 2:
        return header2Attribution;
      case 3:
        return header3Attribution;
      case 4:
        return header4Attribution;
      case 5:
        return header5Attribution;
      case 6:
        return header6Attribution;
      default:
        return header1Attribution;
    }
  }
}
