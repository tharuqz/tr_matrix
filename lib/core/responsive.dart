import 'package:flutter/widgets.dart';

/// Breakpoints from the brief: mobile < 600, tablet 600–900, desktop > 900.
enum FormFactor { mobile, tablet, desktop }

class Responsive {
  static const mobileMax = 600.0;
  static const desktopMin = 900.0;

  static FormFactor of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < mobileMax) return FormFactor.mobile;
    if (w < desktopMin) return FormFactor.tablet;
    return FormFactor.desktop;
  }

  static bool isMobile(BuildContext c) => of(c) == FormFactor.mobile;
  static bool isDesktop(BuildContext c) => of(c) == FormFactor.desktop;

  /// Side-by-side panes (list + chat) from tablet upwards.
  static bool multiPane(BuildContext c) => of(c) != FormFactor.mobile;
}

/// Builds different widgets per form factor.
class AdaptiveBuilder extends StatelessWidget {
  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder desktop;
  const AdaptiveBuilder({super.key, required this.mobile, this.tablet, required this.desktop});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, _) {
      switch (Responsive.of(context)) {
        case FormFactor.mobile:
          return mobile(context);
        case FormFactor.tablet:
          return (tablet ?? desktop)(context);
        case FormFactor.desktop:
          return desktop(context);
      }
    });
  }
}
