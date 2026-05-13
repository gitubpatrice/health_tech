import 'dart:ui' show Locale;

import '../../domain/report_template.dart';
import '../repositories/report_template_repository.dart';

/// Sème les 6 templates de comptes rendus par défaut au 1er unlock après
/// l'upgrade vers v1.6.0 (DB v6).
///
/// **Idempotent + transactionnel** (audit v1.6.0 P1 + F4) : la palette est
/// insérée en bloc dans une seule transaction Drift, avec un re-check de
/// `hasAnySystemTemplate()` à l'intérieur de la transaction pour
/// neutraliser une race au double-unlock (deux invocations concurrentes
/// du `FutureProvider`). Si l'utilisateur supprime un template système
/// (autorisé), il ne revient pas — c'est le contrat avec l'utilisateur
/// explicité dans la spec v1.6.0.
class ReportTemplateSeed {
  ReportTemplateSeed(this._repo);

  final ReportTemplateRepository _repo;

  /// Sème la palette par défaut si la table ne contient encore aucun
  /// template système. La locale détermine la langue des canevas (FR par
  /// défaut, EN si `locale.languageCode == 'en'`) — passée par le caller
  /// depuis `PlatformDispatcher.instance.locale` (audit v1.6.0 C8 / G2 —
  /// avant : `Locale('fr')` codé en dur dans la signature).
  Future<void> seedDefaultsIfEmpty({Locale locale = const Locale('fr')}) async {
    // Pré-check rapide hors transaction pour éviter le coût d'ouvrir une
    // transaction si la table est déjà peuplée (cas dominant après le
    // 1er unlock). Le re-check à l'intérieur de la transaction côté
    // `seedSystemDefaults` est la garantie réelle d'idempotence.
    if (await _repo.hasAnySystemTemplate()) return;
    final templates = locale.languageCode == 'en'
        ? _defaultsEn()
        : _defaultsFr();
    await _repo.seedSystemDefaults(templates);
  }

  // ---------------------------------------------------------------------------
  // Canevas FR
  // ---------------------------------------------------------------------------

