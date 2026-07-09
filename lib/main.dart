import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/config/routes.dart';
import 'package:secure_chat/services/notification_service.dart';
import 'package:secure_chat/services/call_service.dart';
import 'package:secure_chat/models/call_model.dart';

import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

final Set<String> _backgroundProcessedMessageIds = {};

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final messageId = data['messageId'] as String?;
  
  if (messageId != null) {
    if (_backgroundProcessedMessageIds.contains(messageId)) {
      print("Duplicate background FCM message ignored: $messageId");
      return;
    }
    _backgroundProcessedMessageIds.add(messageId);
  }

  final title = data['title'] as String? ?? 'New Message';
  final body = data['body'] as String? ?? '';
  final senderUid = data['senderUid'] as String?;

  final notificationsPlugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);

  await notificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: NotificationService.onNotificationResponse,
  );

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

  final payloadData = json.encode({
    'senderUid': senderUid,
    'senderName': title,
    'messageId': messageId,
    'messageText': body,
  });

  await notificationsPlugin.show(
    message.hashCode,
    title,
    body,
    notificationDetails,
    payload: payloadData,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (Platform.isWindows) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSy' 'Aj6A6qPSfuIuVCCJlKK1RnVDrGAV_t31o',
        appId: '1:908950949230:android:4276bd60c27f59ca89c57f',
        messagingSenderId: '908950949230',
        projectId: 'secret-chat-69',
        storageBucket: 'secret-chat-69.firebasestorage.app',
      ),
    );
  } else {
    await Firebase.initializeApp();
  }
  
  if (Platform.isAndroid || Platform.isIOS) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 640),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const SecureChatApp());
}

// Global navigator key so incoming call overlay can push routes from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SecureChatApp extends StatefulWidget {
  const SecureChatApp({super.key});

  @override
  State<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends State<SecureChatApp> {
  StreamSubscription? _incomingCallSub;
  String? _currentIncomingCallId; // prevent duplicate navigations

  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();

    // Re-subscribe when auth state changes (login/logout)
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _incomingCallSub?.cancel();
      _currentIncomingCallId = null;
      if (user != null) {
        _listenForIncomingCalls();
      }
    });
  }

  void _listenForIncomingCalls() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _incomingCallSub = CallService().getIncomingCalls().listen((call) {
      if (call != null && call.callId != _currentIncomingCallId) {
        _currentIncomingCallId = call.callId;

        // Don't show if we are the caller
        if (call.callerUid == user.uid) return;

        // Don't show if already on a call
        if (CallService().currentCallId != null) return;

        navigatorKey.currentState?.pushNamed(
          AppRoutes.incomingCall,
          arguments: {'callModel': call},
        );
      } else if (call == null) {
        _currentIncomingCallId = null;
      }
    });
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Secret Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
