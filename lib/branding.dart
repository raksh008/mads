import 'package:flutter/material.dart';

const Color forestGreen = Color(0xFF147D64);
const Color cream = Color(0xFFF7F6EF);
const Color ink = Color(0xFF172B3A);
const Color coral = Color(0xFFD85E58);

final ValueNotifier<ThemeMode> ruvoThemeMode = ValueNotifier(ThemeMode.system);

class RuvoLogo extends StatelessWidget {
  final double fontSize;
  final bool showTagline;

  const RuvoLogo({super.key, this.fontSize = 25, this.showTagline = false});

  @override
  Widget build(BuildContext context) {
    final markSize = fontSize * 1.25;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            color: forestGreen,
            borderRadius: BorderRadius.circular(fontSize * 0.32),
          ),
          alignment: Alignment.center,
          child: Text(
            'R',
            style: TextStyle(
              color: cream,
              fontSize: fontSize * 0.82,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        SizedBox(width: fontSize * 0.32),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'RUVO',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: fontSize * 0.035,
                color: forestGreen,
                height: 1,
              ),
            ),
            if (showTagline) ...[
              SizedBox(height: fontSize * 0.16),
              const Text(
                'Your finance pal',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
