<script lang="ts">let { title }: { title: string } = $props();</script>
<header><h1 tabindex="-1">{title}</h1></header>
<section class="placeholder" aria-label={title}><span class="symbol" lang="ja" aria-hidden="true">言</span><h2>慢慢积累，每天向前</h2><p class="muted">此功能将在后续阶段实现。</p><p class="muted">现在可以在「单词管理」和「词书」中浏览日语词汇。</p></section>
<style>.placeholder { margin:auto; text-align:center; display:flex; flex-direction:column; align-items:center; gap:14px; max-width:380px; } .symbol { color:var(--accent); background:var(--surface-secondary); border-radius:var(--radius); padding:12px 24px; font-size:38px; margin-bottom:8px; }</style>
