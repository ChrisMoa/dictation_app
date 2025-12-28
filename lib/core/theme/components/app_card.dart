import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';

/// A modern card component with consistent styling
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool highlighted;
  final Color? backgroundColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.highlighted = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final bgColor = backgroundColor ?? 
      (highlighted 
        ? theme.colorScheme.primary.withValues(alpha: 0.05)
        : theme.cardTheme.color);
    
    final borderColor = highlighted
      ? theme.colorScheme.primary.withValues(alpha: 0.3)
      : (isDark ? AppColors.borderDark : AppColors.borderLight);

    Widget cardContent = Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      cardContent = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: cardContent,
        ),
      );
    }

    if (margin != null) {
      cardContent = Padding(padding: margin!, child: cardContent);
    }

    return cardContent;
  }
}

/// A section card with header and optional actions
class AppSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? margin;

  const AppSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.actions,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AppCard(
      margin: margin,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions != null) ...actions!,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}
