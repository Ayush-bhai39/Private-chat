import 'package:flutter/material.dart';
import 'package:secure_chat/screens/splash_screen.dart';
import 'package:secure_chat/screens/welcome_screen.dart';
import 'package:secure_chat/screens/username_setup_screen.dart';
import 'package:secure_chat/screens/home_screen.dart';
import 'package:secure_chat/screens/chat_screen.dart';
import 'package:secure_chat/screens/new_chat_screen.dart';
import 'package:secure_chat/screens/story_viewer_screen.dart';
import 'package:secure_chat/screens/account_screen.dart';
import 'package:secure_chat/screens/settings_screen.dart';
import 'package:secure_chat/screens/profile_view_screen.dart';
import 'package:secure_chat/screens/story_editor_screen.dart';
import 'package:secure_chat/screens/followers_list_screen.dart';
import 'package:secure_chat/screens/call_screen.dart';
import 'package:secure_chat/screens/incoming_call_screen.dart';

import 'package:secure_chat/widgets/platform_layout.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String welcome = '/welcome';
  static const String usernameSetup = '/username-setup';
  static const String home = '/home';
  static const String chat = '/chat';
  static const String newChat = '/new-chat';
  static const String storyViewer = '/story-viewer';
  static const String createStory = '/create-story';
  static const String account = '/account';
  static const String settings = '/settings';
  static const String profileView = '/profile-view';
  static const String storyEditor = '/story-editor';
  static const String followersList = '/followers-list';
  static const String call = '/call';
  static const String incomingCall = '/incoming-call';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen(), settings: routeSettings);
      case welcome:
        return _buildRoute(const WelcomeScreen(), routeSettings);
      case usernameSetup:
        return _buildRoute(const UsernameSetupScreen(), routeSettings);
      case home:
        return _buildRoute(const PlatformLayout(mobileLayout: HomeScreen()), routeSettings);
      case chat:
        return _buildRoute(const ChatScreen(), routeSettings);
      case newChat:
        return _buildRoute(const NewChatScreen(), routeSettings);
      case storyViewer:
        return _buildRoute(const StoryViewerScreen(), routeSettings);
      case account:
        return _buildRoute(const AccountScreen(), routeSettings);
      case settings:
        return _buildRoute(const SettingsScreen(), routeSettings);
      case profileView:
        return _buildRoute(const ProfileViewScreen(), routeSettings);
      case storyEditor:
        return _buildRoute(const StoryEditorScreen(), routeSettings);
      case followersList:
        return _buildRoute(const FollowersListScreen(), routeSettings);
      case call:
        return _buildRoute(const CallScreen(), routeSettings);
      case incomingCall:
        return _buildRoute(const IncomingCallScreen(), routeSettings);
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${routeSettings.name}'),
            ),
          ),
        );
    }
  }

  static PageRouteBuilder _buildRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
