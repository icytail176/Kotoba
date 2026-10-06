import type { Card, Direction } from "./types.ts";
// Foundation trims U+200B as whitespace and preserves combining marks expanded
// from halfwidth voiced marks. Golden vectors come from the actual Swift source.
export function trimText(value: string): string { return value.replace(/^[\p{White_Space}\u200b]+|[\p{White_Space}\u200b]+$/gu, ""); }
export function normalizeText(value: string): string {
    return trimText(value).split(/([\uff9e\uff9f])/u).map(part => part === "\uff9e" ? "\u3099" : part === "\uff9f" ? "\u309a" : part.normalize("NFKC")).join("").replace(/[ \u3000]/gu, "");
}
export function normalizeReading(value: string): string { return [...normalizeText(value)].map(c => { const n = c.codePointAt(0) ?? 0; return n >= 0x30a1 && n <= 0x30f6 ? String.fromCodePoint(n - 0x60) : c; }).join(""); }
export function answerCorrect(answer: string, expected: string, direction: Direction): boolean {
    if (direction === "meaningToExpression")
        return normalizeText(answer).normalize("NFC") === normalizeText(expected).normalize("NFC");
    const value = normalizeReading(answer);
    return /^[\u3041-\u3096\u30fc]+$/u.test(value) && value.normalize("NFC") === normalizeReading(expected).normalize("NFC");
}
const hanRanges = [[0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xf900, 0xfaff], [0x20000, 0x2a6df], [0x2a700, 0x2b73f], [0x2b740, 0x2b81f], [0x2b820, 0x2ceaf], [0x2ceb0, 0x2ebef], [0x2ebf0, 0x2ee5f], [0x2f800, 0x2fa1f], [0x30000, 0x3134f], [0x31350, 0x323af]];
export function containsHan(value: string): boolean { return [...value].some(c => hanRanges.some(([a, b]) => { const n = c.codePointAt(0) ?? 0; return n >= a && n <= b; })); }
export interface Question {
    wordId: string;
    direction: Direction;
    prompt: string;
    expected: string;
    reading: string;
    meaning: string;
    context: string;
    exampleChinese: string;
}
export interface PhaseResult {
    requiresSpelling: boolean;
    wrongCount: number;
    usedHint: boolean;
    requeueCount: number;
    passedFirstTry: boolean;
}
export interface WordResult {
    expression: PhaseResult;
    reading: PhaseResult;
    lastTypedAnswer: string | null;
    lastExpectedAnswer: string | null;
    lastQuestionDirectionRawValue: Direction | null;
}
export interface RoundSummary {
    totalCount: number;
    firstAttemptCorrectCount: number;
    retryCorrectCount: number;
    usedHintCount: number;
}
const phaseResult = (): PhaseResult => ({ requiresSpelling: false, wrongCount: 0, usedHint: false, requeueCount: 0, passedFirstTry: false });
export function questions(cards: Card[], direction: Direction): Question[] {
    const seen = new Set<string>();
    return cards.flatMap(({ word, expectedProgress }) => {
        if (seen.has(word.id) || expectedProgress?.state === "suspended")
            return [];
        seen.add(word.id);
        const expression = trimText(word.expression), reading = trimText(word.reading);
        const prompt = trimText(direction === "meaningToExpression" ? word.meaningChinese : expression);
        const expected = direction === "meaningToExpression" ? expression : reading;
        if (!prompt || !expected || !expression || !reading || (direction === "expressionToReading" && !containsHan(expression)))
            return [];
        const example = trimText(word.exampleJapanese);
        const target = expression;
        return [{ wordId: word.id, direction, prompt, expected, reading: word.reading, meaning: word.meaningChinese, context: example.split(target).join("＿＿＿＿"), exampleChinese: word.exampleChinese }];
    });
}
export class SpellingSession {
    phase: "expression" | "reading" | "completed" = "expression";
    queue: Question[];
    index = 0;
    answer = "";
    locked = false;
    feedback: "correct" | "incorrect" | null = null;
    hint = false;
    private hadWrong = false;
    private usedHint = false;
    private first = { expression: new Set<string>(), reading: new Set<string>() };
    private retries = { expression: new Set<string>(), reading: new Set<string>() };
    readonly results = new Map<string, WordResult>();
    readonly expression: Question[];
    readonly reading: Question[];
    constructor(cards: Card[], shuffle: (items: Question[]) => Question[] = items => items) {
        this.expression = shuffle(questions(cards, "meaningToExpression"));
        this.reading = shuffle(questions(cards, "expressionToReading"));
        this.queue = [...this.expression];
        if (!this.queue.length) {
            this.phase = this.reading.length ? "reading" : "completed";
            this.queue = [...this.reading];
        }
        for (const [phase, list] of [["expression", this.expression], ["reading", this.reading]] as const)
            for (const q of list) {
                const result = this.results.get(q.wordId) ?? { expression: phaseResult(), reading: phaseResult(), lastTypedAnswer: null, lastExpectedAnswer: null, lastQuestionDirectionRawValue: null };
                result[phase].requiresSpelling = true;
                this.results.set(q.wordId, result);
            }
    }
    get current(): Question | null { return this.queue[this.index] ?? null; }
    get canHint(): boolean { return this.phase === "expression" && !this.locked && !!this.current; }
    get requeued(): boolean { return this.locked && (this.hadWrong || this.usedHint); }
    revealHint(composing = false): boolean { if (composing || !this.canHint || this.hint || !this.current)
        return false; this.hint = true; this.usedHint = true; const result = this.results.get(this.current.wordId); if (result)
        result.expression.usedHint = true; return true; }
    enter(composing = false): "ignored" | "submitted" | "advanced" | "completed" {
        if (composing || !this.current || this.phase === "completed")
            return "ignored";
        if (this.locked) {
            this.advance();
            return (this.phase as string) === "completed" ? "completed" : "advanced";
        }
        if (!this.answer.trim())
            return "ignored";
        const q = this.current;
        const result = this.results.get(q.wordId);
        if (!result)
            return "ignored";
        const phase = this.phase;
        if (!answerCorrect(this.answer, q.expected, q.direction)) {
            this.feedback = "incorrect";
            this.hadWrong = true;
            result[phase].wrongCount++;
            result.lastTypedAnswer = this.answer;
            result.lastExpectedAnswer = q.expected;
            result.lastQuestionDirectionRawValue = q.direction;
            return "submitted";
        }
        this.feedback = "correct";
        this.locked = true;
        if (this.hadWrong || this.usedHint) {
            result[phase].requeueCount++;
            this.queue.push(q);
        }
        else if (result[phase].requeueCount === 0) {
            result[phase].passedFirstTry = true;
            this.first[phase].add(q.wordId);
        }
        else
            this.retries[phase].add(q.wordId);
        return "submitted";
    }
    private advance() { this.index++; if (this.index >= this.queue.length) {
        if (this.phase === "expression" && this.reading.length) {
            this.phase = "reading";
            this.queue = [...this.reading];
            this.index = 0;
        }
        else
            this.phase = "completed";
    } this.answer = ""; this.locked = false; this.feedback = null; this.hint = false; this.hadWrong = false; this.usedHint = false; }
    roundSummary(phase: "expression" | "reading"): RoundSummary { return { totalCount: new Set(this[phase].map(q => q.wordId)).size, firstAttemptCorrectCount: this.first[phase].size, retryCorrectCount: this.retries[phase].size, usedHintCount: phase === "expression" ? [...this.results.values()].filter(r => r.expression.usedHint).length : 0 }; }
}
