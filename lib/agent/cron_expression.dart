/// 표준 5필드 cron 표현식(`분 시 일 월 요일`).
///
/// 순수 Dart(Flutter 무관). 로컬 시간을 기준으로 "다음에 언제 맞는지"만 답하고,
/// 실제 타이머와 실행은 [AgentScheduler]가 맡는다.
///
/// 지원 문법: `*`, `a`, `a-b`, `*/n`, `a-b/n`, `a/n`, `a,b,c`, 월·요일 영문
/// 약어(`jan`, `mon`), 요일 `0`과 `7`은 모두 일요일, 프리셋 `@hourly` `@daily`
/// `@midnight` `@weekly` `@monthly` `@yearly` `@annually`. 일(日)과 요일이 둘 다
/// 제한되면 cron 관례대로 둘 중 하나만 맞아도 실행한다.
library;

class CronExpression {
  CronExpression._({
    required this.source,
    required this.minutes,
    required this.hours,
    required this.days,
    required this.months,
    required this.weekdays,
    required this.dayRestricted,
    required this.weekdayRestricted,
  });

  /// 프리셋을 풀고 공백을 정리한 표현식. 저장·표시에 쓴다.
  final String source;

  /// 각 필드에 맞는 값(오름차순, 중복 없음). 요일은 0(일)~6(토).
  final List<int> minutes;
  final List<int> hours;
  final List<int> days;
  final List<int> months;
  final List<int> weekdays;

  /// 일/요일 필드가 `*`가 아닌지. 둘 다 제한이면 OR로 본다.
  final bool dayRestricted;
  final bool weekdayRestricted;

  /// 다음 실행을 이 기간 안에서 찾지 못하면 없는 것으로 본다(예: 2월 30일).
  static const searchHorizonDays = 366 * 5;

  static const presets = <String, String>{
    '@yearly': '0 0 1 1 *',
    '@annually': '0 0 1 1 *',
    '@monthly': '0 0 1 * *',
    '@weekly': '0 0 * * 0',
    '@daily': '0 0 * * *',
    '@midnight': '0 0 * * *',
    '@hourly': '0 * * * *',
  };

