<script lang="ts">
import { onMount, onDestroy } from 'svelte';
import { productService } from './service.ts';
import { SettingsController, type SettingsState } from './actions.ts';
import type { AppSettings, ProductBook } from './types.ts';
import ReadStatus from '../components/ReadStatus.svelte';
import KeyboardHelp from './KeyboardHelp.svelte';
import ImportExport from './ImportExport.svelte';
import BackupRestore from './BackupRestore.svelte';
let view = $state<SettingsState>({ loading: true, pending: false, value: null, error: null, saved: false });
let values = $state<AppSettings>({ formatVersion: 1, dailyNewWordCount: 10, dailyReviewWordCount: 20, randomizesStudyOrder: true, selectedBookId: null });
let books = $state<ProductBook[]>([]);
let bookError = $state(false);
let alive = true;
const controller = new SettingsController(productService, v => {
    view = v;
    if (v.value)
        values = { ...v.value };
});
function reloadBooks() {
    bookError = false;
    void productService.books().then(v => {
        if (alive)
            books = v;
    }).catch(() => {
        if (alive)
            bookError = true;
    });
}
onMount(() => { void controller.load(); reloadBooks(); });
onDestroy(() => { alive = false; controller.dispose(); });
</script>
<header><h1 tabindex="-1">设置</h1><p class="muted">学习偏好与本地数据。</p></header>
<div class="scroll"><ReadStatus status={view.loading?'loading':view.value?'ready':'error'} errorMessage="无法加载设置，原文件已保留。" retry={()=>{void controller.load();}} />
 {#if view.value}<section><h2>学习</h2><form onsubmit={e=>{e.preventDefault();void controller.save({...values});}}><label>每组新词数量<input type="number" min="1" max="100" bind:value={values.dailyNewWordCount} required disabled={view.pending} /></label><label>每组复习数量<input type="number" min="1" max="200" bind:value={values.dailyReviewWordCount} required disabled={view.pending} /></label><label class="check"><input type="checkbox" bind:checked={values.randomizesStudyOrder} disabled={view.pending} />随机排列学习队列</label><label>当前词书<select value={values.selectedBookId??''} onchange={e=>{values.selectedBookId=e.currentTarget.value||null;}} disabled={view.pending}><option value="">首次可用词书</option>{#each books as book}<option value={book.id}>{book.name}</option>{/each}</select></label><button type="submit" disabled={view.pending}>{view.pending?'正在保存…':'保存学习设置'}</button></form>{#if view.error}<p role="alert">{view.error}</p>{/if}{#if view.saved}<p role="status">学习设置已保存。</p>{/if}</section>{/if}
 <section><h2>快捷键</h2><KeyboardHelp /></section>{#if bookError}<p role="alert">无法加载词书。<button onclick={reloadBooks}>重试</button></p>{/if}<section><ImportExport {books} onchanged={reloadBooks} /></section><section><BackupRestore onchanged={reloadBooks} /></section>
 <section><h2>关于 Kotoba</h2><p>Windows Client · 本地优先 · 数据保存在本机</p><p class="muted">客户端工程版本 0.1.0 · 功能对齐目标 macOS 0.2.1 Build 3</p><h3>词库与授权</h3><p><a href="https://github.com/5mdld/anki-jlpt-decks" target="_blank" rel="noreferrer">eggrolls / anki-jlpt-decks</a> · CC BY-NC 4.0</p><p><a href="https://www.edrdg.org/jmdict/j_jmdict.html" target="_blank" rel="noreferrer">EDRDG / JMdict</a> · CC BY-SA 4.0（外来语词源数据）</p></section>
</div>
<style>header{margin-bottom:20px;}header p{margin-top:5px;}.scroll{min-height:0;flex:1;overflow:auto;padding:4px;}section{padding:20px;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);margin-bottom:18px;}h2{font-size:17px;margin-bottom:14px;}h3{font-size:14px;margin:18px 0 8px;}form{display:flex;flex-direction:column;gap:12px;max-width:400px;}label{display:flex;justify-content:space-between;align-items:center;gap:10px;}input[type=number]{width:85px;}.check{justify-content:flex-start;}select{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:8px;max-width:210px;}form button{align-self:flex-start;}section>p{font-size:13px;margin-top:10px;overflow-wrap:anywhere;}a{color:var(--accent);}[role=alert]{color:var(--danger);}</style>
