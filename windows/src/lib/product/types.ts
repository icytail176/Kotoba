import type { VocabularyWordListItem, LoanwordSource } from "../types/vocabulary.ts";
import type { Progress } from "../study/types.ts";
export interface Pitch {
    displayText: string;
    accessibilityText: string;
}
export interface Conjugation {
    conjugationClass: string;
    forms: {
        formType: string;
        label: string;
        surface: string;
        reading: string;
    }[];
}
export type Filter = "all" | "new" | "review" | "mastered" | "favorite" | "difficult";
export type Sort = "defaultOrder" | "recentlyStudied" | "nextDue" | "lapseCount";
export interface Filters {
    bookId: string | null;
    search: string;
    status: Filter;
    favoritesOnly: boolean;
    jlpt: string | null;
    partOfSpeech: string | null;
    tag: string | null;
    sort: Sort;
}
export const defaultFilters = (bookId: string | null = null): Filters => ({ bookId, search: "", status: "all", favoritesOnly: false, jlpt: null, partOfSpeech: null, tag: null, sort: "defaultOrder" });
export interface ProductWord extends VocabularyWordListItem {
    isFavorite: boolean;
    learningStatus: "unlearned" | "reviewing" | "mastered";
    isDifficult: boolean;
    romaji: string;
}
export interface ProductPage {
    items: ProductWord[];
    total: number;
    limit: number;
    offset: number;
}
export interface ProductBook {
    id: string;
    name: string;
    bookDescription: string;
    isBuiltIn: boolean;
    jlptLevel: string;
    wordCount: number;
    unlearned: number;
    reviewing: number;
    mastered: number;
}
export interface ProductDetail extends ProductWord {
    partOfSpeech: string;
    exampleJapanese: string;
    exampleChinese: string;
    tags: string[];
    editingTags: string[];
    pitch: Pitch | null;
    conjugation: Conjugation | null;
    loanword: LoanwordSource | null;
    progress: Progress | null;
    historyCount: number;
}
export interface HistoryRow {
    ratingLabel: string;
    transition: string;
    log: {
        id: string;
        reviewedAt: number;
        readingWrongCount: number;
        spellingWrongCount: number;
        typedAnswer: string | null;
        expectedAnswer: string | null;
        questionDirectionRawValue: string | null;
        nextState: string;
    };
}
export interface HistoryPage {
    items: HistoryRow[];
    total: number;
    limit: number;
    offset: number;
}
export interface ForecastDay {
    day: number;
    count: number;
}
export interface Statistics {
    days: number;
    timezone: string;
    todayNewWordCount: number;
    todayReviewCount: number;
    totalLearnedWordCount: number;
    totalReviewCount: number;
    currentStreakDays: number;
    periodFormalReviewCount: number;
    periodNewlyLearnedWordCount: number;
    periodManualMasteryCount: number;
    periodAutomaticMasteryCount: number;
    ratingDistribution: number[];
    spellingPassed: number;
    spellingEligible: number;
    dailyActivity: {
        day: number;
        totalCount: number;
        newWordCount: number;
        reviewCount: number;
    }[];
    topLapsedWords: {
        id: string;
        expression: string;
        reading: string;
        meaningChinese: string;
        lapseCount: number;
    }[];
}
export interface AppSettings {
    formatVersion: 1;
    dailyNewWordCount: number;
    dailyReviewWordCount: number;
    randomizesStudyOrder: boolean;
    selectedBookId: string | null;
}
export interface WordEdit {
    id: string | null;
    bookId: string;
    expression: string;
    reading: string;
    meaningChinese: string;
    partOfSpeech: string;
    jlptLevel: string;
    exampleJapanese: string;
    exampleChinese: string;
    tags: string[];
    isFavorite: boolean;
}
export type FileKind = "csv" | "backup";
export interface ImportTarget {
    bookId: string | null;
    newBookName: string | null;
}
export interface Preview {
    token: string;
    kind: FileKind;
    fileName: string;
    validRows: number;
    duplicateRows: number;
    errors: {
        row: number;
        reason: string;
    }[];
    errorCount: number;
    sample: {
        row: number;
        expression: string;
        reading: string;
        meaningChinese: string;
    }[];
    books: number;
    words: number;
    progress: number;
    logs: number;
    quality: {
        criticalCount: number;
        warningCount: number;
        infoCount: number;
        conjugatableMissingValidDataCount: number;
        issues: {
            severity: string;
            lineNumber: number;
            expression: string;
            reason: string;
        }[];
    } | null;
}
export interface FileSummary {
    csv: {
        imported: number;
        updated: number;
        skipped: number;
        errors: number;
    } | null;
    backup: {
        inserted: number;
        updated: number;
        skipped: number;
    } | null;
}
export const dateText = (micros: number) => new Date(micros / 1000).toLocaleDateString("zh-CN", { month: "numeric", day: "numeric" });
export const timeText = (micros: number) => new Date(micros / 1000).toLocaleString("zh-CN");
export interface EditorPreview {
    normalizedPartOfSpeechTokens: string[];
    conjugation: Conjugation | null;
    isConjugatable: boolean;
    requiresManualReview: boolean;
    warnings: string[];
}
