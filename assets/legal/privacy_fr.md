# Politique de confidentialité — Health Tech

_Version 1.2 — applicable à compter du 10 mai 2026._

_Conforme au Règlement (UE) 2016/679 (RGPD)._

---

## 1. Principes généraux

L'application Health Tech (« l'Application ») fonctionne **intégralement en local** sur l'appareil Android de l'utilisateur.

Aucune donnée personnelle :
- n'est transmise à l'Éditeur (Patrice Haltaya / Files Tech) ;
- n'est collectée à distance ;
- n'est vendue, partagée, louée ou exploitée à des fins commerciales ;
- n'est utilisée pour du profilage, de la publicité ou de l'analyse comportementale.

L'Application ne contient **aucun cookie**, **aucun pixel de tracking**, **aucun SDK publicitaire**, **aucun outil d'analyse** (Google Analytics, Firebase Analytics, Sentry, Crashlytics, etc.).

---

## 2. Positionnement de l'Éditeur au regard du RGPD

**L'Éditeur n'est ni responsable de traitement, ni sous-traitant** au sens des articles 4(7) et 4(8) du RGPD.

L'Éditeur fournit uniquement un logiciel libre. Il :
- n'a **aucun accès** aux données enregistrées par l'utilisateur ;
- ne réalise **aucune opération de traitement** sur les données ;
- n'opère **aucun serveur** ou service en ligne dans le cadre du fonctionnement de l'Application ;
- ne saurait être engagé par un quelconque contrat de sous-traitance au sens de l'article 28 du RGPD.

**Le seul responsable de traitement est l'utilisateur professionnel** qui enregistre et utilise les données dans le cadre de son activité.

---

## 3. Données enregistrées par l'utilisateur

L'utilisateur peut enregistrer dans l'Application, **sur son seul appareil** :
- des informations clients (identité, contact, profession, adresse) ;
- des notes de suivi et de séance ;
- des rendez-vous ;
- des informations relatives à des animaux (espèce, race, identifiants, soins) ;
- des observations liées à des pratiques de bien-être ou d'accompagnement holistique ;
- des pièces jointes (photos, documents).

Ces données :
- restent **exclusivement stockées sur l'appareil** de l'utilisateur ;
- sont **chiffrées au repos** par défaut (SQLCipher AES-256) ;
- font l'objet d'un **second chiffrement par champ** (AES-GCM) pour les notes de bien-être, comptes rendus et pièces jointes.

---

## 4. Absence de connexion serveur

L'Application :
- ne nécessite **aucun compte utilisateur** ;
- **ne synchronise pas** les données sur Internet ;
- **ne transmet pas** les données vers un serveur distant ;
- **ne communique pas** avec l'Éditeur de quelque manière que ce soit ;
- ne contient **aucun système publicitaire** ;
- ne contient **aucun tracker** ni outil d'analyse comportementale ;
- **ne demande aucune permission réseau** pour son fonctionnement principal.

L'utilisateur peut activer **optionnellement** :
- la **synchronisation d'un rendez-vous** vers le calendrier système Android (Google Calendar ou autre) — opt-in explicite par rendez-vous, transmettant uniquement la date, le titre et le lieu choisis par l'utilisateur ;
- le **partage** d'un export PDF de séance ou d'une sauvegarde chiffrée via le sélecteur de partage Android (mail, cloud, message) — la destination devient alors un sous-traitant de fait choisi par l'utilisateur.

L'Éditeur n'a aucun contrôle ni aucune visibilité sur ces opérations volontairement déclenchées par l'utilisateur.

---

## 5. Sécurité des données

L'Application met en œuvre les mesures techniques suivantes :
- chiffrement de la base de données SQLCipher (AES-256) ;
- chiffrement de chaque champ sensible (AES-GCM) ;
- dérivation de la clé maître par Argon2id 64 MiB ;
- **biométrie optionnelle** (BiometricPrompt + clé Keystore Android invalidée en cas de modification des empreintes) ;
- verrouillage automatique paramétrable ;
- blocage de la capture d'écran (FLAG_SECURE) ;
- exclusion de toute sauvegarde Android automatique vers le cloud ;
- aucune donnée ne quitte l'appareil sans action explicite de l'utilisateur.

L'utilisateur demeure néanmoins **seul responsable** :
- de la protection physique de son appareil (verrouillage écran, chiffrement device, non-prêt) ;
- de ses sauvegardes (export régulier de la fonction « Sauvegarde chiffrée » vers un emplacement sûr) ;
- de la confidentialité de la phrase secrète, qui ne peut être récupérée par aucun moyen ;
- de la confidentialité des données enregistrées vis-à-vis de tiers ayant accès à son appareil.

