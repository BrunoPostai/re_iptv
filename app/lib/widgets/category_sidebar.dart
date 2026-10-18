import 'package:flutter/material.dart';

import '../blocs/content_bloc.dart';
import '../core/theme/app_theme.dart';

/// Left-hand category list with counts and an optional "hidden" marker.
class CategorySidebar extends StatefulWidget {
  const CategorySidebar({
    super.key,
    required this.rows,
    required this.selectedId,
    required this.onSelected,
    this.isHidden,
    this.header,
  });

  final List<CategoryRow> rows;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final bool Function(String id)? isHidden;
  final Widget? header;

  @override
  State<CategorySidebar> createState() => _CategorySidebarState();
}

class _CategorySidebarState extends State<CategorySidebar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: widget.header,
            ),
          Expanded(
            child: Scrollbar(
              controller: _controller,
              child: ListView.builder(
                controller: _controller,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: widget.rows.length,
                itemBuilder: (context, index) {
                  final row = widget.rows[index];
                  return _CategoryRowTile(
                    row: row,
                    selected: row.id == widget.selectedId,
                    hidden: widget.isHidden?.call(row.id) ?? false,
                    onTap: () => widget.onSelected(row.id),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRowTile extends StatefulWidget {
  const _CategoryRowTile({
    required this.row,
    required this.selected,
    required this.hidden,
    required this.onTap,
  });

  final CategoryRow row;
  final bool selected;
  final bool hidden;
  final VoidCallback onTap;

  @override
  State<_CategoryRowTile> createState() => _CategoryRowTileState();
}

class _CategoryRowTileState extends State<_CategoryRowTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blue.withValues(alpha: 0.45)
                : (_hovered ? Colors.white.withValues(alpha: 0.06) : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: selected
                ? const Border(left: BorderSide(color: AppColors.gold, width: 3))
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.hidden)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.visibility_off_outlined, size: 13, color: AppColors.textMuted),
                ),
              if (widget.row.pseudo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'PIN',
                    style: TextStyle(color: AppColors.gold, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              Text(
                '${widget.row.count}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
