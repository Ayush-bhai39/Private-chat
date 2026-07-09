import 'package:flutter/material.dart';
import 'package:secure_chat/config/theme.dart';
import 'package:secure_chat/models/note_model.dart';
import 'package:secure_chat/models/user_model.dart';

class NoteCircle extends StatelessWidget {
  final NoteModel? note;
  final String? displayName;
  final bool isAddNote;
  final VoidCallback? onTap;
  final String? profilePhotoUrl;

  const NoteCircle({
    super.key,
    this.note,
    this.displayName,
    this.isAddNote = false,
    this.onTap,
    this.profilePhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? (note?.displayName ?? '');
    final text = note?.text;
    final photoUrl = profilePhotoUrl ?? note?.photoUrl ?? '';
    final hasNote = text != null && text.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Padding to accommodate the bubble above avatar
          const SizedBox(height: 28),
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Avatar
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.surface,
                backgroundImage: UserModel.getAvatarImageProvider(photoUrl),
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person, color: AppTheme.textSecondary)
                    : null,
              ),

              // Note bubble above avatar
              if (hasNote)
                Positioned(
                  top: -24,
                  left: -14,
                  right: -14,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.surfaceLight,
                              AppTheme.surfaceLight.withOpacity(0.85),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.accentPrimary.withOpacity(0.15),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentPrimary.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                            const BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(maxWidth: 84),
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                      // Small downward pointer
                      CustomPaint(
                        size: const Size(8, 4),
                        painter: BubbleTrianglePainter(AppTheme.surfaceLight),
                      ),
                    ],
                  ),
                ),

              // + sign for adding note
              if (isAddNote)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppTheme.accentPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.background,
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 64,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BubbleTrianglePainter extends CustomPainter {
  final Color color;
  BubbleTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

