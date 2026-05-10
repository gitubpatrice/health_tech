# Politique de confidentialité

_Health Tech — version v1.1 — RGPD (Règlement (UE) 2016/679)._

> **L'utilisateur de l'application est SEUL RESPONSABLE de l'usage qu'il en fait, y compris du traitement des données personnelles qu'il y enregistre.** En installant et en utilisant Health Tech, l'utilisateur accepte d'utiliser l'application de façon responsable et reconnaît qu'il est le seul responsable de son utilisation.

## 1. Responsable de traitement

L'utilisateur professionnel de l'application est **seul responsable du traitement** au sens de l'article 4 du RGPD. L'éditeur de l'application (Files Tech) ne traite aucune donnée client : Health Tech est exécutée intégralement sur l'appareil de l'utilisateur, sans serveur intermédiaire. **Files Tech ne peut être tenu responsable de la conformité RGPD du traitement opéré par l'utilisateur** (consentement des personnes concernées, durées de conservation, suites données aux droits, sécurité physique de l'appareil, etc.).

## 2. Catégories de données collectées

L'application stocke localement, chiffrées sur l'appareil :

**Identité et contact** — nom, prénom, civilité, date de naissance, téléphone, email, adresse, profession.

**Informations sur l'animal** (le cas échéant) — nom, espèce, race, sexe, identifiants (puce, tatouage, pedigree), poids, antécédents, comportement, vétérinaire référent.

**Informations entreprise / lieu** (le cas échéant) — raison sociale, SIRET, SIREN, type de lieu, observations site et recommandations.

**Notes de bien-être** — l'utilisateur peut consigner des observations relatives au mieux-être ressenti par le client (état émotionnel, fatigue, sommeil, douleurs perçues). Ces données ne sont **pas des données de santé au sens médical strict** (article L.1110-4 CSP) car elles ne sont pas produites dans le cadre d'un acte médical. Elles relèvent toutefois de données **sensibles RGPD** lorsqu'elles révèlent un état de santé — l'utilisateur s'engage à les traiter avec la même rigueur.

**Comptes rendus de séance** — état avant/après, ressenti, observations, conseils.

**Rendez-vous** — date, lieu, statut, rappels.

**Pièces jointes** — photos d'animaux, documents transmis par le client (consentements, ordonnances vétérinaires éventuelles).

## 3. Bases légales

- **Consentement explicite** du client (article 6.1.a et 9.2.a RGPD), recueilli via les cases obligatoires de la fiche client lors de la création.
- **Intérêt légitime** du praticien à tenir un dossier de suivi pour la qualité de sa prestation (article 6.1.f).

## 4. Finalités

- Tenue du dossier client / animal / lieu pour le suivi des prestations.
- Préparation et compte rendu des séances.
- Gestion des rendez-vous.
- Facturation éventuelle.

**Aucune** des finalités suivantes n'est mise en œuvre : profilage, marketing ciblé, revente, statistique anonymisée transmise à un tiers.

## 5. Durée de conservation

L'utilisateur professionnel détermine la durée de conservation en fonction de son cadre. À titre indicatif :
- **5 ans** après la dernière prestation pour la tenue de dossier client courante ;
- **10 ans** pour les données comptables (factures, paiements).

L'utilisateur est invité à supprimer les fiches dont la conservation n'est plus justifiée, via le bouton **Effacement définitif** dans Paramètres.

## 6. Sécurité

- Phrase secrète personnelle (12 caractères minimum, dérivée par Argon2id 64 MiB).
- Base de données chiffrée AES-256 (SQLCipher) au repos.
- Champs sensibles (notes santé, comptes rendus, pièces jointes) chiffrés une seconde fois au niveau colonne (AES-GCM).
- Verrouillage automatique paramétrable.
- Capture d'écran bloquée (FLAG_SECURE).
- Aucune sauvegarde Android automatique vers le cloud.
- Aucun transfert hors de l'appareil sans action explicite.

## 7. Sous-traitants

- **Aucun sous-traitant cloud n'a accès aux données** (l'application est 100 % locale).
- Si l'utilisateur active l'**ajout au calendrier système** Android, les informations du **rendez-vous uniquement** (titre, date, lieu, durée) sont transmises à l'application Calendrier de l'appareil (souvent Google Calendar). Aucune donnée santé, aucune note de séance, aucun nom de client n'est transmis dans la description sauf si l'utilisateur l'inclut volontairement dans le titre.
- L'export PDF d'une séance et l'export ZIP RGPD passent par le menu de partage Android — c'est l'utilisateur qui choisit l'application destinataire (mail, cloud, message). À partir du moment où il partage, ce destinataire devient sous-traitant de fait.

## 8. Droits des personnes (articles 15 à 22 RGPD)

Le client peut demander à l'utilisateur professionnel :
- **Accès** à ses données → **Paramètres → Droit à la portabilité (RGPD)** génère un ZIP complet.
- **Rectification** → modifier la fiche directement.
- **Effacement** → **Paramètres → Droit à l'effacement (RGPD)** supprime définitivement le client + animaux + séances + pièces jointes + événements de calendrier associés.
- **Opposition** au traitement.
- **Limitation** du traitement.
- **Portabilité** au format JSON (inclus dans le ZIP).

L'utilisateur professionnel est tenu d'honorer ces demandes dans un délai d'un mois.

## 9. Mineurs

Le traitement des données d'un client mineur requiert l'accord parental (article 8 RGPD). L'utilisateur professionnel est responsable de recueillir cet accord en dehors de l'application avant toute saisie.

## 10. Réclamation

En cas de litige non résolu directement avec l'utilisateur professionnel, le client peut saisir la CNIL : [www.cnil.fr](https://www.cnil.fr).

## 11. Contact

contact@files-tech.com
