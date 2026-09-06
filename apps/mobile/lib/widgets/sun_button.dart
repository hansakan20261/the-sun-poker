import 'package:flutter/material.dart';

/// SunButton — ปุ่มมีมิติ 3D + gradient ไล่สี + shimmer กระพริบ
/// ใช้แทนปุ่มทั่วไปในทุกหน้า
class SunButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final List<Color> colors; // gradient colors (2-3 สี)
  final double width;
  final double height;
  final double fontSize;
  final IconData? icon;
  final bool shimmer; // เปิด/ปิด shimmer animation
  final double borderRadius;

  const SunButton({
    super.key,
    required this.label,
    this.onTap,
    this.colors = const [Color(0xFFCC2222), Color(0xFF8B0000)],
    this.width = double.infinity,
    this.height = 48,
    this.fontSize = 14,
    this.icon,
    this.shimmer = true,
    this.borderRadius = 12,
  });

  // ── Preset factories ──
  factory SunButton.red({
    required String label,
    required VoidCallback? onTap,
    double? width,
    double? height,
    IconData? icon,
  }) => SunButton(
    label: label,
    onTap: onTap,
    width: width ?? double.infinity,
    height: height ?? 48,
    icon: icon,
    colors: const [Color(0xFFE03030), Color(0xFFCC2222), Color(0xFF8B0000)],
  );

  factory SunButton.gold({
    required String label,
    required VoidCallback? onTap,
    double? width,
    double? height,
    IconData? icon,
  }) => SunButton(
    label: label,
    onTap: onTap,
    width: width ?? double.infinity,
    height: height ?? 48,
    icon: icon,
    colors: const [Color(0xFFFFE082), Color(0xFFFFD700), Color(0xFFB8860B)],
  );

  factory SunButton.green({
    required String label,
    required VoidCallback? onTap,
    double? width,
    double? height,
    IconData? icon,
    double? borderRadius,
  }) => SunButton(
    label: label,
    onTap: onTap,
    width: width ?? double.infinity,
    height: height ?? 48,
    icon: icon,
    borderRadius: borderRadius ?? 12,
    colors: const [Color(0xFF4CAF50), Color(0xFF2E8B57), Color(0xFF1B5E20)],
  );

  factory SunButton.orange({
    required String label,
    required VoidCallback? onTap,
    double? width,
    double? height,
    IconData? icon,
  }) => SunButton(
    label: label,
    onTap: onTap,
    width: width ?? double.infinity,
    height: height ?? 48,
    icon: icon,
    colors: const [Color(0xFFFF8C00), Color(0xFFE65100), Color(0xFFBF360C)],
  );

  @override
  State<SunButton> createState() => _SunButtonState();
}

class _SunButtonState extends State<SunButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  late Animation<double> _shimmerAnim;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _shimmerAnim = Tween<double>(
      begin: -1.5,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));
    if (widget.shimmer) {
      _shimmerCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final c0 = colors[0];
    final c1 = colors.length > 1 ? colors[1] : colors[0];
    final c2 = colors.length > 2 ? colors[2] : c1;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _shimmerAnim,
            builder: (_, __) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c0, c1, c2],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c1.withOpacity(_pressed ? 0.2 : 0.5),
                      blurRadius: _pressed ? 4 : 10,
                      offset: Offset(0, _pressed ? 1 : 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Top highlight bevel
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: widget.height * 0.45,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withOpacity(0.18),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Shimmer sweep
                      if (widget.shimmer)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(
                              _shimmerAnim.value * widget.width.clamp(100, 400),
                              0,
                            ),
                            child: Container(
                              width: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0),
                                    Colors.white.withOpacity(0.18),
                                    Colors.white.withOpacity(0),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Content
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(
                                    widget.icon,
                                    color: Colors.white,
                                    size: widget.fontSize + 4,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: widget.fontSize,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
