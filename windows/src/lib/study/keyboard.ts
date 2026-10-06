import type { Phase, Rating } from "./types.ts";
export type Platform = "mac" | "windows";
export interface KeyInput {
    key: string;
    repeat: boolean;
    isComposing: boolean;
    keyCode?: number;
    metaKey: boolean;
    ctrlKey: boolean;
    altKey: boolean;
    shiftKey: boolean;
}
export interface KeyContext {
    phase: Phase;
    editing: boolean;
    spellingInput: boolean;
    composing: boolean;
    dialog: boolean;
    pending: boolean;
    revealed: boolean;
    platform: Platform;
    searchFocused?: boolean;
    hasSecondaryPage?: boolean;
}
export type Command = {
    kind: "help" | "pagePrevious" | "pageNext" | "reveal" | "favorite" | "exit" | "spellingEnter" | "hint" | "finish" | "search" | "searchUp" | "searchDown" | "searchOpen" | "searchClose";
} | {
    kind: "formalRating" | "reinforcementRating";
    rating: Rating;
} | {
    kind: "start";
    mode: "newWordsOnly" | "dueReviewsOnly";
};
export const modifierLabel = (platform: Platform) => platform === "mac" ? "⌘" : "Ctrl";
function primary(e: KeyInput, p: Platform) { return p === "mac" ? e.metaKey && !e.ctrlKey : e.ctrlKey && !e.metaKey; }
export function dispatchKey(e: KeyInput, c: KeyContext): Command | null {
    if (e.repeat || e.isComposing || e.keyCode === 229 || c.composing || c.dialog || c.pending)
        return null;
    if (e.key === "?" && !c.editing && !e.metaKey && !e.ctrlKey && !e.altKey) return {kind:"help"};
    const lower = e.key.toLowerCase();
    const spell = c.phase === "spellingExpression" || c.phase === "spellingReading";
    if (primary(e, c.platform) && !e.altKey) {
        if (e.shiftKey && lower === "h" && c.phase === "spellingExpression")
            return { kind: "hint" };
        if (!e.shiftKey && lower === "f" && ["idle", "cancelled", "completed"].includes(c.phase))
            return { kind: "search" };
        return null;
    }
    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey)
        return null;
    if (spell) {
        if (e.key === "Enter" && (!c.editing || c.spellingInput))
            return { kind: "spellingEnter" };
        if (e.key === "Escape")
            return { kind: "exit" };
        return null;
    }
    if (c.searchFocused) {
        switch (e.key) {
            case "ArrowUp": return { kind: "searchUp" };
            case "ArrowDown": return { kind: "searchDown" };
            case "Enter": return { kind: "searchOpen" };
            case "Escape": return { kind: "searchClose" };
            default: return null;
        }
    }
    if (c.editing)
        return null;
    if (c.phase === "summary" && e.key === "Enter")
        return { kind: "finish" };
    if (e.key === "Escape" && !["idle", "cancelled", "completed"].includes(c.phase))
        return { kind: "exit" };
    if (c.phase === "flashcard" || c.phase === "flashcardRetry") {
        if (e.key === " ")
            return { kind: "reveal" };
        if (lower === "f")
            return { kind: "favorite" };
        if (!c.revealed)
            return null;
        if (c.hasSecondaryPage && e.key === "ArrowLeft") return {kind:"pagePrevious"};
        if (c.hasSecondaryPage && e.key === "ArrowRight") return {kind:"pageNext"};
        const rating: Rating | undefined = ({ "1": "again", "2": "hard", "3": "good", "Delete": "easy", "Backspace": "easy" } as Record<string, Rating>)[e.key];
        return rating ? { kind: c.phase === "flashcard" ? "formalRating" : "reinforcementRating", rating } : null;
    }
    if (["idle", "cancelled", "completed"].includes(c.phase)) {
        if (lower === "l")
            return { kind: "start", mode: "newWordsOnly" };
        if (lower === "r")
            return { kind: "start", mode: "dueReviewsOnly" };
    }
    return null;
}
export const shortcutReference = (platform: Platform) => [
    { title: "通用", items: [["快捷键帮助", "?"], ["聚焦搜索", `${modifierLabel(platform)}+F`]] },
    { title: "今日学习", items: [["学习新词", "L"], ["复习旧词", "R"], ["聚焦单词搜索", `${modifierLabel(platform)}+F`], ["选择 / 打开 / 关闭搜索建议", "↑ / ↓ / Enter / Escape"]] },
    { title: "学习卡片", items: [["显示答案", "Space"], ["忘记 / 模糊 / 认识", "1 / 2 / 3"], ["熟练", "Delete / Backspace"], ["收藏或取消收藏", "F"], ["切换卡片页（答案已显示且有活用）", "← / →"], ["退出本组", "Escape"]] },
    { title: "拼写", items: [["提交 / 下一题", "Enter"], ["第一轮假名提示", `${modifierLabel(platform)}+Shift+H`], ["退出本组", "Escape"]] },
    { title: "学习小结", items: [["返回首页", "Enter"]] },
];
export class CompositionGuard {
    composing = false;
    ending = false;
    private generation = 0;
    start() { this.generation++; this.composing = true; this.ending = false; }
    end(schedule: (fn: () => void) => void = fn => { setTimeout(fn, 0); }) { this.composing = false; this.ending = true; const generation = ++this.generation; schedule(() => { if (generation === this.generation)
        this.ending = false; }); }
    get active() { return this.composing || this.ending; }
}

/** Shared guard for scoped reference navigation (for example the kana grid). */
export function isSafeReferenceKey(e:KeyInput):boolean {return !e.repeat&&!e.isComposing&&e.keyCode!==229&&!e.metaKey&&!e.ctrlKey&&!e.altKey&&!e.shiftKey;}
export function dispatchPageKey(e:KeyInput,c:{editing:boolean;composing:boolean;dialog:boolean;pending:boolean;platform:Platform}):'help'|'search'|'close'|null {
 if(e.repeat||e.isComposing||e.keyCode===229||c.composing||c.dialog||c.pending)return null;
 if(e.key==='?'&&!c.editing&&!e.metaKey&&!e.ctrlKey&&!e.altKey)return 'help';
 if(primary(e,c.platform)&&!e.shiftKey&&!e.altKey&&e.key.toLowerCase()==='f')return 'search';
 if(c.editing||e.metaKey||e.ctrlKey||e.altKey||e.shiftKey)return null;
 return e.key==='Escape'?'close':null;
}
