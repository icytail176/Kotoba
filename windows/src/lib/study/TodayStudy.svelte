<script lang="ts">
import { onMount, tick } from "svelte";
import { vocabularyService } from "$lib/services/vocabulary";
import { studyService } from "$lib/services/study";
import type { WordBookSummary } from "$lib/types/vocabulary";
import type { Availability, Mode, Rating } from "./types.ts";
import { StudySessionController } from "./controller.ts";
import type { ViewState } from "./controller.ts";
import { CompositionGuard, dispatchKey, modifierLabel, shortcutReference } from "./keyboard.ts";
import type { Platform, Command } from "./keyboard.ts";
import type { Question } from "./spelling.ts";
import StudyCard from "./StudyCard.svelte";
import SpellingCard from "./SpellingCard.svelte";
import StudySummary from "./StudySummary.svelte";
import StudyDialog from "./StudyDialog.svelte";
import HomeSearch from "./HomeSearch.svelte";
import type { SearchHandle } from "./HomeSearch.svelte";
let { registerLeaveGuard }: {
    registerLeaveGuard: (guard: ((leave: () => void) => void) | null) => void;
} = $props();
let view = $state<ViewState>({ phase: "idle", card: null, index: 0, total: 0, revealed: false, pending: false, error: null, errorCode: null, retryKind: null, exitDialog: false, helpDialog: false, question: null, answer: "", locked: false, feedback: null, hint: false, requeued: false, summary: null, timezone: "" });
let books = $state<WordBookSummary[]>([]);
let bookId = $state("");
let availability = $state<Availability | null>(null);
let homeError = $state<string | null>(null);
let loading = $state(true);
let newLimit = $state(10);
let reviewLimit = $state(20);
let platform = $state<Platform>("windows");
let composing = $state(false);
let availabilityGeneration = 0;
let alive = true;
let searchHandle: SearchHandle | null = null;
const ime = new CompositionGuard();
function shuffle(items: Question[]): Question[] { const copy = [...items]; for (let i = copy.length - 1; i > 0; i--) {
    const values = new Uint32Array(1);
    crypto.getRandomValues(values);
    const j = values[0] % (i + 1);
    [copy[i], copy[j]] = [copy[j], copy[i]];
} return copy; }
const controller = new StudySessionController(studyService, next => { view = structuredClone(next); }, () => Date.now() * 1000, shuffle, () => { void refreshHome(); });
const home = $derived(["idle", "cancelled", "completed"].includes(view.phase));
async function refreshHome() { const current = ++availabilityGeneration; if (!bookId)
    return; loading = true; availability = null; homeError = null; try {
    const result = await studyService.availability(bookId);
    if (alive && current === availabilityGeneration)
        availability = result;
}
catch (e) {
    if (alive && current === availabilityGeneration) {
        const error = e as {
            code?: string;
        };
        homeError = error?.code === "timezone" ? "无法读取当前系统时区，请检查时区设置后重试。" : "无法加载当前词书，请重试。";
    }
}
finally {
    if (alive && current === availabilityGeneration)
        loading = false;
} }
function chooseBook(value: string) { bookId = value; try {
    localStorage.setItem("kotoba.selectedWordBook", value);
}
catch { /* Session remains usable without preferences storage. */ } void refreshHome(); }
function start(mode: Mode) { if (!bookId || loading || !availability)
    return; if (mode === "newWordsOnly" && !availability.newCount || mode === "dueReviewsOnly" && !availability.dueCount)
    return; void controller.start(bookId, mode, Number.isFinite(newLimit) ? Math.max(1, Math.min(100, Math.trunc(newLimit))) : 10, Number.isFinite(reviewLimit) ? Math.max(1, Math.min(200, Math.trunc(reviewLimit))) : 20).then(() => { void tick().then(() => document.getElementById("study-title")?.focus()); }); }
function rate(rating: Rating) { if (view.phase === "flashcard")
    void controller.rateFormal(rating);
else if (view.phase === "flashcardRetry")
    void controller.rateReinforcement(rating); }
