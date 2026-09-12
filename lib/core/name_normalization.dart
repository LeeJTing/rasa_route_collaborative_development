/// Best-effort Traditional → Simplified Chinese folding for dish and place
/// names used by matching.
///
/// Gemini and submitted text frequently mix scripts (天義 vs 天义, 福建麵 vs
/// 福建面). Matching used to only lowercase and compare bytes, so a
/// traditional variant never matched its simplified sibling and the same real
/// dish / shop got duplicated (`local_food` rows, submitted landmarks).
/// This is the one shared normalisation both the food matcher and the
/// place-name lookups use, so every comparison folds scripts the same way.
///
/// Folding is char-level over the FULL OpenCC Traditional → Simplified
/// dataset (generated into `simplified_chinese_data.dart` - see
/// `tools/generate_simplified_map.py`), plus a small curated override map
/// tuned for Malaysian food/shop vocabulary. Unknown glyphs pass through
/// unchanged.
library;

import 'simplified_chinese_data.dart' as opencc;

/// Curated overrides/extras on top of the generated full OpenCC map.
const Map<String, String> traditionalToSimplified = <String, String>{
  // Shop / place-name characters.
  '義': '义',
  '臺': '台',
  '裡': '里',
  '裏': '里',
  '東': '东',
  '馬': '马',
  '來': '来',
  '亞': '亚',
  '國': '国',
  '學': '学',
  '萬': '万',
  '與': '与',
  '為': '为',
  '雲': '云',
  '電': '电',
  '車': '车',
  '龍': '龙',
  '鳳': '凤',
  '寶': '宝',
  '貝': '贝',
  '貴': '贵',
  '買': '买',
  '賣': '卖',
  '錢': '钱',
  '銀': '银',
  '號': '号',
  '門': '门',
  '樓': '楼',
  '館': '馆',
  '鋪': '铺',
  '檔': '档',
  '攤': '摊',
  '販': '贩',
  '場': '场',
  '園': '园',
  '閣': '阁',
  '廈': '厦',
  '廟': '庙',
  '區': '区',
  '縣': '县',
  '鎮': '镇',
  '鄉': '乡',
  '橋': '桥',
  '島': '岛',
  '灣': '湾',
  '頭': '头',
  '華': '华',
  '蘭': '兰',
  '檳': '槟',
  '關': '关',
  '當': '当',
  '時': '时',
  '間': '间',
  '點': '点',
  '熱': '热',
  // Food / dish characters.
  '麵': '面',
  '麪': '面',
  '雞': '鸡',
  '豬': '猪',
  '魚': '鱼',
  '蝦': '虾',
  '飯': '饭',
  '湯': '汤',
  '醬': '酱',
  '蠔': '蚝',
  '參': '参',
  '鍋': '锅',
  '燒': '烧',
  '燉': '炖',
  '燜': '焖',
  '滷': '卤',
  '腸': '肠',
  '條': '条',
  '餃': '饺',
  '飽': '饱',
  '飲': '饮',
  '蔥': '葱',
  '薑': '姜',
  '蓮': '莲',
  '餅': '饼',
  '餡': '馅',
  '撻': '挞',
  '鬆': '松',
  '軟': '软',
  '滾': '滚',
  '燙': '烫',
  '燴': '烩',
  '釀': '酿',
  '醃': '腌',
  '斬': '斩',
  '瀨': '濑',
  '饅': '馒',
  '撈': '捞',
  '乾': '干',
  '幹': '干',
  '壺': '壶',
  '鹽': '盐',
  '黃': '黄',
  '綠': '绿',
  '紅': '红',
};

/// Returns [value] with Traditional Chinese glyphs replaced by their
/// Simplified forms. The full OpenCC-derived map is consulted first, then the
/// curated overrides; characters without a mapping are returned unchanged.
String toSimplifiedChinese(String value) {
  if (value.isEmpty) return value;
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    final String character = String.fromCharCode(rune);
    buffer.write(
      opencc.traditionalToSimplified[character] ??
          traditionalToSimplified[character] ??
          character,
    );
  }
  return buffer.toString();
}

/// The equality key used when deciding whether two PLACE names are the same:
/// trimmed, Traditional → Simplified folded, lowercased.
///
/// Interior punctuation is deliberately kept (matching byte-for-byte beyond
/// script folding): a shop name containing "&" or "-" must not start matching
/// an unrelated name just because punctuation was dropped. Only scripts are
/// folded here - the broader punctuation collapsing stays in the food matcher,
/// where a Gemini dish name is fuzzy-matched anyway.
String placeNameKey(String value) =>
    toSimplifiedChinese(value.trim()).toLowerCase();

/// Glyphs that appear ONLY in Traditional Chinese (OpenCC maps them to a
/// different Simplified glyph) and glyphs that appear ONLY in Simplified
/// Chinese (the targets of those mappings). Glyphs on both sides - e.g. 干,
/// which simplified both 乾 and 幹 - prove nothing about the style and are
/// deliberately in neither set; so do Simplified TARGETS that are legitimate
/// Traditional glyphs in their own right (后 in 皇后 - see
/// [_dualRoleSimplified]). Built once, lazily.
final ({Set<String> traditionalOnly, Set<String> simplifiedOnly})
_scriptGlyphs = _buildScriptGlyphs();

