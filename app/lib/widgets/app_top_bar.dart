import 'package:flutter/material.dart';

import '../models/pen_link.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
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
  Size get preferredSize => const Size.fromHeight(PaperTokens.barHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?overflow,
        if (overflow != null && link != null)
          const SizedBox(width: PaperTokens.space8),
        if (link != null) StatusPill(link: link!, onTap: onStatusTap),
      ],
    );

    return Material(
      color: colors.canvas,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: PaperTokens.barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PaperTokens.space12,
            ),
            child: Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: leading ?? const SizedBox.shrink(),
                  ),
                ),
                Expanded(
                  flex: expandTitle ? 3 : 2,
                  child: expandTitle
                      ? title
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [Flexible(child: title)],
                        ),
                ),
                Flexible(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
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
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
