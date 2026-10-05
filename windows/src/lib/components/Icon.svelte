<script lang="ts">
  let { name }: { name: string } = $props();
  const paths: Record<string,string> = {
    home: "M3 10 12 3l9 7v10H3Z M9 20v-7h6v7", words: "M4 4h16v16H4Z M8 8h8 M8 12h8 M8 16h5",
    books: "M3 5h6l3 2 3-2h6v15h-6l-3 2-3-2H3Z M12 7v15", chart: "M4 20V5 M4 20h17 M9 16v-5 M14 16V7 M19 16v-8",
    kana: "M4 4h16v16H4Z M4 12h16 M12 4v16", settings: "M12 3v3 M12 18v3 M3 12h3 M18 12h3 M5.6 5.6l2.1 2.1 M16.3 16.3l2.1 2.1 M18.4 5.6l-2.1 2.1 M7.7 16.3l-2.1 2.1 M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
    arrow: "M5 12h14 M14 7l5 5-5 5", search: "M16 10a6 6 0 1 1-12 0 6 6 0 0 1 12 0 M14.5 14.5 20 20",
  };
</script>
<svg aria-hidden="true" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d={paths[name] ?? paths.words} /></svg>
