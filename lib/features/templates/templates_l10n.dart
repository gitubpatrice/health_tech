import '../../domain/lifestyle.dart';
import '../../domain/report_template.dart';
import '../../l10n/generated/app_localizations.dart';

/// Libellé localisé pour un [ReportTemplateKind].
String reportTemplateKindLabel(AppL10n l10n, String kind) {
  switch (kind) {
    case ReportTemplateKind.human:
      return l10n.templatesKindHuman;
    case ReportTemplateKind.animal:
      return l10n.templatesKindAnimal;
    case ReportTemplateKind.duo:
      return l10n.templatesKindDuo;
    case ReportTemplateKind.distance:
      return l10n.templatesKindDistance;
    case ReportTemplateKind.other:
      return l10n.templatesKindOther;
    default:
      return kind;
  }
}

/// Libellé localisé pour une [ContactSource].
String contactSourceLabel(AppL10n l10n, String? source) {
  switch (source) {
    case ContactSource.wordOfMouth:
      return l10n.contactSourceWordOfMouth;
    case ContactSource.website:
      return l10n.contactSourceWebsite;
    case ContactSource.socialMedia:
      return l10n.contactSourceSocialMedia;
    case ContactSource.recommendation:
      return l10n.contactSourceRecommendation;
    case ContactSource.localPress:
      return l10n.contactSourceLocalPress;
    case ContactSource.fair:
      return l10n.contactSourceFair;
    case ContactSource.other:
      return l10n.contactSourceOther;
    default:
      return l10n.contactSourceUnspecified;
  }
}

/// Libellé localisé pour une valeur de [Lifestyle] (tabac, sport, sommeil,
/// stress, alimentation). Renvoie `lifestyleUnspecified` pour `null`.
String lifestyleLabel(AppL10n l10n, String? value) {
  switch (value) {
    // Tabac
    case Lifestyle.smokerYes:
      return l10n.lifestyleSmokerYes;
    case Lifestyle.smokerNo:
      return l10n.lifestyleSmokerNo;
    case Lifestyle.smokerFormer:
      return l10n.lifestyleSmokerFormer;
    case Lifestyle.smokerOccasional:
      return l10n.lifestyleSmokerOccasional;
    // Sport
    case Lifestyle.sportNone:
      return l10n.lifestyleSportNone;
    case Lifestyle.sportOccasional:
      return l10n.lifestyleSportOccasional;
    case Lifestyle.sportRegular:
      return l10n.lifestyleSportRegular;
    case Lifestyle.sportIntense:
      return l10n.lifestyleSportIntense;
    // Sommeil
    case Lifestyle.sleepGood:
      return l10n.lifestyleSleepGood;
    case Lifestyle.sleepAverage:
      return l10n.lifestyleSleepAverage;
    case Lifestyle.sleepLight:
      return l10n.lifestyleSleepLight;
    case Lifestyle.sleepDisturbed:
      return l10n.lifestyleSleepDisturbed;
    // Stress
    case Lifestyle.stressLow:
      return l10n.lifestyleStressLow;
    case Lifestyle.stressModerate:
      return l10n.lifestyleStressModerate;
    case Lifestyle.stressHigh:
      return l10n.lifestyleStressHigh;
    case Lifestyle.stressBurnout:
      return l10n.lifestyleStressBurnout;
    // Alimentation
    case Lifestyle.dietOmnivore:
      return l10n.lifestyleDietOmnivore;
    case Lifestyle.dietVegetarian:
      return l10n.lifestyleDietVegetarian;
    case Lifestyle.dietVegan:
      return l10n.lifestyleDietVegan;
    case Lifestyle.dietPescatarian:
      return l10n.lifestyleDietPescatarian;
    case Lifestyle.dietOther:
      return l10n.lifestyleDietOther;
    default:
      return l10n.lifestyleUnspecified;
  }
}
