import 'package:flutter/material.dart';
import 'package:scribe/features/editor/application/editor_controller.dart';

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({required this.controller, super.key});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (controller.isDistractionFree) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              _ToolbarButton(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                onPressed: controller.formatBold,
              ),
              _ToolbarButton(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                onPressed: controller.formatItalic,
              ),
              _ToolbarButton(
                icon: Icons.format_underlined,
                tooltip: 'Underline',
                onPressed: controller.formatUnderline,
              ),
              const SizedBox(width: 8),
              _ToolbarButton(
                icon: Icons.title,
                tooltip: 'Header 1',
                onPressed: controller.formatHeader1,
              ),
              _ToolbarButton(
                icon: Icons.text_fields,
                tooltip: 'Header 2',
                onPressed: controller.formatHeader2,
              ),
              const SizedBox(width: 8),
              _ToolbarButton(
                icon: Icons.link,
                tooltip: 'Insert Link',
                onPressed: () => _showLinkDialog(context),
              ),
              const Spacer(),
              _ToolbarButton(
                icon: controller.isDistractionFree
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
                tooltip: 'Toggle Distraction-Free Mode',
                onPressed: controller.toggleDistractionFree,
              ),
              const SizedBox(width: 16),
            ],
          ),
        );
      },
    );
  }

  void _showLinkDialog(BuildContext context) {
    final urlController = TextEditingController();
    final textController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insert Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Link Text',
                hintText: 'Enter link text',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (urlController.text.isNotEmpty &&
                  textController.text.isNotEmpty) {
                controller.insertLink(
                  urlController.text,
                  textController.text,
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Insert'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
