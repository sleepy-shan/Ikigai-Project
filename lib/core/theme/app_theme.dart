import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'design_tokens.dart';

/// Light and dark [ThemeData] built from the design tokens.
///
/// Signature look — "Komorebi lagoon" (chill minimal):
/// * Mist-tinted backgrounds with soft lagoon glows (painted
///   by [AppShell] behind the content).
/// * 10-16px rounded cards with soft shadows + hairline borders.
/// * Flat docked top bar with underline tabs (no floating pill).
/// * Fade+slide page transitions and a slim rounded scrollbar so every
///   scroll feels smooth.
abstract final class AppTheme {
  static ThemeData light([AppAccent accent = AppAccent.lagoon]) =>
      _base(Brightness.light, accent);
  static ThemeData dark([AppAccent accent = AppAccent.lagoon]) =>
      _base(Brightness.dark, accent);

  static ThemeData _base(Brightness brightness, AppAccent accent) {
    final bool isDark = brightness == Brightness.dark;
    // Lagoon keeps the signature primary values so the Ikigai look is
    // calm; other accents use the accessible M3 tonal primary derived
    // from the seed (white-on-primary contrast guaranteed by fromSeed).
    final seeded = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
    );
    final ColorScheme scheme = accent == AppAccent.lagoon
        ? seeded.copyWith(
            primary: isDark ? Tokens.brandDark : Tokens.brand,
            secondary: Tokens.accent,
            tertiary: const Color(0xFF7D9B8A),
            surface: isDark
                ? const Color(0xFF131B1B)
                : const Color(0xFFF4F7F5),
            error: Tokens.danger,
          )
        : seeded.copyWith(
            surface: isDark
                ? const Color(0xFF131B1B)
                : const Color(0xFFF4F7F5),
            error: Tokens.danger,
          );

    final Color background = isDark
        ? const Color(0xFF0B1212)
        : const Color(0xFFEEF3F0);
    final Color card = isDark ? const Color(0xFF151F1F) : Colors.white;
    final Color border = isDark
        ? const Color(0xFF26302F)
        : const Color(0xFFDCE5E0);

    final baseTextTheme = isDark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: card,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        displaySmall: TypeScale.displaySmall.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: TypeScale.headlineMedium.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        headlineSmall: TypeScale.headlineSmall.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: TypeScale.titleLarge,
        titleMedium: TypeScale.titleMedium,
        bodyLarge: TypeScale.bodyLarge,
        bodyMedium: TypeScale.bodyMedium,
        labelLarge: TypeScale.labelLarge,
        labelSmall: TypeScale.labelSmall,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background.withValues(alpha: 0.82),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TypeScale.titleLarge.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : border,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        brightness: brightness,
        backgroundColor: isDark
            ? const Color(0xFF1B2625).withValues(alpha: 0.85)
            : Colors.white,
        selectedColor: scheme.primary.withValues(alpha: 0.14),
        secondarySelectedColor: scheme.secondaryContainer,
        disabledColor: scheme.onSurface.withValues(alpha: 0.12),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.10) : border,
        ),
        // Explicit label colors: relying on Chip defaults left genre /
        // category tag text near-invisible in dark mode (dark text on the
        // dark chip background). Derive from the color scheme so contrast
        // is guaranteed in both brightnesses. onSurface (not
        // onSurfaceVariant) keeps small 13px semibold labels above 4.5:1
        // on the dark chip fill.
        labelStyle: TypeScale.labelLarge.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: TypeScale.labelLarge.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        checkmarkColor: scheme.primary,
        deleteIconColor: scheme.onSurfaceVariant,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
        ),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space12,
          vertical: Tokens.space8,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1B2625).withValues(alpha: 0.85)
            : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space16,
          vertical: Tokens.space12,
        ),
        border: _inputBorder(
          isDark ? Colors.white.withValues(alpha: 0.10) : border,
          radius: Tokens.radiusMd,
        ),
        enabledBorder: _inputBorder(
          isDark ? Colors.white.withValues(alpha: 0.10) : border,
          radius: Tokens.radiusMd,
        ),
        focusedBorder: _inputBorder(scheme.primary, width: 1.5, radius: Tokens.radiusMd),
        errorBorder: _inputBorder(scheme.error, radius: Tokens.radiusMd),
        focusedErrorBorder:
            _inputBorder(scheme.error, width: 1.5, radius: Tokens.radiusMd),
        hintStyle: TypeScale.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, Tokens.inputHeight),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          textStyle: TypeScale.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, Tokens.inputHeight),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.14) : border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          textStyle: TypeScale.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: TypeScale.labelLarge.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(Tokens.iconButtonSize, Tokens.iconButtonSize),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? const Color(0xFF1B2625) : Colors.white,
          border: _inputBorder(border, radius: Tokens.radiusMd),
          enabledBorder: _inputBorder(border, radius: Tokens.radiusMd),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedLabelTextStyle: TypeScale.labelLarge.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TypeScale.labelSmall,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF0E1515).withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
        labelTextStyle: WidgetStatePropertyAll(TypeScale.labelSmall),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(999),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withValues(alpha: 0.55);
          }
          return scheme.primary.withValues(alpha: 0.28);
        }),
        trackColor: WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF26302F)
            : const Color(0xFF14201F),
        contentTextStyle: TypeScale.bodyLarge.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26302F) : const Color(0xFF14201F),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
        ),
        textStyle: TypeScale.bodyMedium.copyWith(color: Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : border,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: isDark
            ? Colors.white.withValues(alpha: 0.12)
            : border,
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusXl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Tokens.radiusXl),
          ),
        ),
        showDragHandle: true,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: _SmoothFadeBuilder(),
          TargetPlatform.linux: _SmoothFadeBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(
    Color color, {
    double width = 1,
    double radius = 12,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// Soft fade + slide + slight scale page transition used on desktop/web so
/// route changes feel smooth instead of snappy.
class _SmoothFadeBuilder extends PageTransitionsBuilder {
  const _SmoothFadeBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final slide =
        Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(fade);
    final scale = Tween<double>(begin: 0.985, end: 1.0).animate(fade);
    // Outgoing page fades slightly for a cross-fade feel.
    final outFade = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.92).animate(outFade),
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(scale: scale, child: child),
        ),
      ),
    );
  }
}