Il est fortement recommandé d'utiliser :
- une phrase secrète robuste (au moins 12 caractères avec une réelle entropie) ;
- un verrouillage biométrique de l'appareil ;
- un chiffrement device activé ;
- la fonction « Sauvegarde chiffrée » de l'Application au moins une fois par semaine.

---

## 6. Données sensibles et obligations de l'utilisateur

Certaines informations enregistrées peuvent être considérées comme **données sensibles** au sens de l'article 9 du RGPD lorsqu'elles révèlent un état de santé.

L'utilisateur, en sa qualité de **responsable de traitement**, s'engage à respecter notamment :
- le **consentement explicite** de chaque personne dont il enregistre les données (art. 9.2.a RGPD) — l'Application met à disposition des cases à cocher dédiées dans le formulaire client pour matérialiser ce consentement ;
- les **durées de conservation** appropriées à son activité ;
- les **droits des personnes concernées** (accès, rectification, effacement, opposition, limitation, portabilité) ;
- la **notification d'éventuelles violations** à la CNIL et aux personnes concernées ;
- la tenue d'un **registre des traitements** lorsque cela est requis ;
- la **confidentialité** des informations concernant ses clients et leurs animaux.

L'Application met à disposition des fonctions techniques pour faciliter le respect de ces obligations :
- export RGPD complet d'un dossier client (Article 15 RGPD) ;
- effacement définitif d'un dossier client (Article 17 RGPD) ;
- sauvegarde chiffrée pour la portabilité (Article 20 RGPD).

L'utilisation et la mise en œuvre de ces fonctions relèvent de la seule responsabilité de l'utilisateur.

---

## 7. Permissions Android

L'Application demande uniquement les permissions strictement nécessaires à son fonctionnement :

| Permission | Usage | Optionnelle ? |
|---|---|---|
| `READ_CALENDAR` / `WRITE_CALENDAR` | Synchroniser un rendez-vous vers le calendrier système | Oui (opt-in par rendez-vous) |
| `POST_NOTIFICATIONS` | Afficher les rappels de rendez-vous | Oui (Android 13+) |
| `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` | Planifier les rappels à l'heure exacte | Non (cœur fonctionnel) |
| `RECEIVE_BOOT_COMPLETED` | Replanifier les rappels après redémarrage de l'appareil | Non |

L'Application **ne demande pas** : Internet, accès aux contacts, accès aux SMS, accès aux fichiers externes, accès à la localisation, accès à la caméra, accès aux capteurs, etc.

---

## 8. Logiciel libre — Vérifiabilité

Le code source de l'application étant accessible publiquement (à l'issue de la phase de test) sous licence Apache 2.0, **chacun peut vérifier** le fonctionnement réel de l'application, ses traitements de données et l'absence de toute communication réseau cachée.

Licence : [https://www.apache.org/licenses/LICENSE-2.0](https://www.apache.org/licenses/LICENSE-2.0)

---

## 9. Conservation des données

Les données sont conservées **uniquement sur l'appareil** de l'utilisateur jusqu'à :
- leur suppression manuelle via les fonctions de l'Application ;
- la désinstallation de l'Application ;
- l'effacement des données via les Réglages Android.

L'utilisateur reconnaît que la désinstallation entraîne la **perte définitive et irréversible** des données enregistrées (sauf restauration d'une sauvegarde `.htbk` préalablement exportée).

---

## 10. Droits des personnes concernées

Les personnes physiques dont les données sont enregistrées dans l'Application par un utilisateur professionnel peuvent exercer leurs droits RGPD (accès, rectification, effacement, opposition, limitation, portabilité) **directement auprès de l'utilisateur professionnel** qui les a enregistrées, et qui en est le seul responsable de traitement.

L'Éditeur, n'ayant aucun accès aux données, ne peut pas répondre directement à de telles demandes. Il pourra orienter une demande reçue par erreur vers l'utilisateur professionnel concerné si celui-ci est identifiable, mais sans garantie.

---

## 11. Modification de la présente politique

L'Éditeur peut modifier la présente Politique de confidentialité à tout moment, notamment pour refléter une évolution du logiciel ou de la réglementation.

La version applicable est celle accessible dans l'Application via **Paramètres → Documents légaux** au moment de l'utilisation.

---

## 12. Contact

Pour toute question relative à la présente Politique de confidentialité :

**contact@files-tech.com**

L'utilisateur peut également exercer ses droits ou poser des questions à l'autorité de contrôle française, la CNIL :
[https://www.cnil.fr](https://www.cnil.fr)
