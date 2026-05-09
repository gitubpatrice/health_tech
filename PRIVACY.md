# Politique de confidentialité — Health Tech

_Version 0.1.0 — 9 mai 2026_

## En une phrase

**Health Tech ne transmet aucune donnée à qui que ce soit.** Toutes les informations restent sur ton appareil, chiffrées.

## Données traitées

L'application stocke localement, sur ton appareil uniquement :

- identité et coordonnées des clients (nom, prénom, contact, adresse) ;
- informations relatives à la santé physique et émotionnelle, y compris **données sensibles au sens de l'article 9 du RGPD** ;
- fiches animaux (espèce, race, antécédents, identifiants) ;
- comptes rendus de séances et notes du praticien ;
- rendez-vous (dates, lieux, statuts) ;
- documents et photos joints aux fiches.

## Aucun service tiers

- Aucune connexion réseau pour transmettre des données client.
- Aucune télémétrie, aucun crash reporting automatique.
- Aucun identifiant publicitaire collecté.
- Aucun compte cloud requis.

L'application demande la permission d'accéder au calendrier Android local **uniquement si tu actives la synchronisation agenda**. Les événements créés restent sur l'appareil et suivent les règles du calendrier que tu choisis.

## Sauvegarde Android

L'application **désactive explicitement la sauvegarde Android automatique** (`allowBackup="false"`). Tes données ne sont pas copiées vers Google Drive sans action explicite de ta part.

## Chiffrement

- Base de données chiffrée avec SQLCipher (AES-256).
- Champs sensibles re-chiffrés au niveau colonne avec AES-256-GCM.
- Clé maîtresse dérivée de ta phrase secrète via Argon2id (paramètres : 64 MiB, 3 itérations).
- Verrouillage automatique après inactivité.
- Protection écran (`FLAG_SECURE`) pour bloquer les captures d'écran.

## Tes droits (RGPD)

- **Droit d'accès et de portabilité** : la fonction "Exporter" génère un PDF ou un ZIP chiffré avec toutes les données d'un client.
- **Droit à l'effacement** : la suppression d'un client supprime physiquement les données et écrase les fichiers joints.
- **Pas de profilage automatisé**.

Comme l'application est entièrement locale, **toi seul es responsable du traitement** de ces données dans le cadre de ton activité professionnelle.

## Avertissement médical

Les séances proposées par l'utilisateur de cette application s'inscrivent dans une démarche de bien-être et d'accompagnement énergétique. Elles ne remplacent ni un avis médical, ni un diagnostic, ni un traitement prescrit par un professionnel de santé ou un vétérinaire.

## Contact

contact@files-tech.com

---

# Privacy Policy — Health Tech (English)

_Version 0.1.0 — 9 May 2026_

## In one sentence

**Health Tech does not transmit any data to anyone.** All information stays on your device, encrypted.

## Data processed

The application stores locally, on your device only:

- client identity and contact details (name, address, phone, email);
- physical and emotional health information, including **sensitive data within the meaning of GDPR Article 9**;
- animal records (species, breed, history, identifiers);
- session reports and practitioner notes;
- appointments (dates, locations, statuses);
- documents and photos attached to records.

## No third-party services

- No network connection is used to transmit client data.
- No telemetry, no automatic crash reporting.
- No advertising identifiers collected.
- No cloud account required.

The application asks for permission to access the local Android calendar **only if you enable agenda synchronisation**. Events created stay on the device and follow the rules of the calendar you choose.

## Android backup

The application **explicitly disables automatic Android backup** (`allowBackup="false"`). Your data is not copied to Google Drive without an explicit action on your part.

## Encryption

- Database encrypted with SQLCipher (AES-256).
- Sensitive fields re-encrypted at column level with AES-256-GCM.
- Master key derived from your passphrase via Argon2id (parameters: 64 MiB, 3 iterations).
- Automatic locking after inactivity.
- Screen protection (`FLAG_SECURE`) to block screenshots.

## Your rights (GDPR)

- **Right of access and portability**: the "Export" function generates a PDF or an encrypted ZIP with all data for a client.
- **Right to erasure**: deleting a client physically removes the data and overwrites attached files.
- **No automated profiling**.

As the application is entirely local, **you alone are responsible for processing** this data in the context of your professional activity.

## Medical disclaimer

The sessions offered by the user of this application are part of a wellness and energetic accompaniment approach. They do not replace medical advice, a diagnosis, or a treatment prescribed by a health or veterinary professional.

## Contact

contact@files-tech.com
