import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app_theme.dart';

/// Colours carry the same meaning as on the Trading dashboard.
class HubColors {
  static const Color wait = AppColors.stockTeal;
  static const Color holding = Colors.deepPurple;
  static const Color palai = AppColors.primaryGreen;
  static const Color owes = AppColors.error;
  static const Color farmOwes = AppColors.success;
  static const Color estimate = AppColors.warning;
  static const Color customers = Colors.indigo;
}

final NumberFormat _inr =
NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String hubMoney(double value) => _inr.format(value.abs().round());

String hubInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

/// White card with a clipped ripple, same as the dashboard's cards.
class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppTheme.card(radius: radius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class HubIconBox extends StatelessWidget {
  const HubIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class HubPill extends StatelessWidget {
  const HubPill(this.text, this.color, {super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class HubAvatar extends StatelessWidget {
  const HubAvatar({super.key, required this.name, this.size = 42});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.lightGreen,
        shape: BoxShape.circle,
      ),
      child: Text(
        hubInitials(name),
        style: AppTheme.heading(size: size * 0.36, color: AppColors.darkGreen),
      ),
    );
  }
}

class HubHeaderButton extends StatelessWidget {
  const HubHeaderButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HubCard(
        radius: 14,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 22, color: AppColors.textDark),
        ),
      ),
    );
  }
}

/// Back button + title (+ optional subtitle), used on every hub screen.
class HubTopBar extends StatelessWidget {
  const HubTopBar({super.key, required this.title, this.subtitle = '', this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          HubHeaderButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 19)),
                if (subtitle.trim().isNotEmpty)
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(size: 11.5)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Net figure with its meaning in words, never a bare minus sign.
class HubNetText extends StatelessWidget {
  const HubNetText({super.key, required this.net, this.big = false});

  final double net;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final settled = net.abs() < 0.5;
    final color = settled
        ? AppColors.textGrey
        : net > 0
        ? HubColors.owes
        : HubColors.farmOwes;
    final label = settled
        ? 'Settled'
        : net > 0
        ? 'Customer owes'
        : 'Farm owes customer';

    return Column(
      crossAxisAlignment: big ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!settled)
          Text(hubMoney(net),
              maxLines: 1, style: AppTheme.heading(size: big ? 30 : 15, color: color)),
        Text(
          label,
          maxLines: 1,
          style: AppTheme.body(
            size: big ? 12 : 9.5,
            color: color,
            weight: settled ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Small label over a bold value, used in summary cards.
class HubFact extends StatelessWidget {
  const HubFact(this.label, this.value, {super.key, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.body(size: 10.5)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading(size: 13.5, color: color ?? AppColors.textDark),
          ),
        ],
      ),
    );
  }
}

/// Section heading with an optional count.
class HubSection extends StatelessWidget {
  const HubSection(this.title, {super.key, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Text(title, style: AppTheme.heading(size: 15)),
          if (count != null) ...[
            const SizedBox(width: 8),
            HubPill('$count', AppColors.textGrey),
          ],
        ],
      ),
    );
  }
}

/// Grey placeholder block for loading states.
class HubBone extends StatelessWidget {
  const HubBone({super.key, required this.height, this.width, this.radius = 16});

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class HubMessage extends StatelessWidget {
  const HubMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          HubIconBox(icon: icon, color: AppColors.textGrey, size: 52),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppTheme.heading(size: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTheme.body(size: 12)),
          ],
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}

/// Loads one customer's data and shows loading / error / not-found states.
class HubProfileLoader<T> extends StatelessWidget {
  const HubProfileLoader({
    super.key,
    required this.stream,
    required this.builder,
    required this.isMissing,
  });

  final Stream<T> stream;
  final bool Function(T data) isMissing;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return const HubMessage(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load",
            subtitle: 'Check your connection and open this screen again.',
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryGreen),
          );
        }
        if (isMissing(snap.data as T)) {
          return const HubMessage(
            icon: Icons.person_off_outlined,
            title: 'Customer not found',
            subtitle: 'This customer may have been deleted.',
          );
        }
        return builder(snap.data as T);
      },
    );
  }
}