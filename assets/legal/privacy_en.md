# Privacy Policy — Health Tech

_Version 1.2 — applicable from 10 May 2026._

_Compliant with Regulation (EU) 2016/679 (GDPR)._

---

## 1. General principles

The Health Tech application ("the Application") runs **entirely locally** on the user's Android device.

No personal data:
- is transmitted to the Publisher (Patrice Haltaya / Files Tech);
- is collected remotely;
- is sold, shared, rented or used for commercial purposes;
- is used for profiling, advertising or behavioural analysis.

The Application contains **no cookies**, **no tracking pixels**, **no advertising SDK**, **no analytics tools** (Google Analytics, Firebase Analytics, Sentry, Crashlytics, etc.).

---

## 2. Publisher's GDPR positioning

**The Publisher is neither a data controller nor a data processor** within the meaning of Articles 4(7) and 4(8) of the GDPR.

The Publisher only provides free software. They:
- have **no access** to the data recorded by the user;
- carry out **no processing operation** on the data;
- operate **no server** or online service as part of the Application's functioning;
- cannot be bound by any data processing agreement under Article 28 GDPR.

**The sole data controller is the professional user** who records and uses the data in the course of their activity.

---

## 3. Data recorded by the user

The user may record in the Application, **on their device only**:
- client information (identity, contact details, profession, address);
- follow-up and session notes;
- appointments;
- information about animals (species, breed, identifiers, care);
- observations related to wellness or holistic support practices;
- attachments (photos, documents).

These data:
- remain **stored exclusively on the user's device**;
- are **encrypted at rest** by default (SQLCipher AES-256);
- are subject to **second-level field encryption** (AES-GCM) for wellness notes, session reports and attachments.

---

## 4. No server connection

The Application:
- requires **no user account**;
- does **not synchronise** data over the Internet;
- does **not transmit** data to a remote server;
- does **not communicate** with the Publisher in any way;
- contains **no advertising system**;
- contains **no tracker** or behavioural analytics tool;
- **requests no network permission** for its core functioning.

The user may **optionally** enable:
- the **synchronisation of an appointment** to the system Android calendar (Google Calendar or other) — explicit per-appointment opt-in, transmitting only the date, title and location chosen by the user;
- the **sharing** of a session PDF export or an encrypted backup via the Android share sheet (mail, cloud, message) — the destination then becomes a de facto processor chosen by the user.

The Publisher has no control over and no visibility into these operations voluntarily triggered by the user.

---

## 5. Data security

The Application implements the following technical measures:
- SQLCipher database encryption (AES-256);
- field-level encryption of each sensitive field (AES-GCM);
- master key derivation via Argon2id 64 MiB;
- **optional biometrics** (BiometricPrompt + Android Keystore key invalidated when fingerprints change);
- configurable auto-lock;
- screenshot blocking (FLAG_SECURE);
- exclusion from all automatic Android cloud backup;
- no data leaves the device without explicit user action.

The user nevertheless remains **solely responsible for**:
- the physical protection of their device (lock screen, device encryption, no lending);
- their backups (regular export via the "Encrypted backup" feature to a safe location);
- the confidentiality of the passphrase, which cannot be recovered by any means;
- the confidentiality of the data recorded with respect to third parties having access to their device.

It is strongly recommended to use:
- a robust passphrase (at least 12 characters with real entropy);
- a biometric lock on the device;
- enabled device encryption;
- the "Encrypted backup" feature of the Application at least once a week.

---

## 6. Sensitive data and user obligations

Some information recorded may be considered **sensitive data** under Article 9 of the GDPR when it reveals a health condition.

The user, as **data controller**, undertakes to comply in particular with:
- the **explicit consent** of every person whose data is recorded (Art. 9.2.a GDPR) — the Application provides dedicated checkboxes in the client form to materialise this consent;
- the **retention periods** appropriate to their activity;
- the **data subject rights** (access, rectification, erasure, objection, restriction, portability);
- the **notification of any data breach** to the supervisory authority and to the data subjects;
- the keeping of a **record of processing activities** when required;
- the **confidentiality** of information regarding their clients and their animals.

The Application provides technical features to facilitate compliance with these obligations:
- full GDPR export of a client record (Article 15 GDPR);
- definitive erasure of a client record (Article 17 GDPR);
- encrypted backup for portability (Article 20 GDPR).

The use and configuration of these features are the sole responsibility of the user.

---

## 7. Android permissions

The Application requests only the permissions strictly necessary for its functioning:

| Permission | Use | Optional? |
|---|---|---|
| `READ_CALENDAR` / `WRITE_CALENDAR` | Sync an appointment to the system calendar | Yes (per-appointment opt-in) |
| `POST_NOTIFICATIONS` | Display appointment reminders | Yes (Android 13+) |
| `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` | Schedule reminders at the exact time | No (core functional) |
| `RECEIVE_BOOT_COMPLETED` | Reschedule reminders after device reboot | No |

The Application **does not request**: Internet, contacts access, SMS access, external storage access, location, camera, sensors, etc.

---

## 8. Free software — Verifiability

Since the source code of the application is publicly accessible (after the testing phase) under the Apache 2.0 license, **anyone can verify** the actual behaviour of the application, its data handling and the absence of any hidden network communication.

License: [https://www.apache.org/licenses/LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0)

---

## 9. Data retention

Data is kept **only on the user's device** until:
- manually deleted via the Application's features;
- the Application is uninstalled;
- data is cleared via Android Settings.

The user acknowledges that uninstallation results in the **definitive and irreversible loss** of recorded data (unless a previously exported `.htbk` backup is restored).

---

## 10. Data subject rights

Natural persons whose data is recorded in the Application by a professional user may exercise their GDPR rights (access, rectification, erasure, objection, restriction, portability) **directly with the professional user** who recorded them, and who is their sole data controller.

The Publisher, having no access to the data, cannot directly respond to such requests. They may forward a request received by mistake to the relevant professional user if identifiable, but without guarantee.

---

## 11. Modification of this policy

The Publisher may modify this Privacy Policy at any time, in particular to reflect changes in the software or in regulations.

The applicable version is the one accessible in the Application via **Settings → Legal documents** at the time of use.

---

## 12. Contact

For any question relating to this Privacy Policy:

**contact@files-tech.com**

The user may also exercise their rights or ask questions to the French data protection authority, the CNIL:
[https://www.cnil.fr](https://www.cnil.fr)
