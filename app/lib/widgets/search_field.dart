import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search...',
    this.width = 280,
    this.initialValue = '',
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;
  final String hint;

  /// Fixed width, or null to fill the width it is given — which is what a
  /// stacked header on a phone asks for.
  final double? width;
  final String initialValue;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A null width fills whatever it is given, which is only meaningful inside a
    // bounded parent — a stacked header, never a Row.
    final field = TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                  child: const Icon(Icons.close, size: 15, color: AppColors.textMuted),
                ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
    return SizedBox(width: widget.width, height: 34, child: field);
  }
}

/// Sort selector shown next to the search box on content screens.
class SortDropdown extends StatelessWidget {
  const SortDropdown({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const options = <String, String>{
    'default': 'Default',
    'a-z': 'Name (A-Z)',
    'z-a': 'Name (Z-A)',
    'added': 'Recently added',
    'rating': 'Rating',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : 'default',
          dropdownColor: AppColors.panelAlt,
          iconEnabledColor: AppColors.textMuted,
          isDense: true,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}
