import 'package:flutter/material.dart';

import '../models/pen_link.dart';
import '../theme/app_colors.dart';
import 'status_indicators.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.leading,
    required this.title,
    this.link,
    this.onStatusTap,
    this.overflow,
    this.expandTitle = false,
  });

  final Widget? leading;
  final Widget title;
  final PenLink? link;
  final VoidCallback? onStatusTap;
  final Widget? overflow;
  final bool expandTitle;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?overflow,
        if (link != null) StatusPill(link: link!, onTap: onStatusTap),
      ],
    );

    return Material(
      color: colors.canvas,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(width: 48, child: leading),
                Expanded(child: expandTitle ? title : Center(child: title)),
                trailing,
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TopTitle extends StatelessWidget {
  const TopTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(letterSpacing: -0.4),
    );
  }
}
