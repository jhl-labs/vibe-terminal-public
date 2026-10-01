import 'package:flutter/material.dart';

/// 세션 레일 타일에 표시할 CLI/에디터 브랜드 색상과 짧은 라벨.
///
/// [AgentSessionInspection.agentHint]가 여기 등록된 값일 때만 배지를 그린다.
/// 'agent'/'unknown' 같은 느슨한 값은 의도적으로 제외한다.
class AgentBrand {
  const AgentBrand({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  static const Map<String, AgentBrand> _byHint = {
    'claude': AgentBrand(
      label: 'claude',
      background: Color(0xFFCC785C),
      foreground: Colors.white,
    ),
    'codex': AgentBrand(
      label: 'codex',
      background: Color(0xFF000000),
      foreground: Colors.white,
    ),
    'opencode': AgentBrand(
      label: 'opencode',
      background: Color(0xFF4A4A4A),
      foreground: Colors.white,
    ),
    'antigravity': AgentBrand(
      label: 'antigravity',
      background: Color(0xFF6750A4),
      foreground: Colors.white,
    ),
    'gemini': AgentBrand(
      label: 'gemini',
      background: Color(0xFF4285F4),
      foreground: Colors.white,
    ),
    'vim': AgentBrand(
      label: 'vim',
      background: Color(0xFF019833),
      foreground: Colors.white,
    ),
    'sepilot': AgentBrand(
      label: 'sepilot',
      background: Color(0xFF14B8A6),
      foreground: Colors.white,
    ),
  };

  static AgentBrand? forHint(String? agentHint) => _byHint[agentHint];
}

/// 세션 레일 타일 좌측에 표시하는 작은 브랜드 배지.
class AgentBrandBadge extends StatelessWidget {
  const AgentBrandBadge({super.key, required this.brand});

  final AgentBrand brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        brand.label,
        style: TextStyle(
          color: brand.foreground,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}
