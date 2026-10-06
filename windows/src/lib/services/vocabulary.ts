import { productService } from "../product/service.ts";
import {defaultFilters} from "../product/types.ts";
import { invoke } from "@tauri-apps/api/core";
import type { VocabularyWordDetail } from "$lib/types/vocabulary";
async function read<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  const start = performance.now();
  try { return await invoke<T>(command, args); }
  finally { if (import.meta.env.DEV) console.debug(`[Kotoba read] ${command}: ${(performance.now() - start).toFixed(1)} ms`); }
}
export const vocabularyService = {
  listBooks: () => productService.books(),
  listWords: (bookId: string | null, limit = 50, offset = 0) => productService.words(defaultFilters(bookId),limit,offset),
  searchWords: (query: string, limit = 50, offset = 0) => query.trim() ? productService.words({...defaultFilters(),search:query},limit,offset) : Promise.resolve({items:[],total:0,limit,offset}),
  getWord: (id: string) => read<VocabularyWordDetail | null>("word_detail", { id }),
};
