import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'dart:io' show Platform;

class UpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Current local app version parameters
  static const int currentVersionCode = 46; // Incremented for this build
  static const String currentVersionName = "1.0.45";

  Future<void> initLocalNotifications() async {
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final uri = Uri.parse(response.payload!);
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              print("Blocked launching insecure URL: ${response.payload}");
            }
          } catch (e) {
            print("Error launching update URL from notification response: $e");
          }
        }
      },
    );
  }

  Future<void> showNativeUpdateNotification(String versionName, String downloadUrl) async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final notification = LocalNotification(
          title: 'Update Secret Chat',
          body: 'Version $versionName is available. Click to download and install!',
        );
        notification.onClick = () {
          try {
            final uri = Uri.parse(downloadUrl);
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              print("Blocked launching insecure URL: $downloadUrl");
            }
          } catch (e) {
            print("Error launching update URL from notification: $e");
          }
        };
        notification.show();
        return;
      }

      await initLocalNotifications();
      
      // Request permission on Android 13+
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final androidDetails = AndroidNotificationDetails(
        'update_channel',
        'App Updates',
        channelDescription: 'Notifications for new version updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );
      final notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        999,
        'Update Secret Chat',
        'Version $versionName is available. Tap to download and install!',
        notificationDetails,
        payload: downloadUrl,
      );
    } catch (e) {
      print("Failed to show native update notification: $e");
    }
  }

  Future<Map<String, dynamic>?> getUpdateInfo() async {
    try {
      final doc = await _firestore.collection('metadata').doc('app_config').get();
      if (!doc.exists || doc.data() == null) return null;

      final data = doc.data()!;
      
      if (Platform.isWindows) {
        final latestVersionCode = data['latestVersionCodeWindows'] as int? ?? 1;
        final latestVersionName = data['latestVersionNameWindows'] as String? ?? "1.0.0";
        final downloadUrl = data['downloadUrlWindows'] as String? ?? "";
        final forceUpdate = data['forceUpdateWindows'] as bool? ?? false;

        if (latestVersionCode > currentVersionCode && downloadUrl.isNotEmpty) {
          return {
            'versionName': latestVersionName,
            'downloadUrl': downloadUrl,
            'forceUpdate': forceUpdate,
          };
        }
      } else {
        final latestVersionCode = data['latestVersionCode'] as int? ?? 1;
        final latestVersionName = data['latestVersionName'] as String? ?? "1.0.0";
        final downloadUrl = data['downloadUrl'] as String? ?? "";
        final forceUpdate = data['forceUpdate'] as bool? ?? false;

        if (latestVersionCode > currentVersionCode && downloadUrl.isNotEmpty) {
          return {
            'versionName': latestVersionName,
            'downloadUrl': downloadUrl,
            'forceUpdate': forceUpdate,
          };
        }
      }
    } catch (e) {
      print("Error checking for updates: $e");
    }
    return null;
  }

  Future<void> checkForUpdates(BuildContext context) async {
    final info = await getUpdateInfo();
    if (info != null) {
      if (context.mounted) {
        showUpdateDialog(context, info['versionName'], info['downloadUrl'], info['forceUpdate']);
      }
      showNativeUpdateNotification(info['versionName'], info['downloadUrl']);
    }
  }

  void showUpdateDialog(BuildContext context, String version, String url, bool force) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async => !force,
          child: AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.system_update_rounded, color: AppTheme.accentPrimary),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [AppTheme.accentPrimary, AppTheme.accentSecondary],
                  ).createShader(bounds),
                  child: const Text(
                    'Update Available',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A new update (Version $version) is available! Please download and install the latest version to continue using Secret Chat.',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textPrimary),
                ),
              ],
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Later', style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (uri.scheme == 'http' || uri.scheme == 'https') {
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (e) {
                      print("Error launching update URL: $e");
                    }
                  } else {
                    print("Blocked launching insecure URL: $url");
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  minimumSize: const Size(100, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Update Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }
}
