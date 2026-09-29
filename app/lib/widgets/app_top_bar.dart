import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.leading,
    required this.title,
    this.overflow,
    this.expandTitle = false,
    this.height = PaperTokens.barHeight,
  });

  final Widget? leading;
  final Widget title;
  final Widget? overflow;
  final bool expandTitle;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailing = Row(mainAxisSize: MainAxisSize.min, children: [?overflow]);

    return Material(
      color: colors.canvas,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PaperTokens.space12,
            ),
            child: expandTitle
                ? Row(
                    children: [
                      leading ?? const SizedBox.shrink(),
                      Expanded(child: title),
                      trailing,
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        children: [
                          leading ?? const SizedBox.shrink(),
                          const Spacer(),
                          trailing,
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PaperTokens.minTap + PaperTokens.space24,
                        ),
                        child: title,
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
