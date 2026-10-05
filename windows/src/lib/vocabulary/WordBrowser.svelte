<script lang="ts">
  import { onMount, onDestroy, tick } from "svelte";
  import { vocabularyService } from "$lib/services/vocabulary";
  import type { WordBookSummary, PagedResult, VocabularyWordDetail } from "$lib/types/vocabulary";
  import { LatestRead, WordBrowser, rangeLabel, type ReadState } from "./state";
  import ReadStatus from "$lib/components/ReadStatus.svelte";
  import WordDetail from "./WordDetail.svelte";
  let { book = null, back }: { book?: WordBookSummary | null; back?: () => void } = $props();
  let page = $state<ReadState<PagedResult>>({status:"loading",data:null});
  let detail = $state<ReadState<VocabularyWordDetail | null>>({status:"loading",data:null});
  let query = $state(""); let selected = $state<string | null>(null); let returnFocus: HTMLElement | null = null;
  const createController = () => new WordBrowser(book?.id ?? null,(query,bookId,offset) => query ? vocabularyService.searchWords(query,50,offset) : vocabularyService.listWords(bookId,50,offset),value => {page=value;});
  const controller = createController();
  const detailRead = new LatestRead<VocabularyWordDetail | null>(value => {detail=value;});
  function refresh() {void controller.refresh();}
  async function open(id: string, trigger: HTMLElement) {returnFocus=trigger; selected=id; void detailRead.run(() => vocabularyService.getWord(id)); await tick(); document.getElementById("detail-heading")?.focus();}
  async function close(restore = true) {detailRead.dispose(); selected=null; await tick(); if (!restore) return; if (returnFocus?.isConnected) returnFocus.focus(); else document.querySelector<HTMLElement>(".search-input")?.focus();}
  function search(value: string) { if (selected) void close(false); query=value; controller.search(value); }
  async function clearSearch() { search(""); await tick(); document.querySelector<HTMLElement>(".search-input")?.focus(); }
  async function turn(offset: number, trigger: HTMLButtonElement) {
    if (selected) void close(false);
    await controller.page(offset); await tick();
    if (page.status !== "ready" || page.data?.offset !== offset) return;
    document.querySelector<HTMLElement>(".list-scroll")?.scrollTo({top:0});
    if (document.activeElement === trigger || document.activeElement === document.body) {
      const target = trigger.disabled ? trigger.parentElement?.querySelector<HTMLButtonElement>("button:not(:disabled)") : trigger;
      target?.focus();
    }
  }
  function escape(event: KeyboardEvent) { if (event.key !== "Escape") return; if (selected) {event.preventDefault(); void close();} else if (book && back) {event.preventDefault(); back();} }
  onMount(refresh); onDestroy(() => {controller.dispose();detailRead.dispose();});
