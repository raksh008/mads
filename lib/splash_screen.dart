import 'package:flutter/material.dart';

import 'branding.dart';

/// First word of the user's full name, or null when no name is saved.
String? madsFirstName(String? fullName) {
  final trimmed = fullName?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).first;
}

/// The MADS logo on its own dark background, optionally followed by a
/// greeting. The logo image fades from navy to pure black at its edges,
/// so it sits on a black screen with no visible border.
class MadsSplash extends StatelessWidget {
  /// The user's first name. Null shows the logo only.
  final String? firstName;
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
          Align(
            alignment: const Alignment(0, 0.38),
            child: AnimatedSlide(
              offset: showGreeting ? Offset.zero : const Offset(0, 0.4),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: showGreeting ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: Text.rich(
                  TextSpan(
                    text: 'Hi',
                    children: [
                      if (firstName != null) ...[
                        const TextSpan(text: ', '),
                        TextSpan(
                          text: firstName,
                          style: const TextStyle(color: madsBlue),
                        ),
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: madsSoftWhite,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
