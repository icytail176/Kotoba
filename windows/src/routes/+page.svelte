<script lang="ts">
  import { tick } from "svelte";
  import AppShell from "$lib/layout/AppShell.svelte";
  import Placeholder from "$lib/layout/Placeholder.svelte";
  import Wordbooks from "$lib/vocabulary/Wordbooks.svelte";
  import WordBrowser from "$lib/vocabulary/WordBrowser.svelte";
  import type { WordBookSummary } from "$lib/types/vocabulary";
  let section = $state("单词管理");
  let book = $state<WordBookSummary | null>(null);
  function select(value: string) { section=value;book=null; }
  async function openBook(value: WordBookSummary | null) { book=value; await tick(); document.querySelector<HTMLElement>("main h1")?.focus(); }
</script>
<AppShell selected={section} onselect={select}>
  {#key section}
    {#if section === "单词管理"}<WordBrowser />
    {:else if section === "词书"}{#if book}<WordBrowser {book} back={() => {void openBook(null);}} />{:else}<Wordbooks open={value => {void openBook(value);}} />{/if}
    {:else}<Placeholder title={section} />{/if}
  {/key}
</AppShell>
