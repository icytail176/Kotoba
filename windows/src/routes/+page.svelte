<script lang="ts">
  import { tick } from "svelte";
  import AppShell from "$lib/layout/AppShell.svelte";
  import Placeholder from "$lib/layout/Placeholder.svelte";
  import Wordbooks from "$lib/vocabulary/Wordbooks.svelte";
  import WordBrowser from "$lib/vocabulary/WordBrowser.svelte";
  import type { WordBookSummary } from "$lib/types/vocabulary";
  import TodayStudy from "$lib/study/TodayStudy.svelte";
  let leaveGuard:((leave:()=>void)=>void)|null=null;
  let section = $state("今日学习");
  let book = $state<WordBookSummary | null>(null);
  function select(value: string) { if(value===section)return;const change=()=>{section=value;book=null;};if(leaveGuard)leaveGuard(change);else change(); }
  async function openBook(value: WordBookSummary | null) { book=value; await tick(); document.querySelector<HTMLElement>("main h1")?.focus(); }
</script>
<AppShell selected={section} onselect={select}>
  {#key section}
    {#if section === "今日学习"}<TodayStudy registerLeaveGuard={guard=>{leaveGuard=guard;}} />
    {:else if section === "单词管理"}<WordBrowser />
    {:else if section === "词书"}{#if book}<WordBrowser {book} back={() => {void openBook(null);}} />{:else}<Wordbooks open={value => {void openBook(value);}} />{/if}
    {:else}<Placeholder title={section} />{/if}
  {/key}
</AppShell>
