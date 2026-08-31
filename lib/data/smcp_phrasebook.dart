import 'package:flutter/foundation.dart';

import '../models/speech_direction.dart';

/// A bridge-to-bridge phrase drawn from the IMO Standard Marine Communication
/// Phrases (SMCP).
@immutable
class MaritimePhrase {
  const MaritimePhrase({required this.english, required this.chinese});

  final String english;
  final String chinese;

  String source(SpeechDirection direction) =>
      direction == SpeechDirection.englishToChinese ? english : chinese;

  String target(SpeechDirection direction) =>
      direction == SpeechDirection.englishToChinese ? chinese : english;
}

/// Phrases the crew speaks in English (collision avoidance, pilotage, VTS).
const List<MaritimePhrase> englishPhrases = [
  MaritimePhrase(
    english: 'Vessel on my port bow, what are your intentions?',
    chinese: '我船左舷船首方向的船舶，你船意图如何？',
  ),
  MaritimePhrase(
    english: 'I am altering course to starboard, passing red to red.',
    chinese: '我船正在向右转向，红灯对红灯通过。',
  ),
  MaritimePhrase(
    english: 'Stand by on VHF channel one six.',
    chinese: '请在甚高频十六频道守听。',
  ),
  MaritimePhrase(
    english:
        'My present position is bearing zero four five, distance two miles.',
    chinese: '我船当前位置为方位零四五，距离两海里。',
  ),
  MaritimePhrase(
    english: 'Please reduce speed, I am overtaking on your starboard side.',
    chinese: '请减速，我船正从你船右舷追越。',
  ),
  MaritimePhrase(
    english: 'Anchor is aweigh, engine dead slow ahead.',
    chinese: '锚已离底，主机微速前进。',
  ),
  MaritimePhrase(
    english: 'Pilot boarding ground is two miles ahead, lee side to port.',
    chinese: '引航员登船点在前方两海里，下风舷为左舷。',
  ),
  MaritimePhrase(
    english: 'We require two tugs for berthing at zero six hundred hours.',
    chinese: '我船靠泊需要两艘拖轮协助，时间为零六时整。',
  ),
];

/// Phrases the crew speaks in Mandarin.
const List<MaritimePhrase> chinesePhrases = [
  MaritimePhrase(
    chinese: '本船吃水十二点五米，请确认航道水深。',
    english:
        'My draft is one two decimal five metres, please confirm the depth of the fairway.',
  ),
  MaritimePhrase(
    chinese: '我船主机故障，操纵能力受到限制。',
    english: 'I have engine trouble, I am restricted in my ability to manoeuvre.',
  ),
  MaritimePhrase(
    chinese: '请求进港许可，预计到达时间零八时三十分。',
    english: 'Request permission to enter port, my ETA is zero eight three zero.',
  ),
  MaritimePhrase(
    chinese: '收到，我船将在一号锚地等待引航员。',
    english: 'Roger, I will wait for the pilot at anchorage number one.',
  ),
  MaritimePhrase(chinese: '请重复你的最后一句话。', english: 'Say again your last message.'),
  MaritimePhrase(
    chinese: '前方有渔船作业，请注意避让。',
    english: 'Fishing vessels are operating ahead, keep clear.',
  ),
  MaritimePhrase(
    chinese: '缆绳已备妥，左舷靠泊。',
    english: 'Mooring lines are ready, we will berth port side alongside.',
  ),
  MaritimePhrase(
    chinese: '风力七级，涌浪两米，靠泊作业推迟。',
    english: 'Wind force seven, swell two metres, berthing operation is postponed.',
  ),
];

List<MaritimePhrase> phrasesFor(SpeechDirection direction) =>
    direction == SpeechDirection.englishToChinese
    ? englishPhrases
    : chinesePhrases;
