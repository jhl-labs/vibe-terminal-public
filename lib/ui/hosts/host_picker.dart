import 'package:flutter/material.dart';

import '../../data/models/host.dart';
import '../adaptive/breakpoints.dart';
import 'host_list_page.dart';

/// 새 세션용 호스트 선택 UI를 연다. 선택한 [Host]를, 취소하면 null을 돌려준다.
///
/// compact(모바일)에서는 전체화면 페이지로, 그 외(데스크톱)에서는 설정 화면과
/// 같은 중앙 다이얼로그로 띄운다. 다이얼로그 안에는 별도 [Navigator]를 두어
/// 호스트 추가/수정 화면도 다이얼로그 안에서 열리게 한다.
Future<Host?> showHostPicker(BuildContext context) {
  if (context.isCompact) {
    return Navigator.push<Host>(
      context,
      MaterialPageRoute(builder: (_) => const HostListPage(pickMode: true)),
    );
  }

  return showDialog<Host>(
    context: context,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 560,
        height: 640,
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => HostListPage(
              pickMode: true,
              onPick: (host) => Navigator.pop(dialogContext, host),
              onClose: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
      ),
    ),
  );
}
