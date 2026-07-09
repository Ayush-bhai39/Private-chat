import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:secure_chat/models/note_model.dart';
import 'package:secure_chat/models/conversation_model.dart';
import 'package:secure_chat/services/user_service.dart';
import 'package:secure_chat/services/chat_service.dart';
import 'package:secure_chat/services/mock_config.dart';

class NoteService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final UserService _userService = UserService();

  static final Map<String, NoteModel> _mockNotes = {};
  static final StreamController<List<NoteModel>> _mockNotesController = StreamController<List<NoteModel>>.broadcast();
  static final StreamController<NoteModel?> _mockMyNoteController = StreamController<NoteModel?>.broadcast();

  Future<void> createOrUpdateNote(String text) async {
    final user = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (user?.uid ?? '');
    if (uid.isEmpty) throw Exception("User not logged in");

    final userData = await _userService.getUserData(uid);
    if (userData == null) throw Exception("User profile not found");

    final note = NoteModel(
      uid: uid,
      text: text,
      createdAt: DateTime.now(),
      displayName: userData.displayName,
      photoUrl: userData.photoUrl,
    );

    if (MockConfig.useMock) {
      _mockNotes[uid] = note;
      _mockNotesController.add(_getMockNotesList());
      if (uid == "mock_uid_123") {
        _mockMyNoteController.add(note);
      }
      return;
    }

    await _firestore.collection('notes').doc(uid).set(note.toMap());
  }

  List<NoteModel> _getMockNotesList() {
    return _mockNotes.entries
        .where((e) => e.key != "mock_uid_123" && !e.value.isExpired)
        .map((e) => e.value)
        .toList();
  }

  Stream<List<NoteModel>> getNotes() {
    final oneDayAgo = DateTime.now().subtract(const Duration(hours: 24));
    final chatStream = ChatService().getConversations();

    final notesStream = MockConfig.useMock
        ? _mockNotesController.stream
        : _firestore
            .collection('notes')
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(oneDayAgo))
            .snapshots()
            .map((snapshot) {
            return snapshot.docs.map((doc) => NoteModel.fromMap(doc.data())).toList();
          });

    if (MockConfig.useMock) {
      Timer(const Duration(milliseconds: 100), () {
        _mockNotesController.add(_getMockNotesList());
      });
    }

    return Rx.combineLatest2<List<NoteModel>, List<ConversationModel>, List<NoteModel>>(
      notesStream,
      chatStream,
      (notes, conversations) {
        final currentUid = MockConfig.useMock ? "mock_uid_123" : (_auth.currentUser?.uid ?? '');
        final contactedUids = conversations.map((c) => c.otherUser.uid).toSet();

        final filtered = notes.where((note) {
          return note.uid != currentUid && contactedUids.contains(note.uid);
        }).toList();

        return filtered;
      },
    );
  }

  Stream<NoteModel?> getMyNote() {
    if (MockConfig.useMock) {
      Timer(const Duration(milliseconds: 100), () {
        final note = _mockNotes["mock_uid_123"];
        if (note != null && !note.isExpired) {
          _mockMyNoteController.add(note);
        } else {
          _mockMyNoteController.add(null);
        }
      });
      return _mockMyNoteController.stream;
    }
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _firestore.collection('notes').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      final note = NoteModel.fromMap(doc.data()!);
      if (note.isExpired) return null;
      return note;
    });
  }

  Future<void> deleteNote() async {
    final user = MockConfig.useMock ? null : _auth.currentUser;
    final uid = MockConfig.useMock ? "mock_uid_123" : (user?.uid ?? '');
    if (uid.isEmpty) return;

    if (MockConfig.useMock) {
      _mockNotes.remove(uid);
      _mockNotesController.add(_getMockNotesList());
      if (uid == "mock_uid_123") {
        _mockMyNoteController.add(null);
      }
      return;
    }
    await _firestore.collection('notes').doc(uid).delete();
  }
}