({Set<String> traditionalOnly, Set<String> simplifiedOnly})
_buildScriptGlyphs() {
  final Set<String> traditional = <String>{};
  final Set<String> simplified = <String>{};
  for (final Map<String, String> map in <Map<String, String>>[
    opencc.traditionalToSimplified,
    traditionalToSimplified,
  ]) {
    for (final MapEntry<String, String> entry in map.entries) {
      if (entry.key == entry.value) continue;
      traditional.add(entry.key);
      simplified.add(entry.value);
    }
  }
  return (
    traditionalOnly: traditional.difference(simplified),
    // Simplified glyphs that are ALSO legitimate Traditional forms prove
    // nothing either - a Traditional sign may legally paint them (皇后).
    simplifiedOnly: simplified
        .difference(traditional)
        .difference(_dualRoleSimplified),
  );
}

/// The Chinese script STYLE of [value]:
///  * "traditional" - at least one Traditional-only glyph;
///  * "simplified" - at least one Simplified-only glyph;
///  * "mixed" - both styles appear;
///  * "unknown" - no style-specific glyph at all (shared by both styles, or
///    not Chinese - "海天" looks the same in either style).
///
/// Callers use this to check a signboard transcription against the style
/// reported as PAINTED on the sign: a name that carries the other style's
/// glyphs cannot be an exact copy of the signboard.
String chineseScriptStyleOf(String value) {
  bool hasTraditional = false;
  bool hasSimplified = false;
  for (final int rune in value.runes) {
    final String character = String.fromCharCode(rune);
    if (_scriptGlyphs.traditionalOnly.contains(character)) {
      hasTraditional = true;
    } else if (_scriptGlyphs.simplifiedOnly.contains(character)) {
      hasSimplified = true;
    }
    if (hasTraditional && hasSimplified) return 'mixed';
  }
  if (hasTraditional) return 'traditional';
  if (hasSimplified) return 'simplified';
  return 'unknown';
}

/// Simplified glyphs with exactly ONE provable Traditional origin, used to
/// RESTORE a transcription that contradicts the Chinese style reported for
/// the sign ("义" can only have been painted as "義"). A glyph qualifies
/// only when both sides are provably style-specific - the sets already
/// exclude dual-role glyphs (see [_dualRoleSimplified]). Built once, lazily,
/// from the same maps as [_scriptGlyphs].
final Map<String, String> _traditionalForSimplified =
    _buildTraditionalForSimplified();

Map<String, String> _buildTraditionalForSimplified() {
  final ({Set<String> traditionalOnly, Set<String> simplifiedOnly}) glyphs =
      _scriptGlyphs;
  final Map<String, Set<String>> origins = <String, Set<String>>{};
  for (final Map<String, String> map in <Map<String, String>>[
    opencc.traditionalToSimplified,
    traditionalToSimplified,
  ]) {
    for (final MapEntry<String, String> entry in map.entries) {
      if (entry.key == entry.value) continue;
      if (!glyphs.simplifiedOnly.contains(entry.value)) continue;
      if (!glyphs.traditionalOnly.contains(entry.key)) continue;
      (origins[entry.value] ??= <String>{}).add(entry.key);
    }
  }
  return <String, String>{
    for (final MapEntry<String, Set<String>> entry in origins.entries)
      if (entry.value.length == 1) entry.key: entry.value.single,
  };
}

/// Simplified glyphs that are ALSO legitimate Traditional glyphs in their
/// own right - "后" is 皇后 in both styles, "只", "系", "表" and friends are
/// normal Traditional characters as well. Restoring them to their complex
/// sibling could invent a character the sign never painted, so they are
/// never converted.
const Set<String> _dualRoleSimplified = <String>{
  '后',
  '台',
  '里',
  '面',
  '干',
  '布',
  '只',
  '系',
  '制',
  '表',
  '冲',
  '才',
  '划',
  '舍',
  '采',
  '叶',
  '丑',
  '准',
  '胡',
  '须',
  '余',
  '谷',
  '于',
  '与',
  '云',
  '斗',
  '丰',
  '万',
  '宁',
  '郁',
  '泄',
  '游',
  '志',
  '彩',
  '卷',
  '蒙',
  '昆',
  '挂',
};

/// [value] RESTORED to [scriptVariant], the Chinese style the model reported
/// as painted on the signboard: with a "traditional" claim, Simplified-only
/// glyphs with a provable origin become Traditional again ("义" -> "義");
/// with a "simplified" claim, Traditional-only glyphs fold ("樓" -> "楼").
/// This is how the app enforces "return the form you detected" - a
/// transcription that contradicts its own style report is corrected to the
/// reported style instead of being thrown away.
///
/// Glyphs that cannot be converted with certainty pass through untouched:
/// "发" is the Simplified form of both 發 and 髮, and "后" is valid in both
/// styles. A partial conversion is visible by comparing the result with
/// [value]. Any claim other than the two styles ("mixed", "n/a") returns
/// [value] unchanged.
String correctChineseScriptStyle(String value, String scriptVariant) {
  if (scriptVariant != 'traditional' && scriptVariant != 'simplified') {
    return value;
  }
  if (value.isEmpty) return value;
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    final String character = String.fromCharCode(rune);
    String written = character;
    if (scriptVariant == 'traditional') {
      if (_scriptGlyphs.simplifiedOnly.contains(character)) {
        written = _traditionalForSimplified[character] ?? character;
      }
    } else if (_scriptGlyphs.traditionalOnly.contains(character)) {
      written =
          opencc.traditionalToSimplified[character] ??
          traditionalToSimplified[character] ??
          character;
    }
    buffer.write(written);
  }
  return buffer.toString();
}
