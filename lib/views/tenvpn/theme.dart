import 'package:fl_clash/common/shape.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:material_ui/material_ui.dart';

const tenvpnDisplayFont = 'Geologica';
const tenvpnTextFont = 'Onest';

/// Brand tokens of the "Тёплая нора" brandbook. Lime is a signal, not paint:
/// it marks "working" and the one primary action on a screen.
@immutable
class TenvpnPalette extends ThemeExtension<TenvpnPalette> {
  final Color ink;
  final Color surface;
  final Color elevated;
  final Color border;
  final Color borderStrong;
  final Color accent;
  final Color accentText;
  final Color accentSoft;
  final Color onAccent;
  final Color cream;
  final Color cocoa;
  final Color cocoaText;
  final Color cocoaSoft;
  final Color text;
  final Color muted;
  final Color mutedDeep;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final bool showMascot;

  /// «Строгий»: visible 1 px lines, 8 px corners and capital labels instead
  /// of soft fills — the clarity comes from lines, not from new colours.
  final bool strict;

  const TenvpnPalette({
    required this.ink,
    required this.surface,
    required this.elevated,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.onAccent,
    required this.cream,
    required this.cocoa,
    required this.cocoaText,
    required this.cocoaSoft,
    required this.text,
    required this.muted,
    required this.mutedDeep,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    this.showMascot = true,
    this.strict = false,
  });

  static const dark = TenvpnPalette(
    ink: Color(0xFF0C100E),
    surface: Color(0xFF141A17),
    elevated: Color(0xFF1D2521),
    border: Color(0x12FFFFFF),
    borderStrong: Color(0x21FFFFFF),
    accent: Color(0xFFB6E32E),
    accentText: Color(0xFFB6E32E),
    accentSoft: Color(0x1FB6E32E),
    onAccent: Color(0xFF0C100E),
    cream: Color(0xFFF2E6C8),
    cocoa: Color(0xFFA9714A),
    cocoaText: Color(0xFFD9A87E),
    cocoaSoft: Color(0x29A9714A),
    text: Color(0xFFE8EDE6),
    muted: Color(0xFF8A968D),
    mutedDeep: Color(0xFF6E7A72),
    warn: Color(0xFFFFB245),
    warnSoft: Color(0x1AFFB245),
    danger: Color(0xFFFF6B5E),
    dangerSoft: Color(0x1AFF6B5E),
  );

  static const light = TenvpnPalette(
    ink: Color(0xFFF6F1E6),
    surface: Color(0xFFFFFCF5),
    elevated: Color(0xFFEDE6D7),
    border: Color(0x140C100E),
    borderStrong: Color(0x260C100E),
    accent: Color(0xFFB6E32E),
    accentText: Color(0xFF4A6600),
    accentSoft: Color(0x33B6E32E),
    onAccent: Color(0xFF0C100E),
    cream: Color(0xFF3B2A1C),
    cocoa: Color(0xFFA9714A),
    cocoaText: Color(0xFF7A4A27),
    cocoaSoft: Color(0x29A9714A),
    text: Color(0xFF17201B),
    muted: Color(0xFF5B675F),
    mutedDeep: Color(0xFF7A867E),
    warn: Color(0xFFB86E00),
    warnSoft: Color(0x1FFFB245),
    danger: Color(0xFFC8372B),
    dangerSoft: Color(0x1AFF6B5E),
  );

  /// Tokens from docs/client-app/hiro-study: lines 1.9:1, grey 10.6:1.
  static const strictDark = TenvpnPalette(
    ink: Color(0xFF0C100E),
    surface: Color(0xFF121714),
    elevated: Color(0xFF1B211D),
    border: Color(0xFF3A443E),
    borderStrong: Color(0xFFE8EDE6),
    accent: Color(0xFFB6E32E),
    accentText: Color(0xFFB6E32E),
    accentSoft: Color(0x14B6E32E),
    onAccent: Color(0xFF0C100E),
    cream: Color(0xFFF4F7F2),
    cocoa: Color(0xFF8A968D),
    cocoaText: Color(0xFFDCE2DD),
    cocoaSoft: Color(0x1AFFFFFF),
    text: Color(0xFFF4F7F2),
    muted: Color(0xFFB9C3BB),
    mutedDeep: Color(0xFF8A968D),
    warn: Color(0xFFFFB245),
    warnSoft: Color(0x1AFFB245),
    danger: Color(0xFFFF5A4E),
    dangerSoft: Color(0x1AFF5A4E),
    showMascot: false,
    strict: true,
  );

