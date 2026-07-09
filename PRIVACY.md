# Privacy Policy for SecureChat

**Last Updated:** July 9, 2026

At SecureChat, we prioritize your privacy above all else. This Privacy Policy describes how we collect, use, store, and disclose your personal data, in compliance with international privacy regulations including the General Data Protection Regulation (GDPR), California Consumer Privacy Act (CCPA), and India's Digital Personal Data Protection Act (DPDPA).

---

## 1. Who We Are (Data Controller)

SecureChat is an open-source, end-to-end encrypted messaging application.
- **Contact:** For privacy queries, please open a secure issue or request support in the GitHub repository.

---

## 2. Personal Data We Collect

To run a functioning peer-to-peer secure messaging service, we collect minimal identifiers:

1. **Account Registration Data:**
   - Email address and password (when registering via email).
   - Display name, email, and Google profile picture reference (when signing in via Google OAuth).
   - A unique username you select.

2. **Encryption Keys (Public Only):**
   - Your RSA public key is uploaded to our secure directory so other users can encrypt messages specifically for your device.
   - **Your RSA private key NEVER leaves your device.** It is stored locally in hardware-backed secure storage.

3. **Active Chat Metadata:**
   - Participant lists (uids) and timestamp markers of the latest message for ordering.
   - The status of messages (sent, delivered, read) to sync indicators.
   - **We do NOT store or transmit message plaintext in metadata.** Message contents are encrypted locally.

4. **Notifications & Push Tokens:**
   - Firebase Cloud Messaging (FCM) push notification tokens to alert you of new incoming messages.

5. **Temporary Stories & Notes:**
   - Self-expiring story posts or brief status notes, stored temporarily on cloud storage and automatically cleared after 24 hours.

---

## 3. Lawful Basis for Processing (GDPR compliance)

We process your data under the following legal bases:
- **Contractual Necessity (Art. 6(1)(b) GDPR):** To deliver the encrypted messaging, notification, and profile lookup services you request.
- **Consent (Art. 6(1)(a) GDPR):** When you opt-in to terms, agree to notifications, or permit camera/microphone access.

---

## 4. End-to-End Encryption Architecture

- All text messages, media attachments, and WebRTC signaling (offers/answers) are encrypted on the sender's device using high-grade hybrid cryptography: **RSA-OAEP-2048 + AES-256-CBC**.
- These payloads can **only** be decrypted by the recipient's matching private key.
- Since we do not possess the private keys, we cannot access, read, or inspect your communications under any circumstances.

---

## 5. Third-Party Services We Use

We restrict third-party integration to the absolute minimum necessary:

- **Google Firebase:** Underpins user authentication, Firestore databases, and FCM notifications.
- **Litterbox (catbox.moe):** An anonymous hosting service used for storing temporary media (stories) that automatically deletes files after 24 hours.
- **ImgBB:** A backup media storage service for image hosting.
- **Google STUN Servers:** Used to establish peer-to-peer WebRTC connections for voice/video calling.

---

## 6. Data Retention Policies

- **User Accounts:** Retained until you delete your account.
- **Messages:** Stored encrypted on Firestore until deleted by you or your recipient.
- **Stories:** Automatically deleted after 24 hours.
- **Notes:** Automatically deleted after 24 hours.

---

## 7. Your Data Rights (GDPR / CCPA / DPDPA)

You hold full control over your data:
- **Right to Access/Portability:** You can download a copy of all your profile, metadata, and history via the in-app **"Export My Data"** option in your Profile screen.
- **Right to Erasure (Right to be Forgotten):** You can instantly delete all your data, messages, files, and Auth credentials from our systems via the in-app **"Delete My Account"** option.
- **Right to Object/Consent Withdrawal:** You can toggle permissions (notifications, camera, mic) off at any point in system settings.

---

## 8. Age Restrictions (COPPA / DPDPA Compliance)

SecureChat is strictly intended for users who are **16 years of age or older**. We do not knowingly collect, maintain, or process personal data from children under the age of 16. If we learn that we have collected personal data from a child under 16 without appropriate consent verification, we will immediately delete that account.
