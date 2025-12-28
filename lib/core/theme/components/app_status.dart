import 'package:flutter/material.dart';
import 'package:dictation_app/core/theme/app_theme.dart';

/// Status indicator badge
class AppStatusBadge extends StatelessWidget {
  final AppStatusType type;
  final String label;
  final bool showIcon;

  const AppStatusBadge({
    super.key,
    required this.type,
    required this.label,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (type) {
      case AppStatusType.success:
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case AppStatusType.error:
        color = AppColors.error;
        icon = Icons.error_rounded;
        break;
      case AppStatusType.warning:
        color = AppColors.warning;
        icon = Icons.warning_rounded;
        break;
      case AppStatusType.info:
        color = AppColors.info;
        icon = Icons.info_rounded;
        break;
      case AppStatusType.neutral:
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

enum AppStatusType {
  success,
  error,
  warning,
  info,
  neutral,
}

/// Status banner for showing connection/health status
class AppStatusBanner extends StatelessWidget {
  final AppStatusType type;
  final String message;
  final bool isLoading;
  final VoidCallback? onAction;
  final String? actionLabel;

  const AppStatusBanner({
    super.key,
    required this.type,
    required this.message,
    this.isLoading = false,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (type) {
      case AppStatusType.success:
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case AppStatusType.error:
        color = AppColors.error;
        icon = Icons.error_rounded;
        break;
      case AppStatusType.warning:
        color = AppColors.warning;
        icon = Icons.warning_rounded;
        break;
      case AppStatusType.info:
        color = AppColors.info;
        icon = Icons.info_rounded;
        break;
      case AppStatusType.neutral:
        color = Colors.grey;
        icon = Icons.circle_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          if (onAction != null && actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Modern loading overlay
class AppLoadingOverlay extends StatelessWidget {
  final bool isVisible;
  final String? message;
  final Widget child;

  const AppLoadingOverlay({
    super.key,
    required this.isVisible,
    this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isVisible)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        message!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
