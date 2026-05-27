import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class Constants {
  static const appName = "R-VPN+";
  // Source + license point at our public GPL-3.0 fork (which carries
  // CREDITS.md attributing Hiddify-Next). The *releases* / appcast URLs
  // are only read by the update checker, which is disabled
  // (Release.allowCustomUpdateChecker=false); kept on-brand for when we
  // ship our own checker.
  static const githubUrl = "https://github.com/Nexxus604/rvpnplus-app";
  static const licenseUrl = "https://github.com/Nexxus604/rvpnplus-app?tab=GPL-3.0-1-ov-file#readme";
  static const githubReleasesApiUrl = "https://api.github.com/repos/Nexxus604/rvpnplus-app/releases";
  static const githubLatestReleaseUrl = "https://github.com/Nexxus604/rvpnplus-app/releases/latest";
  static const appCastUrl = "https://plus.rvpn.app/appcast.xml";
  static const telegramBotUrl = "https://t.me/rvpnplus_bot";
  static const telegramChannelUrl = "https://t.me/+cBrdSmAipI8zNmJi";
  static const telegramChatUrl = "https://t.me/+DG6iDqI1wAo1YzYy";
  static const privacyPolicyUrl = "https://plus.rvpn.app/privacy/";
  static const termsAndConditionsUrl = "https://plus.rvpn.app/terms/";
  static const cfWarpPrivacyPolicy = "https://www.cloudflare.com/application/privacypolicy/";
  static const cfWarpTermsOfService = "https://www.cloudflare.com/application/terms/";
}

const kAnimationDuration = Duration(milliseconds: 250);

abstract class AddProfileModalConst {
  static const fixBtnsGap = 16.0;
  static const fixBtnsGapCount = 4;
  static const fixBtnsItemCount = 3;
  static const navBarGap = 16.0;
  static const navBarBottomGap = 4.0;
  //switch default height
  static const navBarcontentHeight = 32.0;
  static const navBarHeight = navBarGap + navBarBottomGap + navBarcontentHeight;
}

abstract class AlertDialogConst {
  static const minWidth = 280.0;
  static const maxWidth = 560.0;
  static const boxConstraints = BoxConstraints(minWidth: minWidth, maxWidth: maxWidth);
}

abstract class BottomSheetConst {
  static const maxWidth = 456.0;
  static const boxConstraints = BoxConstraints(maxWidth: maxWidth);
  static const borderRadius = BorderRadius.vertical(top: Radius.circular(32));
}

abstract class ProfileTileConst {
  static const radius = Radius.circular(16);
  static const cardBorderRadius = BorderRadius.all(radius);
  static const borderRadiusRight = BorderRadius.horizontal(right: radius);
  static const borderRadiusLeft = BorderRadius.horizontal(left: radius);
  static BorderRadius startBorderRadius(TextDirection direction) =>
      direction == TextDirection.ltr ? borderRadiusLeft : borderRadiusRight;
  static BorderRadius endBorderRadius(TextDirection direction) =>
      direction == TextDirection.ltr ? borderRadiusRight : borderRadiusLeft;
}

abstract class IntroConst {
  static const maxwidth = 620;
  static const termsAndConditionsKey = 'terms-and-conditions';
  static const githubKey = 'github';
  static const licenseKey = 'license';
  static const url = <String, String>{IntroConst.termsAndConditionsKey: Constants.termsAndConditionsUrl, IntroConst.githubKey: Constants.githubUrl, IntroConst.licenseKey: Constants.licenseUrl};
}

abstract class WarpConst {
  static const warpAccountId = 'warp-account-id';
  static const warpAccessToken = "warp-access-token";
  static const warpConsentGiven = "warp-consent-given";
  static const warpTermsOfServiceKey = 'warp-terms-of-service';
  static const warpPrivacyPolicyKey = 'warp-privacy-policy';
  static const url = <String, String>{WarpConst.warpTermsOfServiceKey: Constants.cfWarpTermsOfService, WarpConst.warpPrivacyPolicyKey: Constants.cfWarpPrivacyPolicy};
}

abstract class KeyboardConst {
  static final allArrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  static final horizontalArrows = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  static final verticalArrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown};
  static final select = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.tab};
}
