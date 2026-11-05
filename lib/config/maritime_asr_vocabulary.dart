/// Compact terminology selected during the maritime dialogue revision.
/// Domain bias only: never replaces a transcript or infers a command/value.
abstract final class MaritimeAsrVocabulary {
  static const english =
      'VTS, VHF, CPA, UKC, ETA, GM, SWL. '
      'Pilot ladder, pilot chart, passage plan, Port bow, starboard side, '
      'anchorage, draught, knots, mooring, breast wire, messenger rope, '
      'hawser, shackle, capstan, windlass, oily water separator, quick closing valve. '
      'Stand by engine. Finished with engines. Half ahead. Full astern. Mayday. Over.';
  static const chinese =
      '海事对话。引航员，引航梯，航路设计图，航次计划，左舷首，右舷，'
      '锚地，吃水，航速，海里，节，系泊，横缆，倒缆，引缆，钢丝绳，'
      '卸扣，绞缆机，锚机，分油机，油水分离器，速闭阀，初稳性高度。'
      '备车，完车，半速前进，全速后退。VTS，CPA，UKC，ETA，GM。';
}
