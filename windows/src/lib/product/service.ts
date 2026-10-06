import { invoke } from "@tauri-apps/api/core";
import type { Filters, ProductPage, ProductBook, ProductDetail, HistoryPage, ForecastDay, Statistics, AppSettings, WordEdit, FileKind, ImportTarget, Preview, FileSummary, EditorPreview } from "./types.ts";
export const productService = {
    editorPreview: (expression: string, reading: string, partOfSpeech: string) => invoke<EditorPreview>("product_editor_preview", { expression, reading, partOfSpeech }),
    exportQuality: (token: string) => invoke<string | null>("product_export_quality", { token }),
    words: (filters: Filters, limit = 50, offset = 0) => invoke<ProductPage>("product_words", { query: { ...filters, limit, offset } }),
    books: () => invoke<ProductBook[]>("product_books"), detail: (id: string) => invoke<ProductDetail | null>("product_detail", { id }), options: () => invoke<{
        partsOfSpeech: string[];
        tags: string[];
    }>("product_filter_options"),
    history: (id: string, offset = 0) => invoke<HistoryPage>("product_history", { id, limit: 10, offset }),
    resetWord: (id: string, confirmed: boolean) => invoke<void>("product_reset_word", { id, confirmed }), resetBook: (id: string, confirmed: boolean) => invoke<void>("product_reset_book", { id, confirmed }),
    editWord: (edit: WordEdit) => invoke<string>("product_edit_word", { edit }), deleteWord: (id: string, confirmed: boolean) => invoke<void>("product_delete_word", { id, confirmed }),
    editBook: (id: string | null, name: string, description: string) => invoke<string>("product_edit_book", { id, name, description }), deleteBook: (id: string, confirmed: boolean) => invoke<void>("product_delete_book", { id, confirmed }),
    forecast: (bookId: string | null = null) => invoke<ForecastDay[]>("product_forecast", { bookId }), statistics: (days: 7 | 30) => invoke<Statistics>("product_statistics", { days }), randomExample: (bookId: string | null) => invoke<ProductDetail | null>("product_random_example", { bookId }),
    settings: () => invoke<AppSettings>("product_settings"), saveSettings: (value: AppSettings) => invoke<AppSettings>("product_save_settings", { value }),
    pickImport: (kind: FileKind, target: ImportTarget | null) => invoke<Preview | null>("product_pick_import", { kind, target }), confirmImport: (token: string, duplicatePolicy: "skip" | "update" | null, restorePolicy: "merge" | "skipExisting" | "overwrite" | null) => invoke<FileSummary>("product_confirm_import", { token, confirmed: true, duplicatePolicy, restorePolicy }), cancelImport: () => invoke<void>("product_cancel_import"), exportFile: (kind: FileKind, bookId: string | null) => invoke<string | null>("product_export_file", { kind, bookId }),
};
