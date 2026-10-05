<script lang="ts">
  import type { VocabularyWordDetail } from "$lib/types/vocabulary";
  import type { ReadState } from "./state";
  import ReadStatus from "$lib/components/ReadStatus.svelte";
  let { state, close, retry }: { state: ReadState<VocabularyWordDetail | null>; close: () => void; retry: () => void } = $props();
</script>
<section class="detail-panel" aria-label="单词详情">
  <header><h2 id="detail-heading" tabindex="-1">单词详情</h2><button onclick={close} aria-label="关闭单词详情">关闭 <span aria-hidden="true">×</span></button></header>
  <ReadStatus status={state.status} errorMessage="无法加载单词详情，请重试。" retry={retry} />
  {#if state.status === "ready"}
    {#if state.data}{@const word = state.data}<div class="detail-content">
      <span class="badge">{word.bookName}</span><h3 lang="ja">{word.expression || "—"}</h3>{#if word.reading}<p class="reading" lang="ja">{word.reading}</p>{/if}
      <section class="block"><h4>中文释义</h4><p>{word.meaningChinese || "暂无释义"}</p>{#if word.partOfSpeech}<span class="part">{word.partOfSpeech}</span>{/if}</section>
      {#if word.exampleJapanese || word.exampleChinese}<section class="block"><h4>例句</h4>{#if word.exampleJapanese}<p lang="ja">{word.exampleJapanese}</p>{/if}{#if word.exampleChinese}<p class="muted translation">{word.exampleChinese}</p>{/if}</section>{/if}
      {#if word.loanword}<section class="block"><h4>{word.loanword.isPartial ? "部分词源" : "外来语词源"}</h4><p>{word.loanword.sourceTerm}{#if word.loanword.isWasei}（{word.loanword.languageName && word.loanword.languageName !== "英语" ? `和制${word.loanword.languageName}` : "和制英语"}）{:else if word.loanword.languageName}（{word.loanword.languageName}）{/if}</p></section>{/if}
      {#if word.tags.length}<section class="block"><h4>标签</h4><div class="tags">{#each word.tags as tag}<span>{tag}</span>{/each}</div></section>{/if}
    </div>{:else}<div class="missing" role="status">未找到该单词。<button onclick={close}>返回单词列表</button></div>{/if}
  {/if}
</section>
<style>
  .detail-panel { min-width:0; min-height:0; height:100%; overflow:auto; border:1px solid var(--border); border-radius:var(--radius); background:var(--surface); }
  header { position:sticky; top:0; background:var(--surface); padding:16px 20px; border-bottom:1px solid var(--border); display:flex; align-items:center; justify-content:space-between; gap:12px; } header h2 { font-size:15px; } header button { border:0; font-size:13px; }
  .detail-content { padding:24px; overflow-wrap:anywhere; } .badge,.part { font-size:12px; color:var(--text-secondary); background:var(--surface-secondary); border-radius:5px; padding:3px 7px; display:inline-block; }
  h3 { font-size:31px; margin:18px 0 5px; font-weight:600; line-height:1.3; } .reading { color:var(--text-secondary); font-size:17px; }
  .block { border-top:1px solid var(--border); padding-top:20px; margin-top:24px; } h4 { margin:0 0 10px; font-size:12px; color:var(--text-secondary); font-weight:500; } .block p { font-size:16px; } .part { margin-top:12px; } .translation { margin-top:8px; font-size:14px!important; } .tags { display:flex; flex-wrap:wrap; gap:6px; } .tags span { background:var(--surface-secondary); padding:4px 8px; border-radius:5px; font-size:12px; }
  .missing { padding:30px; display:flex; flex-direction:column; gap:16px; }
</style>
