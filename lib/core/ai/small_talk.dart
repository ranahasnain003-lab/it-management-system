/// Recognises a message that is ONLY small talk - "Hello", "Assalam o
/// Alaikum", "How are you?", "Good morning", "Thanks", "Khuda Hafiz" - so the
/// assistants can answer it as conversation rather than as an inventory
/// question.
///
/// Both assistants need the same line drawn in the same place:
///
///   * the in-app assistant (InventoryAssistant) would otherwise fall through
///     every inventory rule and ask which figure was meant;
///   * the Local AI context builder would otherwise read a short message that
///     names nothing as a follow-up, and send the previous question's records
///     (or the whole inventory overview) along with a greeting.
///
/// The test is strict on purpose: every word must belong to a greeting, a
/// "how are you", a thank-you, a farewell, or a short list of fillers ("sir",
/// "there", "again"). "Hello, how many laptops are at Head Office?" leaves
/// "how many laptops at head office" over, so it is NOT small talk and is
/// answered from the inventory exactly as before. A false "no" costs nothing
/// new - the message is handled as it always was - while a false "yes" would
/// swallow a question, so anything unrecognised counts as a question.
library;

/// What kind of small talk a message is. One message can be several ("Hi,
/// how are you?"), so the reply can answer all of it.
enum SmallTalkKind { greeting, salam, howAreYou, thanks, farewell }

class SmallTalk {
  const SmallTalk._(this.kinds, {required this.timeOfDay, required this.hafiz});

  final Set<SmallTalkKind> kinds;

  /// "morning", "afternoon" or "evening" when the greeting named one.
  final String? timeOfDay;

  /// The farewell was "Khuda Hafiz" / "Allah Hafiz", answered in kind.
  final bool hafiz;

  /// Longer messages are questions with a greeting in front, not small talk.
  static const int _maxWords = 12;

  /// The message as [SmallTalk], or null when it is anything more than small
  /// talk - including an empty message.
  static SmallTalk? read(String message) {
    final words = _normalise(message);
    if (words.isEmpty || words.length > _maxWords) return null;

    final kinds = <SmallTalkKind>{};
    String? timeOfDay;
    var hafiz = false;

    var i = 0;
    while (i < words.length) {
      final match = _phraseAt(words, i);
      if (match != null) {
        kinds.add(match.kind);
        timeOfDay ??= match.timeOfDay;
        hafiz = hafiz || match.hafiz;
        i += match.length;
        continue;
      }
      if (_fillers.contains(words[i])) {
        i++;
        continue;
      }
      // A word that is neither small talk nor a filler: a real question.
      return null;
    }

    if (kinds.isEmpty) return null;
    return SmallTalk._(kinds, timeOfDay: timeOfDay, hafiz: hafiz);
  }

  /// A short, natural answer that names no figure, so it can never state an
  /// inventory fact - for the in-app assistant, which has no language model
  /// to phrase one.
  String get reply {
    final salam = kinds.contains(SmallTalkKind.salam);
    final thanks = kinds.contains(SmallTalkKind.thanks);
    const welcome = "You're welcome!";

    // A goodbye is answered as one, whatever came before it: "salam, khuda
    // hafiz" is someone leaving, not arriving.
    if (kinds.contains(SmallTalkKind.farewell)) {
      return [
        if (thanks) welcome,
        hafiz ? 'Allah Hafiz!' : 'Goodbye!',
        'I am here whenever you need the inventory.',
      ].join(' ');
    }

    final opening = salam
        ? 'Wa alaikum assalam!'
        : timeOfDay != null
        ? 'Good $timeOfDay!'
        : kinds.contains(SmallTalkKind.greeting)
        ? 'Hello!'
        : null;

    const offer = 'How can I help you with the inventory today?';

    if (kinds.contains(SmallTalkKind.howAreYou)) {
      return [
        ?opening,
        "I'm doing well, thank you for asking.",
        offer,
      ].join(' ');
    }

    // "Thanks" answered as thanks; only a salam is returned alongside it.
    if (thanks) {
      return [
        if (salam) 'Wa alaikum assalam!',
        welcome,
        'Ask me about the inventory whenever you need.',
      ].join(' ');
    }

    return '${opening ?? 'Hello!'} $offer';
  }

  // ---------------------------------------------------------------- reading

