<script lang="ts">
import { tick } from "svelte";
import type { ViewState } from "./controller.ts";
let { state: view, input, hint, submit, compositionstart, compositionend, composing, hintKeys }: {
    state: ViewState;
    input: (v: string) => void;
    hint: () => void;
    submit: () => void;
    compositionstart: () => void;
    compositionend: () => void;
    composing: boolean;
    hintKeys: string;
} = $props();
let field = $state<HTMLInputElement>();
$effect(() => { const id = view.question?.wordId; const phase = view.phase; const locked = view.locked; const feedback = view.feedback; void id; void phase; void feedback; if (!locked)
    void tick().then(() => field?.focus()); });
</script>
{#if view.question}
 <div class="spelling-scroll">
  <div class="spelling">
   <p role="status">{view.phase==="spellingExpression"?"第一轮 · 单词拼写":"第二轮 · 假名拼写"}</p>
   <div class="prompt"><p class="muted">{view.phase==="spellingExpression"?"根据释义和语境写出完整日语单词":"看汉字词写假名"}</p><h2 lang={view.phase==="spellingReading"?"ja":undefined}>{view.question.prompt}</h2>
    {#if view.phase==="spellingExpression"}{#if view.question.context}<p lang="ja">{view.question.context}</p>{#if view.question.exampleChinese}<p class="muted">{view.question.exampleChinese}</p>{/if}{/if}<div class="hint">{#if view.hint}<p>假名提示：<span lang="ja">{view.question.reading}</span></p>{:else}<button onclick={hint} disabled={view.pending||view.locked||composing}>提示 <kbd>{hintKeys}</kbd></button>{/if}</div>{:else}<p class="muted">{view.question.meaning}</p>{/if}
   </div>
   <label for="study-answer">答案</label>
   <input bind:this={field} id="study-answer" lang="ja" autocomplete="off" spellcheck="false" value={view.answer} oninput={e=>input(e.currentTarget.value)} oncompositionstart={compositionstart} oncompositionend={compositionend} disabled={view.locked||view.pending} placeholder={view.phase==="spellingReading"?"输入假名":"输入日语单词"} />
   {#if view.feedback}<div role="status" class="feedback"><strong>{view.feedback==="correct"?"正确":"拼写错误，请重新输入"}</strong>{#if view.feedback==="incorrect"}<p>正确答案：<span lang="ja">{view.question.expected}</span></p>{/if}{#if view.requeued}<p>本次已纠正；该词已加入本轮队尾，稍后将再次测试。</p>{/if}</div>{/if}
   <button class="primary" onclick={submit} disabled={view.pending||composing||(!view.locked&&!view.answer.trim())}>{view.locked?"下一题":"提交"} <kbd>Enter</kbd></button>
  </div>
 </div>
{/if}
<style>.spelling-scroll{flex:1;min-height:0;overflow:auto;padding:4px;}.spelling{max-width:760px;margin:auto;display:flex;flex-direction:column;gap:16px;padding-bottom:24px;}.prompt{padding:24px;border:1px solid var(--border);border-radius:var(--radius);background:var(--surface);display:flex;flex-direction:column;gap:12px;overflow-wrap:anywhere;}.prompt h2{font-size:28px;}.hint{padding-top:12px;border-top:1px solid var(--border);}.feedback{padding:16px;background:var(--surface-secondary);border-radius:8px;overflow-wrap:anywhere;}.primary{align-self:flex-start;background:var(--accent);color:var(--surface);}kbd{font-size:12px;margin-left:8px;}input{font-size:22px;width:100%;}label{font-weight:600;}@media(max-width:800px){.prompt{padding:18px;}}</style>
