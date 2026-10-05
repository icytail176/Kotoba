<script lang="ts">
  import { tick } from "svelte";
  import type { Snippet } from "svelte";
  import Icon from "$lib/components/Icon.svelte";
  import "../styles/tokens.css";
  let { selected, onselect, children }: { selected: string; onselect: (section: string) => void; children: Snippet } = $props();
  const sections = [{name:"今日学习",icon:"home"},{name:"单词管理",icon:"words"},{name:"词书",icon:"books"},{name:"学习统计",icon:"chart"},{name:"五十音图",icon:"kana"},{name:"设置",icon:"settings"}];
  async function navigate(name: string) { onselect(name); await tick(); document.querySelector<HTMLElement>("main h1")?.focus(); }
</script>
<a class="skip" href="#content">跳到主要内容</a>
<div class="shell">
  <aside class="sidebar">
    <div class="brand"><span class="mark" lang="ja">言</span><div><strong>Kotoba</strong><p>日语词汇</p></div></div>
    <nav aria-label="主导航">{#each sections as section}<button aria-current={selected === section.name ? "page" : undefined} onclick={() => navigate(section.name)}><Icon name={section.icon} /><span>{section.name}</span></button>{/each}</nav>
    <div class="local"><span aria-hidden="true">●</span> 本地词库</div>
  </aside>
  <main id="content" class="workspace" tabindex="-1">{@render children()}</main>
</div>
<style>
  .shell { height: 100dvh; display: grid; grid-template-columns: var(--sidebar-width) minmax(0,1fr); }
  .sidebar { background: var(--surface); border-right: 1px solid var(--border); display: flex; flex-direction: column; padding: 30px 14px 18px; }
  .brand { display:flex; gap:12px; align-items:center; padding:0 10px 32px; } .brand strong { font-size:22px; letter-spacing:-.5px; } .brand p { font-size:12px; color:var(--text-secondary); }
  .mark { display:grid; place-items:center; width:37px; height:40px; border-radius:10px; color:var(--accent); background:var(--surface-secondary); font-size:24px; }
  nav { display:flex; flex-direction:column; gap:6px; } nav button { border:0; background:transparent; display:flex; align-items:center; gap:12px; padding:12px 14px; text-align:left; }
  nav button[aria-current="page"] { background:var(--surface-secondary); color:var(--accent); font-weight:650; } .local { margin-top:auto; padding:14px; color:var(--text-secondary); font-size:12px; } .local span { color:var(--accent); margin-right:5px; }
  .workspace { min-width:0; min-height:0; display:flex; flex-direction:column; overflow:hidden; padding:var(--content-spacing); }
  .skip { position:fixed; top:-100px; left:16px; z-index:10; padding:10px; background:var(--surface); color:var(--accent); } .skip:focus { top:10px; }
  @media(max-width:800px) { .sidebar { padding:22px 10px 14px; } .brand { padding:0 4px 26px; gap:8px; } .brand strong { font-size:19px; } nav button { padding:11px 10px; gap:8px; } }
</style>
