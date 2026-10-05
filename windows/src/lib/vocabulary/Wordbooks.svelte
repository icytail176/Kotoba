<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { vocabularyService } from "$lib/services/vocabulary";
  import type { WordBookSummary } from "$lib/types/vocabulary";
  import { LatestRead, type ReadState } from "./state";
  import ReadStatus from "$lib/components/ReadStatus.svelte";
  import Icon from "$lib/components/Icon.svelte";
  let { open }: { open: (book: WordBookSummary) => void } = $props();
  let state = $state<ReadState<WordBookSummary[]>>({status:"loading",data:null});
  const resource = new LatestRead<WordBookSummary[]>(value => {state=value;});
  const refresh = () => {void resource.run(vocabularyService.listBooks);};
  onMount(refresh); onDestroy(() => resource.dispose());
  let total = $derived(state.data?.reduce((sum,book) => sum + book.wordCount,0) ?? 0);
</script>
<header><h1 tabindex="-1">词书</h1><p class="muted">按等级浏览，找到适合你的词汇。</p></header>
<ReadStatus status={state.status} empty={state.data?.length === 0} errorMessage="无法加载词书，请重试。" emptyMessage="暂无可浏览的词书" retry={refresh} />
{#if state.status === "ready" && state.data?.length}
  <div class="summary"><span>{state.data.length} 本词书</span><span>{total.toLocaleString("zh-CN")} 个单词</span></div>
  <section class="book-grid" aria-label="内置词书">{#each state.data as book (book.id)}
    <button class="book" onclick={() => open(book)} aria-label={`打开 ${book.name}，${book.wordCount} 个单词`}><span class="level">{book.jlptLevel}</span><div><h2>{book.name}</h2><p class="muted">{book.wordCount.toLocaleString("zh-CN")} 个单词</p></div><span class="open"><span>浏览词书</span><Icon name="arrow" /></span></button>
  {/each}</section>
{/if}
<style>
  header p { margin-top:6px; } .summary { margin:24px 0 16px; display:flex; gap:18px; color:var(--text-secondary); font-size:13px; }
  .book-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:16px; overflow:auto; padding:4px; }
  .book { padding:24px; display:flex; flex-direction:column; align-items:flex-start; gap:18px; text-align:left; border-radius:var(--radius); min-height:230px; }
  .level { display:grid; place-items:center; width:56px; height:56px; background:var(--surface-secondary); color:var(--accent); border-radius:12px; font-size:23px; font-weight:600; } .book p { margin-top:4px; }
  .open { display:flex; align-items:center; justify-content:space-between; width:100%; font-size:13px; color:var(--accent); margin-top:auto; }
</style>
