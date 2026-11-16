import 'package:flutter/material.dart';

import 'branding.dart';

/// First word of the user's full name, or null when no name is saved.
String? madsFirstName(String? fullName) {
  final trimmed = fullName?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// The MADS logo with the tagline "Your finance pal", on the logo's own dark
/// background. The logo image fades from navy to pure black at its edges,
/// so it sits on a black screen with no visible border.
class MadsSplash extends StatelessWidget {
  /// Not shown. Kept so existing callers still compile.
  final String? firstName;

  /// Not used. Kept so existing callers still compile.
  final bool showGreeting;

  const MadsSplash({super.key, this.firstName, this.showGreeting = false});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 440.0);
    return Scaffold(
      backgroundColor: madsLogoEdge,
      body: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            madsLogoAsset,
            width: width,
            fit: BoxFit.contain,
            semanticLabel: 'MADS',
          ),
          // Sits just below the "mads" wordmark in the middle of the image.
          Padding(
            padding: EdgeInsets.only(top: width * 0.42),
            child: const Text(
              'Your finance pal',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: madsMutedText,
                fontSize: 16,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
