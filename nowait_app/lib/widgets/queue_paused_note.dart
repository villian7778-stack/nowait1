import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// "Queue is paused by the owner." line for shop cards and the shop page.
/// [fit] shrinks the text to a single line for fixed-height cards.
class QueuePausedNote extends StatelessWidget {
  final double fontSize;
  final bool fit;

  const QueuePausedNote({super.key, this.fontSize = 11, this.fit = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      LocaleService.instance.tr('queuePausedByOwner'),
      style: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.w600, color: AppColors.error),
      maxLines: fit ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.pause_circle_outline_rounded, size: fontSize + 3, color: AppColors.error),
        const SizedBox(width: 4),
        fit ? text : Flexible(child: text),
      ],
    );
    return fit
        ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: row)
        : row;
  }
}
