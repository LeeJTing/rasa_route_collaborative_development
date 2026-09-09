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
