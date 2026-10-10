## MODIFIED Requirements

### Requirement: History word count uses linguistic tokenizer
The HistoryView SHALL count words using the `voiceTextWordCount(in:)` linguistic tokenizer (which uses `enumerateSubstrings(.byWords)`) instead of whitespace-based splitting. This ensures consistent word counting between VoiceToTextView usage stats and HistoryView session badges, particularly for CJK text where whitespace splitting produces incorrect counts.

#### Scenario: Word count for English text
- **WHEN** a session with English text "Hello world test" is displayed in HistoryView
- **THEN** the word count badge SHALL show "3 words"
- **THEN** this SHALL match the count returned by `voiceTextWordCount(in:)`

#### Scenario: Word count for CJK text
- **WHEN** a session with Chinese text "你好世界测试" is displayed in HistoryView
- **THEN** the word count SHALL use linguistic word boundary detection
- **THEN** the count SHALL match `voiceTextWordCount(in:)` (not whitespace split which would return 1)

#### Scenario: Word count for mixed text
- **WHEN** a session with mixed CJK and Latin text is displayed
- **THEN** the word count SHALL correctly tokenize both scripts using the linguistic tokenizer
