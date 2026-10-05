<script lang="ts">
  let { status, errorMessage = "无法加载内容，请重试。", emptyMessage = "暂无内容", empty = false, retry }: { status: "loading" | "ready" | "error"; errorMessage?: string; emptyMessage?: string; empty?: boolean; retry: () => void } = $props();
</script>
{#if status === "loading"}<div class="state" role="status"><span class="dot" aria-hidden="true"></span><p>正在加载…</p></div>
{:else if status === "error"}<div class="state" role="alert"><p>{errorMessage}</p><button onclick={retry}>重试</button></div>
{:else if empty}<div class="state" role="status"><p>{emptyMessage}</p><span class="muted">试试其他关键词，或清空搜索继续浏览。</span></div>{/if}
<style>.state { padding: 40px 20px; display: flex; flex-direction: column; gap: 14px; align-items: center; text-align: center; color: var(--text-secondary); } .state button { color: var(--accent); } .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--accent); }</style>
