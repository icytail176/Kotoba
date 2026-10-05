export interface WordBookSummary { id: string; name: string; jlptLevel: string; wordCount: number }
export interface VocabularyWordListItem { id: string; expression: string; reading: string; meaningChinese: string; bookId: string; bookName: string; jlptLevel: string }
export interface PagedResult { items: VocabularyWordListItem[]; total: number; limit: number; offset: number }
export interface LoanwordSource { sourceTerm: string; languageName: string | null; isWasei: boolean; isPartial: boolean }
export type LearningStatusPresentation = "unlearned" | "reviewing" | "mastered";
export interface VocabularyWordDetail extends VocabularyWordListItem { learningStatus: LearningStatusPresentation; partOfSpeech: string; exampleJapanese: string; exampleChinese: string; tags: string[]; loanword: LoanwordSource | null }
