/// Enumeration of all Rive animation files used in the game.
///
/// Each key maps to a specific `.riv` file in the `assets/rive/` directory.
/// These files contain state machines that can be triggered programmatically
/// from game events.
enum RiveAssetKey {
  cardDeal('assets/rive/card_deal.riv'),
  cardFlip('assets/rive/card_flip.riv'),
  chipMovement('assets/rive/chip_movement.riv'),
  chipStack('assets/rive/chip_stack.riv'),
  celebration('assets/rive/celebration.riv'),
  countdownRing('assets/rive/countdown_ring.riv'),
  allInEffect('assets/rive/all_in_effect.riv'),
  tableLoading('assets/rive/table_loading.riv'),
  royaltyEffect('assets/rive/royalty_effect.riv'),
  fantasylandAura('assets/rive/fantasyland_aura.riv');

  const RiveAssetKey(this.filePath);

  /// The asset file path for this Rive animation.
  final String filePath;
}
