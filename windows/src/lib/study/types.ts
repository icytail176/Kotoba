import type { VocabularyWordDetail } from "../types/vocabulary.ts";
export type Rating = "again" | "hard" | "good" | "easy";
export type PersistedState = "new" | "learning" | "relearning" | "review" | "suspended";
export interface Progress {
    id: string;
    wordId: string;
    state: PersistedState;
    dueAt: number;
    intervalDays: number;
    reviewCount: number;
    lapseCount: number;
    lastReviewedAt: number | null;
    createdAt: number;
    updatedAt: number;
}
export interface Card {
    word: VocabularyWordDetail;
    kind: "newWord" | "dueReview";
    expectedProgress: Progress | null;
    isFavorite: boolean;
}
export type Mode = "mixed" | "newWordsOnly" | "dueReviewsOnly";
export type Phase = "idle" | "loadingWords" | "flashcard" | "flashcardRetry" | "spellingExpression" | "spellingReading" | "emptyQueue" | "summary" | "cancelled" | "error" | "completed";
export interface Availability {
    newCount: number;
    dueCount: number;
    totalCount: number;
    reviewingCount: number;
    masteredCount: number;
    timezone: string;
}
export interface FormalRequest {
    wordId: string;
    expectedProgress: Progress | null;
    rating: Rating;
    now: number;
}
export interface FormalCommit {
    progress: Progress;
    logId: string;
    automaticMastery: boolean;
    didLapse: boolean;
}
export interface SessionStart {
    cards: Card[];
    timezone: string;
}
export interface Enrichment {
    wordId: string;
    logId: string;
    typedAnswer: string | null;
    expectedAnswer: string | null;
    questionDirectionRawValue: Direction | null;
    readingWrongCount: number;
    spellingWrongCount: number;
}
export type Direction = "meaningToExpression" | "expressionToReading";
export interface StudyService {
    availability(bookId: string): Promise<Availability>;
    start(bookId: string, mode: Mode, newLimit: number, reviewLimit: number): Promise<SessionStart>;
    formal(request: FormalRequest): Promise<FormalCommit>;
    reinforcementMastered(wordId: string, expectedProgress: Progress, now: number): Promise<Progress>;
    favorite(wordId: string, expected: boolean): Promise<boolean>;
    enrich(entries: Enrichment[]): Promise<void>;
}
