import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'colors.dart';

/// One design system for the Android app and the web dashboard.
///
/// Light and dark themes are built by the same function, so every component
/// (cards, inputs, buttons, tables, dialogs, navigation, chips, tabs...) looks
/// identical on both platforms and in both modes. The accent colour chosen in
/// Settings replaces only the primary tone; surfaces stay neutral slate.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => light();

  static ThemeData get darkTheme => dark();

  /// Light theme built from [seedColor] (defaults to the brand colour).
  static ThemeData light({Color? seedColor}) {
    return _build(_scheme(seedColor ?? AppColors.primary, Brightness.light));
  }

  /// Dark theme built from [seedColor] (defaults to the brand colour).
  static ThemeData dark({Color? seedColor}) {
    return _build(_scheme(seedColor ?? AppColors.primary, Brightness.dark));
  }

  // ===========================================================================
  // COLOUR SCHEME
  // ===========================================================================

  static ColorScheme _scheme(Color seed, Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      // Keeps the chosen hue recognisable instead of a washed-out tone.
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );

    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: seed,
        onPrimary: Colors.white,
        surface: AppColors.lightSurface,
        onSurface: AppColors.lightText,
        onSurfaceVariant: AppColors.lightTextMuted,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF8FAFC),
        surfaceContainer: const Color(0xFFF1F4F9),
        surfaceContainerHigh: const Color(0xFFEAEFF6),
        surfaceContainerHighest: const Color(0xFFE3E8F0),
        outline: const Color(0xFFC5CEDB),
        outlineVariant: AppColors.lightBorder,
        error: AppColors.error,
        onError: Colors.white,
        surfaceTint: Colors.transparent,
      );
    }

    return base.copyWith(
      primary: Color.lerp(seed, Colors.white, 0.22),
      onPrimary: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      onSurfaceVariant: AppColors.darkTextMuted,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: const Color(0xFF0F1726),
      surfaceContainer: AppColors.darkCard,
      surfaceContainerHigh: const Color(0xFF1B2536),
      surfaceContainerHighest: const Color(0xFF222D40),
      outline: const Color(0xFF3A475C),
      outlineVariant: AppColors.darkBorder,
      error: const Color(0xFFF87171),
      onError: const Color(0xFF3B0A0A),
      surfaceTint: Colors.transparent,
    );
  }

  // ===========================================================================
  // THEME
  // ===========================================================================

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    final background =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardColor = isDark ? AppColors.darkCard : AppColors.lightSurface;
    final inputFill = isDark ? const Color(0xFF0F1726) : const Color(0xFFF8FAFC);
    final border = scheme.outlineVariant;
    final hint = isDark ? AppColors.darkTextHint : AppColors.lightTextHint;

    final radiusMd = BorderRadius.circular(AppSpacing.radiusMd);
    final radiusLg = BorderRadius.circular(AppSpacing.radiusLg);

    final baseText = (isDark
            ? Typography.material2021().white
            : Typography.material2021().black)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final textTheme = baseText.copyWith(
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      // Body text uses a medium weight: regular (400) weight rendered thin
      // and faded, especially on the web.
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: radiusMd);
    const buttonText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: scheme.surface,
      cardColor: cardColor,
      dividerColor: border,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      // ---------------------------------------------------------------------
      // APP BAR
      // ---------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: border)),
        titleSpacing: 16,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      ),

      // ---------------------------------------------------------------------
      // CARDS
      // ---------------------------------------------------------------------
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0 : 0.05),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLg,
          side: BorderSide(color: border),
        ),
      ),

      // ---------------------------------------------------------------------
      // INPUTS
      // ---------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: hint, fontSize: 14),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        helperStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        disabledBorder: inputBorder(
          border.withValues(alpha: 0.45),
        ),
        focusedBorder: inputBorder(scheme.primary, 1.5),
        errorBorder: inputBorder(scheme.error.withValues(alpha: 0.7), 1.2),
        focusedErrorBorder: inputBorder(scheme.error, 1.5),
        errorStyle: TextStyle(
          color: scheme.error,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: radiusMd,
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),

      // ---------------------------------------------------------------------
      // BUTTONS
      // ---------------------------------------------------------------------
      // Compact horizontal padding; height stays 44 (48 touch target on
      // mobile through the default padded tap target size).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: buttonShape,
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: buttonShape,
          side: BorderSide(color: border),
          selectedBackgroundColor: AppColors.tint(scheme.primary, scheme.brightness),
          selectedForegroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: buttonText,
      ),

      // ---------------------------------------------------------------------
      // OVERLAYS
      // ---------------------------------------------------------------------
      dialogTheme: DialogThemeData(
        elevation: 8,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: isDark ? BorderSide(color: border) : BorderSide.none,
        ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 14),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: radiusMd,
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        backgroundColor: isDark ? const Color(0xFF1F2A3C) : const Color(0xFF1E293B),
        actionTextColor: Color.lerp(scheme.primary, Colors.white, 0.45),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ---------------------------------------------------------------------
      // NAVIGATION
      // ---------------------------------------------------------------------
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        width: 300,
        shape: const RoundedRectangleBorder(),
        endShape: const RoundedRectangleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.tint(scheme.primary, scheme.brightness),
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: border,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ---------------------------------------------------------------------
      // LISTS, CHIPS, TABLES
      // ---------------------------------------------------------------------
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        selectedColor: scheme.primary,
        selectedTileColor: AppColors.tint(scheme.primary, scheme.brightness),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: AppColors.tint(scheme.primary, scheme.brightness),
        secondarySelectedColor: AppColors.tint(scheme.primary, scheme.brightness),
        checkmarkColor: scheme.primary,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.primary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        headingRowHeight: 44,
        dataRowMinHeight: 50,
        dataRowMaxHeight: 64,
        horizontalMargin: 16,
        columnSpacing: 24,
        dividerThickness: 0.7,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        headingTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        dataTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: Colors.white,
        textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(8),
        thumbColor: WidgetStatePropertyAll(scheme.outline.withValues(alpha: 0.55)),
      ),

      // ---------------------------------------------------------------------
      // PROGRESS & SELECTION CONTROLS
      // ---------------------------------------------------------------------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: AppColors.tint(scheme.primary, scheme.brightness),
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline.withValues(alpha: 0.6),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// =============================================================================
// BUTTON LAYOUT HELPERS (shared by the Android app and the web dashboard)
// =============================================================================