</script>
<svelte:window onkeydown={escape} />
<header class="page-header"><div>{#if book}<button class="back" onclick={back} aria-label="返回词书">← 词书</button>{/if}<h1 tabindex="-1">{book?.name ?? "单词管理"}</h1><p class="muted">{book ? `${book.wordCount.toLocaleString("zh-CN")} 个单词 · 按词条浏览` : "浏览词汇，读懂每一个意思。"}</p></div></header>
{#if !book}<div class="searchbar"><label for="word-search">搜索词汇</label><div class="search-field"><input class="search-input" id="word-search" type="search" maxlength="200" placeholder="搜索单词、读音或中文释义" value={query} oninput={event => search(event.currentTarget.value)} />{#if query}<button onclick={() => {void clearSearch();}} aria-label="清空搜索">清空</button>{/if}</div></div>{/if}
<div class:has-detail={selected !== null} class="browser-panels">
  <section class="list-panel" aria-label={book ? `${book.name} 单词列表` : "单词列表"} aria-busy={page.status === "loading"}>
    <div class="list-head"><span>单词 / 读音</span><span>中文释义</span><span>等级</span></div>
    <div class="list-scroll"><ReadStatus status={page.status} empty={page.data?.items.length === 0} emptyMessage={query.trim() ? "没有找到匹配的单词" : "暂无可浏览的单词"} errorMessage="无法加载单词列表，请重试。" retry={refresh} />
      {#if page.status === "ready" && page.data}<ul>{#each page.data.items as word (word.id)}<li><button class="word-row" class:selected={selected === word.id} aria-label={`${word.expression}，${word.reading}，${word.meaningChinese}，${word.bookName}，打开详情`} aria-expanded={selected === word.id} onclick={event => open(word.id,event.currentTarget)}><span class="word"><strong lang="ja">{word.expression || "—"}</strong><span class="reading" lang="ja">{word.reading || "—"}</span></span><span class="meaning">{word.meaningChinese || "暂无释义"}</span><span class="level">{word.jlptLevel}</span></button></li>{/each}</ul>{/if}
    </div>
    <footer class="pagination"><span role="status">{page.status === "ready" && page.data ? rangeLabel(page.data) : page.status === "error" ? "加载失败" : "正在加载…"}</span><div><button aria-label="上一页单词" disabled={page.status !== "ready" || !page.data || page.data.offset === 0} onclick={event => {void turn(Math.max(0,(page.data?.offset ?? 0)-50),event.currentTarget);}}>上一页</button><button aria-label="下一页单词" disabled={page.status !== "ready" || !page.data || page.data.offset + page.data.items.length >= page.data.total} onclick={event => {void turn((page.data?.offset ?? 0)+50,event.currentTarget);}}>下一页</button></div></footer>
  </section>
  {#if selected}<WordDetail state={detail} close={() => {void close();}} retry={() => {if (selected) void detailRead.run(() => vocabularyService.getWord(selected as string));}} />{/if}
</div>
<style>
  .page-header { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:20px; } .page-header p { margin-top:5px; } .back { margin-bottom:10px; border:0; padding:0; background:transparent; color:var(--accent); }
  .searchbar { margin-bottom:20px; } .searchbar label { display:block; font-size:12px; color:var(--text-secondary); margin-bottom:7px; } .search-field { display:flex; gap:8px; } .search-input { flex:1; }
  .browser-panels { min-height:0; flex:1; min-width:0; } .list-panel { display:flex; flex-direction:column; height:100%; min-height:0; border:1px solid var(--border); border-radius:var(--radius); background:var(--surface); overflow:hidden; }
  .list-head { display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr) 42px; gap:14px; padding:12px 20px; background:var(--surface-secondary); color:var(--text-secondary); font-size:12px; }
  .list-scroll { flex:1; min-height:0; overflow:auto; padding:0 4px; } ul { list-style:none; margin:0; padding:0; } li+li { border-top:1px solid var(--border); }
  .word-row { border:0; border-radius:0; display:grid; grid-template-columns:minmax(0,1fr) minmax(0,1fr) 42px; gap:14px; padding:14px 16px; text-align:left; width:100%; align-items:center; } .word-row:focus-visible { outline-offset:-3px; } .word-row.selected { background:var(--surface-secondary); }
  .word { display:flex; flex-direction:column; min-width:0; overflow-wrap:anywhere; } strong { font-size:17px; font-weight:600; } .reading { color:var(--text-secondary); margin-top:2px; font-size:13px; } .meaning { overflow-wrap:anywhere; display:-webkit-box; -webkit-line-clamp:2; line-clamp:2; -webkit-box-orient:vertical; overflow:hidden; } .level { color:var(--text-secondary); font-size:12px; }
  .pagination { display:flex; align-items:center; justify-content:space-between; gap:10px; padding:12px 16px; border-top:1px solid var(--border); font-size:12px; } .pagination>span { color:var(--text-secondary); } .pagination div { display:flex; gap:6px; } .pagination button { font-size:12px; padding:6px 10px; }
  .has-detail .list-panel { display:none; }
  @media(min-width:1100px) { .has-detail { display:grid; grid-template-columns:minmax(0,1fr) 330px; gap:16px; } .has-detail .list-panel { display:flex; } }
</style>
