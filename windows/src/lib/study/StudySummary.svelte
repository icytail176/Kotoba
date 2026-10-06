<script lang="ts">
import type { Summary } from "./controller.ts";
let { summary, finish }: {
    summary: Summary;
    finish: () => void;
} = $props();
let heading = $state<HTMLHeadingElement>();
$effect(() => { heading?.focus(); });
const ratingLabels = { again: "忘记", hard: "模糊", good: "认识", easy: "熟练" };
</script>
<div class="summary-scroll"><div class="summary"><h2 bind:this={heading} tabindex="-1">本组学习完成</h2><p class="total">{summary.total} 个词</p><p class="muted">辛苦了，这组学习已经完成。</p><div class="metrics">{#each [["忘记",summary.forgotten],["模糊",summary.fuzzy],["认识",summary.known],["熟练",summary.mastered]] as [label,value]}<p><strong>{value}</strong><span>{label}</span></p>{/each}</div>
 {#each [{title:"第一轮 · 单词拼写",round:summary.expression,hints:true},{title:"第二轮 · 假名拼写",round:summary.reading,hints:false}] as {title,round,hints}}{#if round.totalCount}<section><h3>{title}</h3><p>需要拼写 {round.totalCount} · 一次通过 {round.firstAttemptCorrectCount} · 重练通过 {round.retryCorrectCount}{#if hints} · 其中使用提示 {round.usedHintCount}{/if}</p></section>{/if}{/each}
 <section><h3>本组单词</h3>{#each summary.outcomes as result}<div class="word-result"><strong lang="ja">{result.card.word.expression}</strong><span lang="ja">{result.card.word.reading}</span><p>{result.card.word.meaningChinese}</p><p class="muted">{result.mastered?"熟练":ratingLabels[result.rating]} · 卡片重练 {result.retryCount} 次{#if !result.mastered} · {result.card.expectedProgress?.intervalDays?`${result.card.expectedProgress.intervalDays} 天后复习`:"10 分钟后复习"}{/if}</p>{#if result.spelling}<p class="muted">单词拼写：{!result.spelling.expression.requiresSpelling?"无需拼写":result.spelling.expression.passedFirstTry?"拼写一次通过":result.spelling.expression.usedHint?"使用提示后重练通过":"重练通过"}{#if result.spelling.reading.requiresSpelling} · 假名：{result.spelling.reading.passedFirstTry?"拼写一次通过":"重练通过"}{/if}</p>{/if}</div>{/each}</section>
 </div></div><div class="summary-footer"><button onclick={finish}>返回首页 <kbd>Enter</kbd></button></div>
<style>.summary-scroll{flex:1;min-height:0;overflow:auto;padding:4px;}.summary{max-width:760px;margin:auto;padding-bottom:24px;display:flex;flex-direction:column;gap:18px;}.summary>h2,.summary>.total{text-align:center;}.total{font-size:30px;}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;}.metrics p{display:flex;flex-direction:column;align-items:center;padding:14px;background:var(--surface);border:1px solid var(--border);border-radius:8px;}.metrics strong{font-size:26px;}.metrics span{color:var(--text-secondary);}section{display:flex;flex-direction:column;gap:12px;}.word-result{border:1px solid var(--border);border-radius:8px;padding:16px;overflow-wrap:anywhere;}.word-result>span{margin-left:12px;}.summary-footer{border-top:1px solid var(--border);padding-top:14px;display:flex;justify-content:flex-end;}kbd{font-size:12px;margin-left:10px;}</style>
