import '../../domain/session.dart';
import '../../l10n/generated/app_localizations.dart';

String kindLabel(AppL10n l, String key) {
  switch (key) {
    case SessionKind.human:
      return l.kindHuman;
    case SessionKind.animal:
      return l.kindAnimal;
    case SessionKind.duo:
      return l.kindDuo;
    case SessionKind.distance:
      return l.kindDistance;
    case SessionKind.onsite:
      return l.kindOnsite;
    case SessionKind.home:
      return l.kindHome;
    default:
      return l.kindOther;
  }
}

String statusLabel(AppL10n l, String key) {
  switch (key) {
    case SessionStatus.planned:
      return l.statusPlanned;
    case SessionStatus.confirmed:
      return l.statusConfirmed;
    case SessionStatus.done:
      return l.statusDone;
    case SessionStatus.cancelled:
      return l.statusCancelled;
    case SessionStatus.noShow:
      return l.statusNoShow;
    default:
      return key;
  }
}

String paymentStatusLabel(AppL10n l, String? key) {
  switch (key) {
    case PaymentStatus.unpaid:
      return l.paymentUnpaid;
    case PaymentStatus.paid:
      return l.paymentPaid;
    case PaymentStatus.deposit:
      return l.paymentDeposit;
    case PaymentStatus.free:
      return l.paymentFree;
    default:
      return '—';
  }
}

String paymentMethodLabel(AppL10n l, String? key) {
  switch (key) {
    case PaymentMethod.cash:
      return l.methodCash;
    case PaymentMethod.card:
      return l.methodCard;
    case PaymentMethod.transfer:
      return l.methodTransfer;
    case PaymentMethod.check:
      return l.methodCheck;
    default:
      return l.methodOther;
  }
}

String motiveLabel(AppL10n l, String key) {
  switch (key) {
    case SessionMotives.reiki:
      return l.motiveReiki;
    case SessionMotives.energetic:
      return l.motiveEnergetic;
    case SessionMotives.harmonisation:
      return l.motiveHarmonisation;
    case SessionMotives.stress:
      return l.motiveStress;
    case SessionMotives.fatigue:
      return l.motiveFatigue;
    case SessionMotives.pain:
      return l.motivePain;
    case SessionMotives.emotional:
      return l.motiveEmotional;
    case SessionMotives.spiritual:
      return l.motiveSpiritual;
    case SessionMotives.grief:
      return l.motiveGrief;
    case SessionMotives.sleep:
      return l.motiveSleep;
    case SessionMotives.followUp:
      return l.motiveFollowUp;
    case SessionMotives.endOfLife:
      return l.motiveEndOfLife;
    case SessionMotives.calming:
      return l.motiveCalming;
    default:
      return key;
  }
}
