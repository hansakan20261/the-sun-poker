import 'package:flutter/material.dart';
import '../theme.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../widgets/app_background.dart';
import '../widgets/sun_button.dart';
import 'club_detail_screen.dart';

class ClubScreen extends StatefulWidget {
  final bool isEmbedded;
  const ClubScreen({super.key, this.isEmbedded = false});
  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  int _tab = 0; // 0=my clubs, 1=all clubs
  List<dynamic> _myClubs = [];
  List<dynamic> _allClubs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    List<dynamic> myClubs = [];
    List<dynamic> allClubs = [];

    try {
      final my = await ApiService.getMyClubs().timeout(AppConfig.httpTimeout);
      myClubs = my['clubs'] ?? [];
    } catch (e) {
      debugPrint('Club load my error: $e');
    }

    try {
      final all = await ApiService.getClubs().timeout(AppConfig.httpTimeout);
      allClubs = all['clubs'] ?? [];
    } catch (e) {
      debugPrint('Club load all error: $e');
    }

    if (mounted)
      setState(() {
        _myClubs = myClubs;
        _allClubs = allClubs;
        _loading = false;
      });
  }

  void _showCreateClubDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => Center(
        child: SingleChildScrollView(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            margin: const EdgeInsets.symmetric(vertical: 40),
            padding: const EdgeInsets.all(24),
            decoration: SunTheme.cardDecoration(
              radius: 24,
              bgColor: const Color(0xFF1A0606),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'สร้างคลับ',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'ชื่อคลับ',
                      labelStyle: TextStyle(
                        color: const Color(0xFFDAA520).withOpacity(0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: const Color(0xFFDAA520).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFFFD700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'คำอธิบาย (ไม่บังคับ)',
                      labelStyle: TextStyle(
                        color: const Color(0xFFDAA520).withOpacity(0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: const Color(0xFFDAA520).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFFFD700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      try {
                        await ApiService.createClub(
                          nameCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                        );
                        if (mounted) Navigator.pop(context);
                        _load();
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('สร้างคลับสำเร็จ!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                      } catch (e) {
                        debugPrint('Create club error: $e');
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('สร้างคลับไม่สำเร็จ: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3CB371), Color(0xFF2E8B57)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'สร้างคลับ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
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
      ),
    );
  }

  Future<void> _joinClub(String clubId) async {
    try {
      await ApiService.joinClub(clubId);
      _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เข้าร่วมคลับสำเร็จ!'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เข้าร่วมไม่สำเร็จ'),
            backgroundColor: Colors.red,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        if (!widget.isEmbedded)
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(
                              Icons.arrow_back_ios,
                              color: Color(0xFFFFD700),
                              size: 20,
                            ),
                          ),
                        const Icon(
                          Icons.groups,
                          color: Color(0xFFFFD700),
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'คลับ',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        SunButton.green(
                          label: 'สร้างคลับ',
                          onTap: _showCreateClubDialog,
                          width: 100,
                          height: 34,
                          icon: Icons.add,
                        ),
                      ],
                    ),
                  ),
                  // Tabs
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF5C2020),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        _tabBtn('คลับของฉัน', 0),
                        const SizedBox(width: 4),
                        _tabBtn('คลับทั้งหมด', 1),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Content
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFFD700),
                            ),
                          )
                        : _tab == 0
                        ? _buildMyClubs()
                        : _buildAllClubs(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFFCC2222), Color(0xFF8B0000)],
                  )
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFFFD700) : Colors.white38,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyClubs() {
    if (_myClubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups, color: Colors.white.withOpacity(0.1), size: 64),
            const SizedBox(height: 12),
            const Text(
              'ยังไม่ได้เข้าร่วมคลับ',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFFFD700),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _myClubs.length,
        itemBuilder: (_, i) => _buildClubCard(_myClubs[i], isMember: true),
      ),
    );
  }

  Widget _buildAllClubs() {
    if (_allClubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              color: Colors.white.withOpacity(0.1),
              size: 64,
            ),
            const SizedBox(height: 12),
            const Text(
              'ยังไม่มีคลับ',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFFFFD700),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _allClubs.length,
        itemBuilder: (_, i) {
          final club = _allClubs[i];
          final isMember = _myClubs.any((c) => c['id'] == club['id']);
          return _buildClubCard(club, isMember: isMember);
        },
      ),
    );
  }

  Widget _buildClubCard(dynamic club, {bool isMember = false}) {
    final name = club['name'] ?? '';
    final owner = club['owner_name'] ?? '';
    final memberCount = club['member_count'] ?? 0;
    final maxMembers = club['max_members'] ?? 200;
    final role = club['role'] ?? '';

    return GestureDetector(
      onTap: isMember
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ClubDetailScreen(club: Map<String, dynamic>.from(club)),
              ),
            )
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: SunTheme.cardDecoration(
          radius: 14,
          bgColor: const Color(0xFF1A0606),
        ),
        child: Row(
          children: [
            // Club avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDAA520).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                image: const DecorationImage(
                  image: AssetImage('assets/logo.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (role == 'owner') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDAA520).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'เจ้าของ',
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'เจ้าของ: $owner',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    'สมาชิก: $memberCount/$maxMembers',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Action
            if (!isMember)
              SunButton.green(
                label: 'เข้าร่วม',
                onTap: () => _joinClub(club['id']),
                width: 80,
                height: 36,
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}
