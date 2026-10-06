<script lang="ts">
import { onDestroy, untrack } from 'svelte';
import { LatestRead, type ReadState } from '../vocabulary/state.ts';
import ReadStatus from '../components/ReadStatus.svelte';
import { productService } from './service.ts';
import type { ProductDetail, Statistics } from './types.ts';
let { bookId, revision }: {
    bookId: string;
    revision: number;
} = $props();
let example = $state<ReadState<ProductDetail | null>>({ status: 'loading', data: null });
let stats = $state<ReadState<Statistics>>({ status: 'loading', data: null });
const er = new LatestRead<ProductDetail | null>(v => { example = v; });
const sr = new LatestRead<Statistics>(v => { stats = v; });
function load() { void er.run(() => productService.randomExample(bookId)); void sr.run(() => productService.statistics(7)); }
$effect(() => { void bookId; void revision; untrack(load); });
onDestroy(() => { er.dispose(); sr.dispose(); });
function parts(text: string, word: string): {
    text: string;
    highlight: boolean;
}[] {
    if (!word || !text.includes(word))
        return [{ text, highlight: false }];
    const result: {
        text: string;
        highlight: boolean;
    }[] = [];
    const segments = text.split(word);
    for (let i = 0; i < segments.length; i++) {
        if (i)
            result.push({ text: word, highlight: true });
        if (segments[i])
            result.push({ text: segments[i], highlight: false });
    }
    return result;
}
</script>
<section><h2>今日概览</h2><ReadStatus status={stats.status} errorMessage="无法加载今日概览。" retry={()=>{void sr.run(()=>productService.statistics(7));}} />{#if stats.status==='ready'&&stats.data}<p>今日新词 {stats.data.todayNewWordCount} · 今日复习 {stats.data.todayReviewCount} · 连续学习 {stats.data.currentStreakDays} 天</p>{/if}</section>
<section><div class="heading"><h2>随机例句</h2><button onclick={()=>{void er.run(()=>productService.randomExample(bookId));}} disabled={example.status==='loading'}>换一句</button></div><ReadStatus status={example.status} empty={example.data===null} emptyMessage="此词书暂无完整双语例句。" errorMessage="无法加载例句。" retry={()=>{void er.run(()=>productService.randomExample(bookId));}} />{#if example.status==='ready'&&example.data}{@const word=example.data}<p lang="ja">{#each parts(word.exampleJapanese,word.expression) as part}{#if part.highlight}<mark>{part.text}</mark>{:else}{part.text}{/if}{/each}</p><p class="muted">{word.exampleChinese}</p><p class="muted" lang="ja">{word.expression} · {word.reading} · {word.romaji}</p>{/if}</section>
<style>section{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:18px;}h2{font-size:17px;}p{margin-top:10px;overflow-wrap:anywhere;}.heading{display:flex;justify-content:space-between;align-items:center;gap:12px;}mark{background:var(--surface-secondary);color:var(--accent);font-weight:650;}</style>
