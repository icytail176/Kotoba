<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  interface AppInfo {
    name: string;
    platform: string;
    phase: number;
  }

  let appInfo = $state<AppInfo | null>(null);
  let errorMessage = $state<string | null>(null);

  onMount(() => {
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
  <p lang="en">Phase 0</p>
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
  </div>
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
  @media (prefers-color-scheme: dark) {
    :global(html) { color: #ededee; background: #202124; }
    .status { color: #b8bbc0; }
  }
</style>
