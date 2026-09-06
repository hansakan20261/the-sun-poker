import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/profile_provider.dart';
import '../utils/number_formatter.dart';
import '../widgets/app_background.dart';
import 'settings_screen.dart';
import '../widgets/transaction_history_popup.dart';
import '../widgets/poker_chip_icon.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    ProfileProvider.instance.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    ProfileProvider.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted)
      setState(() {
        _profile = ProfileProvider.instance.profile;
      });
  }

  Future<void> _load() async {
    await ProfileProvider.instance.load();
    if (!mounted) return;
    setState(() {
      _profile = ProfileProvider.instance.profile;
      _loading = false;
    });
  }

  void _showEditProfile() {
    final nameCtrl = TextEditingController(
      text: _profile?['display_name'] ?? _profile?['username'] ?? '',
    );
    final bioCtrl = TextEditingController(text: _profile?['bio'] ?? '');
    File? selectedImage;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0606),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'แก้ไขโปรไฟล์',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Avatar picker
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 512,
                    maxHeight: 512,
                    imageQuality: 80,
                  );
                  if (picked != null) {
                    setModalState(() => selectedImage = File(picked.path));
                  }
                },
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFD700),
                          width: 2.5,
                        ),
                        image: selectedImage != null
                            ? DecorationImage(
                                image: FileImage(selectedImage!),
                                fit: BoxFit.cover,
                              )
                            : (_profile?['avatar_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                        _profile!['avatar_url'],
                                      ),
                                      fit: BoxFit.cover,
                                    )
                                  : null),
                        color: const Color(0xFF2A0A0A),
                      ),
                      child:
                          selectedImage == null &&
                              _profile?['avatar_url'] == null
                          ? Center(
                              child: Text(
                                (nameCtrl.text.isNotEmpty
                                        ? nameCtrl.text[0]
                                        : 'U')
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 32,
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B0000),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1A0505),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'แตะเพื่อเปลี่ยนรูป',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              _inputField('ชื่อที่แสดง', nameCtrl),
              const SizedBox(height: 12),
              _inputField('คำอธิบาย', bioCtrl, maxLines: 2),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B0000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await ProfileProvider.instance.update(
                        displayName: nameCtrl.text.trim().isNotEmpty
                            ? nameCtrl.text.trim()
                            : null,
                        bio: bioCtrl.text.trim(),
                        avatarFile: selectedImage,
                      );
                      if (mounted) Navigator.pop(ctx);
                    } catch (e) {
                      debugPrint('Profile update error: $e');
                      if (mounted)
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('บันทึกไม่สำเร็จ: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                    }
                  },
                  child: const Text(
                    'บันทึก',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePassword() {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A0606),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 30,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'เปลี่ยนรหัสผ่าน',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _inputField('รหัสผ่านปัจจุบัน', curCtrl, obscure: true),
            const SizedBox(height: 12),
            _inputField('รหัสผ่านใหม่', newCtrl, obscure: true),
            const SizedBox(height: 12),
            _inputField('ยืนยันรหัสผ่านใหม่', confirmCtrl, obscure: true),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B0000),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  if (newCtrl.text != confirmCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('รหัสผ่านไม่ตรงกัน'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  try {
                    await ApiService.changePassword(curCtrl.text, newCtrl.text);
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('เปลี่ยนรหัสผ่านสำเร็จ'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                },
                child: const Text(
                  'เปลี่ยนรหัสผ่าน',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: SunTheme.goldLight.withOpacity(0.5),
          fontSize: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: SunTheme.gold.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SunTheme.goldLight),
        ),
        filled: true,
        fillColor: Colors.black.withOpacity(0.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    if (_profile == null)
      return Center(
        child: Text(
          'ไม่สามารถโหลดข้อมูลได้',
          style: TextStyle(color: SunTheme.gold.withOpacity(0.5)),
        ),
      );

    final name = _profile!['display_name'] ?? _profile!['username'] ?? '?';
    final username = _profile!['username'] ?? '';
    final balance = _profile!['balance'] ?? 0;
    final avatarUrl = _profile!['avatar_url'] as String?;
    final bio = _profile!['bio'] as String? ?? '';

    return AppBackground(
      child: Stack(
        children: [
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
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              child: Column(
                children: [
                  // Avatar + name + settings
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _showEditProfile,
                        child: Stack(
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    SunTheme.goldLight.withOpacity(0.3),
                                    SunTheme.red.withOpacity(0.4),
                                  ],
                                ),
                                border: Border.all(
                                  color: SunTheme.goldLight,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: SunTheme.goldLight.withOpacity(0.2),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                                image:
                                    ProfileProvider.instance.avatarImage != null
                                    ? DecorationImage(
                                        image: ProfileProvider
                                            .instance
                                            .avatarImage!,
                                        fit: BoxFit.cover,
                                      )
                                    : (avatarUrl != null
                                          ? DecorationImage(
                                              image: NetworkImage(avatarUrl),
                                              fit: BoxFit.cover,
                                            )
                                          : null),
                              ),
                              child:
                                  ProfileProvider.instance.avatarImage ==
                                          null &&
                                      avatarUrl == null
                                  ? Center(
                                      child: Text(
                                        name[0].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 28,
                                          color: SunTheme.goldLight,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B0000),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF1A0505),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: SunTheme.goldLight,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '@$username',
                              style: TextStyle(
                                color: SunTheme.gold.withOpacity(0.4),
                                fontSize: 12,
                              ),
                            ),
                            if (bio.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  bio,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 11,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.settings_outlined,
                          color: SunTheme.gold.withOpacity(0.5),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ).then((_) => _load()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Balance card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: SunTheme.cardDecoration(
                      radius: 16,
                      bgColor: const Color(0xFF1A0505),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PokerChipIcon(amount: balance, size: 32),
                        const SizedBox(width: 10),
                        Text(
                          NumberFormatter.formatWithCommas(balance),
                          style: TextStyle(
                            color: SunTheme.goldLight,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats
                  Row(
                    children: [
                      _statCard(
                        Icons.videogame_asset,
                        'เกม',
                        '${_profile!['total_games'] ?? 0}',
                      ),
                      const SizedBox(width: 6),
                      _statCard(
                        Icons.emoji_events,
                        'ชนะ',
                        '${_profile!['total_wins'] ?? 0}',
                      ),
                      const SizedBox(width: 6),
                      _statCard(
                        Icons.show_chart,
                        'อัตรา',
                        '${_profile!['win_rate'] ?? 0}%',
                      ),
                      const SizedBox(width: 6),
                      _statCard(
                        Icons.style,
                        'มือ',
                        '${_profile!['hands_played'] ?? 0}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Action buttons
                  _menuItem(
                    Icons.receipt_long,
                    'ประวัติเหรียญ',
                    'ชนะ แพ้ ซื้อของ',
                    () => showDialog(
                      context: context,
                      builder: (_) => const TransactionHistoryPopup(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _menuItem(
                    Icons.settings,
                    'ตั้งค่า',
                    'เสียง ภาษา เปลี่ยนชื่อ รหัสผ่าน',
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ).then((_) => _load()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: SunTheme.cardDecoration(
          radius: 12,
          bgColor: const Color(0xFF0E0404),
        ),
        child: Column(
          children: [
            Icon(icon, color: SunTheme.goldLight.withOpacity(0.6), size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: SunTheme.gold.withOpacity(0.35),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: SunTheme.cardDecoration(
          radius: 14,
          bgColor: const Color(0xFF1A0505),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF8B0000).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: SunTheme.goldLight.withOpacity(0.7),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: SunTheme.gold.withOpacity(0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: SunTheme.gold.withOpacity(0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
