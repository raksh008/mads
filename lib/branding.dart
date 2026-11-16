import 'package:flutter/material.dart';

// Colours sampled from assets/mads-logo.png.
const String madsLogoAsset = 'assets/mads-logo.png';
const Color madsLogoEdge = Color(0xFF000000); // logo background at its edges
const Color madsNavy = Color(0xFF021423); // logo background at its centre
const Color madsSoftWhite = Color(0xFFF7F7F8); // "mads" lettering
const Color madsBlue = Color(0xFF2FAAFF); // the stroke on the "d" (accent)

// App palette built from the logo.
const Color madsBackground = Color(0xFF020D18); // navy-black screens
const Color madsSurface = Color(0xFF0A1B2C); // cards, sheets, nav bar
const Color madsSurfaceHigh = Color(0xFF12273D); // inputs, tinted panels
const Color madsOutline = Color(0xFF233A52);
const Color madsMutedText = Color(0xFFA3B1C2); // secondary text
const Color madsFaintText = Color(0xFF6E8096); // hints, disabled
const Color madsDanger = Color(0xFFFF7A70); // over budget, log out
const Color madsWarning = Color(0xFFFFB454); // offline / not synced

// The app always uses the dark logo theme. This notifier still carries the
// user's saved preference so the profile setting keeps saving.
final ValueNotifier<ThemeMode> madsThemeMode = ValueNotifier(ThemeMode.system);

/// The logo wordmark: the centre band of the logo image, as a rounded badge.
class MadsLogo extends StatelessWidget {
  final double fontSize;
  final bool showTagline;

  const MadsLogo({super.key, this.fontSize = 25, this.showTagline = false});

  @override
  Widget build(BuildContext context) {
    final height = fontSize * 1.7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(fontSize * 0.4),
          child: Image.asset(
            madsLogoAsset,
            height: height,
            width: height / 0.3,
            fit: BoxFit.cover,
            semanticLabel: 'MADS',
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: fontSize * 0.3),
          const Text(
            'Your finance pal',
            style: TextStyle(color: madsMutedText, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
