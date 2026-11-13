import 'package:flutter/material.dart';

/// Horizontally scrollable single-select chip row (e.g. Daily / Weekly /
/// Monthly). Generic over the option type [T].
class FilterChipsRow<T> extends StatelessWidget {
  const FilterChipsRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T option) labelOf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(labelOf(o)),
                selected: o == selected,
                onSelected: (_) => onSelected(o),
              ),
            ),
        ],
      ),
    );
  }
}
