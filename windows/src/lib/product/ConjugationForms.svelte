<script lang="ts">
import type { Conjugation } from './types.ts';
let { value, excludeDictionary = false }: {
    value: Conjugation;
    excludeDictionary?: boolean;
} = $props();
</script>
<dl class="forms">{#each value.forms.filter(f=>!excludeDictionary||f.formType!=='dictionary') as form}<div><dt>{form.label}</dt><dd><span lang="ja">{form.surface}</span>{#if form.reading!==form.surface}<small lang="ja">{form.reading}</small>{/if}</dd></div>{/each}</dl>
<style>.forms{margin:0;}.forms div{display:grid;grid-template-columns:85px minmax(0,1fr);gap:12px;padding:7px 0;border-bottom:1px solid var(--border);}dt{color:var(--text-secondary);font-size:12px;}dd{margin:0;overflow-wrap:anywhere;}small{display:block;color:var(--text-secondary);font-size:12px;}</style>
