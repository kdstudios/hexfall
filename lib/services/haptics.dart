import 'package:flutter/services.dart';

/// Thin wrapper over HapticFeedback honouring the user's setting. Platforms
/// without a vibration motor (desktop, most browsers) silently do nothing.
class Haptics {
  Haptics({this.enabled = true});

  bool enabled;

  void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