function exit(leave: () => void = () => { void refreshHome(); }) { controller.requestExit(leave); }
function compositionStart() { ime.start(); composing = true; }
function compositionEnd() { ime.end(); composing = false; }
function execute(command: Command) { switch (command.kind) {
    case "start":
        start(command.mode);
        break;
    case "reveal":
        controller.reveal();
        break;
    case "formalRating":
        void controller.rateFormal(command.rating);
        break;
    case "reinforcementRating":
        void controller.rateReinforcement(command.rating);
        break;
    case "favorite":
        void controller.toggleFavorite();
        break;
    case "exit":
        exit();
        break;
    case "hint":
        controller.hint(ime.active);
        break;
    case "spellingEnter":
        void controller.spellingEnter(ime.active);
        break;
    case "finish":
        controller.finishOnce();
        break;
    case "search":
        searchHandle?.focus();
        break;
    default: searchHandle?.command(command.kind);
} }
function keydown(event: KeyboardEvent) { const target = event.target as HTMLElement | null; const editing = !!target?.closest("input,textarea,select,[contenteditable=true]"); const command = dispatchKey(event, { phase: view.phase, editing, spellingInput: target?.id === "study-answer", composing: ime.active, dialog: !!document.querySelector("dialog[open]"), pending: view.pending || !!view.retryKind, revealed: view.revealed, platform, searchFocused: target?.id === "study-home-search" }); if (command) {
    event.preventDefault();
    execute(command);
} }
onMount(() => { platform = navigator.platform.toLowerCase().includes("mac") ? "mac" : "windows"; registerLeaveGuard(leave => { if (home) {
    leave();
    return;
} exit(leave); }); void vocabularyService.listBooks().then(result => { if (!alive)
    return; books = result; let stored = ""; try {
    stored = localStorage.getItem("kotoba.selectedWordBook") ?? "";
}
catch { /* Optional preference only. */ } bookId = books.find(b => b.id === stored)?.id ?? books[0]?.id ?? ""; return refreshHome(); }).catch(() => { if (alive) {
    loading = false;
    homeError = "无法加载词书，请重试。";
} }); const timer = setInterval(() => { if (home)
    void refreshHome(); }, 30000); return () => { alive = false; availabilityGeneration++; clearInterval(timer); registerLeaveGuard(null); }; });
