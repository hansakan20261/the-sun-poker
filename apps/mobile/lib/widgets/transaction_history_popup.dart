import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../theme.dart';

/// Transaction history popup — shows all financial transactions.
class TransactionHistoryPopup extends StatefulWidget {
  const TransactionHistoryPopup({super.key});
  @override
  State<TransactionHistoryPopup> createState() =>
      _TransactionHistoryPopupState();
}

class _TransactionHistoryPopupState extends State<TransactionHistoryPopup> {
  List<dynamic> _transactions = [];
  bool _loading = true;
  String _filter = 'all'; // all, game, shop

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final type = _filter == 'all' ? null : _filter;
      final data = await ApiService.getTransactions(limit: 50, type: type);
      if (mounted)
        setState(() {
          _transactions = data['transactions'] ?? [];
          _loading = false;
        });
    } catch (_) {
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
                const Icon(
                  Icons.receipt_long,
                  color: Color(0xFFFFD700),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'ประวัติเหรียญ',
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
          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('ทั้งหมด', 'all'),
                  _filterChip('เกม', 'game'),
                  _filterChip('ร้านค้า', 'shop'),
                ],
              ),
            ),
          ),
          const Divider(color: Color(0xFF3A1515), height: 1),
          // List
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                  )
                : _transactions.isEmpty
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
                          'ไม่มีรายการ',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    itemCount: _transactions.length,
                    itemBuilder: (_, i) {
                      try {
                        return _buildTransactionCard(_transactions[i]);
                      } catch (_) {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filter = value);
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFDAA520).withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? const Color(0xFFDAA520).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFFFD700) : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(dynamic tx) {
    final type = tx['type']?.toString() ?? '';
    final amount = int.tryParse(tx['amount']?.toString() ?? '0') ?? 0;
    final balanceAfter =
        int.tryParse(tx['balance_after']?.toString() ?? '0') ?? 0;
    final createdAt = tx['created_at']?.toString() ?? '';
    final refId = tx['reference_id']?.toString() ?? '';

    final info = _getTypeInfo(type);
    final isPositive = amount > 0;

    // Format date
    String dateStr = '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      dateStr =
          '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      dateStr = createdAt;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: SunTheme.cardDecoration(
        radius: 10,
        bgColor: const Color(0xFF1A0606),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: info.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Icon(info.icon, color: info.color, size: 18)),
          ),
          const SizedBox(width: 10),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 9,
                  ),
                ),
                if (refId.isNotEmpty && refId != 'null')
                  Text(
                    'Ref: ${refId.length > 12 ? '${refId.substring(0, 12)}...' : refId}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.15),
                      fontSize: 8,
                    ),
                  ),
              ],
            ),
          ),
          // Amount + balance
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isPositive ? "+" : ""}${NumberFormatter.formatWithCommas(amount)}',
                style: TextStyle(
                  color: isPositive ? Colors.greenAccent : Colors.red.shade300,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'คงเหลือ ${NumberFormatter.formatWithCommas(balanceAfter)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _TypeInfo _getTypeInfo(String type) {
    switch (type) {
      case 'game_buy_in':
        return _TypeInfo('ซื้อเข้าเกม', Icons.login, Colors.orange);
      case 'game_win':
        return _TypeInfo('ชนะเกม', Icons.emoji_events, Colors.greenAccent);
      case 'game_loss':
        return _TypeInfo('แพ้เกม', Icons.trending_down, Colors.red);
      case 'game_cashout':
        return _TypeInfo('ออกจากห้อง', Icons.logout, Colors.amber);
      case 'topup':
      case 'deposit':
        return _TypeInfo('รับเหรียญ', Icons.add_circle, Colors.green);
      case 'withdraw':
        return _TypeInfo('ใช้เหรียญ', Icons.remove_circle, Colors.red);
      case 'shop_purchase':
        return _TypeInfo('ซื้อของ', Icons.shopping_bag, Colors.purple);
      case 'daily_bonus':
        return _TypeInfo('โบนัสรายวัน', Icons.card_giftcard, Colors.amber);
      case 'referral_bonus':
        return _TypeInfo('โบนัสเชิญเพื่อน', Icons.people, Colors.cyan);
      case 'admin_credit':
        return _TypeInfo(
          'เครดิตจากแอดมิน',
          Icons.admin_panel_settings,
          Colors.blue,
        );
      default:
        return _TypeInfo(
          type.isNotEmpty ? type : 'อื่นๆ',
          Icons.receipt,
          Colors.grey,
        );
    }
  }
}

class _TypeInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _TypeInfo(this.label, this.icon, this.color);
}
