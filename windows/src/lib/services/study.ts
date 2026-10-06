import { invoke } from "@tauri-apps/api/core";
import type { StudyService } from "../study/types.ts";
export const studyService: StudyService = {
    availability: bookId => invoke("study_availability", { bookId }),
    start: (bookId, mode, newLimit, reviewLimit) => invoke("study_start", { bookId, mode, newLimit, reviewLimit }),
    formal: request => invoke("study_formal", { request }),
    reinforcementMastered: (wordId, expectedProgress, now) => invoke("study_reinforcement_mastered", { wordId, expectedProgress, now }),
    favorite: (wordId, expected) => invoke("study_favorite", { wordId, expected }),
    enrich: entries => invoke("study_enrich", { entries }),
};
