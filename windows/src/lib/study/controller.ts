import type { Card, Enrichment, FormalRequest, Mode, Phase, Progress, Rating, StudyService } from "./types.ts";
import { SpellingSession } from "./spelling.ts";
import type { RoundSummary, WordResult, Question } from "./spelling.ts";
export interface Outcome {
    card: Card;
    rating: Rating;
    logId: string;
    mastered: boolean;
    retryCount: number;
    didLapse: boolean;
    spelling: WordResult | null;
}
export interface Summary {
    total: number;
    newCount: number;
    lapseCount: number;
    forgotten: number;
    fuzzy: number;
    known: number;
    mastered: number;
    expression: RoundSummary;
    reading: RoundSummary;
    outcomes: Outcome[];
}
export interface ViewState {
    phase: Phase;
    card: Card | null;
    index: number;
    total: number;
    revealed: boolean;
    pending: boolean;
    error: string | null;
    errorCode: string | null;
    retryKind: "rating" | "spelling" | null;
    exitDialog: boolean;
    helpDialog: boolean;
    question: Question | null;
    answer: string;
    locked: boolean;
    feedback: "correct" | "incorrect" | null;
    hint: boolean;
    requeued: boolean;
    summary: Summary | null;
    timezone: string;
}
type Attempt = {
    kind: "formal";
    request: FormalRequest;
} | {
    kind: "reinforcement";
    wordId: string;
    expected: Progress;
    now: number;
};
export class StudySessionController {
    phase: Phase = "idle";
    cards: Card[] = [];
    index = 0;
    revealed = false;
    pending = false;
    error: string | null = null;
    errorCode: string | null = null;
    exitDialog = false;
    helpDialog = false;
    timezone = "";
    spelling: SpellingSession | null = null;
    readonly outcomes = new Map<string, Outcome>();
    private attempt: Attempt | null = null;
    private spellingEntries: Enrichment[] | null = null;
    private didFinish = false;
    private leave: (() => void) | null = null;
    private generation = 0;
    private service: StudyService;
    private changed: (state: ViewState) => void;
    private clock: () => number;
    private shuffle: (q: Question[]) => Question[];
    private completed: () => void;
    constructor(service: StudyService, changed: (state: ViewState) => void, clock: () => number = () => Date.now() * 1000, shuffle: (q: Question[]) => Question[] = items => items, completed: () => void = () => { }) { this.service = service; this.changed = changed; this.clock = clock; this.shuffle = shuffle; this.completed = completed; }
    get card(): Card | null { return this.cards[this.index] ?? null; }
    snapshot(): ViewState { const s = this.spelling; return { phase: this.phase, card: this.card, index: this.index, total: this.cards.length, revealed: this.revealed, pending: this.pending, error: this.error, errorCode: this.errorCode, retryKind: this.attempt ? "rating" : this.spellingEntries ? "spelling" : null, exitDialog: this.exitDialog, helpDialog: this.helpDialog, question: s?.current ?? null, answer: s?.answer ?? "", locked: s?.locked ?? false, feedback: s?.feedback ?? null, hint: s?.hint ?? false, requeued: s?.requeued ?? false, summary: this.phase === "summary" ? this.summary() : null, timezone: this.timezone }; }
    private emit() { this.changed(this.snapshot()); }
    async start(bookId: string, mode: Mode, newLimit = 10, reviewLimit = 20) {
        if (this.pending || !["idle", "cancelled", "completed", "emptyQueue", "error"].includes(this.phase))
            return;
        const generation = ++this.generation;
        this.reset();
        this.phase = "loadingWords";
        this.pending = true;
        this.emit();
        try {
            const result = await this.service.start(bookId, mode, newLimit, reviewLimit);
            if (generation !== this.generation)
                return;
            this.cards = result.cards;
            this.timezone = result.timezone;
            this.phase = this.cards.length ? "flashcard" : "emptyQueue";
        }
        catch (e) {
            if (generation !== this.generation)
                return;
            this.phase = "error";
            this.fail(e, "无法加载学习队列，请重试。");
        }
        finally {
            if (generation === this.generation) {
                this.pending = false;
                this.emit();
            }
        }
    }
    reveal() { if (!this.pending && !this.attempt && !this.exitDialog && !this.helpDialog && this.isCard()) {
        this.revealed = true;
        this.emit();
    } }
    private isCard() { return this.phase === "flashcard" || this.phase === "flashcardRetry"; }
    async rateFormal(rating: Rating) { if (!this.canRate() || this.phase !== "flashcard" || !this.card)
        return; this.attempt = { kind: "formal", request: { wordId: this.card.word.id, expectedProgress: this.card.expectedProgress, rating, now: this.clock() } }; await this.persistRating(); }
    async rateReinforcement(rating: Rating) {
        if (!this.canRate() || this.phase !== "flashcardRetry" || !this.card)
            return;
        if (rating === "easy") {
            if (!this.card.expectedProgress)
                return;
            this.attempt = { kind: "reinforcement", wordId: this.card.word.id, expected: this.card.expectedProgress, now: this.clock() };
            await this.persistRating();
        }
        else {
            this.commitReinforcement(rating);
            this.emit();
        }
    }
    private canRate() { return this.isCard() && this.revealed && !this.pending && !this.attempt && !this.exitDialog && !this.helpDialog && this.errorCode !== "stale"; }
    async retryRating() { if (this.attempt && !this.pending && !this.exitDialog && !this.helpDialog)
        await this.persistRating(); }
    returnToCard() { if (this.pending || this.errorCode === "stale")
        return; this.attempt = null; this.error = null; this.errorCode = null; this.emit(); }
    private async persistRating() {
        if (this.pending || !this.attempt || !this.card)
            return;
        const attempt = this.attempt;
        const card = this.card;
        this.pending = true;
        this.error = null;
        this.errorCode = null;
        this.emit();
        try {
            if (attempt.kind === "formal") {
                const result = await this.service.formal(attempt.request);
                card.expectedProgress = result.progress;
                const mastered = result.progress.state === "suspended";
                this.outcomes.set(card.word.id, { card, rating: attempt.request.rating, logId: result.logId, mastered, retryCount: 0, didLapse: result.didLapse, spelling: null });
                if (attempt.request.rating === "again" && !mastered)
                    this.cards.push(card);
                this.attempt = null;
                this.advance();
            }
            else {
                const progress = await this.service.reinforcementMastered(attempt.wordId, attempt.expected, attempt.now);
                card.expectedProgress = progress;
                this.attempt = null;
                this.commitReinforcement("easy");
            }
        }
        catch (e) {
            this.fail(e, "保存失败，请重试。");
            if (this.errorCode === "stale") {
                this.attempt = null;
                this.phase = "error";
            }
        }
        finally {
            this.pending = false;
            this.emit();
        }
    }
    private commitReinforcement(rating: Rating) { const card = this.card; if (!card)
        return; const outcome = this.outcomes.get(card.word.id); if (!outcome)
        return; outcome.retryCount++; if (rating === "again")
        this.cards.push(card); if (rating === "easy") {
        outcome.mastered = true;
        this.cards = this.cards.filter((c, i) => i <= this.index || c.word.id !== card.word.id);
    } this.advance(); }
    private advance() { this.index++; this.revealed = false; if (this.index < this.cards.length) {
        this.phase = this.outcomes.has(this.card?.word.id ?? "") ? "flashcardRetry" : "flashcard";
    }
    else {
        const candidates = [...this.outcomes.values()].filter(o => !o.mastered && o.card.expectedProgress?.state !== "suspended").map(o => o.card);
        this.spelling = new SpellingSession(candidates, this.shuffle);
        this.syncSpellingPhase();
    } }
    private syncSpellingPhase() { const phase = this.spelling?.phase; this.phase = phase === "expression" ? "spellingExpression" : phase === "reading" ? "spellingReading" : "summary"; }
    input(value: string) { if (this.spelling && !this.spelling.locked && !this.pending) {
        this.spelling.answer = value;
        this.emit();
    } }
    hint(composing = false) { if (!this.pending && !this.exitDialog && !this.helpDialog) {
        this.spelling?.revealHint(composing);
        this.emit();
    } }
    async spellingEnter(composing = false) { if (this.pending || this.exitDialog || this.helpDialog || this.spellingEntries || !this.spelling || !["spellingExpression", "spellingReading"].includes(this.phase))
        return; const action = this.spelling.enter(composing); if (action === "completed") {
        this.spellingEntries = [...this.spelling.results].flatMap(([id, r]) => { const outcome = this.outcomes.get(id); if (!outcome || outcome.mastered)
            return []; outcome.spelling = r; return [{ wordId: id, logId: outcome.logId, typedAnswer: r.lastTypedAnswer, expectedAnswer: r.lastExpectedAnswer, questionDirectionRawValue: r.lastQuestionDirectionRawValue, readingWrongCount: r.reading.wrongCount, spellingWrongCount: r.expression.wrongCount }]; });
        await this.persistSpelling();
    }
    else {
        this.syncSpellingPhase();
        this.emit();
    } }
    async retrySpelling() { if (this.spellingEntries && !this.pending)
        await this.persistSpelling(); }
    continueWithoutSpellingSave() { if (this.pending || !this.spellingEntries)
        return; this.spellingEntries = null; this.error = null; this.errorCode = null; this.phase = "summary"; this.emit(); }
    private async persistSpelling() { if (this.pending || !this.spellingEntries)
        return; this.pending = true; this.error = null; this.errorCode = null; this.emit(); try {
        await this.service.enrich(this.spellingEntries);
        this.spellingEntries = null;
        this.phase = "summary";
    }
    catch (e) {
        this.phase = "error";
        this.fail(e, "学习进度已保存，但拼写记录保存失败，请重试。");
    }
    finally {
        this.pending = false;
        this.emit();
    } }
    async toggleFavorite() { if (this.pending || this.attempt || !this.isCard() || !this.card || this.exitDialog || this.helpDialog)
        return; const card = this.card; this.pending = true; this.emit(); try {
        card.isFavorite = await this.service.favorite(card.word.id, card.isFavorite);
        this.error = null;
        this.errorCode = null;
    }
    catch (e) {
        this.fail(e, "收藏状态保存失败，请重试。");
    }
    finally {
        this.pending = false;
        this.emit();
    } }
    requestExit(leave: () => void = () => { }) { if (this.pending)
        return; if (["idle", "cancelled", "completed", "emptyQueue", "summary"].includes(this.phase)) {
        this.cancel();
        leave();
        return;
    } this.leave = leave; this.exitDialog = true; this.emit(); }
    continueLearning() { this.exitDialog = false; this.leave = null; this.emit(); }
    confirmExit() { if (!this.exitDialog || this.pending)
        return; const leave = this.leave; this.cancel(); leave?.(); }
    showHelp() { if (!this.pending && !this.exitDialog) {
        this.helpDialog = true;
        this.emit();
    } }
    closeHelp() { this.helpDialog = false; this.emit(); }
    finishOnce() { if (this.phase !== "summary" || this.didFinish || this.pending || this.exitDialog || this.helpDialog)
        return; this.didFinish = true; this.phase = "completed"; this.emit(); this.completed(); }
    cancel() { if (this.pending)
        return; this.generation++; this.reset(); this.phase = "cancelled"; this.emit(); }
    private reset() { this.cards = []; this.index = 0; this.revealed = false; this.error = null; this.errorCode = null; this.attempt = null; this.spellingEntries = null; this.spelling = null; this.outcomes.clear(); this.exitDialog = false; this.helpDialog = false; this.leave = null; this.didFinish = false; }
    private fail(e: unknown, fallback: string) { const value = e as {
        code?: string;
        message?: string;
    }; this.errorCode = value?.code ?? "save"; this.error = value?.code === "stale" ? "学习状态已发生变化，请重新开始本组学习。" : value?.code === "timezone" ? "无法读取当前系统时区，请检查时区设置后重试。" : fallback; }
    private summary(): Summary { const list = [...this.outcomes.values()].sort((a, b) => a.card.word.expression.localeCompare(b.card.word.expression, "ja", { numeric: true })); const empty = { totalCount: 0, firstAttemptCorrectCount: 0, retryCorrectCount: 0, usedHintCount: 0 }; return { total: list.length, newCount: list.filter(o => o.card.kind === "newWord").length, lapseCount: list.filter(o => o.didLapse).length, forgotten: list.filter(o => o.rating === "again" && !o.mastered).length, fuzzy: list.filter(o => o.rating === "hard" && !o.mastered).length, known: list.filter(o => o.rating === "good" && !o.mastered).length, mastered: list.filter(o => o.mastered).length, expression: this.spelling?.roundSummary("expression") ?? empty, reading: this.spelling?.roundSummary("reading") ?? empty, outcomes: list }; }
}
