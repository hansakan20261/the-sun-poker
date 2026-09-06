import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/app_background.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  List<dynamic> _categories = [];
  List<dynamic> _items = [];
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getShopItems();
      final cats = data['categories'] as List? ?? [];
      final items = data['items'] as List? ?? [];
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _items = items;
      });
    } catch (_) {}
  }

  void _showItemPopup(dynamic item) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2A0A0A), Color(0xFF1A0505)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🔜', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                const Text(
                  'Coming Soon',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ฟีเจอร์นี้กำลังพัฒนา\nเร็วๆ นี้!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'ตกลง',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<dynamic> get _filteredItems {
    if (_categories.isEmpty) return [];
    final cat = _categories[_selectedTab];
    return _items.where((i) => i['category_slug'] == cat['slug']).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_categories.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }
    return AppBackground(
      child: Stack(
        children: [
          // Subtle red glow
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B0000).withOpacity(0.15),
                    Colors.transparent,
                  ],
                  radius: 0.9,
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [
                        Color(0xFFFFE082),
                        Color(0xFFFFD700),
                        Color(0xFFB8860B),
                      ],
                    ).createShader(b),
                    child: const Text(
                      'ร้านค้า',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 3,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 10,
                            offset: Offset(2, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // ── Tab bar ──
                _buildTabBar(),
                const SizedBox(height: 6),
                // ── Scrollable content with dark board frame ──
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                      decoration: SunTheme.cardDecoration(
                        radius: 16,
                        bgColor: const Color(0xFF0D0D0D),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Section title
                          if (_categories.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 8,
                              ),
                              child: Text(
                                (_categories[_selectedTab]['name'] as String)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withOpacity(0.55),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          // Grid (non-scrollable, wrapped in column)
                          _buildWrappedGrid(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0A0A), Color(0xFF1A0505), Color(0xFF2A0A0A)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5C2020), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_categories.length, (i) {
            final isActive = _selectedTab == i;
            final name = (_categories[i]['name'] as String).toUpperCase();
            return GestureDetector(
              onTap: () => setState(() => _selectedTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFCC2222),
                            Color(0xFF8B0000),
                            Color(0xFF5C0000),
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFFB22222).withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFFFD700)
                        : const Color(0xFF8B6914).withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildWrappedGrid() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 48,
                color: SunTheme.gold.withOpacity(0.15),
              ),
              const SizedBox(height: 8),
              Text(
                'ยังไม่มีสินค้า',
                style: TextStyle(
                  color: SunTheme.gold.withOpacity(0.25),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build rows of 3
    final List<Widget> rows = [];
    for (int i = 0; i < items.length; i += 3) {
      final rowItems = <Widget>[];
      for (int j = 0; j < 3; j++) {
        if (i + j < items.length) {
          rowItems.add(
            Expanded(
              child: AspectRatio(
                aspectRatio: 0.72,
                child: _ShopItemTile(
                  item: items[i + j],
                  onTap: () => _showItemPopup(items[i + j]),
                ),
              ),
            ),
          );
        } else {
          rowItems.add(const Expanded(child: SizedBox()));
        }
        if (j < 2) rowItems.add(const SizedBox(width: 10));
      }
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 3 < items.length ? 10 : 0),
          child: Row(children: rowItems),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _buildGrid() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: SunTheme.gold.withOpacity(0.15),
            ),
            const SizedBox(height: 8),
            Text(
              'ยังไม่มีสินค้า',
              style: TextStyle(
                color: SunTheme.gold.withOpacity(0.25),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      key: ValueKey('grid_$_selectedTab'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _ShopItemTile(item: items[i], onTap: () => _showItemPopup(items[i])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shop Item Tile — 3 per row, red bordered, image or icon
// ═══════════════════════════════════════════════════════════════
class _ShopItemTile extends StatefulWidget {
  final dynamic item;
  final VoidCallback onTap;
  const _ShopItemTile({required this.item, required this.onTap});
  @override
  State<_ShopItemTile> createState() => _ShopItemTileState();
}

class _ShopItemTileState extends State<_ShopItemTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.item['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final name = widget.item['name'] ?? '';
    final price = widget.item['price']?.toString() ?? '0';

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(_pressed ? 0.03 : -0.015),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF3D1414),
                  Color(0xFF2A0C0C),
                  Color(0xFF1A0606),
                  Color(0xFF120404),
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
              border: Border.all(
                color: const Color(0xFFAA2222).withOpacity(0.55),
                width: 1.5,
              ),
              boxShadow: [
                // Main drop shadow for 3D lift
                BoxShadow(
                  color: Colors.black.withOpacity(0.8),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                  spreadRadius: -1,
                ),
                // Subtle red underglow
                BoxShadow(
                  color: const Color(0xFF8B0000).withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
                // Top edge light reflection
                BoxShadow(
                  color: Colors.white.withOpacity(0.03),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                children: [
                  // Top bevel highlight for 3D depth
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Bottom darkening for depth
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Inner border highlight (left + top edges)
                  Positioned.fill(
                    child: Container(
                      margin: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(0.06),
                            width: 0.5,
                          ),
                          left: BorderSide(
                            color: Colors.white.withOpacity(0.04),
                            width: 0.5,
                          ),
                          right: BorderSide(
                            color: Colors.black.withOpacity(0.2),
                            width: 0.5,
                          ),
                          bottom: BorderSide(
                            color: Colors.black.withOpacity(0.3),
                            width: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                    child: Column(
                      children: [
                        // Image area
                        Expanded(
                          child: Center(
                            child: hasImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          _fallbackIcon(),
                                    ),
                                  )
                                : _fallbackIcon(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Name
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        // Price tag with 3D effect
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFDD1818),
                                Color(0xFFBB0000),
                                Color(0xFF880000),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border(
                              top: BorderSide(
                                color: Colors.white.withOpacity(0.15),
                                width: 0.5,
                              ),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF880000).withOpacity(0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '$price C',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Icon(
      Icons.image_outlined,
      size: 36,
      color: const Color(0xFFFFD700).withOpacity(0.25),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Item Popup Dialog — center of screen
// ═══════════════════════════════════════════════════════════════
class _ItemPopupDialog extends StatelessWidget {
  final dynamic item;
  const _ItemPopupDialog({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item['image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final name = item['name'] ?? '';
    final price = item['price']?.toString() ?? '0';

    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: SunTheme.cardDecoration(
          radius: 24,
          bgColor: const Color(0xFF1A0606),
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: Icon(
                        Icons.close,
                        color: const Color(0xFFDAA520).withOpacity(0.5),
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // Image / Icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFF3A1212), Color(0xFF1A0606)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withOpacity(0.25),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withOpacity(0.12),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.diamond_rounded,
                            color: Color(0xFFFFD700),
                            size: 44,
                          ),
                        )
                      : const Icon(
                          Icons.diamond_rounded,
                          color: Color(0xFFFFD700),
                          size: 44,
                          shadows: [
                            Shadow(color: Color(0x88FFD700), blurRadius: 16),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 6),
                // Price
                Text(
                  '\$ $price',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                // Info
                Text(
                  'If you wish to make a payment\nplease contact the Admin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFDAA520).withOpacity(0.35),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // QR Code
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.qr_code_2,
                      size: 110,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // LINE button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06C755),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 6,
                      shadowColor: const Color(0xFF06C755).withOpacity(0.4),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/line_icon.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.chat_bubble,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'LINE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
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
    );
  }
}
