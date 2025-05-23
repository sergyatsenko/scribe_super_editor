# Paste Testing Guide for Scribe App

This file contains sample content to test the rich text and markdown paste functionality in your Scribe app.

## Testing Instructions

1. **Copy sections from this file** and paste them into your Scribe editor
2. **Copy rich content from web browsers** (like formatted text from Wikipedia or documentation sites)
3. **Copy content from other rich text editors** (like Google Docs, Notion, etc.)

## Sample Markdown Content for Testing

### Headers Test

Copy this section to test header parsing:

# This is H1 Header

## This is H2 Header

### This is H3 Header

### Formatting Test

Copy this section to test text formatting:

This is **bold text** and this is _italic text_.
You can also use **bold** and _italic_ formatting.
~~Strikethrough text~~ should also work.

### Lists Test

Copy these lists to test list parsing:

Unordered list:

- First item
- Second item
  - Nested item
  - Another nested item
- Third item

Ordered list:

1. First numbered item
2. Second numbered item
3. Third numbered item

### Code Block Test

Copy this section to test code block parsing:

Here's a simple code block:

```dart
void main() {
  print('Hello, World!');

  final editor = SuperEditor(
    plugins: [CustomPastePlugin()],
  );
}
```

```javascript
function greet(name) {
  return `Hello, ${name}!`;
}

console.log(greet("World"));
```

```python
def calculate_sum(a, b):
    """Calculate the sum of two numbers."""
    return a + b

result = calculate_sum(5, 3)
print(f"Result: {result}")
```

### Links and Quotes Test

Copy this section to test links and blockquotes:

> This is a blockquote
> It can span multiple lines
> And should be styled differently

Check out [Super Editor](https://github.com/superlistapp/super_editor) for more information.

### Mixed Content Test

Copy this entire section to test complex markdown:

# Mixed Content Example

Here's a paragraph with **bold**, _italic_, and `inline code`.

## Code Example

```typescript
interface User {
  id: number;
  name: string;
  email: string;
}

const users: User[] = [
  { id: 1, name: "John Doe", email: "john@example.com" },
  { id: 2, name: "Jane Smith", email: "jane@example.com" },
];
```

## List with formatting

1. **First item** with emphasis
2. _Second item_ in italics
3. Regular third item
   - Nested **bold** item
   - Nested _italic_ item

> **Note:** This blockquote contains formatting as well!

---

## HTML Content Testing

You can also test by copying rich HTML content from:

- **Wikipedia articles** (copy any formatted paragraph)
- **GitHub README files** (copy sections with headers, code, lists)
- **Google Docs** (create a document with various formatting and copy portions)
- **Notion pages** (copy blocks with different content types)
- **Medium articles** (copy formatted text sections)

## Expected Results

When you paste content into your Scribe editor, you should see:

✅ **Headers** converted to proper heading blocks
✅ **Bold, italic, underline** formatting preserved  
✅ **Code blocks** styled with monospace font and background
✅ **Lists** converted to proper list items
✅ **Blockquotes** styled with indentation and italic text
✅ **Links** preserved (if copying HTML content)
✅ **Plain text** gracefully handled when no formatting is detected

## Troubleshooting

If paste functionality isn't working:

1. **Check browser/app permissions** - some apps may restrict clipboard access
2. **Try different content types** - start with plain text, then try formatted content
3. **Check console output** - the plugin logs detailed information about paste operations
4. **Verify focus** - ensure the editor has focus before pasting

## Performance Testing

For performance testing, try pasting:

- Very long documents (1000+ lines)
- Documents with many code blocks
- Mixed content with heavy formatting
- Large HTML content from complex web pages

The paste plugin should handle all these scenarios gracefully with proper fallbacks.
