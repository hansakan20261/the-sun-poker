import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/audio_manager.dart';
import '../utils/thai_labels.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _soundOn = AudioManager.instance.isSoundEnabled;
  bool _musicOn = AudioManager.instance.isMusicEnabled;
  double _sfxVolume = AudioManager.instance.sfxVolume;
  double _bgmVolume = AudioManager.instance.bgmVolume;
  bool _guideEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('SETTING'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A0505),
                    Color(0xFF0E0303),
                    Color(0xFF0A0202),
                  ],
                ),
              ),
            ),
          ),
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
            child: ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                // ── Sound effects toggle
                _item(
                  Icons.volume_up,
                  _soundOn ? 'เสียงเอฟเฟกต์: เปิด' : 'เสียงเอฟเฟกต์: ปิด',
                  () {
                    setState(() => _soundOn = !_soundOn);
                    AudioManager.instance.setSoundEnabled(_soundOn);
                  },
                  trailing: Switch(
                    value: _soundOn,
                    onChanged: (v) {
                      setState(() => _soundOn = v);
                      AudioManager.instance.setSoundEnabled(v);
                    },
                    activeColor: SunTheme.green,
                  ),
                ),
                // ── SFX Volume slider
                if (_soundOn)
                  _volumeSlider(
                    icon: Icons.graphic_eq,
                    label: 'ระดับเสียงเอฟเฟกต์',
                    value: _sfxVolume,
                    onChanged: (v) {
                      setState(() => _sfxVolume = v);
                      AudioManager.instance.setSfxVolume(v);
                    },
                  ),
                // ── Background music toggle
                _item(
                  Icons.music_note,
                  _musicOn ? 'เพลงประกอบ: เปิด' : 'เพลงประกอบ: ปิด',
                  () {
                    setState(() => _musicOn = !_musicOn);
                    AudioManager.instance.setMusicEnabled(_musicOn);
                  },
                  trailing: Switch(
                    value: _musicOn,
                    onChanged: (v) {
                      setState(() => _musicOn = v);
                      AudioManager.instance.setMusicEnabled(v);
                    },
                    activeColor: SunTheme.green,
                  ),
                ),
                // ── BGM Volume slider
                if (_musicOn)
                  _volumeSlider(
                    icon: Icons.music_video,
                    label: 'ระดับเสียงเพลงประกอบ',
                    value: _bgmVolume,
                    onChanged: (v) {
                      setState(() => _bgmVolume = v);
                      AudioManager.instance.setBgmVolume(v);
                    },
                  ),
                _item(Icons.person, 'Change name', () => _showChangeName()),
                _item(
                  Icons.tips_and_updates,
                  ThaiLabels.gameGuide,
                  () {
                    setState(() => _guideEnabled = !_guideEnabled);
                  },
                  trailing: Switch(
                    value: _guideEnabled,
                    onChanged: (v) {
                      setState(() => _guideEnabled = v);
                    },
                    activeColor: SunTheme.green,
                  ),
                ),
                _item(
                  Icons.key,
                  'Change password',
                  () => _showChangePassword(),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _showDeleteAccount(),
                    child: const Text(
                      'Delete account',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      await ApiService.logout();
                      if (mounted)
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (_) => false,
                        );
                    },
                    child: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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

  Widget _item(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: SunTheme.gold.withOpacity(0.6)),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing:
          trailing ??
          Icon(Icons.chevron_right, color: SunTheme.gold.withOpacity(0.3)),
      onTap: onTap,
    );
  }

  Widget _volumeSlider({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: SunTheme.gold.withOpacity(0.5), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '${(value * 100).round()}%',
                      style: TextStyle(
                        color: SunTheme.goldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: SunTheme.gold,
                    inactiveTrackColor: SunTheme.gold.withOpacity(0.2),
                    thumbColor: SunTheme.goldLight,
                    overlayColor: SunTheme.gold.withOpacity(0.15),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== Change Name =====
  void _showChangeName() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Change Name',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ชื่อใหม่',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SunTheme.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty) return;
                  try {
                    await ApiService.updateProfile(
                      displayName: ctrl.text.trim(),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('เปลี่ยนชื่อสำเร็จ'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (_) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('เปลี่ยนชื่อไม่สำเร็จ'),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                },
                child: const Text(
                  'SAVE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Language =====
  void _showLanguage() {
    String selected = 'th';
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Language',
                style: TextStyle(
                  color: SunTheme.goldLight,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _langTile(
                '🇹🇭',
                'ไทย',
                'th',
                selected,
                (v) => setS(() => selected = v),
              ),
              _langTile(
                '🇺🇸',
                'English',
                'en',
                selected,
                (v) => setS(() => selected = v),
              ),
              _langTile(
                '🇱🇦',
                'ລາວ',
                'lo',
                selected,
                (v) => setS(() => selected = v),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SunTheme.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await ApiService.updateProfile(locale: selected);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('เปลี่ยนภาษาเป็น $selected สำเร็จ'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (_) {}
                  },
                  child: const Text(
                    'SAVE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langTile(
    String flag,
    String name,
    String code,
    String selected,
    Function(String) onTap,
  ) {
    return ListTile(
      leading: Text(flag, style: const TextStyle(fontSize: 24)),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      trailing: selected == code
          ? Icon(Icons.check_circle, color: SunTheme.green)
          : null,
      onTap: () => onTap(code),
    );
  }

  // ===== Change Password =====
  void _showChangePassword() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Change Password',
              style: TextStyle(
                color: SunTheme.goldLight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: currentCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('รหัสผ่านปัจจุบัน'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('รหัสผ่านใหม่ (อย่างน้อย 6 ตัว)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('ยืนยันรหัสผ่านใหม่'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SunTheme.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  if (newCtrl.text != confirmCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('รหัสผ่านใหม่ไม่ตรงกัน'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  try {
                    final res = await ApiService.changePassword(
                      currentCtrl.text,
                      newCtrl.text,
                    );
                    if (res['success'] == true) {
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('เปลี่ยนรหัสผ่านสำเร็จ'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } else {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['error'] ?? 'ไม่สำเร็จ'),
                            backgroundColor: Colors.red,
                          ),
                        );
                    }
                  } catch (_) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('เปลี่ยนรหัสผ่านไม่สำเร็จ'),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                },
                child: const Text(
                  'SAVE',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Delete Account =====
  void _showDeleteAccount() {
    final passCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2D2D2D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).viewPadding.bottom +
              20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Delete Account',
              style: TextStyle(
                color: Colors.red.shade400,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'คุณแน่ใจหรือไม่ว่าต้องการลบบัญชี?\nข้อมูลทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SunTheme.gold.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('กรอกรหัสผ่านเพื่อยืนยัน'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  if (passCtrl.text.isEmpty) return;
                  try {
                    final res = await ApiService.deleteAccount(passCtrl.text);
                    if (res['success'] == true) {
                      ApiService.clearToken();
                      if (mounted)
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (_) => false,
                        );
                    } else {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res['error'] ?? 'ลบบัญชีไม่สำเร็จ'),
                            backgroundColor: Colors.red,
                          ),
                        );
                    }
                  } catch (_) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('ลบบัญชีไม่สำเร็จ'),
                          backgroundColor: Colors.red,
                        ),
                      );
                  }
                },
                child: const Text(
                  'DELETE ACCOUNT',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade500),
    filled: true,
    fillColor: Colors.white.withOpacity(0.1),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );
}
