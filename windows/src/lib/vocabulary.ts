import { invoke } from "@tauri-apps/api/core";

export interface BookSummary {
  id: string;
  canonicalId: string;
  canonicalKey: string;
  name: string;
  jlptLevel: string;
  wordCount: number;
  archivedWordCount: number;
}
export interface VocabularyWord {
  id: string;
  canonicalId: string | null;
  canonicalKey: string | null;
  japanese: string;
  kana: string;
  chineseMeaning: string;
  partOfSpeech: string;
  jlptLevel: string;
  exampleJapanese: string;
  exampleChinese: string;
  tags: string[];
  createdAt: number;
  updatedAt: number;
  isArchived: boolean;
  isFavorite: boolean;
  loanwordSourceTerm: string | null;
  loanwordSourceLanguageCode: string | null;
  loanwordIsWasei: boolean;
  loanwordIsPartial: boolean;
  wordBookId: string | null;
}
export interface WordPage {
  items: VocabularyWord[];
  total: number;
  limit: number;
  offset: number;
}
export const listBuiltinWordBooks = () => invoke<BookSummary[]>("list_builtin_word_books");
export const getWordBookSummary = (id: string) => invoke<BookSummary | null>("get_word_book_summary", { id });
export const listWords = (bookId: string, limit = 20, offset = 0) => invoke<WordPage>("list_words", { bookId, limit, offset });
export const getWord = (id: string) => invoke<VocabularyWord | null>("get_word", { id });
export const searchWords = (query: string, limit = 20, offset = 0) => invoke<WordPage>("search_words", { query, limit, offset });