  static const _monthNames = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];
  static const _weekdayNames = [
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
  ];
  static const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  /// 해석에 실패하면 [FormatException]. 메시지는 사용자에게 그대로 보여줄 수 있다.
  static CronExpression parse(String expression) {
    var text = expression.trim().toLowerCase();
    if (text.isEmpty) throw const FormatException('cron 표현식이 비어 있습니다.');
    text = presets[text] ?? text;
    final fields = text.split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw FormatException(
        'cron 표현식은 5개 필드(분 시 일 월 요일)여야 합니다. '
        '${fields.length}개를 받았습니다: "$expression"',
      );
    }
    final minutes = _parseField(fields[0], '분', 0, 59);
    final hours = _parseField(fields[1], '시', 0, 23);
    final days = _parseField(fields[2], '일', 1, 31);
    final months = _parseField(fields[3], '월', 1, 12, names: _monthNames);
    final weekdays = _parseField(
      fields[4],
      '요일',
      0,
      7,
      names: _weekdayNames,
      // 7도 일요일이다. 0으로 접어 중복을 없앤다.
      fold: (value) => value == 7 ? 0 : value,
    );
    return CronExpression._(
      source: fields.join(' '),
      minutes: minutes.values,
      hours: hours.values,
      days: days.values,
      months: months.values,
      weekdays: weekdays.values,
      dayRestricted: days.restricted,
      weekdayRestricted: weekdays.restricted,
    );
  }

  static CronExpression? tryParse(String expression) {
    try {
      return parse(expression);
    } on FormatException {
      return null;
    }
  }

  static ({List<int> values, bool restricted}) _parseField(
    String field,
    String label,
    int min,
    int max, {
    List<String>? names,
    int Function(int value)? fold,
  }) {
    final values = <int>{};
    var restricted = false;
    for (final entry in field.split(',')) {
      if (entry.isEmpty) {
        throw FormatException('$label 필드에 빈 항목이 있습니다: "$field"');
      }
      final slash = entry.indexOf('/');
      final base = slash == -1 ? entry : entry.substring(0, slash);
      var step = 1;
      if (slash != -1) {
        final parsed = int.tryParse(entry.substring(slash + 1));
        if (parsed == null || parsed <= 0) {
          throw FormatException('$label 필드의 간격이 잘못됐습니다: "$entry"');
        }
        step = parsed;
      }
      int start;
      int end;
      if (base == '*') {
        start = min;
        end = max;
      } else {
        final dash = base.indexOf('-');
        if (dash == -1) {
          start = _parseValue(base, label, min, max, names);
          // vixie cron: `5/10`은 5부터 끝까지 10 간격이다.
          end = slash == -1 ? start : max;
        } else {
          start = _parseValue(base.substring(0, dash), label, min, max, names);
          end = _parseValue(base.substring(dash + 1), label, min, max, names);
          if (start > end) {
            throw FormatException('$label 필드의 범위가 뒤집혀 있습니다: "$entry"');
          }
        }
        restricted = true;
      }
      if (base == '*' && step > 1) restricted = true;
      for (var value = start; value <= end; value += step) {
        values.add(fold == null ? value : fold(value));
      }
    }
    return (values: values.toList()..sort(), restricted: restricted);
  }

  static int _parseValue(
    String text,
    String label,
    int min,
    int max,
    List<String>? names,
  ) {
    var value = int.tryParse(text);
    if (value == null && names != null) {
      final index = names.indexOf(text);
      if (index != -1) value = index + (names == _monthNames ? 1 : 0);
    }
    if (value == null || value < min || value > max) {
      throw FormatException('$label 필드 값이 잘못됐습니다: "$text" ($min~$max)');
    }
    return value;
  }

  bool _dayMatches(DateTime day) {
    final dom = days.contains(day.day);
    final dow = weekdays.contains(day.weekday % 7);
    if (dayRestricted && weekdayRestricted) return dom || dow;
    if (dayRestricted) return dom;
    if (weekdayRestricted) return dow;
    return true;
  }

  /// [at]의 분 단위 시각이 표현식에 맞는지.
  bool matches(DateTime at) =>
      months.contains(at.month) &&
      _dayMatches(at) &&
      hours.contains(at.hour) &&
      minutes.contains(at.minute);

  /// [now] 뒤(같은 분 제외) 처음 맞는 로컬 시각. [searchHorizonDays] 안에 없으면 null.
  DateTime? nextAfter(DateTime now) {
    final local = now.toLocal();
    final floorMinute = local.hour * 60 + local.minute + 1;
    for (var offset = 0; offset < searchHorizonDays; offset++) {
      final day = DateTime(local.year, local.month, local.day + offset);
      if (!months.contains(day.month) || !_dayMatches(day)) continue;
      final floor = offset == 0 ? floorMinute : 0;
      for (final hour in hours) {
        if (hour * 60 + 59 < floor) continue;
        for (final minute in minutes) {
          if (hour * 60 + minute < floor) continue;
          final candidate = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          );
          // DST 전환으로 존재하지 않는 시각은 앞뒤로 밀린다. 과거로 가면 버린다.
          if (candidate.isAfter(local)) return candidate;
        }
      }
    }
    return null;
  }

  /// 사용자에게 보여줄 짧은 설명. 흔한 패턴은 우리말로, 그 밖에는 원문을 붙인다.
  String get label {
    final everyMonth = months.length == 12;
    final everyDay = !dayRestricted && !weekdayRestricted && everyMonth;
    if (minutes.length == 1 && hours.length == 1) {
      final time = '${_two(hours.first)}:${_two(minutes.first)}';
      if (everyDay) return '매일 $time';
      if (everyMonth && !dayRestricted && weekdayRestricted) {
        final names = weekdays.map((d) => _weekdayLabels[d]).join('·');
        return '매주 $names $time';
      }
      if (everyMonth &&
          dayRestricted &&
          !weekdayRestricted &&
          days.length == 1) {
        return '매월 ${days.first}일 $time';
      }
    }
    if (everyDay && hours.length == 24) {
      if (minutes.length == 1) return '매시 ${_two(minutes.first)}분';
      final step = _uniformStep(minutes, 60);
      if (step != null) return '$step분마다';
    }
    if (everyDay && minutes.length == 1 && minutes.first == 0) {
      final step = _uniformStep(hours, 24);
      if (step != null) return '$step시간마다';
    }
    return 'cron $source';
  }

  /// 0부터 같은 간격으로 [span]을 덮는 목록이면 그 간격.
  static int? _uniformStep(List<int> values, int span) {
    if (values.length < 2 || values.first != 0) return null;
    final step = values[1] - values[0];
    for (var i = 1; i < values.length; i++) {
      if (values[i] - values[i - 1] != step) return null;
    }
    return values.last + step > span - 1 ? step : null;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  bool operator ==(Object other) =>
      other is CronExpression && other.source == source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'CronExpression($source)';
}
