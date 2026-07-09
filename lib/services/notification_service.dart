import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:secure_chat/screens/chat_screen.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/chat_service.dart';

class NotificationService {
  static final Set<String> _foregroundProcessedMessageIds = {};
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final UserService _userService = UserService();
  final Map<String, DateTime?> _lastMessageTimes = {};

  StreamSubscription? _chatsSubscription;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await localNotifier.setup(
        appName: 'Secret Chat',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
      return;
    }

    // 1. Initialize Local Notifications (For Foreground Alerts and Actions on Mobile)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationResponse,
    );

    // 2. Request FCM & System Notification Permissions on Mobile
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 3. Setup Foreground messaging listener on Mobile
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final data = message.data;
      final messageId = data['messageId'] as String?;

      if (messageId != null) {
        if (_foregroundProcessedMessageIds.contains(messageId)) {
          print("Duplicate foreground FCM message ignored: $messageId");
          return;
        }
        _foregroundProcessedMessageIds.add(messageId);
      }

      final chatId = data['chatId'] as String?;
      final title = data['title'] as String? ?? 'New Message';
      final body = data['body'] as String? ?? '';
      final senderUid = data['senderUid'] as String?;

      // Do not display alert if user is actively chatting on that screen
      if (chatId != null && ChatScreen.activeChatId == chatId) {
        return;
      }

      final payloadData = json.encode({
        'senderUid': senderUid,
        'senderName': title,
        'messageId': messageId,
        'messageText': body,
      });

      await _showNotification(
        message.hashCode,
        title,
        body,
        payload: payloadData,
      );
    });

    // 4. Token Refresh Listener
    _fcm.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': token,
        });
      }
    });

    _initialized = true;
  }

  static Future<void> onNotificationResponse(NotificationResponse response) async {
    final input = response.input;
    final payload = response.payload; 
    if (response.actionId == 'reply_action' && input != null && input.isNotEmpty && payload != null && payload.isNotEmpty) {
      try {
        final chatService = ChatService();
        Map<String, dynamic>? decodedPayload;
        try {
          decodedPayload = json.decode(payload) as Map<String, dynamic>;
        } catch (_) {}

        if (decodedPayload != null) {
          final recipientUid = decodedPayload['senderUid'] as String;
          final repliedId = decodedPayload['messageId'] as String?;
          final repliedName = decodedPayload['senderName'] as String?;
          final repliedText = decodedPayload['messageText'] as String?;

          await chatService.sendMessage(
            recipientUid,
            input,
            repliedMessageId: repliedId,
            repliedMessageSenderUid: recipientUid,
            repliedMessageSenderName: repliedName,
            repliedMessageText: repliedText,
          );
        } else {
          // Fallback for older legacy payloads
          await chatService.sendMessage(payload, input);
        }
        
        final notificationsPlugin = FlutterLocalNotificationsPlugin();
        await notificationsPlugin.cancel(response.id ?? 0);
      } catch (e) {
        print("Error sending reply from notification action: $e");
      }
    }
  }

  Future<void> updateFcmToken() async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final token = await _fcm.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'fcmToken': token,
          });
        }
      }
    } catch (e) {
      print("Error updating FCM token: $e");
    }
  }

  void startListening(String currentUid) {
    _chatsSubscription?.cancel();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final chatService = ChatService();
      _chatsSubscription = chatService.getConversations().listen((conversations) {
        for (final conversation in conversations) {
          final otherUser = conversation.otherUser;
          final chatId = chatService.getChatId(currentUid, otherUser.uid);

          // Don't show notifications if actively chatting with this user
          if (ChatScreen.activeChatId == chatId) {
            _lastMessageTimes[chatId] = conversation.lastMessageTime;
            continue;
          }

          if (conversation.hasUnread) {
            final lastTime = conversation.lastMessageTime;
            final prevTime = _lastMessageTimes[chatId];

            if (prevTime == null || (lastTime != null && lastTime.isAfter(prevTime))) {
              // Trigger Windows local toast notification
              final notification = LocalNotification(
                title: otherUser.displayName,
                body: conversation.lastMessage ?? 'Encrypted message 🔒',
              );
              notification.show();
            }
          }
          _lastMessageTimes[chatId] = conversation.lastMessageTime;
        }
      });
      return;
    }
    _chatsSubscription = null;
  }

  void stopListening() {
    _chatsSubscription?.cancel();
    _chatsSubscription = null;
  }

  Future<void> _showNotification(int id, String title, String body, {String? payload}) async {
    const androidDetails = AndroidNotificationDetails(
      'message_channel',
      'New Messages',
      channelDescription: 'Notifications for incoming messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'reply_action',
          'Reply',
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              label: 'Type your reply...',
            ),
          ],
        ),
      ],
    );
    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> clearAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      print("Error clearing notifications: $e");
    }
  }
}
