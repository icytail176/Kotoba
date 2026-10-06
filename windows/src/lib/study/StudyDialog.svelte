<script lang="ts">
import type { Snippet } from "svelte";
let { open, title, onclose, children }: {
    open: boolean;
    title: string;
    onclose: () => void;
    children: Snippet;
} = $props();
let dialog = $state<HTMLDialogElement>();
$effect(() => { if (!dialog)
    return; if (open && !dialog.open)
    dialog.showModal();
else if (!open && dialog.open)
    dialog.close(); });
</script>
<dialog bind:this={dialog} aria-label={title} oncancel={e=>{e.preventDefault();onclose();}}>
 <h2>{title}</h2>{@render children()}
</dialog>
<style>dialog{color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);max-width:min(560px,calc(100vw - 40px));max-height:calc(100dvh - 40px);padding:24px;overflow:auto;}dialog::backdrop{background:rgb(0 0 0 / .35);}h2{margin-bottom:18px;}</style>
