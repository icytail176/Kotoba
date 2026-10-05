ALTER TABLE word_books ADD COLUMN canonical_id TEXT CHECK(canonical_id IS NULL OR (length(canonical_id)=36 AND substr(canonical_id,9,1)='-' AND substr(canonical_id,14,1)='-' AND substr(canonical_id,19,1)='-' AND substr(canonical_id,24,1)='-' AND length(replace(canonical_id,'-',''))=32 AND canonical_id NOT GLOB '*[^0-9a-f-]*'));
ALTER TABLE word_books ADD COLUMN canonical_key TEXT CHECK((canonical_id IS NULL AND canonical_key IS NULL) OR (canonical_id IS NOT NULL AND canonical_key IS NOT NULL AND length(canonical_key)>0));
CREATE UNIQUE INDEX word_books_canonical_id ON word_books(canonical_id) WHERE canonical_id IS NOT NULL;
CREATE UNIQUE INDEX word_books_canonical_key ON word_books(canonical_key) WHERE canonical_key IS NOT NULL;
CREATE TRIGGER word_books_immutable_canonical BEFORE UPDATE ON word_books
WHEN OLD.canonical_id IS NOT NULL AND (NEW.canonical_id IS NOT OLD.canonical_id OR NEW.canonical_key IS NOT OLD.canonical_key)
BEGIN SELECT RAISE(ABORT,'canonical identity is immutable'); END;
ALTER TABLE vocabulary_words ADD COLUMN canonical_id TEXT CHECK(canonical_id IS NULL OR (length(canonical_id)=36 AND substr(canonical_id,9,1)='-' AND substr(canonical_id,14,1)='-' AND substr(canonical_id,19,1)='-' AND substr(canonical_id,24,1)='-' AND length(replace(canonical_id,'-',''))=32 AND canonical_id NOT GLOB '*[^0-9a-f-]*'));
ALTER TABLE vocabulary_words ADD COLUMN canonical_key TEXT CHECK((canonical_id IS NULL AND canonical_key IS NULL) OR (canonical_id IS NOT NULL AND canonical_key IS NOT NULL AND length(canonical_key)>0));
CREATE UNIQUE INDEX vocabulary_words_canonical_id ON vocabulary_words(canonical_id) WHERE canonical_id IS NOT NULL;
CREATE UNIQUE INDEX vocabulary_words_canonical_key ON vocabulary_words(canonical_key) WHERE canonical_key IS NOT NULL;
CREATE TRIGGER vocabulary_words_immutable_canonical BEFORE UPDATE ON vocabulary_words
WHEN OLD.canonical_id IS NOT NULL AND (NEW.canonical_id IS NOT OLD.canonical_id OR NEW.canonical_key IS NOT OLD.canonical_key)
BEGIN SELECT RAISE(ABORT,'canonical identity is immutable'); END;
CREATE TRIGGER canonical_book_insert BEFORE INSERT ON word_books
WHEN NEW.canonical_id IS NOT NULL AND NEW.is_built_in != 1
BEGIN SELECT RAISE(ABORT,'canonical book must be built-in'); END;
CREATE TRIGGER canonical_book_update BEFORE UPDATE ON word_books
WHEN NEW.canonical_id IS NOT NULL AND NEW.is_built_in != 1
BEGIN SELECT RAISE(ABORT,'canonical book must be built-in'); END;
CREATE TRIGGER canonical_word_insert BEFORE INSERT ON vocabulary_words
WHEN NEW.canonical_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM word_books WHERE id=NEW.word_book_id AND is_built_in=1 AND canonical_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'canonical word requires canonical built-in book'); END;
CREATE TRIGGER canonical_word_update BEFORE UPDATE ON vocabulary_words
WHEN NEW.canonical_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM word_books WHERE id=NEW.word_book_id AND is_built_in=1 AND canonical_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'canonical word requires canonical built-in book'); END;
CREATE TABLE built_in_content (
 singleton INTEGER NOT NULL PRIMARY KEY CHECK(singleton=1),
 manifest_version INTEGER NOT NULL CHECK(manifest_version>=1),
 format_version INTEGER NOT NULL CHECK(format_version=1),
 namespace_uuid TEXT NOT NULL,
 manifest_fingerprint TEXT NOT NULL,
 identity_fingerprint TEXT NOT NULL
) STRICT;
