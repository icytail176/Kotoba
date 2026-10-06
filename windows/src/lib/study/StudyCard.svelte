<script lang="ts">
import ConjugationForms from "../product/ConjugationForms.svelte";
import type { ViewState } from "./controller.ts";
import type { Rating } from "./types.ts";
let { state, reveal, rate, favorite, page }: {
    state: ViewState;
    reveal: () => void;
    rate: (r: Rating) => void;
    favorite: () => void;
    page: (direction:-1|1)=>void;
} = $props();
const ratings: [
    Rating,
    string,
    string
][] = [["again", "忘记", "1"], ["hard", "模糊", "2"], ["good", "认识", "3"], ["easy", "熟练", "Delete / Backspace"]];
</script>
{#if state.card}
 <div class="card-content">
  <div class="card-header"><p role="status">{state.phase==="flashcardRetry"?"卡片错词重试":"卡片学习"} · {state.index+1} / {state.total}</p><button onclick={favorite} disabled={state.pending||!!state.retryKind} aria-label={state.card.isFavorite?"取消收藏（F）":"收藏（F）"}>{state.card.isFavorite?"★ 已收藏":"☆ 收藏"} <kbd>F</kbd></button></div>
  <div class="surface">
   <h2 lang="ja">{state.card.word.expression}</h2>
   {#if state.revealed}
    {#if state.cardPage===1&&state.card.word.conjugation}<ConjugationForms value={state.card.word.conjugation} excludeDictionary />{:else}<dl><dt>假名</dt><dd lang="ja">{state.card.word.reading}</dd>{#if state.card.word.romaji}<dt>罗马音</dt><dd>{state.card.word.romaji}</dd>{/if}{#if state.card.word.pitch}<dt>音调</dt><dd aria-label={state.card.word.pitch.accessibilityText}>{state.card.word.pitch.displayText}</dd>{/if}<dt>释义</dt><dd>{state.card.word.meaningChinese}</dd>{#if state.card.word.partOfSpeech}<dt>词性</dt><dd>{state.card.word.partOfSpeech}</dd>{/if}{#if state.card.word.exampleJapanese}<dt>例句</dt><dd lang="ja">{state.card.word.exampleJapanese}</dd>{/if}{#if state.card.word.exampleChinese}<dt>翻译</dt><dd>{state.card.word.exampleChinese}</dd>{/if}{#if state.card.word.loanword}<dt>{state.card.word.loanword.isPartial?"部分词源":"外来语词源"}</dt><dd>{state.card.word.loanword.sourceTerm}（{state.card.word.loanword.isWasei?state.card.word.loanword.languageName&&state.card.word.loanword.languageName!=="英语"?`和制${state.card.word.loanword.languageName}`:"和制英语":state.card.word.loanword.languageName??"词源"}{state.card.word.loanword.isPartial?" · 部分词源":""}）</dd>{/if}</dl>{/if}
    {#if state.card.word.conjugation&&state.card.word.conjugation.forms.length>1}<div class="card-pages"><button onclick={()=>page(-1)} disabled={state.cardPage===0||state.pending}>← 答案</button><span>{state.cardPage+1} / 2</span><button onclick={()=>page(1)} disabled={state.cardPage===1||state.pending}>活用 →</button></div>{/if}
   {:else}<button class="reveal" onclick={reveal} disabled={state.pending}>按空格或点击显示答案 <kbd>Space</kbd></button>{/if}
  </div>
 </div>
 {#if state.revealed}<div class="ratings" aria-label={state.phase==="flashcardRetry"?"强化评价":"正式评分"}>{#each ratings as [value,label,key]}<button onclick={()=>rate(value)} disabled={state.pending||!!state.retryKind} aria-label={`${label}（${key}）`}><strong>{label}</strong><kbd>{key}</kbd></button>{/each}</div>{/if}
{/if}
<style>.card-pages{display:flex;align-items:center;justify-content:center;gap:12px;margin-top:20px;}.card-content{flex:1;min-height:0;overflow:auto;padding:8px 4px 20px;}.card-header{display:flex;justify-content:space-between;gap:12px;align-items:center;max-width:820px;margin:0 auto 18px;}.card-header p{color:var(--text-secondary);}.surface{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:28px;max-width:820px;margin:auto;min-height:250px;}.surface h2{font-size:42px;text-align:center;overflow-wrap:anywhere;margin-bottom:24px;}.reveal{display:block;width:100%;padding:24px 12px;}dl{max-width:620px;margin:auto;}dt{font-size:12px;color:var(--text-secondary);margin-top:14px;}dd{margin:4px 0 0;font-size:19px;white-space:pre-wrap;overflow-wrap:anywhere;}.ratings{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;border-top:1px solid var(--border);padding-top:14px;}.ratings button{display:flex;flex-direction:column;gap:6px;min-height:72px;align-items:center;justify-content:center;background:var(--surface-secondary);}kbd{font-size:11px;color:var(--text-secondary);white-space:normal;}@media(max-width:800px){.surface{padding:18px;}.surface h2{font-size:34px;}.ratings{gap:6px;}.ratings button{padding:8px 4px;}}</style>
