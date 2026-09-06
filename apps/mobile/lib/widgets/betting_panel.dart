import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils/bet_calculator.dart';
import '../utils/thai_labels.dart';
import '../utils/number_formatter.dart';
import '../services/audio_manager.dart';
import '../widgets/sun_button.dart';
import 'bet_confirm_button.dart';

/// Professional betting panel with Thai action buttons, pot-fraction presets,
/// snap-to-grid slider, confirm button, and context-sensitive display.
///
/// Requirements: 15.1–15.10, 16.1, 16.2, 17.1–17.4, 18.1–18.5, 20.1–20.9, 21.1, 21.2
class BettingPanel extends StatefulWidget {
  final int currentPot;
  final int playerChips;
  final int minRaise;
  final int maxRaise;
  final int callAmount;
  final bool isMyTurn;
  final bool needCall;
  final String phase; // 'preflop', 'flop', 'turn', 'river'
  final int bigBlind; // Task 10.1: for snap-to-grid
  final Function(String action, {int amount}) onAction;

  /// Whether actions are blocked due to an animation playing (Req 2.4).
  /// When true, all betting buttons (fold/call/raise/all-in) are disabled.
  final bool isAnimationBlocking;

  /// Pre-action: 'call_any' | 'check_fold' | null — set before our turn.
  final String? preAction;

  /// Called when user taps a pre-action button (before their turn).
  final void Function(String action)? onSetPreAction;

  const BettingPanel({
    super.key,
    required this.currentPot,
    required this.playerChips,
    required this.minRaise,
    required this.maxRaise,
    required this.callAmount,
    required this.isMyTurn,
    required this.needCall,
    this.phase = 'preflop',
    this.bigBlind = 20,
    required this.onAction,
    this.isAnimationBlocking = false,
    this.preAction,
    this.onSetPreAction,
  });

  @override
  State<BettingPanel> createState() => _BettingPanelState();
}

