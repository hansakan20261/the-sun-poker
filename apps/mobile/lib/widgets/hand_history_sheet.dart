import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/thai_labels.dart';
import '../utils/hand_evaluator.dart';
import 'playing_card.dart';
import 'hand_replay_overlay.dart';

/// Show as: showDialog(context: ctx, builder: (_) => HandHistoryPopup(tableId: tid, gameType: 'OFC'));
class HandHistoryPopup extends StatefulWidget {
  final String? tableId;
  final String gameType; // 'OFC' or 'NLH'

  const HandHistoryPopup({super.key, this.tableId, this.gameType = 'NLH'});
  @override
  State<HandHistoryPopup> createState() => _HandHistoryPopupState();
}

class _HandHistoryPopupState extends State<HandHistoryPopup> {
  List<dynamic> _hands = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      debugPrint('📜 [History] Loading history for tableId=${widget.tableId}');
      final data = await ApiService.getHandHistory(
        limit: 20,
        tableId: widget.tableId,
      );
      debugPrint(
        '📜 [History] Got ${(data['hands'] as List?)?.length ?? 0} hands',
      );
      if (mounted)
        setState(() {
          _hands = data['hands'] ?? [];
          _loading = false;
        });
    } catch (e) {
      debugPrint('📜 [History] Error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A0606),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFFFFD700).withOpacity(0.55),
          width: 1.5,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'ประวัติการเล่น',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 22,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF3A1515), height: 1),
          // List
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                  )
                : _hands.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          color: Colors.white.withOpacity(0.2),
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'ยังไม่มีประวัติในห้องนี้',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'เล่นจบมือแรกแล้วจะแสดงที่นี่',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    itemCount: _hands.length,
                    itemBuilder: (_, i) {
                      try {
                        final hand = _hands[i];
                        if (hand is! Map<String, dynamic>)
                          return const SizedBox.shrink();
                        return _buildHandCard(hand);
                      } catch (e) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ไม่สามารถแสดงข้อมูลมือนี้ได้',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandCard(Map<String, dynamic> hand) {
    final userId = ApiService.currentUserId ?? '';
    final rawWinnerIds = hand['winner_ids'];
    final winnerIds = rawWinnerIds is List
        ? rawWinnerIds.whereType<String>().toList()
        : <String>[];
    final isWinner = userId.isNotEmpty && winnerIds.contains(userId);
    final pot = int.tryParse(hand['pot_total']?.toString() ?? '') ?? 0;
    final rakeAmount = int.tryParse(hand['rake_amount']?.toString() ?? '') ?? 0;
    final handNumber = hand['hand_number'] ?? '';
    final gameType = hand['game_type']?.toString() ?? '';

    Map<String, dynamic> details = {};
    try {
      final raw = hand['community_cards'];
      if (raw is String && raw.isNotEmpty)
        details = jsonDecode(raw);
      else if (raw is Map)
        details = Map<String, dynamic>.from(raw);
    } catch (_) {}

    final players = details['players'] as Map<String, dynamic>? ?? {};

    // Detect OFC — check actual data structure first, then widget.gameType as fallback
    final isOFC =
        details.containsKey('results') ||
        details.containsKey('front') ||
        details.containsKey('arranged') ||
        (gameType.contains('chinese') || gameType.contains('ofc'));

    if (isOFC) {
      return _buildOFCHandCard(hand, details, isWinner, pot, handNumber);
    }
    return _buildNLHHandCard(
      hand,
      details,
      isWinner,
      pot,
      handNumber,
      rakeAmount,
      players,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // OFC Hand History Card — 3 rows with overlapping cards
  // ═══════════════════════════════════════════════════════════

  Widget _buildOFCHandCard(
    Map<String, dynamic> hand,
    Map<String, dynamic> details,
    bool isWinner,
    int pot,
    dynamic handNumber,
  ) {
    final userId = ApiService.currentUserId ?? '';

    List<String> myFront = [];
    List<String> myMiddle = [];
    List<String> myBack = [];
    int coinChange = 0;
    bool isFoul = false;

    // Check results array
    final results = details['results'] as List? ?? [];
    for (final r in results) {
      if (r is Map && r['id'] == userId) {
        myFront = List<String>.from(r['front'] ?? []);
        myMiddle = List<String>.from(r['middle'] ?? []);
        myBack = List<String>.from(r['back'] ?? []);
        coinChange = r['coinChange'] ?? 0;
        isFoul = r['isFoul'] == true;
        break;
      }
    }

    // Fallback: check arranged field
    if (myFront.isEmpty && details.containsKey('front')) {
      myFront = List<String>.from(details['front'] ?? []);
      myMiddle = List<String>.from(details['middle'] ?? []);
      myBack = List<String>.from(details['back'] ?? []);
    }

    // Fallback: check players map
    if (myFront.isEmpty) {
      final players = details['players'] as Map<String, dynamic>? ?? {};
      for (final entry in players.entries) {
        final p = entry.value;
        if (p is Map && p['id'] == userId) {
          final arranged = p['arranged'] as Map<String, dynamic>? ?? {};
          myFront = List<String>.from(arranged['front'] ?? p['front'] ?? []);
          myMiddle = List<String>.from(arranged['middle'] ?? p['middle'] ?? []);
          myBack = List<String>.from(arranged['back'] ?? p['back'] ?? []);
          coinChange = p['coinChange'] ?? coinChange;
          isFoul = p['isFoul'] == true || isFoul;
          break;
        }
      }
    }

    if (coinChange == 0) coinChange = isWinner ? pot : -pot;

    String frontName = myFront.length == 3
        ? HandEvaluator.evaluate3(myFront).nameTh
        : '';
    String middleName = myMiddle.length == 5
        ? HandEvaluator.evaluate5(myMiddle).nameTh
        : '';
    String backName = myBack.length == 5
        ? HandEvaluator.evaluate5(myBack).nameTh
        : '';
    final hasCards =
        myFront.isNotEmpty || myMiddle.isNotEmpty || myBack.isNotEmpty;

    return GestureDetector(
      onTap: () => _openReplay(hand),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: SunTheme.cardDecoration(
          radius: 12,
          bgColor: isWinner ? const Color(0xFF0A2E0A) : const Color(0xFF2E0A0A),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '#$handNumber',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDAA520), Color(0xFFB8860B)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OFC',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (isFoul) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ฟาวล์',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isWinner
                        ? Colors.green.shade800
                        : Colors.red.shade900,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${coinChange >= 0 ? "+" : ""}${NumberFormatter.formatWithCommas(coinChange)}',
                    style: TextStyle(
                      color: isWinner
                          ? Colors.greenAccent
                          : Colors.red.shade200,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            if (hasCards) ...[
              const SizedBox(height: 10),
              _buildHistoryRow(ThaiLabels.backHand, myBack, backName),
              const SizedBox(height: 6),
              _buildHistoryRow(ThaiLabels.middleHand, myMiddle, middleName),
              const SizedBox(height: 6),
              _buildHistoryRow(ThaiLabels.frontHand, myFront, frontName),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'ไม่มีข้อมูลไพ่',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Single row in OFC history — cards displayed without overlap
  Widget _buildHistoryRow(String label, List<String> cards, String handName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: SunTheme.goldLight.withOpacity(0.6),
                  fontSize: 10,
                ),
              ),
              Text(
                '${cards.length} ใบ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
        if (cards.isNotEmpty)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableW = constraints.maxWidth;
                final count = cards.length;
                final cardW = (availableW / count) - 2;
                final clampedW = cardW.clamp(24.0, 44.0);
                final cardH = clampedW * 1.4;
                return SizedBox(
                  height: cardH,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (int i = 0; i < count; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            right: i < count - 1 ? 2 : 0,
                          ),
                          child: PlayingCard(
                            card: cards[i],
                            faceUp: true,
                            width: clampedW,
                            height: cardH,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (cards.isEmpty) const Expanded(child: SizedBox()),
        const SizedBox(width: 8),
        if (handName.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0505).withOpacity(0.85),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SunTheme.goldLight.withOpacity(0.3)),
            ),
            child: Text(
              handName,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // NLH Hand History Card — แสดงแบบ reference app
  // ═══════════════════════════════════════════════════════════

  Widget _buildNLHHandCard(
    Map<String, dynamic> hand,
    Map<String, dynamic> details,
    bool isWinner,
    int pot,
    dynamic handNumber,
    int rakeAmount,
    Map<String, dynamic> players,
  ) {
    final userId = ApiService.currentUserId ?? '';
    final community = List<String>.from(details['community'] ?? []);
    final rawWinnerIds = hand['winner_ids'];
    final winnerIds = rawWinnerIds is List
        ? rawWinnerIds.whereType<String>().toList()
        : <String>[];

    // Meta info
    final sb = hand['small_blind'] ?? details['smallBlind'] ?? 0;
    final bb = hand['big_blind'] ?? details['bigBlind'] ?? 0;
    final ante = hand['ante'] ?? details['ante'] ?? 0;
    final playedAt = hand['played_at'] ?? hand['created_at'] ?? '';
    String timeStr = '';
    try {
      if (playedAt.toString().isNotEmpty) {
        final dt = DateTime.tryParse(playedAt.toString());
        if (dt != null) {
          final local = dt.toLocal();
          timeStr =
              '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
              '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        }
      }
    } catch (_) {}

    final handIdStr = hand['id']?.toString() ?? handNumber.toString();

    return GestureDetector(
      onTap: () => _openReplay(hand),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: time • blinds • handID • share ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  // time
                  if (timeStr.isNotEmpty) ...[
                    const Icon(
                      Icons.access_time,
                      color: Colors.white38,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // chip icon + blinds
                  const Icon(
                    Icons.casino_outlined,
                    color: Colors.white38,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ante > 0 ? '$sb/$bb ($ante)' : '$sb/$bb',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Spacer(),
                  // Hand number
                  Text(
                    'มือ #$handNumber',
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                  const SizedBox(width: 6),
                  // Share icon
                  GestureDetector(
                    onTap: () {},
                    child: const Icon(
                      Icons.share_outlined,
                      color: Colors.white38,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),

            // ── Player rows ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildPlayerRows(
                  players,
                  community,
                  winnerIds,
                  userId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build one row per player in hand history
  List<Widget> _buildPlayerRows(
    Map<String, dynamic> players,
    List<String> community,
    List<String> winnerIds,
    String myUserId,
  ) {
    if (players.isEmpty) {
      // fallback — no player data
      return [
        Text(
          'ไม่มีข้อมูลผู้เล่น',
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
        ),
      ];
    }

    final rows = <Widget>[];
    // Sort: me first, then by seat
    final entries = players.entries.toList()
      ..sort((a, b) {
        final aIsMe = (a.value['id']?.toString() == myUserId) ? 0 : 1;
        final bIsMe = (b.value['id']?.toString() == myUserId) ? 0 : 1;
        if (aIsMe != bIsMe) return aIsMe - bIsMe;
        return (a.value['seat'] ?? 0).compareTo(b.value['seat'] ?? 0);
      });

    for (int i = 0; i < entries.length; i++) {
      final p = entries[i].value as Map<String, dynamic>? ?? {};
      final isMe = p['id']?.toString() == myUserId;
      final isWin = winnerIds.contains(p['id']?.toString() ?? '');
      final isFolded = p['folded'] == true;
      final holeCards = List<String>.from(
        p['holeCards'] ?? p['hole_cards'] ?? [],
      );
      final username = p['username'] ?? p['name'] ?? 'Player';
      final position = _positionLabel(p['position'] ?? p['seatLabel'] ?? '');
      final amount = p['amount'] as int? ?? p['net'] as int? ?? 0;
      final handName = p['handName'] ?? p['hand_name'] ?? p['_handName'] ?? '';

      rows.add(
        _buildPlayerRow(
          username: username,
          position: position,
          holeCards: holeCards,
          community: community,
          handName: handName.toString(),
          amount: amount,
          isWin: isWin,
          isFolded: isFolded,
          isMe: isMe,
        ),
      );

      if (i < entries.length - 1) {
        rows.add(
          Divider(
            height: 10,
            thickness: 0.5,
            color: Colors.white.withOpacity(0.06),
          ),
        );
      }
    }
    return rows;
  }

  /// Single player row in NLH history — matches reference app style
  Widget _buildPlayerRow({
    required String username,
    required String position,
    required List<String> holeCards,
    required List<String> community,
    required String handName,
    required int amount,
    required bool isWin,
    required bool isFolded,
    required bool isMe,
  }) {
    const cardW = 26.0;
    const cardH = 36.0;
    const communityCardW = 24.0;
    const communityCardH = 33.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: name + position badge ──
          SizedBox(
            width: 65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username,
                  style: TextStyle(
                    color: isMe ? const Color(0xFFFFD700) : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                if (position.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _positionColor(position),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      position,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // ── Center: hole cards + community cards ──
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hole cards
                if (holeCards.isNotEmpty) ...[
                  for (final c in holeCards)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: PlayingCard(
                        card: isFolded ? null : c,
                        faceUp: !isFolded,
                        width: cardW,
                        height: cardH,
                      ),
                    ),
                ] else ...[
                  // No cards — show face-down placeholders
                  for (int i = 0; i < 2; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: PlayingCard(
                        card: null,
                        faceUp: false,
                        width: cardW,
                        height: cardH,
                      ),
                    ),
                ],
                // Separator
                if (community.isNotEmpty) ...[
                  Container(
                    width: 1,
                    height: 32,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: Colors.white.withOpacity(0.12),
                  ),
                  // Community cards
                  for (final c in community)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: PlayingCard(
                        card: c,
                        faceUp: true,
                        width: communityCardW,
                        height: communityCardH,
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),

          // ── Right: hand name + amount ──
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Hand name
              if (isFolded)
                const Text(
                  'หมอบ',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (handName.isNotEmpty)
                Text(
                  _translateHandName(handName),
                  style: TextStyle(
                    color: isWin ? const Color(0xFFFFD700) : Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                const SizedBox(height: 12),
              const SizedBox(height: 1),
              // Amount
              if (!isFolded && amount != 0)
                Text(
                  '${amount > 0 ? "+" : ""}${NumberFormatter.formatWithCommas(amount)}',
                  style: TextStyle(
                    color: isWin ? Colors.greenAccent : Colors.red.shade300,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                )
              else if (isFolded)
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  /// Map position string to short label
  String _positionLabel(String pos) {
    switch (pos.toUpperCase()) {
      case 'SB':
      case 'SMALL_BLIND':
        return 'SB';
      case 'BB':
      case 'BIG_BLIND':
        return 'BB';
      case 'BTN':
      case 'BUTTON':
      case 'DEALER':
        return 'BTN';
      case 'UTG':
      case 'UNDER_THE_GUN':
        return 'UTG';
      case 'MP':
      case 'MIDDLE_POSITION':
        return 'MP';
      case 'HJ':
      case 'HIJACK':
        return 'HJ';
      case 'CO':
      case 'CUTOFF':
        return 'CO';
      default:
        return pos.isEmpty
            ? ''
            : pos.toUpperCase().substring(0, pos.length.clamp(0, 3));
    }
  }

  /// Position badge background color
  Color _positionColor(String pos) {
    switch (pos) {
      case 'SB':
        return const Color(0xFF1565C0); // blue
      case 'BB':
        return const Color(0xFF6A1B9A); // purple
      case 'BTN':
        return const Color(0xFF2E7D32); // green
      case 'UTG':
        return const Color(0xFF795548); // brown
      default:
        return const Color(0xFF424242); // grey
    }
  }

  String _translateHandName(String? name) {
    if (name == null) return '';
    const map = {
      'Royal Flush': 'รอยัลฟลัช',
      'Straight Flush': 'สเตรทฟลัช',
      'Four of a Kind': 'โฟร์ออฟอะไคนด์',
      'Full House': 'ฟูลเฮาส์',
      'Flush': 'ฟลัช',
      'Straight': 'สเตรท',
      'Three of a Kind': 'ทริปส์',
      'Two Pair': 'สองคู่',
      'One Pair': 'คู่',
      'High Card': 'ไฮการ์ด',
    };
    return map[name] ?? name;
  }

  void _openReplay(Map<String, dynamic> hand) async {
    final handId = hand['id']?.toString();
    if (handId == null) return;
    try {
      final detail = await ApiService.getHandDetail(handId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            body: HandReplayOverlay(
              handData: detail,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถโหลดข้อมูลได้'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class HandHistorySheet extends StatelessWidget {
  const HandHistorySheet({super.key});
  @override
  Widget build(BuildContext context) => const HandHistoryPopup();
}