  static const strictLight = TenvpnPalette(
    ink: Color(0xFFFAFAF7),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFEEF0EC),
    border: Color(0xFFC9CDC6),
    borderStrong: Color(0xFF0C100E),
    accent: Color(0xFFB6E32E),
    accentText: Color(0xFF3F5A00),
    accentSoft: Color(0x29B6E32E),
    onAccent: Color(0xFF0C100E),
    cream: Color(0xFF0C100E),
    cocoa: Color(0xFF6A756D),
    cocoaText: Color(0xFF2A332D),
    cocoaSoft: Color(0x140C100E),
    text: Color(0xFF0C100E),
    muted: Color(0xFF3E4842),
    mutedDeep: Color(0xFF6A756D),
    warn: Color(0xFFB86E00),
    warnSoft: Color(0x1FFFB245),
    danger: Color(0xFFC8372B),
    dangerSoft: Color(0x1AC8372B),
    showMascot: false,
    strict: true,
  );

  static TenvpnPalette of(Brightness brightness, AppLook look) {
    final dark = brightness == Brightness.dark;
    return switch (look) {
      AppLook.burrow => dark ? TenvpnPalette.dark : TenvpnPalette.light,
      AppLook.strict => dark ? strictDark : strictLight,
    };
  }

  @override
  TenvpnPalette copyWith() => this;

  @override
  TenvpnPalette lerp(TenvpnPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return TenvpnPalette(
      ink: mix(ink, other.ink),
      surface: mix(surface, other.surface),
      elevated: mix(elevated, other.elevated),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      accent: mix(accent, other.accent),
      accentText: mix(accentText, other.accentText),
      accentSoft: mix(accentSoft, other.accentSoft),
      onAccent: mix(onAccent, other.onAccent),
      cream: mix(cream, other.cream),
      cocoa: mix(cocoa, other.cocoa),
      cocoaText: mix(cocoaText, other.cocoaText),
      cocoaSoft: mix(cocoaSoft, other.cocoaSoft),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      mutedDeep: mix(mutedDeep, other.mutedDeep),
      warn: mix(warn, other.warn),
      warnSoft: mix(warnSoft, other.warnSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      showMascot: t < 0.5 ? showMascot : other.showMascot,
      strict: t < 0.5 ? strict : other.strict,
    );
  }
}

extension TenvpnPaletteContext on BuildContext {
  TenvpnPalette get palette =>
      Theme.of(this).extension<TenvpnPalette>() ?? TenvpnPalette.dark;
}

const _strictCorner = BorderRadius.all(Radius.circular(8));

extension TenvpnPaletteShapes on TenvpnPalette {
  OutlinedBorder cardShape([BorderSide side = BorderSide.none]) => strict
      ? RoundedRectangleBorder(borderRadius: _strictCorner, side: side)
      : AppShape.lg.copyWith(side: side);

  String caps(String text) => strict ? text.toUpperCase() : text;

  TextStyle captionStyle(Color color) => strict
      ? TextStyle(
          fontFamily: tenvpnDisplayFont,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: color,
        )
      : TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color);
}

ColorScheme tenvpnColorScheme(
  Brightness brightness, [
  AppLook look = AppLook.burrow,
]) {
  final p = TenvpnPalette.of(brightness, look);
  final dark = brightness == Brightness.dark;
  return ColorScheme(
    brightness: brightness,
    primary: p.accentText,
    onPrimary: dark ? p.onAccent : p.surface,
    primaryContainer: p.accent,
    onPrimaryContainer: p.onAccent,
    secondary: p.cocoa,
    onSecondary: p.surface,
    secondaryContainer: p.cocoaSoft,
    onSecondaryContainer: p.cocoaText,
    tertiary: p.cocoaText,
    onTertiary: p.ink,
    error: p.danger,
    onError: p.surface,
    errorContainer: p.dangerSoft,
    onErrorContainer: p.danger,
    surface: p.ink,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.ink,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.elevated,
    surfaceContainerHighest: p.elevated,
    outline: p.borderStrong,
    outlineVariant: p.border,
    inverseSurface: p.text,
    onInverseSurface: p.ink,
    inversePrimary: p.accent,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
  );
}

