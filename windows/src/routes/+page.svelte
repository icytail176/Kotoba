<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listBuiltinWordBooks, searchWords, type BookSummary, type WordPage } from "$lib/vocabulary";

  interface AppInfo {
    name: string;
    platform: string;
    phase: number;
  }

  interface DatabaseInfo {
    schemaVersion: number;
    manifestVersion: number | null;
    location: string;
    tableCounts: {
      wordBooks: number;
      vocabularyWords: number;
      learningProgress: number;
      reviewLogs: number;
    };
  }

  let books = $state<BookSummary[]>([]);
  let query = $state("");
  let results = $state<WordPage | null>(null);
  let searchError = $state<string | null>(null);
  let searching = $state(false);
  async function search(event: SubmitEvent) {
    event.preventDefault();
    searching = true;
    searchError = null;
    try { results = await searchWords(query, 20, 0); }
    catch (error: unknown) { searchError = error instanceof Error ? error.message : String(error); }
    finally { searching = false; }
  }

  let databaseInfo = $state<DatabaseInfo | null>(null);
  let databaseError = $state<string | null>(null);
  let appInfo = $state<AppInfo | null>(null);
  let errorMessage = $state<string | null>(null);

  onMount(() => {
    listBuiltinWordBooks().then((items) => { books = items; }).catch((error: unknown) => {
      databaseError = error instanceof Error ? error.message : String(error);
    });
    invoke<DatabaseInfo>("database_info")
      .then((info) => { databaseInfo = info; })
      .catch((error: unknown) => {
        databaseError = error instanceof Error ? error.message : String(error);
      });
    invoke<AppInfo>("app_info")
      .then((info) => { appInfo = info; })
      .catch((error: unknown) => {
        errorMessage = error instanceof Error ? error.message : String(error);
      });
  });
</script>

<main>
  <h1>Kotoba</h1>
  <p lang="en">Windows client prototype</p>
  <p lang="en">Phase 3</p>
  <p class="japanese">日本語 · ことば · 漢字 · カタカナ</p>
  <div class="status" role="status" lang="en">
    {#if errorMessage}
      <p>IPC failed: {errorMessage}</p>
    {:else if appInfo}
      <p>IPC connected</p>
      <p>{appInfo.name} · {appInfo.platform} · Phase {appInfo.phase}</p>
    {:else}
      <p>Connecting to Rust…</p>
    {/if}
    {#if databaseError}
      <p>Database unavailable: {databaseError}</p>
    {:else if databaseInfo}
      <p>Database connected · Schema {databaseInfo.schemaVersion}</p>
    {:else}
      <p>Connecting to database…</p>
    {/if}
  </div>
  {#if books.length}
    <p lang="en">Built-in vocabulary: {books.reduce((count, book) => count + book.wordCount, 0).toLocaleString("en-US")}</p>
    <p lang="en">Manifest {databaseInfo?.manifestVersion ?? "…"}</p>
    <ul class="books">
      {#each books as book (book.id)}<li>{book.jlptLevel}: {book.wordCount.toLocaleString("en-US")}</li>{/each}
    </ul>
    <form onsubmit={search}>
      <label for="query">查询词条（日文 / 假名 / 中文）</label>
      <div class="search"><input id="query" bind:value={query} maxlength="200" /><button disabled={searching}>查询</button></div>
    </form>
    <div role="status">
      {#if searchError}<p>{searchError}</p>{/if}
      {#if results}
        <p>找到 {results.total} 条，最多显示 20 条。</p>
        <ul class="results">
          {#each results.items as word (word.id)}
            <li><strong>{word.japanese}</strong> · {word.kana} · {word.chineseMeaning}
              <small>{word.jlptLevel} · canonical: {word.canonicalId?.slice(0, 8)}</small></li>
          {/each}
        </ul>
      {/if}
    </div>
  {/if}
</main>

<style>
  :global(html) {
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    color-scheme: light dark;
    color: #202124;
    background: #f7f7f8;
    line-height: 1.6;
  }
  :global(body) { margin: 0; }
  :global(*) { box-sizing: border-box; }
  main {
    width: 100%;
    max-width: 48rem;
    margin: 0 auto;
    padding: clamp(1rem, 5vw, 3rem);
    text-align: center;
    overflow-wrap: anywhere;
  }
  h1 { margin: 1rem 0; font-size: 2.5rem; }
  p { margin: 0.75rem 0; }
  .japanese { margin-top: 2rem; font-size: 1.25rem; }
  .status { margin-top: 2rem; color: #52555a; font-size: 0.9rem; }
  .books { list-style: none; padding: 0; display: flex; flex-wrap: wrap; gap: 0.5rem 1rem; justify-content: center; }
  form { margin-top: 1.5rem; text-align: left; }
  .search { display: flex; gap: 0.5rem; margin-top: 0.5rem; }
  input { flex: 1; min-width: 0; }
  input, button { font: inherit; padding: 0.5rem; }
  .results { padding: 0; list-style: none; text-align: left; }
  .results li { padding: 0.75rem 0; border-top: 1px solid #9996; }
  small { display: block; opacity: 0.7; }
  @media (prefers-color-scheme: dark) {
    :global(html) { color: #ededee; background: #202124; }
    .status { color: #b8bbc0; }
  }
</style>
