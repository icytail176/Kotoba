import { invoke } from "@tauri-apps/api/core";
import type { WordBookSummary, PagedResult, VocabularyWordDetail } from "$lib/types/vocabulary";
async function read<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  const start = performance.now();
  try { return await invoke<T>(command, args); }
  finally { if (import.meta.env.DEV) console.debug(`[Kotoba read] ${command}: ${(performance.now() - start).toFixed(1)} ms`); }
}
export const vocabularyService = {
  listBooks: () => read<WordBookSummary[]>("browse_books"),
  listWords: (bookId: string | null, limit = 50, offset = 0) => read<PagedResult>("browse_words", { bookId, limit, offset }),
  searchWords: (query: string, limit = 50, offset = 0) => read<PagedResult>("browse_search", { query, limit, offset }),
  getWord: (id: string) => read<VocabularyWordDetail | null>("word_detail", { id }),
};
