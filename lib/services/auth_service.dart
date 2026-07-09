import 'dart:io';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:secure_chat/services/mock_config.dart';

class MockFirebaseUser {
  final String uid = "mock_uid_123";
  final String? email = "demo@secretchat.com";
  final String? displayName = "Demo User";
  final String? photoURL = "https://picsum.photos/200";
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  GoogleSignIn get _googleSignIn => GoogleSignIn();
  
  static final MockFirebaseUser _mockUser = MockFirebaseUser();
  static bool _mockLoggedIn = false;

  dynamic get currentUser {
    if (MockConfig.useMock) {
      return _mockLoggedIn ? _mockUser : null;
    }
    return _auth.currentUser;
  }

  Stream<dynamic> get authStateChanges {
    if (MockConfig.useMock) {
      return Stream.value(currentUser);
    }
    return _auth.authStateChanges();
  }

  bool get isLoggedIn => currentUser != null;

  Future<dynamic> signInWithGoogle() async {
    if (MockConfig.useMock) {
      _mockLoggedIn = true;
      return _mockUser;
    }
    
    if (Platform.isWindows) {
      return _signInWithGoogleWindows();
    }

    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      print("Google Sign In Error: $e");
      rethrow;
    }
  }

  Future<User?> _signInWithGoogleWindows() async {
    final port = 58239;
    final clientId = "908950949230-b8k4t7o1pet607qv2vhtbuvac7j1re6r.apps.googleusercontent.com";
    final redirectUri = "http://localhost:$port";
    final state = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    final authUrl = "https://accounts.google.com/o/oauth2/v2/auth"
        "?client_id=$clientId"
        "&redirect_uri=${Uri.encodeComponent(redirectUri)}"
        "&response_type=id_token%20token"
        "&scope=openid%20email%20profile"
        "&state=$state"
        "&nonce=$nonce";

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    print("Local OAuth server listening on $redirectUri");

    try {
      await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      await server.close(force: true);
      throw Exception("Failed to launch default system browser: $e");
    }

    final completer = Completer<Map<String, String>>();

    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      if (path == "/") {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
          <!DOCTYPE html>
          <html>
          <head>
            <meta charset="utf-8">
            <title>Secret Chat - Authenticating</title>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                background-color: #0A0A0F;
                color: #FFFFFF;
                display: flex;
                flex-direction: column;
                align-items: center;
                justify-content: center;
                height: 100vh;
                margin: 0;
              }
              .card {
                background-color: #12121E;
                border: 1px solid rgba(255,255,255,0.06);
                padding: 40px;
                border-radius: 20px;
                text-align: center;
                box-shadow: 0 10px 30px rgba(0,0,0,0.5);
                max-width: 400px;
              }
              h2 {
                color: #6C63FF;
                margin-top: 0;
              }
              p {
                color: #8888A0;
                font-size: 14px;
                line-height: 1.5;
              }
              .loader {
                border: 3px solid rgba(255,255,255,0.1);
                border-radius: 50%;
                border-top: 3px solid #6C63FF;
                width: 24px;
                height: 24px;
                animation: spin 1s linear infinite;
                margin: 20px auto;
              }
              @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
              }
            </style>
          </head>
          <body>
            <div class="card">
              <h2>Connecting to Secret Chat...</h2>
              <div class="loader"></div>
              <p>Completing the secure login flow. Please keep this window open.</p>
            </div>
            <script>
              const hash = window.location.hash.substring(1);
              if (hash) {
                fetch("/callback?" + hash)
                  .then(() => {
                    document.body.innerHTML = `
                      <div class="card">
                        <h2 style="color: #4BB543;">Success!</h2>
                        <p>Sign-in completed successfully. You can close this tab and return to the Secret Chat app.</p>
                      </div>
                    `;
                  })
                  .catch(err => {
                    document.body.innerHTML = `
                      <div class="card">
                        <h2 style="color: #FF9494;">Connection Error</h2>
                        <p>Failed to send login credentials back to the application.</p>
                      </div>
                    `;
                  });
              } else {
                document.body.innerHTML = `
                  <div class="card">
                    <h2 style="color: #FF9494;">Auth Failed</h2>
                    <p>No authentication credentials found. Please try logging in again.</p>
                  </div>
                `;
              }
            </script>
          </body>
          </html>
        ''');
        await request.response.close();
      } else if (path == "/callback") {
        final queryParams = request.uri.queryParameters;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"status": "ok"}');
        await request.response.close();

        if (!completer.isCompleted) {
          completer.complete(queryParams);
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });

    try {
      final result = await completer.future.timeout(const Duration(minutes: 3));
      await server.close(force: true);

      final idToken = result['id_token'];
      final accessToken = result['access_token'];

      if (idToken == null || accessToken == null) {
        throw Exception("Authentication tokens missing from callback.");
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      await server.close(force: true);
      throw Exception("Sign-in timed out or failed: $e");
    }
  }

  Future<dynamic> signInWithEmailAndPassword(String email, String password) async {
    if (MockConfig.useMock) {
      _mockLoggedIn = true;
      return _mockUser;
    }
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      print("Email Sign In Error: $e");
      rethrow;
    }
  }

  Future<dynamic> signUpWithEmailAndPassword(String email, String password) async {
    if (MockConfig.useMock) {
      _mockLoggedIn = true;
      return _mockUser;
    }
    try {
      final UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } catch (e) {
      print("Email Sign Up Error: $e");
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (MockConfig.useMock) {
      print("Password reset email sent to $email (Mock Mode)");
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      print("Password Reset Error: $e");
      rethrow;
    }
  }

  Future<void> sendEmailVerification() async {
    if (MockConfig.useMock) {
      print("Email verification sent (Mock Mode)");
      return;
    }
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      print("Send Email Verification Error: $e");
      rethrow;
    }
  }

  Future<bool> isEmailVerified() async {
    if (MockConfig.useMock) return true;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        return _auth.currentUser!.emailVerified;
      }
    } catch (e) {
      print("Check Email Verification Error: $e");
    }
    return false;
  }

  Future<void> signOut() async {
    if (MockConfig.useMock) {
      _mockLoggedIn = false;
      return;
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