/// Places a screen's main action button at a compact width instead of
/// stretching it across the whole form:
/// - wide layouts (web dialogs, tablets): natural content width
///   (200-360px), aligned to [alignment];
/// - phones: a comfortable centred width (about 82% of the row, 220-340px).
class AppActionButtonBox extends StatelessWidget {
  const AppActionButtonBox({
    super.key,
    required this.child,
    this.height,
    this.alignment = Alignment.centerRight,
  });

  final Widget child;
  final double? height;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return SizedBox(height: height, child: child);
        }

        if (constraints.maxWidth >= 600) {
          return Align(
            // heightFactor: never grow vertically. Inside a pinned action bar
            // (Scaffold.bottomNavigationBar) an expanding Align would take the
            // whole screen and leave no room for the form itself.
            heightFactor: 1,
            alignment: alignment,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
              child: SizedBox(height: height, child: child),
            ),
          );
        }

        final available = constraints.maxWidth;
        final double width = (available * 0.82).clamp(
          math.min(220.0, available),
          math.min(340.0, available),
        );

        return Align(
          heightFactor: 1,
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}

/// A row of related buttons (e.g. Reject / Approve): natural widths aligned
/// to the end on wide layouts, equal halves on phones so each stays easy to
/// tap.
class AppButtonRow extends StatelessWidget {
  const AppButtonRow({super.key, required this.children, this.spacing = 10});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final items = <Widget>[];

        for (var i = 0; i < children.length; i++) {
          if (i > 0) items.add(SizedBox(width: spacing));
          items.add(
            compact
                ? Expanded(child: children[i])
                : ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 120),
                    child: children[i],
                  ),
          );
        }

        return Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: items,
        );
      },
    );
  }
}
