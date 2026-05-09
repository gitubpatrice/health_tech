/// Time helpers shared by all repositories — keeps the second-vs-millisecond
/// boundary in one place.
library;

int nowEpochSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
