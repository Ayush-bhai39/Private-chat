import 'package:secure_chat/models/user_model.dart';

class ConversationModel {
  final UserModel otherUser;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final bool hasUnread;

  const ConversationModel({
    required this.otherUser,
    this.lastMessage,
    this.lastMessageTime,
    this.hasUnread = false,
  });
}
