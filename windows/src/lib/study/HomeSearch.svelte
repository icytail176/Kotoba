<script lang="ts">
import { onMount, tick } from "svelte";
import { vocabularyService } from "$lib/services/vocabulary";
import type { VocabularyWordListItem, VocabularyWordDetail } from "$lib/types/vocabulary";
import WordDetail from "$lib/vocabulary/WordDetail.svelte";
import StudyDialog from "./StudyDialog.svelte";
export interface SearchHandle {
    focus: () => void;
    command: (kind: string) => void;
}
let { register }: {
    register: (handle: SearchHandle | null) => void;
} = $props();
let field = $state<HTMLInputElement>();
let text = $state("");
let items = $state<VocabularyWordListItem[]>([]);
let selected = $state(0);
let detail = $state<VocabularyWordDetail | null>(null);
let error = $state<string | null>(null);
let timer: ReturnType<typeof setTimeout> | null = null;
let generation = 0;
function clear() { generation++; if (timer)
    clearTimeout(timer); items = []; text = ""; selected = 0; field?.blur(); }
function search(value: string) { text = value; generation++; const current = generation; if (timer)
    clearTimeout(timer); items = []; selected = 0; error = null; if (!value.trim())
    return; timer = setTimeout(() => { void vocabularyService.searchWords(value, 8).then(result => { if (current === generation)
    items = result.items; }).catch(() => { if (current === generation)
    error = "无法搜索单词，请重试。"; }); }, 250); }
async function open(id: string) { const current = ++generation; try {
    const word = await vocabularyService.getWord(id);
    if (current !== generation)
        return;
    detail = word;
    items = [];
    await tick();
    document.getElementById("detail-heading")?.focus();
}
catch {
    if (current === generation)
        error = "无法加载单词详情，请重试。";
} }
function command(kind: string) { if (kind === "searchUp")
    selected = Math.max(0, selected - 1); if (kind === "searchDown")
    selected = Math.min(items.length - 1, selected + 1); if (kind === "searchOpen" && items[selected])
    void open(items[selected].id); if (kind === "searchClose")
    clear(); }
onMount(() => { register({ focus: () => field?.focus(), command }); return () => { generation++; if (timer)
    clearTimeout(timer); register(null); }; });
</script>
<div class="search"><label for="study-home-search">搜索单词</label><input bind:this={field} id="study-home-search" value={text} oninput={e=>search(e.currentTarget.value)} placeholder="搜索日语、假名或中文释义…" aria-describedby="search-description" /><p id="search-description" class="muted">↑ / ↓ 选择，Enter 打开，Escape 关闭</p>{#if error}<p role="alert">{error}</p>{/if}{#if items.length}<ul aria-label="搜索建议">{#each items as word,i}<li><button class:highlight={i===selected} onclick={()=>{void open(word.id);}}><span lang="ja">{word.expression} · {word.reading}</span><span>{word.meaningChinese}</span><small>{word.bookName}</small></button></li>{/each}</ul>{/if}</div>
<StudyDialog open={!!detail} title="单词详情" onclose={()=>{detail=null;field?.focus();}}>{#if detail}<WordDetail state={{status:"ready",data:detail}} close={()=>{detail=null;field?.focus();}} retry={()=>{}} />{/if}</StudyDialog>
<style>.search{display:flex;flex-direction:column;gap:8px;}label{font-weight:600;}.search p{font-size:12px;}ul{list-style:none;padding:0;margin:0;border:1px solid var(--border);border-radius:8px;overflow:hidden;}li button{width:100%;text-align:left;border:0;border-radius:0;display:flex;flex-direction:column;gap:4px;overflow-wrap:anywhere;}li+li{border-top:1px solid var(--border);}button.highlight{background:var(--surface-secondary);}small{color:var(--text-secondary);}</style>
