import 'package:flutter/widgets.dart';

/// Motion tokens for P.E.T.
///
/// Interface motion is short and eases out, so things respond the moment
/// they're touched and settle gently. Nothing grows from scale 0, and every
/// animation collapses to an instant change when the system asks for reduced
/// motion (see [Motion.of]).
abstract final class Motion {
  /// Press feedback, toggles, small colour changes.
  static const Duration quick = Duration(milliseconds: 150);

  /// Most UI transitions: showing or hiding a button, expanding a row.
  static const Duration standard = Duration(milliseconds: 220);

  /// Larger surfaces: sheets, page-level fades, a number counting up.
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Strong ease-out: fast start, long gentle settle.
  static const Curve easeOut = Cubic(0.23, 1, 0.32, 1);

  /// For things moving across the screen while staying on it.
  static const Curve easeInOut = Cubic(0.77, 0, 0.175, 1);

  /// How far a pressed surface shrinks.
  static const double pressedScale = 0.97;

  /// [duration], or zero when the user has asked for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  /// Whether animations should be skipped.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
