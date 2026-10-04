CREATE TABLE word_books (
    id TEXT NOT NULL PRIMARY KEY CHECK(length(id) = 36 AND substr(id,9,1) = '-' AND substr(id,14,1) = '-' AND substr(id,19,1) = '-' AND substr(id,24,1) = '-' AND length(replace(id,'-','')) = 32 AND id NOT GLOB '*[^0-9a-f-]*'),
    name TEXT NOT NULL,
    book_description TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    is_built_in INTEGER NOT NULL CHECK(is_built_in IN (0,1))
) STRICT;

CREATE TABLE vocabulary_words (
    id TEXT NOT NULL PRIMARY KEY CHECK(length(id) = 36 AND substr(id,9,1) = '-' AND substr(id,14,1) = '-' AND substr(id,19,1) = '-' AND substr(id,24,1) = '-' AND length(replace(id,'-','')) = 32 AND id NOT GLOB '*[^0-9a-f-]*'),
    japanese TEXT NOT NULL,
    kana TEXT NOT NULL,
    chinese_meaning TEXT NOT NULL,
    part_of_speech TEXT NOT NULL,
    jlpt_level TEXT NOT NULL,
    example_japanese TEXT NOT NULL,
    example_chinese TEXT NOT NULL,
    tags TEXT NOT NULL CHECK(json_valid(tags) AND json_type(tags) = 'array'),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    is_archived INTEGER NOT NULL CHECK(is_archived IN (0,1)),
    is_favorite INTEGER NOT NULL CHECK(is_favorite IN (0,1)),
    loanword_source_term TEXT,
    loanword_source_language_code TEXT,
    loanword_is_wasei INTEGER NOT NULL CHECK(loanword_is_wasei IN (0,1)),
    loanword_is_partial INTEGER NOT NULL CHECK(loanword_is_partial IN (0,1)),
    word_book_id TEXT CHECK(length(word_book_id) = 36 AND substr(word_book_id,9,1) = '-' AND substr(word_book_id,14,1) = '-' AND substr(word_book_id,19,1) = '-' AND substr(word_book_id,24,1) = '-' AND length(replace(word_book_id,'-','')) = 32 AND word_book_id NOT GLOB '*[^0-9a-f-]*') REFERENCES word_books(id) ON DELETE CASCADE
) STRICT;

CREATE TABLE learning_progress (
    id TEXT NOT NULL PRIMARY KEY CHECK(length(id) = 36 AND substr(id,9,1) = '-' AND substr(id,14,1) = '-' AND substr(id,19,1) = '-' AND substr(id,24,1) = '-' AND length(replace(id,'-','')) = 32 AND id NOT GLOB '*[^0-9a-f-]*'),
    word_id TEXT NOT NULL UNIQUE CHECK(length(word_id) = 36 AND substr(word_id,9,1) = '-' AND substr(word_id,14,1) = '-' AND substr(word_id,19,1) = '-' AND substr(word_id,24,1) = '-' AND length(replace(word_id,'-','')) = 32 AND word_id NOT GLOB '*[^0-9a-f-]*') REFERENCES vocabulary_words(id) ON DELETE CASCADE,
    state TEXT NOT NULL CHECK(state IN ('new','learning','relearning','review','suspended')),
    due_at INTEGER NOT NULL,
    interval_days INTEGER NOT NULL CHECK(interval_days >= 0),
    review_count INTEGER NOT NULL CHECK(review_count >= 0),
    lapse_count INTEGER NOT NULL CHECK(lapse_count >= 0),
    last_reviewed_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
) STRICT;

CREATE TABLE review_logs (
    id TEXT NOT NULL PRIMARY KEY CHECK(length(id) = 36 AND substr(id,9,1) = '-' AND substr(id,14,1) = '-' AND substr(id,19,1) = '-' AND substr(id,24,1) = '-' AND length(replace(id,'-','')) = 32 AND id NOT GLOB '*[^0-9a-f-]*'),
    word_id TEXT NOT NULL CHECK(length(word_id) = 36 AND substr(word_id,9,1) = '-' AND substr(word_id,14,1) = '-' AND substr(word_id,19,1) = '-' AND substr(word_id,24,1) = '-' AND length(replace(word_id,'-','')) = 32 AND word_id NOT GLOB '*[^0-9a-f-]*') REFERENCES vocabulary_words(id) ON DELETE CASCADE,
    reviewed_at INTEGER NOT NULL,
    rating TEXT NOT NULL CHECK(rating IN ('again','hard','good','easy')),
    previous_state TEXT NOT NULL CHECK(previous_state IN ('new','learning','relearning','review','suspended')),
    next_state TEXT NOT NULL CHECK(next_state IN ('new','learning','relearning','review','suspended')),
    previous_interval_days INTEGER NOT NULL CHECK(previous_interval_days >= 0),
    next_interval_days INTEGER NOT NULL CHECK(next_interval_days >= 0),
    scheduled_due_at INTEGER NOT NULL,
    error_types TEXT NOT NULL,
    typed_answer TEXT,
    expected_answer TEXT,
    question_direction_raw_value TEXT,
    reading_wrong_count INTEGER NOT NULL CHECK(reading_wrong_count >= 0),
    spelling_wrong_count INTEGER NOT NULL CHECK(spelling_wrong_count >= 0),
    repeated_wrong_count INTEGER NOT NULL CHECK(repeated_wrong_count >= 0)
) STRICT;

CREATE INDEX words_by_book ON vocabulary_words(word_book_id);

CREATE INDEX progress_due ON learning_progress(due_at) WHERE state IN ('learning','relearning','review');

CREATE INDEX logs_by_word_date ON review_logs(word_id, reviewed_at DESC, id);