  List<ReportTemplate> _defaultsFr() => [
    _template(
      name: 'Première séance Reiki — humain',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            "État général à l'arrivée : …\n"
            'Motif de consultation : …\n'
            "Niveau d'énergie ressenti (0-10) : …",
        'client':
            'Le client exprime : …\n'
            'Antécédents énergétiques / soins reçus auparavant : …',
        'observations':
            'Présence : …\n'
            'Respiration : …\n'
            'Posture / tension : …',
        'flow':
            "Position d'accueil et alignement.\n"
            'Passage sur les 7 chakras principaux dans l\'ordre.\n'
            'Temps par zone : … min.\n'
            'Clôture et ancrage.',
        'zones':
            'Chakras travaillés : couronne, frontal, gorge, cœur, '
            'plexus solaire, sacré, racine.\n'
            'Zones complémentaires : …',
        'energetic':
            'Sensations perçues : chaleur / picotements / fraîcheur en …\n'
            'Blocages perçus : …\n'
            'Couleurs / images intuitives : …',
        'after':
            'État après la séance : …\n'
            'Détente ressentie : …\n'
            'Émotions remontées : …',
        'advice':
            'Hydratation abondante les 24 h.\n'
            'Repos / activité douce.\n'
            'Observer rêves et ressentis pendant 3 jours.',
        'next':
            'Séance de suivi suggérée dans … semaines.\n'
            'Approfondissement sur la zone … si besoin.',
      },
    ),
    _template(
      name: 'Séance de suivi — humain',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            'Évolution depuis la dernière séance : …\n'
            'Symptômes / ressentis observés entre les deux séances : …',
        'client':
            'Le client rapporte : …\n'
            'Ce qu\'il a perçu sur les jours suivants : …',
        'observations':
            'Comparaison avec la séance précédente : …\n'
            'Évolution énergétique apparente : …',
        'flow':
            'Reprise du protocole standard adapté à : …\n'
            'Temps insisté sur : …',
        'zones': 'Zones reprises : …\nNouvelles zones explorées : …',
        'energetic':
            'Évolution des ressentis énergétiques : …\n'
            'Apaisement / activation perçus : …',
        'after': 'État après la séance : …\nRetour client : …',
        'advice': 'Continuer / ajuster les recommandations précédentes : …',
        'next':
            'Prochaine séance dans … semaines.\n'
            'Objectif intermédiaire : …',
      },
    ),
    _template(
      name: 'Soin énergétique — animal',
      kind: ReportTemplateKind.animal,
      sections: {
        'before':
            'État général : …\n'
            'Comportement signalé par le propriétaire : …\n'
            'Motif : …',
        'client':
            'Le propriétaire rapporte : …\n'
            'Changements récents (lieu, régime, présence) : …',
        'observations':
            'Attitude au début : agitée / calme / craintive …\n'
            'Position spontanée : …\n'
            'Signes physiques visibles : …',
        'flow':
            "Approche en respectant le rythme de l'animal.\n"
            'Imposition / proximité des mains selon acceptation.\n'
            "Durée : … min (l'animal donne le tempo).",
        'zones':
            'Zones acceptées : …\n'
            'Zones refusées ou évitées : …',
        'energetic':
            "Ressentis sur l'animal : …\n"
            'Émotions perçues : …',
        'after':
            'Comportement après la séance : repos / léchage / '
            'déplacement.\n'
            'Détente visible : …',
        'advice':
            "Laisser l'animal au calme 24-48 h.\n"
            'Eau fraîche à disposition.\n'
            'Observer son comportement les jours suivants.',
        'next':
            "Revoir l'animal dans … semaines si nécessaire.\n"
            'Suivi à distance possible.',
      },
    ),
    _template(
      name: 'Accompagnement fin de vie',
      kind: ReportTemplateKind.other,
      sections: {
        'before':
            'Contexte : …\n'
            'État physique et émotionnel : …\n'
            'Entourage présent : …',
        'client':
            'Paroles partagées : …\n'
            'Émotions exprimées : peur / sérénité / lâcher-prise …',
        'observations':
            'Posture, respiration, regard : …\n'
            "Présence à l'instant : …",
        'flow':
            'Présence silencieuse et bienveillante.\n'
            'Soin énergétique très doux, sans intention de '
            'guérison — accompagnement.\n'
            'Durée adaptée à ce que la personne peut recevoir.',
        'zones':
            'Zones travaillées doucement : cœur, plexus solaire, '
            'couronne.\n'
            'Tenue de main / contact léger : …',
        'energetic':
            'Énergie perçue : …\n'
            'Ouverture / apaisement ressentis : …',
        'after':
            'État après la séance : …\n'
            'Famille / proche présent : retour : …',
        'advice':
            'Honorer le rythme de la personne.\n'
            'Présence aimante, parole sobre, silence accueillant.',
        'next':
            'Disponibilité pour une nouvelle présence selon les '
            'souhaits de la personne et de la famille.',
      },
    ),
    _template(
      name: 'Soin à distance',
      kind: ReportTemplateKind.distance,
      sections: {
        'before':
            'Demande reçue : …\n'
            'Photo / nom / intention partagés.\n'
            'Heure convenue : …',
        'client':
            'Le receveur a exprimé : …\n'
            'Contexte de vie au moment du soin : …',
        'observations':
            'Note du praticien sur sa propre disponibilité : …\n'
            'Conditions du soin (lieu, calme) : …',
        'flow':
            'Centrage et connexion.\n'
            'Visualisation / symboles Reiki à distance.\n'
            'Envoi sur le temps convenu : … min.',
        'zones':
            'Intention portée sur : …\n'
            'Chakras / zones visualisés : …',
        'energetic':
            'Ressentis du praticien : chaleur / images / '
            'intuitions.\n'
            'Difficultés / facilité perçues : …',
        'after':
            'Retour du receveur (par message / téléphone) : …\n'
            'Date du retour : …',
        'advice':
            "Boire de l'eau, repos doux.\n"
            'Noter rêves / ressentis sur 3 jours.',
        'next':
            'Nouvelle séance possible si demandé : …\n'
            'Suivi proposé : …',
      },
    ),
    _template(
      name: 'Bilan énergétique complet',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            'Demande globale : …\n'
            'État physique, émotionnel et mental : …',
        'client':
            'Le client souhaite explorer : …\n'
            'Antécédents : …',
        'observations':
            'Lecture globale : posture, voix, présence.\n'
            'Premières impressions : …',
        'flow':
            'Scan complet des 7 chakras (haut → bas).\n'
            "Lecture de l'aura — couches : éthérique, émotionnelle, "
            'mentale, spirituelle.\n'
            'Durée totale : … min.',
        'zones':
            'Chakra racine : …\n'
            'Chakra sacré : …\n'
            'Plexus solaire : …\n'
            'Cœur : …\n'
            'Gorge : …\n'
            'Frontal : …\n'
            'Couronne : …',
        'energetic':
            'Synthèse énergétique : …\n'
            "Zones d'ancrage : …\n"
            'Zones à libérer : …',
        'after':
            'Synthèse partagée avec le client.\n'
            'État ressenti après le bilan : …',
        'advice':
            'Pistes proposées : …\n'
            'Travail intérieur suggéré : …',
        'next':
            'Séance(s) de soin ciblées proposées sur : …\n'
            'Délai recommandé : … semaines.',
      },
    ),
  ];

  // ---------------------------------------------------------------------------
  // Canevas EN
  // ---------------------------------------------------------------------------

  List<ReportTemplate> _defaultsEn() => [
    _template(
      name: 'First Reiki session — human',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            'Overall state on arrival: …\n'
            'Reason for consultation: …\n'
            'Energy level (0-10): …',
        'client':
            'Client reports: …\n'
            'Past energy work / treatments received: …',
        'observations':
            'Presence: …\n'
            'Breathing: …\n'
            'Posture / tension: …',
        'flow':
            'Centering and alignment.\n'
            'Sweep over the 7 main chakras in order.\n'
            'Time per zone: … min.\n'
            'Closing and grounding.',
        'zones':
            'Chakras worked: crown, third-eye, throat, heart, '
            'solar plexus, sacral, root.\n'
            'Additional zones: …',
        'energetic':
            'Sensations perceived: warmth / tingling / coolness at …\n'
            'Blockages sensed: …\n'
            'Colors / intuitive images: …',
        'after':
            'State after the session: …\n'
            'Relaxation felt: …\n'
            'Emotions surfaced: …',
        'advice':
            'Drink plenty of water for 24 h.\n'
            'Rest or gentle activity.\n'
            'Observe dreams and feelings over 3 days.',
        'next':
            'Follow-up suggested in … weeks.\n'
            'Deeper work on area … if needed.',
      },
    ),
    _template(
      name: 'Follow-up session — human',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            'Evolution since last session: …\n'
            'Symptoms / feelings observed in between: …',
        'client':
            'Client reports: …\n'
            'What was perceived in the following days: …',
        'observations':
            'Comparison with the previous session: …\n'
            'Apparent energy evolution: …',
        'flow':
            'Standard protocol adapted to: …\n'
            'Extended time on: …',
        'zones': 'Areas revisited: …\nNew areas explored: …',
        'energetic':
            'Evolution of energetic sensations: …\n'
            'Soothing / activation perceived: …',
        'after': 'State after the session: …\nClient feedback: …',
        'advice': 'Continue / adjust previous recommendations: …',
        'next':
            'Next session in … weeks.\n'
            'Intermediate goal: …',
      },
    ),
    _template(
      name: 'Energy work — animal',
      kind: ReportTemplateKind.animal,
      sections: {
        'before':
            'Overall state: …\n'
            'Owner-reported behavior: …\n'
            'Reason: …',
        'client':
            'Owner reports: …\n'
            'Recent changes (move, diet, presence): …',
        'observations':
            'Attitude at start: agitated / calm / fearful …\n'
            'Spontaneous position: …\n'
            'Visible physical signs: …',
        'flow':
            "Approach respects the animal's rhythm.\n"
            'Hands-on / proximity depending on acceptance.\n'
            'Duration: … min (animal sets the pace).',
        'zones':
            'Accepted areas: …\n'
            'Refused or avoided areas: …',
        'energetic':
            'Sensations on the animal: …\n'
            'Emotions perceived: …',
        'after':
            'Behavior after the session: rest / licking / moving.\n'
            'Visible relaxation: …',
        'advice':
            'Keep the animal calm for 24-48 h.\n'
            'Fresh water available.\n'
            'Observe behavior in the following days.',
        'next':
            'Recheck the animal in … weeks if needed.\n'
            'Remote follow-up possible.',
      },
    ),
    _template(
      name: 'End-of-life accompaniment',
      kind: ReportTemplateKind.other,
      sections: {
        'before':
            'Context: …\n'
            'Physical and emotional state: …\n'
            'Loved ones present: …',
        'client':
            'Words shared: …\n'
            'Emotions expressed: fear / serenity / letting go …',
        'observations':
            'Posture, breathing, gaze: …\n'
            'Presence in the moment: …',
        'flow':
            'Silent caring presence.\n'
            'Very gentle energy work, with no healing intent — '
            'accompaniment.\n'
            'Duration adapted to what the person can receive.',
        'zones':
            'Areas gently worked: heart, solar plexus, crown.\n'
            'Hand-holding / light touch: …',
        'energetic':
            'Energy felt: …\n'
            'Opening / soothing perceived: …',
        'after':
            'State after the session: …\n'
            'Family / loved one present — feedback: …',
        'advice':
            "Honor the person's rhythm.\n"
            'Loving presence, sparse words, welcoming silence.',
        'next':
            'Availability for another presence according to the '
            "person's and family's wishes.",
      },
    ),
    _template(
      name: 'Remote session',
      kind: ReportTemplateKind.distance,
      sections: {
        'before':
            'Request received: …\n'
            'Photo / name / intention shared.\n'
            'Agreed time: …',
        'client':
            'The receiver expressed: …\n'
            'Life context at the time of the session: …',
        'observations':
            "Practitioner's note on own availability: …\n"
            'Session conditions (place, quietness): …',
        'flow':
            'Centering and connection.\n'
            'Visualization / remote Reiki symbols.\n'
            'Sending over the agreed time: … min.',
        'zones':
            'Intention carried on: …\n'
            'Chakras / areas visualized: …',
        'energetic':
            "Practitioner's sensations: warmth / images / "
            'intuitions.\n'
            'Difficulties / ease felt: …',
        'after':
            'Receiver feedback (by message / phone): …\n'
            'Feedback date: …',
        'advice':
            'Drink water, gentle rest.\n'
            'Write down dreams / feelings over 3 days.',
        'next':
            'Another session possible if requested: …\n'
            'Follow-up proposed: …',
      },
    ),
    _template(
      name: 'Complete energy assessment',
      kind: ReportTemplateKind.human,
      sections: {
        'before':
            'Overall request: …\n'
            'Physical, emotional and mental state: …',
        'client':
            'Client wishes to explore: …\n'
            'Background: …',
        'observations':
            'Overall reading: posture, voice, presence.\n'
            'First impressions: …',
        'flow':
            'Full scan of the 7 chakras (top → bottom).\n'
            'Aura reading — layers: etheric, emotional, mental, '
            'spiritual.\n'
            'Total duration: … min.',
        'zones':
            'Root chakra: …\n'
            'Sacral chakra: …\n'
            'Solar plexus: …\n'
            'Heart: …\n'
            'Throat: …\n'
            'Third eye: …\n'
            'Crown: …',
        'energetic':
            'Energy summary: …\n'
            'Grounding areas: …\n'
            'Areas to release: …',
        'after':
            'Summary shared with the client.\n'
            'State felt after the assessment: …',
        'advice':
            'Suggested paths: …\n'
            'Inner work suggested: …',
        'next':
            'Targeted session(s) suggested on: …\n'
            'Recommended interval: … weeks.',
      },
    ),
  ];

  // ---------------------------------------------------------------------------
  // Helper interne — l'id sera attribué par le repository.
  // ---------------------------------------------------------------------------

  ReportTemplate _template({
    required String name,
    required String kind,
    required Map<String, String> sections,
  }) => ReportTemplate(
    id: '',
    name: name,
    kind: kind,
    sections: sections,
    isSystem: true,
  );
}