class _BettingPanelState extends State<BettingPanel>
    with SingleTickerProviderStateMixin {
  double _sliderValue = 0.0;
  bool _showSlider = false;
  bool _showConfirm =
      false; // Task 10.1: show BetConfirmButton instead of auto-submit
  int _lastSnapPoint = 0; // Task 10.2: track snap point for ratchet sound

  bool _showTextInput = false;
  final TextEditingController _textInputCtrl = TextEditingController();

  // Task 10.2: scale animation for action button taps
  late AnimationController _tapAnimCtrl;
  late Animation<double> _tapScale;
  String? _tappedAction;

  @override
  void initState() {
    super.initState();
    _tapAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _tapScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _tapAnimCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tapAnimCtrl.dispose();
    _textInputCtrl.dispose();
    super.dispose();
  }

  // Task 10.1: Snap raw slider amount to BB grid
  int get _raiseAmount {
    final raw = BetCalculator.fromSlider(
      sliderValue: _sliderValue,
      minRaise: widget.minRaise,
      maxRaise: widget.maxRaise,
    );
    return BetCalculator.snapToGrid(
      rawAmount: raw,
      bigBlind: widget.bigBlind,
      minRaise: widget.minRaise,
      maxRaise: widget.maxRaise,
      playerChips: widget.playerChips,
    );
  }

  bool get _isPreFlop => widget.phase == 'preflop';

  void _setFromPreset(double fraction) {
    if (!widget.isMyTurn) return;
    final amount = _presetAmount(fraction);
    // Send raise action immediately (chip sound plays from game)
    widget.onAction('raise', amount: amount);
    setState(() {
      _showSlider = false;
      _showConfirm = false;
      _sliderValue = 0.0;
    });
  }

  /// Compute the actual bet amount for a given preset fraction
  int _presetAmount(double fraction) {
    if (fraction >= 99) return widget.playerChips; // All-in sentinel
    final bb = widget.bigBlind > 0 ? widget.bigBlind : 20;
    final pot = widget.currentPot;
    final call = widget.callAmount;
    final minR = widget.minRaise;
    int amount;

    if (_isPreFlop) {
      // Pre-flop: use multiples of minRaise (1x, 1.5x, 2x, 3x)
      final multipliers = {0.0: 1.0, 0.5: 1.5, 0.67: 2.0, 1.0: 3.0};
      final mult = multipliers[fraction] ?? 1.0;
      amount = (minR * mult).round();
    } else {
      // Post-flop: use pot fraction (call + fraction * (pot + call))
      if (fraction <= 0) {
        amount = minR; // ขั้นต่ำ
      } else {
        final potAfterCall = pot + call;
        amount = call + (potAfterCall * fraction).round();
        if (amount < minR) amount = minR;
      }
    }

    return BetCalculator.snapToGrid(
      rawAmount: amount,
      bigBlind: bb,
      minRaise: minR,
      maxRaise: widget.playerChips,
      playerChips: widget.playerChips,
    );
  }

  /// Labels for preset buttons based on phase
  String _presetLabel(double fraction) {
    if (_isPreFlop) {
      final labels = {
        0.0: ThaiLabels.minRaiseLabel,
        0.5: '1.5x',
        0.67: '2x',
        1.0: '3x',
      };
      return labels[fraction] ?? ThaiLabels.minRaiseLabel;
    } else {
      final labels = {
        0.0: ThaiLabels.minRaiseLabel,
        0.5: '1/2 Pot',
        0.67: '2/3 Pot',
        1.0: 'Pot',
      };
      return labels[fraction] ?? ThaiLabels.minRaiseLabel;
    }
  }

  /// Determine which preset is recommended based on game context
  double? get _recommendedFraction {
    final call = widget.callAmount;

    // Pre-flop: recommend 2.5x BB (standard open)
    if (_isPreFlop) return 0.0;

    // Post-flop no bet: recommend 2/3 pot (standard c-bet)
    if (!widget.needCall) return 0.67;

    // Post-flop facing bet: no raise preset recommended (call/fold instead)
    return null;
  }

  // Task 10.2: Animate button tap (no extra sound — chip sound plays from game)
  void _onActionTap(String actionKey, VoidCallback action) {
    setState(() => _tappedAction = actionKey);
    _tapAnimCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _tappedAction = null);
    });
    action();
  }

  // Task 10.1: Slider changed — snap and check for ratchet sound
  void _onSliderChanged(double v) {
    setState(() {
      _sliderValue = v;
      _showConfirm = true;
    });
    // Task 10.2: Play ratchet sound when snap point changes
    final snapped = _raiseAmount;
    if (snapped != _lastSnapPoint) {
      _lastSnapPoint = snapped;
      AudioManager.instance.play(SoundEffect.sliderRatchet);
    }
  }

  /// ALL-IN when chips ≤ required bet (Req 15.7)
  bool get _forceAllIn => widget.playerChips <= widget.callAmount;

  @override
  Widget build(BuildContext context) {
    // Req 2.4: Block actions while animation is playing
    final enabled = widget.isMyTurn && !widget.isAnimationBlocking;
    final opacity = enabled ? 1.0 : 0.4;

    // Force ALL-IN display (Req 15.7)
    if (_forceAllIn && enabled) {
      return SafeArea(top: false, child: _buildAllInOnly());
    }

    // Pot percentage calculation
    final potPercent = widget.currentPot > 0
        ? ((_raiseAmount / widget.currentPot) * 100).round()
        : 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Opacity(
          opacity: opacity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasVerticalSpace = constraints.maxHeight > 180;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Pre-action bar (shown when NOT our turn OR when preAction is armed) ──
                  if ((!widget.isMyTurn || widget.preAction != null) &&
                      widget.onSetPreAction != null)
                    _buildPreActionBar(),
                  // Min raise label
                  if (_showSlider)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${ThaiLabels.minRaiseLabel}: ${NumberFormatter.formatWithCommas(widget.minRaise)}',
                        style: TextStyle(
                          color: SunTheme.goldLight.withOpacity(0.5),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  // Preset bet buttons — only show buttons with valid unique amounts
                  if (enabled && hasVerticalSpace) ...[
                    Builder(
                      builder: (_) {
                        final chips = widget.playerChips;
                        final minR = widget.minRaise;
                        // Build list of valid presets with unique amounts
                        final presets = <Map<String, dynamic>>[];
                        final seenAmounts = <int>{};

                        for (final frac in [0.0, 0.5, 0.67, 1.0]) {
                          final amt = _presetAmount(frac);
                          if (amt > chips) continue; // Can't afford
                          if (amt < minR) continue; // Below minimum
                          if (seenAmounts.contains(amt))
                            continue; // Duplicate amount
                          seenAmounts.add(amt);
                          presets.add({
                            'label': _presetLabel(frac),
                            'amount': amt,
                            'fraction': frac,
                          });
                        }

                        // Always add All-in as last option
                        if (!seenAmounts.contains(chips)) {
                          presets.add({
                            'label': ThaiLabels.allIn,
                            'amount': chips,
                            'fraction': 100.0,
                          });
                        }

                        if (presets.isEmpty) return const SizedBox();

                        return Row(
                          children: [
                            for (int i = 0; i < presets.length; i++) ...[
                              if (i > 0) const SizedBox(width: 3),
                              if (presets[i]['fraction'] == 100.0)
                                Expanded(
                                  child: _presetBtn(
                                    presets[i]['label'],
                                    'C${NumberFormatter.formatShort(presets[i]['amount'])}',
                                    100.0,
                                    () {
                                      if (!enabled) return;
                                      widget.onAction('all_in');
                                      setState(() {
                                        _showSlider = false;
                                        _showConfirm = false;
                                        _sliderValue = 0.0;
                                      });
                                    },
                                    enabled,
                                  ),
                                )
                              else
                                Expanded(
                                  child: _presetBtn(
                                    presets[i]['label'],
                                    'C${NumberFormatter.formatShort(presets[i]['amount'])}',
                                    presets[i]['fraction'],
                                    () =>
                                        _setFromPreset(presets[i]['fraction']),
                                    enabled,
                                  ),
                                ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (_showSlider) ...[
                    // Bet amount display (tappable for text input)
                    GestureDetector(
                      onTap: enabled
                          ? () {
                              setState(() {
                                _showTextInput = !_showTextInput;
                                if (_showTextInput) {
                                  _textInputCtrl.text = _raiseAmount.toString();
                                }
                              });
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: SunTheme.gold.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          'C${NumberFormatter.formatWithCommas(_raiseAmount)}',
                          style: TextStyle(
                            color: SunTheme.goldLight,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Pot percentage indicator
                    if (widget.currentPot > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '$potPercent% ${ThaiLabels.potPercentage}',
                          style: TextStyle(
                            color: SunTheme.goldLight.withOpacity(0.4),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    // Text input for custom amount
                    if (_showTextInput)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SizedBox(
                          height: 36,
                          width: 140,
                          child: TextField(
                            controller: _textInputCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: SunTheme.gold.withOpacity(0.3),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: SunTheme.goldLight,
                                ),
                              ),
                            ),
                            onSubmitted: (v) {
                              final parsed = int.tryParse(v) ?? _raiseAmount;
                              final clamped = parsed < 1
                                  ? widget.minRaise
                                  : parsed;
                              final snapped = BetCalculator.snapToGrid(
                                rawAmount: clamped,
                                bigBlind: widget.bigBlind,
                                minRaise: widget.minRaise,
                                maxRaise: widget.maxRaise,
                                playerChips: widget.playerChips,
                              );
                              final range = widget.maxRaise - widget.minRaise;
                              setState(() {
                                _sliderValue = range > 0
                                    ? ((snapped - widget.minRaise) / range)
                                          .clamp(0.0, 1.0)
                                    : 0.0;
                                _showTextInput = false;
                                _showConfirm = true;
                              });
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Slider
                    Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: SunTheme.goldLight,
                              inactiveTrackColor: Colors.white.withOpacity(0.1),
                              thumbColor: SunTheme.goldLight,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              trackHeight: 3,
                            ),
                            child: Slider(
                              value: _sliderValue,
                              onChanged: enabled ? _onSliderChanged : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Confirm button
                    if (_showConfirm && _raiseAmount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: BetConfirmButton(
                          amount: _raiseAmount,
                          onConfirm: () {
                            widget.onAction('raise', amount: _raiseAmount);
                            setState(() {
                              _showSlider = false;
                              _showConfirm = false;
                              _showTextInput = false;
                              _sliderValue = 0.0;
                            });
                          },
                        ),
                      ),
                  ],
                  // Context-sensitive action buttons
                  _isPreFlop
                      ? _buildPreFlopButtons(enabled)
                      : _buildPostFlopButtons(enabled),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Pre-flop buttons: หมอบ (Fold), ตาม X (Call), เก (Raise) — Req 15.1
  Widget _buildPreFlopButtons(bool enabled) {
    return Row(
      children: [
        // หมอบ (Fold)
        Expanded(
          child: _actionBtn(
            'fold',
            ThaiLabels.fold,
            const [Color(0xFF555555), Color(0xFF333333)],
            enabled
                ? () => _onActionTap('fold', () {
                    setState(() {
                      _showSlider = false;
                      _showConfirm = false;
                    });
                    widget.onAction('fold');
                  })
                : null,
          ),
        ),
        const SizedBox(width: 6),
        // ตาม X (Call)
        Expanded(
          flex: 2,
          child: _actionBtn(
            'call',
            widget.needCall
                ? '${ThaiLabels.call} ${NumberFormatter.formatWithCommas(widget.callAmount)}'
                : ThaiLabels.check,
            const [Color(0xFF2E8B57), Color(0xFF155C30)],
            enabled
                ? () => _onActionTap('call', () {
                    if (widget.needCall) {
                      widget.onAction('call');
                    } else {
                      widget.onAction('check');
                    }
                    setState(() {
                      _showSlider = false;
                      _showConfirm = false;
                    });
                  })
                : null,
          ),
        ),
        const SizedBox(width: 6),
        // เก (Raise)
        Expanded(
          child: _actionBtn(
            'raise',
            ThaiLabels.raise,
            const [Color(0xFFCC8800), Color(0xFF8B6000)],
            enabled
                ? () => _onActionTap('raise_toggle', () {
                    setState(() {
                      _showSlider = !_showSlider;
                      if (!_showSlider) {
                        _showConfirm = false;
                        _sliderValue = 0.0;
                      }
                    });
                  })
                : null,
          ),
        ),
      ],
    );
  }

  /// Post-flop buttons: หมอบ/ตาม (Fold/Call), ตรวจสอบ (Check), ตามทุกจำนวน (Call Any) — Req 15.2
  Widget _buildPostFlopButtons(bool enabled) {
    return Row(
      children: [
        // หมอบ (Fold) — always show fold option
        Expanded(
          child: _actionBtn(
            'fold_check',
            ThaiLabels.fold,
            const [Color(0xFF555555), Color(0xFF333333)],
            enabled
                ? () => _onActionTap('fold_check', () {
                    setState(() {
                      _showSlider = false;
                      _showConfirm = false;
                    });
                    widget.onAction('fold');
                  })
                : null,
          ),
        ),
        const SizedBox(width: 6),
        // ตาม X (Call)
        Expanded(
          flex: 2,
          child: _actionBtn(
            'call_post',
            widget.needCall
                ? '${ThaiLabels.call} ${NumberFormatter.formatWithCommas(widget.callAmount)}'
                : ThaiLabels.check,
            const [Color(0xFF2E8B57), Color(0xFF155C30)],
            enabled
                ? () => _onActionTap('call_post', () {
                    if (widget.needCall) {
                      widget.onAction('call');
                    } else {
                      widget.onAction('check');
                    }
                    setState(() {
                      _showSlider = false;
                      _showConfirm = false;
                    });
                  })
                : null,
          ),
        ),
        const SizedBox(width: 6),
        // ตามทุกจำนวน (Call Any) / เก (Raise)
        Expanded(
          child: _actionBtn(
            'raise_post',
            widget.needCall ? ThaiLabels.callAny : ThaiLabels.raise,
            widget.needCall
                ? const [Color(0xFFCC1111), Color(0xFF5C0000)]
                : const [Color(0xFFCC8800), Color(0xFF8B6000)],
            enabled
                ? () => _onActionTap('raise_post', () {
                    if (widget.needCall) {
                      widget.onAction('call');
                    } else {
                      setState(() {
                        _showSlider = !_showSlider;
                        if (!_showSlider) {
                          _showConfirm = false;
                          _sliderValue = 0.0;
                        }
                      });
                    }
                  })
                : null,
          ),
        ),
      ],
    );
  }

  /// ALL-IN only display when chips ≤ required bet (Req 15.7)
  Widget _buildAllInOnly() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: _actionBtn(
              'fold_allin',
              ThaiLabels.fold,
              const [Color(0xFF555555), Color(0xFF333333)],
              () => _onActionTap('fold_allin', () => widget.onAction('fold')),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: _actionBtn(
              'allin',
              ThaiLabels.allIn,
              const [Color(0xFFCC1111), Color(0xFF8B0000), Color(0xFF5C0000)],
              () => _onActionTap('allin', () => widget.onAction('all_in')),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pre-action bar ──────────────────────────────────────────
  /// Shows before our turn — lets player queue "ตามทุกจำนวน" or "หมอบถ้ามีเดิมพัน"
  Widget _buildPreActionBar() {
    final isCallAny = widget.preAction == 'call_any';
    final isCheckFold = widget.preAction == 'check_fold';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // หมอบถ้ามีเดิมพัน (Check/Fold)
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onSetPreAction?.call('check_fold'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCheckFold
                        ? [const Color(0xFF884400), const Color(0xFF552200)]
                        : [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCheckFold
                        ? Colors.orange.shade400
                        : Colors.white24,
                    width: isCheckFold ? 1.5 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isCheckFold)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.orange,
                        size: 14,
                      ),
                    if (isCheckFold) const SizedBox(width: 4),
                    Text(
                      'หมอบถ้ามีเดิมพัน',
                      style: TextStyle(
                        color: isCheckFold
                            ? Colors.orange.shade200
                            : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // ตามทุกจำนวน (Call Any)
          Expanded(
            child: GestureDetector(
              onTap: () => widget.onSetPreAction?.call('call_any'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isCallAny
                        ? [const Color(0xFFCC2200), const Color(0xFF881100)]
                        : [const Color(0xFF2A0A0A), const Color(0xFF1A0505)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCallAny ? Colors.red.shade300 : Colors.white24,
                    width: isCallAny ? 1.5 : 0.5,
                  ),
                  boxShadow: isCallAny
                      ? [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.25),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isCallAny)
                      const Icon(Icons.bolt, color: Colors.redAccent, size: 14),
                    if (isCallAny) const SizedBox(width: 4),
                    Text(
                      'ตามทุกจำนวน',
                      style: TextStyle(
                        color: isCallAny ? Colors.red.shade200 : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetBtn(
    String label,
    String amountText,
    double fraction,
    VoidCallback onTap,
    bool enabled,
  ) {
    final isRecommended = _recommendedFraction == fraction;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isRecommended
                ? [const Color(0xFF2E6B30), const Color(0xFF1A4520)]
                : [const Color(0xFF2A0A0A), const Color(0xFF1A0505)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRecommended
                ? Colors.greenAccent.withOpacity(0.6)
                : SunTheme.gold.withOpacity(0.3),
            width: isRecommended ? 1.5 : 0.5,
          ),
          boxShadow: isRecommended
              ? [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.2),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isRecommended ? Colors.greenAccent : SunTheme.goldLight,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              amountText,
              style: TextStyle(
                color: isRecommended
                    ? Colors.white
                    : SunTheme.goldLight.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(
    String actionKey,
    String label,
    List<Color> colors,
    VoidCallback? onTap,
  ) {
    final enabled = onTap != null;
    final isTapped = _tappedAction == actionKey;
    return AnimatedBuilder(
      animation: _tapAnimCtrl,
      builder: (_, __) => Transform.scale(
        scale: isTapped ? _tapScale.value : 1.0,
        child: SunButton(
          label: label,
          onTap: onTap,
          colors: enabled
              ? colors
              : colors.map((c) => c.withOpacity(0.3)).toList(),
          height: 48,
          fontSize: 11,
          shimmer: enabled,
        ),
      ),
    );
  }
}

/// Minimal AnimatedWidget helper for BettingPanel.
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
