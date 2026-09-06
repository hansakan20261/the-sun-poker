import 'number_formatter.dart';

/// Thai language string constants for THE SUN POKER mobile app.
///
/// All UI labels are stored here rather than using a full i18n framework,
/// since the app targets Thai-only users.
class ThaiLabels {
  // Navigation
  static const store = 'ร้านค้า';
  static const activities = 'กิจกรรม';
  static const career = 'อาชีพ';
  static const profile = 'โปรไฟล์';
  static const lobby = 'ล็อบบี้';

  // Actions
  static const fold = 'หมอบ';
  static const call = 'ตาม';
  static const raise = 'เก';
  static const check = 'ตรวจสอบ';
  static const confirm = 'เรียก';
  static const callAny = 'ตามทุกจำนวน';
  static const allIn = 'หมดหน้าตัก';
  static const pot = 'กองกลาง';
  static const blinds = 'บลายด์';

  // OFC
  static const frontHand = 'Front';
  static const middleHand = 'Middle';
  static const backHand = 'Back';
  static const foul = 'FOUL';
  static const fantasyland = 'Fantasyland';
  static const royalties = 'Royalties';
  static const points = 'pts';
  static const confirmAction = 'Confirm';
  static const reset = 'Reset';
  static const rowFull = 'Row is full';

  // Hand names (0=High Card through 9=Royal Flush)
  static const handNames = <int, String>{
    0: 'ไพ่สูง',
    1: 'คู่',
    2: 'สองคู่',
    3: 'ทริปส์',
    4: 'สเตรท',
    5: 'ฟลัช',
    6: 'ฟูลเฮาส์',
    7: 'โฟร์การ์ด',
    8: 'สเตรทฟลัช',
    9: 'รอยัลฟลัช',
  };

  // Daily Bonus
  static const dailyBonus = 'DAILY BONUS';
  static const gameEntryBonus = 'โบนัสเข้าเกม';
  static const lobbyGameBonus = 'เกมล็อบบี';
  static const invitationBonus = 'โบนัสการเชิญ';
  static const claim = 'รับ';
  static const gold = 'ทอง';

  // Club
  static const joinClub = 'เข้าร่วม คลับ';
  static const createClub = 'สร้าง คลับ';
  static const holdToExpand = 'กดค้างเพื่อขยายรายชื่อคลับ';

  // Game modes
  static const spinUp = 'SPINUP';
  static const worldTournament = 'ทัวร์นาเมนต์ระดับโลก';
  static const minBuyIn = 'ซื้อเข้าขั้นต่ำ';

  // Error messages
  static const cannotAnalyze = 'ไม่สามารถวิเคราะห์ได้ในขณะนี้';
  static const cannotLoadRooms = 'ไม่สามารถโหลดห้องได้';
  static const insufficientFunds = 'เงินไม่เพียงพอ';
  static const retry = 'ลองอีกครั้ง';
  static const skip = 'ข้าม';

  // Bonus invitation text
  static const bonusInviteText =
      'เล่นในเกมล็อบบีหรือเชิญเพื่อนเพื่อรับทองฟรีเพิ่ม!';

  // Lucky Draw
  static const luckyDrawText = 'ให้คุณจับรางวัลฟรี!';

  // Replay
  static const replay = 'ย้อนดู';
  static const step = 'ขั้นตอน';
  static const play = 'เล่น';
  static const pause = 'หยุด';
  static const close = 'ปิด';

  // Split Pot
  static const splitPot = 'แบ่งกองกลาง';
  static const oddChip = 'เศษ';

  // Rake
  static const rake = 'เรค';

  // Reservation
  static const reserved = 'จองแล้ว';
  static const reservationExpired = 'หมดเวลาจอง';
  static const cancel = 'ยกเลิก';

  // Bet Confirm
  static const confirmBet = 'ยืนยันเดิมพัน';

  // Sound
  static const sound = 'เสียง';
  static const soundOn = 'เปิดเสียง';
  static const soundOff = 'ปิดเสียง';

  // Speed labels
  static const speed1x = '1x';
  static const speed2x = '2x';
  static const speed3x = '3x';

  // Rake tooltip
  static String rakeTooltip(double percent, int cap) =>
      'เรค: ${percent.toStringAsFixed(0)}% (สูงสุด ${NumberFormatter.formatWithCommas(cap)})';

  // Showdown
  static const result = 'ผลลัพธ์';
  static const communityCardsLabel = 'ไพ่กลาง';
  static const winner = 'ผู้ชนะ';
  static const loser = 'ผู้แพ้';
  static const tapToClose = 'แตะเพื่อปิด';

  // Welcome
  static const welcome = 'ยินดีต้อนรับ!';
  static const enterGame = 'เข้าสู่เกม';

  // Spectator
  static const waitingForNextRound = 'รอเล่นรอบถัดไป...';
  static const waitForBB = 'รอ BB';
  static const postBehind = 'โพสต์ BB เข้าเล่นเลย';
  static const insufficientChips = 'ชิปไม่เพียงพอ';

  // Bet selection
  static const minRaiseLabel = 'ขั้นต่ำ';
  static const halfPot = '1/2 กองกลาง';
  static const twoThirdsPot = '2/3 กองกลาง';
  static const potLabel = 'กองกลาง';
  static const confirmBetLabel = 'ยืนยันเดิมพัน';
  static const potPercentage = 'ของกองกลาง';

  // Game Guide
  static const strongHand = 'ไพ่แข็ง';
  static const mediumHand = 'ไพ่ปานกลาง';
  static const weakHand = 'ไพ่อ่อน';
  static const shouldRaise = 'ควรเก';
  static const shouldCall = 'ควรตาม';
  static const shouldFold = 'ควรหมอบ';
  static const gameGuide = 'คำแนะนำเกม';

  // Practice
  static const practice = 'ทดลองเล่น';
  static const practicePrefix = 'ทดลอง';
  static const refillPracticeChips = 'เติมชิปทดลอง';
}
