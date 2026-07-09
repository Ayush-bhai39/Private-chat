import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';

class GradientPicker extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onSelected;

  const GradientPicker({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: AppTheme.storyGradients.length,
        itemBuilder: (context, index) {
          final gradient = AppTheme.storyGradients[index];
          final isSelected = index == selectedIndex;

          return GestureDetector(
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