TextTheme _textTheme(TextTheme base, TenvpnPalette p) {
  TextStyle? display(TextStyle? style, FontWeight weight) => style?.copyWith(
    fontFamily: tenvpnDisplayFont,
    fontWeight: weight,
    letterSpacing: -0.6,
    color: p.text,
  );
  final text = base.apply(
    fontFamily: tenvpnTextFont,
    bodyColor: p.text,
    displayColor: p.text,
  );
  return text.copyWith(
    displayLarge: display(text.displayLarge, FontWeight.w800),
    displayMedium: display(text.displayMedium, FontWeight.w800),
    displaySmall: display(text.displaySmall, FontWeight.w700),
    headlineLarge: display(text.headlineLarge, FontWeight.w700),
    headlineMedium: display(text.headlineMedium, FontWeight.w700),
    headlineSmall: display(text.headlineSmall, FontWeight.w700),
    titleLarge: display(text.titleLarge, FontWeight.w700),
  );
}

ThemeData buildTenvpnTheme({
  required Brightness brightness,
  AppLook look = AppLook.burrow,
  PageTransitionsTheme? pageTransitionsTheme,
  TooltipThemeData? tooltipTheme,
}) {
  final palette = TenvpnPalette.of(brightness, look);
  final scheme = tenvpnColorScheme(brightness, look);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: tenvpnTextFont,
    pageTransitionsTheme: pageTransitionsTheme,
    tooltipTheme: tooltipTheme,
  );
  final themed = base
      .copyWith(
        scaffoldBackgroundColor: palette.ink,
        canvasColor: palette.ink,
        textTheme: _textTheme(base.textTheme, palette),
        appBarTheme: AppBarTheme(
          backgroundColor: palette.ink,
          surfaceTintColor: Colors.transparent,
          foregroundColor: palette.text,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: tenvpnDisplayFont,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.5,
            color: palette.text,
          ),
        ),
        dividerTheme: DividerThemeData(color: palette.border, space: 1),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.onAccent
                : palette.muted,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.accent
                : palette.elevated,
          ),
          trackOutlineColor: WidgetStatePropertyAll(palette.borderStrong),
        ),
        extensions: [palette],
      )
      .withAppShapes;
  if (!palette.strict) return themed;
  OutlineInputBorder line(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: _strictCorner,
        borderSide: BorderSide(color: color, width: width),
      );
  return themed.copyWith(
    inputDecorationTheme: themed.inputDecorationTheme.copyWith(
      border: line(palette.borderStrong),
      enabledBorder: line(palette.borderStrong),
      focusedBorder: line(palette.accent, 1.5),
      disabledBorder: line(palette.border),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: _strictCorner),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: palette.borderStrong)),
      ),
    ),
  );
}

class TenvpnCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  const TenvpnCard({
    super.key,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: color ?? p.surface,
      shape: p.cardShape(BorderSide(color: borderColor ?? p.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The one big button of a screen: lime fill when it is the primary action,
/// a quiet outline otherwise.
class TenvpnBigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool loading;
  final double height;

  const TenvpnBigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.loading = false,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final foreground = primary ? p.onAccent : p.text;
    final child = loading
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: foreground,
            ),
          )
        : Text(
            p.caps(label),
            style: p.strict
                ? TextStyle(
                    fontFamily: tenvpnDisplayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: foreground,
                  )
                : TextStyle(
                    fontFamily: tenvpnTextFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
          );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: primary
          ? FilledButton(
              onPressed: loading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                disabledBackgroundColor: p.accent.withValues(alpha: 0.6),
                shape: p.cardShape(),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: loading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.text,
                side: BorderSide(color: p.borderStrong),
                shape: p.cardShape(),
              ),
              child: child,
            ),
    );
  }
}
