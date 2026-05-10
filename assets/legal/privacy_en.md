# Privacy policy

_Health Tech — v1.1 — GDPR (Regulation (EU) 2016/679)._

> **The user of the application is the SOLE PARTY RESPONSIBLE for the use they make of it, including the processing of personal data they record in it.** By installing and using Health Tech, the user agrees to use the application in a responsible manner and acknowledges that they are solely responsible for its use.

## 1. Data controller

The professional user of the application is the **sole data controller** within the meaning of GDPR Article 4. The publisher (Files Tech) processes no client data: Health Tech runs entirely on the user's device, with no intermediary server. **Files Tech cannot be held liable for the GDPR compliance of the processing carried out by the user** (consent of data subjects, retention periods, follow-up on rights, physical security of the device, etc.).

## 2. Categories of data collected

Stored locally and encrypted on the device:

- **Identity & contact**: last name, first name, civility, date of birth, phone, email, address, profession.
- **Animal information** (if applicable): name, species, breed, sex, identifiers (chip, tattoo, pedigree), weight, history, behaviour, vet contact.
- **Business / site information** (if applicable): company name, registration numbers, type of place, site observations, recommendations.
- **Wellness notes**: emotional state, fatigue, sleep, perceived pain. These are **not "health data" in the strict medical sense** (they are not produced as part of a medical act) but qualify as **sensitive data under GDPR** when they reveal a state of health.
- **Session reports**: state before/after, perceptions, observations, advice.
- **Appointments**: date, place, status, reminders.
- **Attachments**: animal photos, documents shared by the client.

## 3. Legal bases

- **Explicit consent** of the client (Articles 6.1.a and 9.2.a GDPR), collected via the mandatory checkboxes in the client form.
- **Legitimate interest** of the practitioner in keeping a follow-up record (Article 6.1.f).

## 4. Purposes

- Maintaining the client / animal / site record for the quality of services.
- Preparing and writing session reports.
- Managing appointments.
- Optional invoicing.

**No** profiling, marketing, resale, or third-party analytics.

## 5. Retention

The professional user determines the retention period. Indicative defaults:
- **5 years** after the last session for routine client records.
- **10 years** for accounting data (invoices, payments).

The user is invited to delete records that no longer need to be kept, via **Settings → Right to erasure**.

## 6. Security

- Personal passphrase (12 characters minimum, derived via Argon2id 64 MiB).
- AES-256 encryption at rest (SQLCipher).
- Sensitive fields (health notes, session reports, attachments) re-encrypted at column level (AES-GCM).
- Configurable auto-lock.
- Screenshot blocking (FLAG_SECURE).
- No automatic Android cloud backup.
- No transfer off device without explicit user action.

## 7. Sub-processors

- **None** for the core data flow (the app is 100 % local).
- If the user opts in to **Add to system calendar**, only **appointment metadata** (title, date, place, duration) is passed to the device's Calendar app (often Google Calendar). No client name, no health note, no session content is included unless the user voluntarily puts it in the title.
- PDF and GDPR ZIP exports go through the Android share sheet — the user picks the destination (mail, cloud, message). From that moment, the destination becomes a de facto sub-processor.

## 8. Data subject rights (GDPR Articles 15-22)

The client may request from the professional user:
- **Access** → **Settings → Right to data portability** generates a complete ZIP.
- **Rectification** → edit the record directly.
- **Erasure** → **Settings → Right to erasure** permanently removes the client + animals + sessions + attachments + linked calendar events.
- **Objection**, **Restriction**, **Portability** (JSON included in the ZIP).

The professional user must respond within one month.

## 9. Minors

Processing data of a minor client requires parental consent (GDPR Article 8). The professional user is responsible for collecting it before any data entry.

## 10. Complaints

If a complaint cannot be resolved with the professional user, the client can lodge it with their local data protection authority (CNIL in France: [www.cnil.fr](https://www.cnil.fr)).

## 11. Contact

contact@files-tech.com
