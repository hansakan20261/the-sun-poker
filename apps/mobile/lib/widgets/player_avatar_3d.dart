import 'package:flutter/material.dart';

/// A 3D-styled player avatar with depth, shadow, and ring effects.
/// Used for all player seats around the poker table.
class PlayerAvatar3D extends StatelessWidget {
  final double size;
  final Color borderColor;
  final Widget? overlay; // countdown, checkmark, etc.
  final String? imageAsset;
  final ImageProvider? imageProvider; // custom image (e.g. from profile)
  final bool showShadow;

  const PlayerAvatar3D({
    super.key,
    this.size = 52,
    this.borderColor = const Color(0xFFDAA520),
    this.overlay,
    this.imageAsset = 'assets/logo.png',
    this.imageProvider,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 3D Shadow (below and behind)
          if (showShadow)
            Positioned(
              bottom: 0,
              child: Container(
                width: size * 0.8,
                height: size * 0.3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

          // Outer ring (3D metallic border)
          Container(
            width: size + 6,
            height: size + 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  borderColor.withOpacity(0.9),
                  borderColor,
                  borderColor.withOpacity(0.6),
                  borderColor.withOpacity(0.3),
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: borderColor.withOpacity(0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),

          // Inner avatar image
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: imageProvider != null
                  ? DecorationImage(image: imageProvider!, fit: BoxFit.cover)
                  : (imageAsset != null
                        ? DecorationImage(
                            image: AssetImage(imageAsset!),
                            fit: BoxFit.cover,
                          )
                        : null),
              color: imageProvider == null && imageAsset == null
                  ? Colors.grey.shade800
                  : null,
            ),
          ),

          // 3D highlight (top-left shine)
          Positioned(
            top: 4,
            left: size * 0.2,
            child: Container(
              width: size * 0.35,
              height: size * 0.2,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.25), Colors.transparent],
                ),
              ),
            ),
          ),

          // Overlay (countdown, checkmark, etc.)
          if (overlay != null)
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: ClipOval(child: overlay!),
            ),
        ],
      ),
    );
  }
}
