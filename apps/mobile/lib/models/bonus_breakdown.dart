/// Daily bonus breakdown with three bonus categories.
class BonusBreakdown {
  final int gameEntryBonus;
  final int lobbyGameBonus;
  final int invitationBonus;

  int get total => gameEntryBonus + lobbyGameBonus + invitationBonus;

  const BonusBreakdown({
    required this.gameEntryBonus,
    required this.lobbyGameBonus,
    required this.invitationBonus,
  });
}
