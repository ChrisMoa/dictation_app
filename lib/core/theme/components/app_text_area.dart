import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';

/// Modern text area for dictation text display
class AppTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final bool readOnly;
  final int? maxLines;
  final bool expands;
  final bool isActive;
  final Widget? suffix;
  final FocusNode? focusNode;

  const AppTextArea({
    super.key,
    required this.controller,
    this.hintText,
    this.readOnly = false,
    this.maxLines,
    this.expands = true,
    this.isActive = false,
    this.suffix,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark 
          ? AppColors.surfaceContainerHighDark 
          : AppColors.surfaceContainerHighLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isActive 
            ? theme.colorScheme.primary 
            : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ] : null,
      ),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: readOnly,
              maxLines: maxLines,
              expands: expands,
              textAlignVertical: TextAlignVertical.top,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.all(AppSpacing.md),
                filled: false,
              ),
            ),
          ),
          if (suffix != null) ...[
            const Divider(height: 1),
            suffix!,
          ],
        ],
      ),
    );
  }
}

/// Action bar for text area with common actions
class TextAreaActions extends StatelessWidget {
  final VoidCallback? onCopy;
  final VoidCallback? onClear;
  final VoidCallback? onSpellCheck;
  final bool isSpellChecking;
  final int characterCount;

  const TextAreaActions({
    super.key,
    this.onCopy,
    this.onClear,
    this.onSpellCheck,
    this.isSpellChecking = false,
    this.characterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '$characterCount Zeichen',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          if (onSpellCheck != null)
            _ActionButton(
              icon: isSpellChecking 
                ? Icons.hourglass_top 
                : Icons.spellcheck_rounded,
              label: 'Prüfen',
              onTap: isSpellChecking ? null : onSpellCheck,
            ),
          if (onCopy != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _ActionButton(
              icon: Icons.copy_rounded,
              label: 'Kopieren',
              onTap: onCopy,
            ),
          ],
          if (onClear != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Löschen',
              onTap: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: onTap == null 
                  ? (isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight)
                  : theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: onTap == null 
                    ? (isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight)
                    : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
