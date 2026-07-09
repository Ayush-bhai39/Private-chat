import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class EncryptionService {
  EncryptionService._();

  // Generate RSA Key Pair
  static Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>> generateRSAKeyPair() async {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  // Generate and PEM-encode keys in a background thread/isolate to avoid UI freezing
  static Map<String, String> _generateAndEncodeKeyPairHelper(void _) {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    final pubKey = pair.publicKey as RSAPublicKey;
    final privKey = pair.privateKey as RSAPrivateKey;

    return {
      'publicKey': encodePublicKeyToPem(pubKey),
      'privateKey': encodePrivateKeyToPem(privKey),
    };
  }

  static Future<Map<String, String>> generateRSAKeyPairInBackground() async {
    return await compute(_generateAndEncodeKeyPairHelper, null);
  }

  // Encode Public Key to JSON-PEM
  static String encodePublicKeyToPem(RSAPublicKey publicKey) {
    final map = {
      'n': publicKey.modulus.toString(),
      'e': publicKey.exponent.toString(),
    };
    final jsonStr = json.encode(map);
    final base64Str = base64.encode(utf8.encode(jsonStr));
    return '-----BEGIN PUBLIC KEY-----\n$base64Str\n-----END PUBLIC KEY-----';
  }

  // Decode Public Key from JSON-PEM
  static RSAPublicKey decodePublicKeyFromPem(String pem) {
    final base64Str = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .trim();
    final jsonStr = utf8.decode(base64.decode(base64Str));
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    return RSAPublicKey(
      BigInt.parse(map['n'] as String),
      BigInt.parse(map['e'] as String),
    );
  }

  // Encode Private Key to JSON-PEM
  static String encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    final map = {
      'n': privateKey.modulus.toString(),
      'd': privateKey.privateExponent.toString(),
      'p': privateKey.p?.toString() ?? '',
      'q': privateKey.q?.toString() ?? '',
    };
    final jsonStr = json.encode(map);
    final base64Str = base64.encode(utf8.encode(jsonStr));
    return '-----BEGIN PRIVATE KEY-----\n$base64Str\n-----END PRIVATE KEY-----';
  }

  // Decode Private Key from JSON-PEM
  static RSAPrivateKey decodePrivateKeyFromPem(String pem) {
    final base64Str = pem
        .replaceAll('-----BEGIN PRIVATE KEY-----', '')
        .replaceAll('-----END PRIVATE KEY-----', '')
        .replaceAll('\n', '')
        .trim();
    final jsonStr = utf8.decode(base64.decode(base64Str));
    final map = json.decode(jsonStr) as Map<String, dynamic>;
    return RSAPrivateKey(
      BigInt.parse(map['n'] as String),
      BigInt.parse(map['d'] as String),
      map['p'] != '' ? BigInt.parse(map['p'] as String) : null,
      map['q'] != '' ? BigInt.parse(map['q'] as String) : null,
    );
  }

  // Encrypt Message using Hybrid Encryption
  static Map<String, String> encryptMessage(String plaintext, RSAPublicKey recipientPublicKey) {
    final random = Random.secure();
    final aesKeyBytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final ivBytes = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));

    final plainTextBytes = utf8.encode(plaintext);
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    final encryptedTextBytes = aesCipher.process(Uint8List.fromList(plainTextBytes));

    final rsaEngine = OAEPEncoding(RSAEngine());
    rsaEngine.init(true, PublicKeyParameter<RSAPublicKey>(recipientPublicKey));
    final encryptedAesKeyBytes = rsaEngine.process(aesKeyBytes);

    return {
      'encryptedMessage': base64.encode(encryptedTextBytes),
      'encryptedKey': base64.encode(encryptedAesKeyBytes),
      'iv': base64.encode(ivBytes),
    };
  }

  // Decrypt Message using Hybrid Decryption
  static String decryptMessage(
    String encryptedMessageB64,
    String encryptedKeyB64,
    String ivB64,
    RSAPrivateKey privateKey,
  ) {
    final encryptedTextBytes = base64.decode(encryptedMessageB64);
    final encryptedAesKeyBytes = base64.decode(encryptedKeyB64);
    final ivBytes = base64.decode(ivB64);

    final rsaEngine = OAEPEncoding(RSAEngine());
    rsaEngine.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final aesKeyBytes = rsaEngine.process(encryptedAesKeyBytes);

    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    final decryptedBytes = aesCipher.process(encryptedTextBytes);

    return utf8.decode(decryptedBytes);
  }

  // Symmetric Encryption using a key derived from chatId
  static String encryptSymmetric(String plaintext, String keySeed) {
    final keyBytes = _deriveKeyFromSeed(keySeed);
    final random = Random.secure();
    final ivBytes = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
    
    final plainTextBytes = utf8.encode(plaintext);
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
        null,
      ),
    );
    final encryptedBytes = aesCipher.process(Uint8List.fromList(plainTextBytes));
    
    final payload = {
      'iv': base64.encode(ivBytes),
      'ct': base64.encode(encryptedBytes),
    };
    return json.encode(payload);
  }

  // Symmetric Decryption using a key derived from chatId
  static String decryptSymmetric(String encryptedJson, String keySeed) {
    final keyBytes = _deriveKeyFromSeed(keySeed);
    final payload = json.decode(encryptedJson) as Map<String, dynamic>;
    final ivBytes = base64.decode(payload['iv'] as String);
    final encryptedBytes = base64.decode(payload['ct'] as String);
    
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
        null,
      ),
    );
    final decryptedBytes = aesCipher.process(encryptedBytes);
    return utf8.decode(decryptedBytes);
  }

  static Uint8List _deriveKeyFromSeed(String seed) {
    final digest = SHA256Digest();
    final inputBytes = utf8.encode(seed);
    return digest.process(Uint8List.fromList(inputBytes));
  }

  static Uint8List encryptFileBytes(Uint8List plainBytes, Uint8List aesKeyBytes, Uint8List ivBytes) {
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    return aesCipher.process(plainBytes);
  }

  static Uint8List _encryptFileBytesHelper(Map<String, dynamic> params) {
    final plainBytes = params['plainBytes'] as Uint8List;
    final aesKeyBytes = params['aesKeyBytes'] as Uint8List;
    final ivBytes = params['ivBytes'] as Uint8List;
    return encryptFileBytes(plainBytes, aesKeyBytes, ivBytes);
  }

  static Future<Uint8List> encryptFileBytesInBackground(
      Uint8List plainBytes, Uint8List aesKeyBytes, Uint8List ivBytes) async {
    return await compute(_encryptFileBytesHelper, {
      'plainBytes': plainBytes,
      'aesKeyBytes': aesKeyBytes,
      'ivBytes': ivBytes,
    });
  }

  static Uint8List decryptFileBytes(Uint8List encryptedBytes, Uint8List aesKeyBytes, Uint8List ivBytes) {
    final cbc = CBCBlockCipher(AESEngine());
    final aesCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
    aesCipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV<KeyParameter>(KeyParameter(aesKeyBytes), ivBytes),
        null,
      ),
    );
    return aesCipher.process(encryptedBytes);
  }
}
