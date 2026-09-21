import 'package:flutter/widgets.dart';

/// The app's own icons.
///
/// [paw] is the goat hoof mark (assets/icon/goat_paw_green_vector.svg turned
/// into the GoatIcons font, assets/fonts/GoatIcons.ttf). It replaces the
/// Material dog paw (Icons.pets) everywhere: it is an ordinary [IconData], so
/// `Icon(GoatIcons.paw, size: 20, color: ...)` and every `icon: GoatIcons.paw`
/// parameter takes the colour and size of the place it is used in.
class GoatIcons {
  GoatIcons._();

  static const IconData paw = IconData(0xe900, fontFamily: 'GoatIcons');
}
