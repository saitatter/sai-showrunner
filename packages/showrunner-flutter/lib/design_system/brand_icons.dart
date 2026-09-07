import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _materialDesignIconsFont = 'Material Design Icons';

const _mdiFallback = IconData(0xF0A66, fontFamily: _materialDesignIconsFont);
const _mdiIcons = <int, IconData>{
  0xF0543: IconData(0xF0543, fontFamily: _materialDesignIconsFont),
  0xF05C3: IconData(0xF05C3, fontFamily: _materialDesignIconsFont),
  0xF046E: IconData(0xF046E, fontFamily: _materialDesignIconsFont),
  0xF0C8C: IconData(0xF0C8C, fontFamily: _materialDesignIconsFont),
  0xF0FE8: IconData(0xF0FE8, fontFamily: _materialDesignIconsFont),
  0xF0163: IconData(0xF0163, fontFamily: _materialDesignIconsFont),
  0xF0A1D: IconData(0xF0A1D, fontFamily: _materialDesignIconsFont),
  0xF157E: IconData(0xF157E, fontFamily: _materialDesignIconsFont),
  0xF097B: IconData(0xF097B, fontFamily: _materialDesignIconsFont),
  0xF1051: IconData(0xF1051, fontFamily: _materialDesignIconsFont),
  0xF059F: IconData(0xF059F, fontFamily: _materialDesignIconsFont),
  0xF030C: IconData(0xF030C, fontFamily: _materialDesignIconsFont),
  0xF061A: IconData(0xF061A, fontFamily: _materialDesignIconsFont),
  0xF06E9: IconData(0xF06E9, fontFamily: _materialDesignIconsFont),
  0xF0373: IconData(0xF0373, fontFamily: _materialDesignIconsFont),
  0xF0565: IconData(0xF0565, fontFamily: _materialDesignIconsFont),
  0xF0379: IconData(0xF0379, fontFamily: _materialDesignIconsFont),
  0xF09FE: IconData(0xF09FE, fontFamily: _materialDesignIconsFont),
  0xF1254: IconData(0xF1254, fontFamily: _materialDesignIconsFont),
  0xF1156: IconData(0xF1156, fontFamily: _materialDesignIconsFont),
  0xF0454: IconData(0xF0454, fontFamily: _materialDesignIconsFont),
  0xF057E: IconData(0xF057E, fontFamily: _materialDesignIconsFont),
  0xF0068: IconData(0xF0068, fontFamily: _materialDesignIconsFont),
  0xF00F0: IconData(0xF00F0, fontFamily: _materialDesignIconsFont),
  0xF0150: IconData(0xF0150, fontFamily: _materialDesignIconsFont),
  0xF0427: IconData(0xF0427, fontFamily: _materialDesignIconsFont),
  0xF12BA: IconData(0xF12BA, fontFamily: _materialDesignIconsFont),
  0xF0AE7: IconData(0xF0AE7, fontFamily: _materialDesignIconsFont),
  0xF0370: IconData(0xF0370, fontFamily: _materialDesignIconsFont),
  0xF07AE: IconData(0xF07AE, fontFamily: _materialDesignIconsFont),
  0xF036B: IconData(0xF036B, fontFamily: _materialDesignIconsFont),
  0xF0F59: IconData(0xF0F59, fontFamily: _materialDesignIconsFont),
  0xF09AD: IconData(0xF09AD, fontFamily: _materialDesignIconsFont),
};

IconData mdiIcon(int codePoint) => _mdiIcons[codePoint] ?? _mdiFallback;

class TwitchBrandIcon extends StatelessWidget {
  const TwitchBrandIcon({
    super.key,
    this.color = const Color(0xff9146ff),
    this.size = 24,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(mdiIcon(0xF0543), color: color, size: size);
}

class YoutubeBrandIcon extends StatelessWidget {
  const YoutubeBrandIcon({
    super.key,
    this.color = const Color(0xffff0033),
    this.size = 24,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(mdiIcon(0xF05C3), color: color, size: size);
}

class BrandSvgIcon extends StatelessWidget {
  const BrandSvgIcon({
    super.key,
    required this.asset,
    required this.color,
    this.size = 24,
  });

  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    asset,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

class ObsBrandIcon extends StatelessWidget {
  const ObsBrandIcon({
    super.key,
    this.color = const Color(0xff256eff),
    this.size = 24,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      BrandSvgIcon(asset: 'assets/icons/obs.svg', color: color, size: size);
}
