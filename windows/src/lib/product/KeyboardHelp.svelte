<script lang="ts">
import { onMount } from 'svelte';
import { shortcutReference, type Platform } from '../study/keyboard.ts';
let platform = $state<Platform>('windows');
onMount(() => { platform = navigator.platform.toLowerCase().includes('mac') ? 'mac' : 'windows'; });
</script>
<div class="shortcut-sections">{#each shortcutReference(platform) as section}<section><h3>{section.title}</h3>{#each section.items as [action,keys]}<p><span>{action}</span><kbd>{keys}</kbd></p>{/each}</section>{/each}</div>
<style>.shortcut-sections{display:flex;flex-direction:column;gap:18px;}.shortcut-sections section p{display:flex;justify-content:space-between;gap:20px;margin-top:6px;}.shortcut-sections kbd{white-space:nowrap;}h3{font-size:15px;}</style>