</script>
<svelte:window onkeydown={keydown} />
<header class="page-heading"><div><h1 id="study-title" tabindex="-1">今日学习</h1><p class="muted">{home?"选择当前词书，开始新词学习或到期复习。":books.find(b=>b.id===bookId)?.name??"本组学习"}</p></div><div class="header-actions">{#if !home}<button onclick={()=>exit()} disabled={view.pending}>返回首页</button>{/if}<button onclick={()=>controller.showHelp()} disabled={view.pending} aria-label="快捷键帮助">快捷键帮助</button></div></header>
{#if home}
 <div class="dashboard-scroll"><div class="dashboard"><label for="current-wordbook">当前词书</label><select id="current-wordbook" value={bookId} onchange={e=>chooseBook(e.currentTarget.value)} disabled={!books.length}>{#each books as book}<option value={book.id}>{book.name}</option>{/each}</select>
  <HomeSearch register={handle=>{searchHandle=handle;}} />
  {#if homeError}<div role="alert"><p>{homeError}</p><button onclick={()=>{void refreshHome();}}>重试</button></div>{/if}
  {#if loading}<p role="status">正在读取当前词书…</p>{:else if availability}<div class="metrics">{#each [["剩余新词",availability.newCount],["当前待复习",availability.dueCount],["词书总词数",availability.totalCount],["复习中",availability.reviewingCount],["已熟练",availability.masteredCount]] as [label,value]}<p><strong>{value}</strong><span>{label}</span></p>{/each}</div>{/if}
  <div class="group-settings"><label>每组新词 <input type="number" min="1" max="100" bind:value={newLimit} aria-label="每组新词数量" /></label><label>每组复习 <input type="number" min="1" max="200" bind:value={reviewLimit} aria-label="每组复习数量" /></label></div>
  <div class="entries"><button onclick={()=>start("newWordsOnly")} disabled={loading||!availability?.newCount}>学习新词 <kbd>L</kbd></button><button onclick={()=>start("dueReviewsOnly")} disabled={loading||!availability?.dueCount}>复习旧词 <kbd>R</kbd></button></div>
 </div></div>
{:else}
 {#if view.error}<div class="error" role="alert"><p>{view.error}</p>{#if view.retryKind==="rating"}<div class="retry"><button onclick={()=>{void controller.retryRating();}} disabled={view.pending}>重试保存</button><button onclick={()=>controller.returnToCard()} disabled={view.pending}>返回卡片</button></div>{:else if view.retryKind==="spelling"}<div class="retry"><button onclick={()=>{void controller.retrySpelling();}} disabled={view.pending}>重试保存</button><button onclick={()=>controller.continueWithoutSpellingSave()} disabled={view.pending}>继续完成</button></div>{:else if view.phase==="error"}<button onclick={()=>exit()} disabled={view.pending}>返回首页</button>{/if}</div>{/if}
 {#if view.phase==="flashcard"||view.phase==="flashcardRetry"}<StudyCard state={view} reveal={()=>controller.reveal()} {rate} favorite={()=>{void controller.toggleFavorite();}} />
 {:else if view.phase==="spellingExpression"||view.phase==="spellingReading"}<SpellingCard state={view} input={value=>controller.input(value)} hint={()=>controller.hint(ime.active)} submit={()=>{void controller.spellingEnter(ime.active);}} compositionstart={compositionStart} compositionend={compositionEnd} {composing} hintKeys={`${modifierLabel(platform)}+Shift+H`} />
 {:else if view.phase==="summary"&&view.summary}<StudySummary summary={view.summary} finish={()=>controller.finishOnce()} />
 {:else if view.phase==="loadingWords"}<p role="status">正在加载本组单词…</p>
 {:else if view.phase==="emptyQueue"}<section class="empty" role="status"><h2>当前没有可学习的单词</h2><p>本词书没有符合当前学习模式的单词。</p><button onclick={()=>exit()}>返回首页</button></section>{/if}
 {#if view.pending}<p class="saving" role="status">正在保存…</p>{/if}
{/if}
<StudyDialog open={view.exitDialog} title="退出当前学习？" onclose={()=>controller.continueLearning()}><p>退出后会清理当前学习会话的临时输入和拼写错题；已保存的评价记录不会删除。</p><div class="dialog-actions"><button onclick={()=>controller.continueLearning()}>继续学习</button><button onclick={()=>controller.confirmExit()}>退出本组</button></div></StudyDialog>
<StudyDialog open={view.helpDialog} title="快捷键帮助" onclose={()=>controller.closeHelp()}><div class="shortcut-sections">{#each shortcutReference(platform) as section}<section><h3>{section.title}</h3>{#each section.items as [action,keys]}<p><span>{action}</span><kbd>{keys}</kbd></p>{/each}</section>{/each}</div><div class="dialog-actions"><button onclick={()=>controller.closeHelp()}>关闭</button></div></StudyDialog>
<style>.page-heading{display:flex;justify-content:space-between;gap:14px;align-items:center;margin-bottom:18px;flex-shrink:0;}.page-heading p{font-size:13px;margin-top:4px;}.header-actions{display:flex;gap:8px;flex-wrap:wrap;}.dashboard-scroll{flex:1;min-height:0;overflow:auto;padding:4px;}.dashboard{max-width:900px;display:flex;flex-direction:column;gap:20px;padding-bottom:24px;}label{font-weight:600;}select{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:7px;padding:10px;width:100%;}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:10px;}.metrics p{display:flex;flex-direction:column;padding:16px;background:var(--surface);border:1px solid var(--border);border-radius:8px;}.metrics strong{font-size:26px;}.metrics span{font-size:12px;color:var(--text-secondary);}.group-settings{display:flex;gap:20px;flex-wrap:wrap;}.group-settings label{display:flex;align-items:center;gap:10px;}.group-settings input{width:85px;}.entries{display:grid;grid-template-columns:1fr 1fr;gap:12px;}.entries button{padding:18px;font-weight:600;}.entries button:first-child{background:var(--accent);color:var(--surface);}.error{padding:14px;border:1px solid var(--danger);border-radius:8px;color:var(--danger);margin-bottom:14px;overflow-wrap:anywhere;}.retry,.dialog-actions{display:flex;gap:10px;justify-content:flex-end;margin-top:18px;}.saving{font-size:12px;color:var(--text-secondary);padding-top:8px;}.empty{margin:auto;text-align:center;display:flex;flex-direction:column;gap:18px;}.shortcut-sections{display:flex;flex-direction:column;gap:18px;}.shortcut-sections section p{display:flex;justify-content:space-between;gap:20px;margin-top:6px;}.shortcut-sections kbd{white-space:nowrap;}@media(max-width:800px){.page-heading{align-items:flex-start;}.header-actions{max-width:130px;justify-content:flex-end;}.header-actions button{padding:6px 8px;font-size:12px;}.metrics{grid-template-columns:repeat(3,minmax(0,1fr));}.metrics p{padding:10px;}.entries button{padding:14px;}}</style>
