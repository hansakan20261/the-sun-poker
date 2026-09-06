import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../config.dart';
import 'runtime_config_service.dart';

class GameSocket {
  static IO.Socket? _socket;
  static Function(Map<String, dynamic>)? onGameState;
  static Function(Map<String, dynamic>)? onGameResult;
  static Function(Map<String, dynamic>)? onChatMessage;
  static Function(String)? onError;
  static Function()? onConnected;
  static Function()? onDisconnected;
  static int _reconnectAttempts = 0;

  static Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;
    final token = ApiService.token;
    if (token == null) return;
    try {
      await RuntimeConfigService.load();
    } catch (_) {
      onError?.call('ไม่สามารถโหลดการตั้งค่าระบบได้');
      return;
    }
    final reconnectAttempts = RuntimeConfigService.integer(
      'socket_reconnect_attempts',
    );
    final reconnectDelayMs =
        RuntimeConfigService.integer('socket_reconnect_delay_sec') * 1000;
    final reconnectMaxDelayMs =
        RuntimeConfigService.integer('socket_reconnect_max_delay_sec') * 1000;
    final reconnectRandomization = RuntimeConfigService.number(
      'socket_reconnect_randomization',
    );

    // Dispose existing socket to prevent duplicate listeners
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }

    _socket = IO.io(
      AppConfig.gameSocketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(reconnectAttempts)
          .setReconnectionDelay(reconnectDelayMs)
          .setReconnectionDelayMax(reconnectMaxDelayMs)
          .setRandomizationFactor(reconnectRandomization)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      print('🎮 Socket connected to ${AppConfig.gameSocketUrl}');
      _reconnectAttempts = 0;
      if (onConnected != null) onConnected!();
    });
    _socket!.onDisconnect((_) {
      print('🎮 Socket disconnected');
      if (onDisconnected != null) onDisconnected!();
    });
    _socket!.onConnectError((e) {
      _reconnectAttempts++;
      print('🎮 Socket error (attempt $_reconnectAttempts): $e');
      if (onError != null && _reconnectAttempts >= reconnectAttempts) {
        onError!('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์เกมได้');
      }
    });
    _socket!.onReconnect((_) {
      print('🎮 Socket reconnected');
      _reconnectAttempts = 0;
    });

    _socket!.on('game:state', (data) {
      if (onGameState != null) onGameState!(Map<String, dynamic>.from(data));
    });
    _socket!.on('game:result', (data) {
      if (onGameResult != null) onGameResult!(Map<String, dynamic>.from(data));
    });
    _socket!.on('chat:message', (data) {
      if (onChatMessage != null)
        onChatMessage!(Map<String, dynamic>.from(data));
    });
    _socket!.on('error', (data) {
      if (onError != null) onError!(data['message'] ?? 'Unknown error');
    });

    _socket!.connect();
  }

  static void joinTable(
    String tableId,
    int seatNumber,
    int buyIn, {
    String? accessToken,
  }) {
    _socket?.emit('game:join', {
      'tableId': tableId,
      'seatNumber': seatNumber,
      'buyIn': buyIn,
      if (accessToken != null) 'accessToken': accessToken,
    });
  }

  static void spectateTable(String tableId, {String? accessToken}) {
    _socket?.emit('game:spectate', {
      'tableId': tableId,
      if (accessToken != null) 'accessToken': accessToken,
    });
  }

  static void startGame() => _socket?.emit('game:start');

  static void sendAction(String action, {int amount = 0}) {
    _socket?.emit('game:action', {'action': action, 'amount': amount});
  }

  static void requestStraddle({bool enabled = true}) {
    _socket?.emit('game:straddle', {'enabled': enabled});
  }

  static void requestRebuy(int amount) {
    _socket?.emit('game:rebuy', {'amount': amount});
  }

  static void sendChat(String message, {String? receiverId}) {
    _socket?.emit('chat:message', {
      'message': message,
      'receiverId': receiverId,
    });
  }

  // Task 13.1: Seat reservation events
  static void reserveSeat(String tableId, int seatNumber) {
    _socket?.emit('seat:reserve', {
      'tableId': tableId,
      'seatNumber': seatNumber,
    });
  }

  static void cancelReservation(String tableId, int seatNumber) {
    _socket?.emit('seat:cancel', {
      'tableId': tableId,
      'seatNumber': seatNumber,
    });
  }

  static void disconnect() {
    // Clear Chinese handlers to prevent cross-game errors
    _onChineseState = null;
    _onChineseResult = null;
    _onChineseError = null;
    _socket?.disconnect();
    _socket = null;
  }

  static bool get isConnected => _socket?.connected ?? false;

  // ===== Chinese Poker =====
  static Function(Map<String, dynamic>)? _onChineseState;
  static Function(Map<String, dynamic>)? _onChineseResult;
  static Function(String)? _onChineseError;

  static Future<void> connectChinese({
    required Function(Map<String, dynamic>) onState,
    required Function(Map<String, dynamic>) onResult,
    required Function(String) onError,
  }) async {
    _onChineseState = onState;
    _onChineseResult = onResult;
    _onChineseError = onError;

    if (_socket != null && _socket!.connected) {
      _setupChineseListeners();
      return;
    }
    final token = ApiService.token;
    if (token == null) return;
    try {
      await RuntimeConfigService.load();
    } catch (_) {
      onError('ไม่สามารถโหลดการตั้งค่าระบบได้');
      return;
    }
    final reconnectAttempts = RuntimeConfigService.integer(
      'socket_reconnect_attempts',
    );
    final reconnectDelayMs =
        RuntimeConfigService.integer('socket_reconnect_delay_sec') * 1000;
    final reconnectMaxDelayMs =
        RuntimeConfigService.integer('socket_reconnect_max_delay_sec') * 1000;
    final reconnectRandomization = RuntimeConfigService.number(
      'socket_reconnect_randomization',
    );

    _socket = IO.io(
      AppConfig.gameSocketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionAttempts(reconnectAttempts)
          .setReconnectionDelay(reconnectDelayMs)
          .setReconnectionDelayMax(reconnectMaxDelayMs)
          .setRandomizationFactor(reconnectRandomization)
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => print('🀄 Chinese Poker socket connected'));
    _socket!.onDisconnect((_) => print('🀄 Chinese Poker socket disconnected'));
    _socket!.onConnectError((e) => print('🀄 Socket error: $e'));

    _setupChineseListeners();
    _socket!.connect();
  }

  static void _setupChineseListeners() {
    _socket!.off('chinese:state');
    _socket!.off('chinese:result');
    // Don't remove 'error' listener — it's shared. Route errors to the correct handler.
    // Instead, set up a combined error handler that routes to the active game type.
    _socket!.off('error');
    _socket!.on('error', (data) {
      final msg = data['message'] ?? 'Unknown error';
      // Route to Chinese handler if Chinese game is active, otherwise to NLH
      if (_onChineseState != null && _onChineseError != null) {
        _onChineseError!(msg);
      } else if (onError != null) {
        onError!(msg);
      }
    });

    _socket!.on('chinese:state', (data) {
      if (_onChineseState != null)
        _onChineseState!(Map<String, dynamic>.from(data));
    });
    _socket!.on('chinese:result', (data) {
      if (_onChineseResult != null)
        _onChineseResult!(Map<String, dynamic>.from(data));
    });
  }

  static void joinChinese(
    String tableId,
    int seatNumber,
    int buyIn, {
    String? accessToken,
  }) {
    _socket?.emit('chinese:join', {
      'tableId': tableId,
      'seatNumber': seatNumber,
      'buyIn': buyIn,
      if (accessToken != null) 'accessToken': accessToken,
    });
  }

  static void spectateChinese(String tableId, {String? accessToken}) {
    _socket?.emit('chinese:spectate', {
      'tableId': tableId,
      if (accessToken != null) 'accessToken': accessToken,
    });
  }

  static void startChinese() => _socket?.emit('chinese:start');

  static void arrangeChinese(
    List<String> front,
    List<String> middle,
    List<String> back,
  ) {
    _socket?.emit('chinese:arrange', {
      'front': front,
      'middle': middle,
      'back': back,
    });
  }

  /// Web reconnect: Flutter 3.11+ fires AppLifecycleState.resumed on web
  /// visibility change, so existing didChangeAppLifecycleState in screens
  /// (poker_table_screen, chinese_poker_screen) already handle reconnection.
  /// Call this to explicitly reconnect if socket is dead.
  static void reconnectIfNeeded() {
    if (_socket == null || !_socket!.connected) {
      debugPrint('🔄 [WebSocket] Reconnecting after background/sleep...');
      connect();
    }
  }
}
