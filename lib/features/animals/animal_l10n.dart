import '../../domain/animal.dart';
import '../../l10n/generated/app_localizations.dart';

/// Centralised label resolution for animal-related stable string keys.
/// Keeping this in one place avoids switch statements in every widget.
String speciesLabel(AppL10n l, String key) {
  switch (key) {
    case Species.dog:
      return l.speciesDog;
    case Species.cat:
      return l.speciesCat;
    case Species.horse:
      return l.speciesHorse;
    case Species.bird:
      return l.speciesBird;
    case Species.rodent:
      return l.speciesRodent;
    case Species.reptile:
      return l.speciesReptile;
    default:
      return l.speciesOther;
  }
}

String sexLabel(AppL10n l, String? key) {
  switch (key) {
    case AnimalSex.male:
      return l.sexMale;
    case AnimalSex.female:
      return l.sexFemale;
    case AnimalSex.maleNeutered:
      return l.sexMaleNeutered;
    case AnimalSex.femaleSpayed:
      return l.sexFemaleSpayed;
    default:
      return l.sexUnknown;
  }
}
