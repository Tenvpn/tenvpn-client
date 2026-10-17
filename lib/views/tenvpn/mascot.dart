import 'dart:math';

import 'package:fl_clash/common/shape.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

enum FerPose { off, connecting, on, error, welcome }

/// Must match the `<pose>-<n>.webp` files tool/cut_mascot.py writes.
const ferVariants = {
  FerPose.off: 2,
  FerPose.connecting: 1,
  FerPose.on: 2,
  FerPose.error: 1,
  FerPose.welcome: 1,
};

FerPose ferPoseFor(ConnectionPhase phase) => switch (phase) {
  ConnectionPhase.off => FerPose.off,
  ConnectionPhase.connecting => FerPose.connecting,
  ConnectionPhase.on => FerPose.on,
  ConnectionPhase.error => FerPose.error,
};

String ferAsset(FerPose pose, int variant) =>
    'assets/images/mascot/${pose.name}-$variant.webp';

/// Picks another drawing on every pose change; the glow behind him is the
/// one place the brandbook lets lime be atmosphere.
class FerMascot extends StatefulWidget {
  final FerPose pose;
  final double size;
  final Random? random;

  const FerMascot({
    super.key,
    required this.pose,
    this.size = 260,
    this.random,
  });

  @override
  State<FerMascot> createState() => _FerMascotState();
}

class _FerMascotState extends State<FerMascot> {
  late final Random _random = widget.random ?? Random();
  late int _variant = _pick();

  int _pick() => 1 + _random.nextInt(ferVariants[widget.pose] ?? 1);

  @override
  void didUpdateWidget(FerMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pose != widget.pose) _variant = _pick();
  }

  Color _glow(TenvpnPalette p) => switch (widget.pose) {
    FerPose.on => p.accent.withValues(alpha: 0.16),
    FerPose.connecting => p.accent.withValues(alpha: 0.08),
    FerPose.error => p.danger.withValues(alpha: 0.10),
    FerPose.off || FerPose.welcome => p.cocoa.withValues(alpha: 0.12),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = widget.size;
    final asset = ferAsset(widget.pose, _variant);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: size * 0.9,
              height: size * 0.9,
              decoration: ShapeDecoration(
                shape: AppShape.circle,
                gradient: RadialGradient(
                  colors: [_glow(p), _glow(p).withValues(alpha: 0)],
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Image.asset(
                asset,
                key: ValueKey(asset),
                width: size,
                height: size,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
