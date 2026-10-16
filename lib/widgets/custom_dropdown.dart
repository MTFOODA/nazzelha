import 'package:flutter/material.dart';
import '../theme/colors.dart';

class CustomDropdown<T> extends StatefulWidget {
  final T? value;
  final List<T> items;
  final List<String> itemLabels;
  final Function(T) onChanged;

  const CustomDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.itemLabels,
    required this.onChanged,
  });

  @override
  State<CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<CustomDropdown<T>> {
  late T? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.value;
  }

  @override
  void didUpdateWidget(CustomDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _selectedValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 1.5,
        ),
      ),
      child: DropdownButton<T>(
        value: _selectedValue,
        isExpanded: true,
        underline: const SizedBox(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        items: List.generate(
          widget.items.length,
          (index) => DropdownMenuItem<T>(
            value: widget.items[index],
            child: Text(
              widget.itemLabels[index],
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        onChanged: (newValue) {
          if (newValue != null) {
            setState(() {
              _selectedValue = newValue;
            });
            widget.onChanged(newValue);
          }
        },
      ),
    );
  }
}