  /// Lower-case words, with punctuation, emoji and apostrophes taken out, so
  /// "Assalam-o-Alaikum!", "how's it going?" and "Hi 👋" read like their
  /// plain spellings. Letters of any script are kept, for Urdu; its optional
  /// vowel and shadda marks are dropped, so "اللّٰہ" reads as "اللہ".
  static List<String> _normalise(String message) {
    return message
        .toLowerCase()
        .replaceAll(RegExp(r"['’`]"), '')
        .replaceAll(RegExp(r'\p{M}', unicode: true), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static _Match? _phraseAt(List<String> words, int start) {
    // Longest phrase first, so "good morning" is not read as a stray "good".
    _Match? best;
    for (final phrase in _phrases) {
      final length = phrase.words.length;
      if (start + length > words.length) continue;
      if (best != null && length <= best.length) continue;

      var matches = true;
      for (var k = 0; k < length; k++) {
        if (!_wordMatches(phrase.words[k], words[start + k])) {
          matches = false;
          break;
        }
      }
      if (matches) best = _Match(phrase, length);
    }
    return best;
  }

  /// A phrase word is a literal, or one of the word classes below.
  static bool _wordMatches(String pattern, String word) {
    switch (pattern) {
      case _salamWord:
        return _salam.hasMatch(word) ||
            _aslamAlaikum.hasMatch(word) ||
            _urduSalam.contains(word);
      case _aslamWord:
        return _aslam.hasMatch(word);
      case _alaikumWord:
        return _alaikum.hasMatch(word) || _urduAlaikum.contains(word);
      case _hiWord:
        return _hi.hasMatch(word);
      case _rahmaWord:
        return _rahma.hasMatch(word);
      default:
        return pattern == word;
    }
  }

  // "salam", "salaam", "assalam", "asalam", "assalamu", "salamo", "alsalam",
  // and the one-word "assalamualaikum" / "asalamoalaikum" / "salamalaikum".
  // The "s" is required, so the names "Alam" and "Aslam" are not greetings.
  static final RegExp _salam = RegExp(
    r'^(?:a?s+|als)ala+m+[uo]?(?:a?l[ae]?i?y?k[uo]m)?$',
  );

  // The common spelling "aslam", accepted only where it cannot be the name:
  // joined to "alaikum" in one word here, or followed by it (see _phrases).
  static final RegExp _aslamAlaikum = RegExp(
    r'^as+lam[uo]?a?l[ae]?i?y?k[uo]m$',
  );
  static final RegExp _aslam = RegExp(r'^as+lam[uo]?$');

  // "rahmatullah", "rehmatullah", "barakatuhu", "barakatuh": the longer
  // salam's closing words.
  static final RegExp _rahma = RegExp(
    r'^(?:r[ae]h?ma+tu?l+ah?i?|baraka+tu+hu?)$',
  );

  // "alaikum", "alaykum", "alykum", "aleikum", and the replies "walaikum",
  // "waalaikum", "walaikumassalam", "walaikumsalam".
  static final RegExp _alaikum = RegExp(
    r'^(?:wa?)?a?l[ae]?i?y?k[uo]m(?:(?:as+|s)ala+m+)?$',
  );

  // "hi", "hii", "hey", "heyy", "hello", "helloo", "helo", "hallo", "hiya",
  // and the chat spellings "hlo", "hlw", "hy", "hye".
  static final RegExp _hi = RegExp(
    r'^(?:hi+|he+y+|hel+o+w?|hal+o+|hiya|heya|hl+o+|hlw|hy+e?)$',
  );

  static const Set<String> _urduSalam = {'السلام', 'اسلام', 'سلام', 'والسلام'};
  static const Set<String> _urduAlaikum = {
    'علیکم',
    'عليكم',
    'وعلیکم',
    'وعليكم',
  };

  static const String _salamWord = '<salam>';
  static const String _aslamWord = '<aslam>';
  static const String _alaikumWord = '<alaikum>';
  static const String _hiWord = '<hi>';
  static const String _rahmaWord = '<rahma>';

  static const List<_Phrase> _phrases = [
    // Greetings.
    _Phrase([_hiWord], SmallTalkKind.greeting),
    _Phrase(['greetings'], SmallTalkKind.greeting),
    _Phrase(['good', 'morning'], SmallTalkKind.greeting, timeOfDay: 'morning'),
    _Phrase(
      ['good', 'afternoon'],
      SmallTalkKind.greeting,
      timeOfDay: 'afternoon',
    ),
    _Phrase(['good', 'evening'], SmallTalkKind.greeting, timeOfDay: 'evening'),
    _Phrase(['morning'], SmallTalkKind.greeting, timeOfDay: 'morning'),
    _Phrase(['good', 'day'], SmallTalkKind.greeting),
    _Phrase(['gud', 'morning'], SmallTalkKind.greeting, timeOfDay: 'morning'),
    _Phrase(
      ['gud', 'afternoon'],
      SmallTalkKind.greeting,
      timeOfDay: 'afternoon',
    ),
    _Phrase(['gud', 'evening'], SmallTalkKind.greeting, timeOfDay: 'evening'),
    _Phrase(['ہیلو'], SmallTalkKind.greeting),
    _Phrase(['aoa'], SmallTalkKind.salam),
    _Phrase([_salamWord], SmallTalkKind.salam),
    _Phrase([_alaikumWord], SmallTalkKind.salam),
    // "assalam o alaikum", "as salamu alaykum", "salam alaikum", "wa alaikum
    // assalam": the connecting words only count between the two halves.
    _Phrase([_salamWord, _alaikumWord], SmallTalkKind.salam),
    _Phrase([_salamWord, 'o', _alaikumWord], SmallTalkKind.salam),
    _Phrase([_salamWord, 'u', _alaikumWord], SmallTalkKind.salam),
    _Phrase(['as', _salamWord, _alaikumWord], SmallTalkKind.salam),
    _Phrase(['wa', _alaikumWord, _salamWord], SmallTalkKind.salam),
    _Phrase([_alaikumWord, _salamWord], SmallTalkKind.salam),
    _Phrase(['wa', _alaikumWord, 'as', _salamWord], SmallTalkKind.salam),
    _Phrase(['wa', _alaikumWord], SmallTalkKind.salam),
    _Phrase(['w', _salamWord], SmallTalkKind.salam),
    _Phrase([_salamWord, 'و', _alaikumWord], SmallTalkKind.salam),
    // "Aslam o alaikum": "aslam" only counts when "alaikum" follows it.
    _Phrase([_aslamWord, _alaikumWord], SmallTalkKind.salam),
    _Phrase([_aslamWord, 'o', _alaikumWord], SmallTalkKind.salam),
    _Phrase([_aslamWord, 'u', _alaikumWord], SmallTalkKind.salam),
    // "... wa rahmatullah wa barakatuhu" closing a salam - only after "wa",
    // because "Rahmatullah" on its own is also a name.
    _Phrase(['wa', _rahmaWord], SmallTalkKind.salam),

    // How are you.
    _Phrase(['how', 'are', 'you'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'are', 'u'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'r', 'u'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'r', 'you'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'are', 'you', 'doing'], SmallTalkKind.howAreYou),
    // "today" only inside the phrase: on its own it is a movement window.
    _Phrase(['how', 'are', 'you', 'today'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'are', 'you', 'doing', 'today'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'are', 'u', 'doing'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'r', 'u', 'doing'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'is', 'your', 'day'], SmallTalkKind.howAreYou),
    _Phrase(['hows', 'your', 'day'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'is', 'it', 'going'], SmallTalkKind.howAreYou),
    _Phrase(['hows', 'it', 'going'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'have', 'you', 'been'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'do', 'you', 'do'], SmallTalkKind.howAreYou),
    _Phrase(['whats', 'up'], SmallTalkKind.howAreYou),
    _Phrase(['and', 'you'], SmallTalkKind.howAreYou),
    _Phrase(['how', 'about', 'you'], SmallTalkKind.howAreYou),
    _Phrase(['kaise', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['kaisay', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['kese', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['kaisi', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['kaise', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['kaisay', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['kese', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['kesy', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['aap', 'kaise', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['aap', 'kaise', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['ap', 'kaise', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['ap', 'kaise', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['app', 'kaise', 'ho'], SmallTalkKind.howAreYou),
    _Phrase(['app', 'kaise', 'hain'], SmallTalkKind.howAreYou),
    _Phrase(['kaise', 'hain', 'aap'], SmallTalkKind.howAreYou),
    _Phrase(['kaisay', 'hain', 'aap'], SmallTalkKind.howAreYou),
    _Phrase(['kya', 'haal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['kia', 'haal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['kya', 'hal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['kia', 'hal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['kaisa', 'hal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['kya', 'haal', 'chaal', 'hai'], SmallTalkKind.howAreYou),
    _Phrase(['آپ', 'کیسے', 'ہیں'], SmallTalkKind.howAreYou),
    _Phrase(['کیا', 'حال', 'ہے'], SmallTalkKind.howAreYou),

    // Thanks.
    _Phrase(['thanks'], SmallTalkKind.thanks),
    _Phrase(['thank', 'you'], SmallTalkKind.thanks),
    _Phrase(['thank', 'u'], SmallTalkKind.thanks),
    _Phrase(['thankyou'], SmallTalkKind.thanks),
    _Phrase(['thx'], SmallTalkKind.thanks),
    _Phrase(['thnx'], SmallTalkKind.thanks),
    _Phrase(['thanx'], SmallTalkKind.thanks),
    _Phrase(['thnks'], SmallTalkKind.thanks),
    _Phrase(['ty'], SmallTalkKind.thanks),
    _Phrase(['shukriya'], SmallTalkKind.thanks),
    _Phrase(['shukria'], SmallTalkKind.thanks),
    _Phrase(['shukran'], SmallTalkKind.thanks),
    _Phrase(['jazakallah'], SmallTalkKind.thanks),
    _Phrase(['jazak', 'allah'], SmallTalkKind.thanks),
    _Phrase(['شکریہ'], SmallTalkKind.thanks),

    // Farewells.
    _Phrase(['bye'], SmallTalkKind.farewell),
    _Phrase(['goodbye'], SmallTalkKind.farewell),
    _Phrase(['good', 'bye'], SmallTalkKind.farewell),
    _Phrase(['good', 'night'], SmallTalkKind.farewell),
    _Phrase(['see', 'you'], SmallTalkKind.farewell),
    _Phrase(['see', 'you', 'later'], SmallTalkKind.farewell),
    _Phrase(['see', 'ya'], SmallTalkKind.farewell),
    _Phrase(['good', 'nite'], SmallTalkKind.farewell),
    _Phrase(['gud', 'night'], SmallTalkKind.farewell),
    _Phrase(['take', 'care'], SmallTalkKind.farewell),
    _Phrase(['khuda', 'hafiz'], SmallTalkKind.farewell, hafiz: true),
    _Phrase(['allah', 'hafiz'], SmallTalkKind.farewell, hafiz: true),
    _Phrase(['khudahafiz'], SmallTalkKind.farewell, hafiz: true),
    _Phrase(['allahhafiz'], SmallTalkKind.farewell, hafiz: true),
    _Phrase(['خدا', 'حافظ'], SmallTalkKind.farewell, hafiz: true),
    _Phrase(['اللہ', 'حافظ'], SmallTalkKind.farewell, hafiz: true),
  ];

  /// Words that may stand next to small talk without making it a question:
  /// forms of address, politeness and intensifiers. Deliberately no word
  /// that could carry an inventory question on its own.
  static const Set<String> _fillers = {
    'there',
    'dear',
    'sir',
    'madam',
    'maam',
    'mam',
    'bro',
    'buddy',
    'friend',
    'team',
    'all',
    'everyone',
    'again',
    'too',
    'and',
    'so',
    'much',
    'very',
    'a',
    'lot',
    'alot',
    'ji',
    'jee',
    'janab',
    'sahib',
    'sahab',
    'bhai',
    'assistant',
    'ai',
    'bot',
    'ok',
    'okay',
    'oh',
    'well',
    'bohat',
    'bahut',
    'bht',
    'khair',
    'اور',
    'جی',
    'بہت',
  };
}

class _Phrase {
  const _Phrase(this.words, this.kind, {this.timeOfDay, this.hafiz = false});

  final List<String> words;
  final SmallTalkKind kind;
  final String? timeOfDay;
  final bool hafiz;
}

class _Match {
  _Match(_Phrase phrase, this.length)
    : kind = phrase.kind,
      timeOfDay = phrase.timeOfDay,
      hafiz = phrase.hafiz;

  final SmallTalkKind kind;
  final String? timeOfDay;
  final bool hafiz;
  final int length;
}
