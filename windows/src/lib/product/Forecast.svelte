<script lang="ts">
import { onDestroy, untrack } from 'svelte';
import { LatestRead, type ReadState } from '../vocabulary/state.ts';
import ReadStatus from '../components/ReadStatus.svelte';
import { productService } from './service.ts';
import { dateText, type ForecastDay } from './types.ts';
let { bookId = null, revision = 0 }: {
    bookId?: string | null;
    revision?: number;
} = $props();
let view = $state<ReadState<ForecastDay[]>>({ status: 'loading', data: null });
const read = new LatestRead<ForecastDay[]>(v => { view = v; });
const load = () => read.run(() => productService.forecast(bookId));
$effect(() => { void bookId; void revision; untrack(() => { void load(); }); });
onDestroy(() => read.dispose());
const maximum = $derived(Math.max(1, ...(view.data ?? []).map(d => d.count)));
</script>
<section class="forecast" aria-label="未来七天复习预报"><h2>未来 7 天</h2><p class="muted">按本地日期计算；逾期单词计入今天。</p><ReadStatus status={view.status} errorMessage="无法读取复习预报，请重试。" retry={()=>{void load();}} />
 {#if view.status==='ready'&&view.data}<ol>{#each view.data as day,index}<li><span class="value">{day.count}</span><div class="track" aria-hidden="true"><span style:height={`${day.count/maximum*100}%`}></span></div><time datetime={new Date(day.day/1000).toISOString()}>{index===0?'今天':dateText(day.day)}</time></li>{/each}</ol>{#if view.data.every(d=>d.count===0)}<p class="muted" role="status">未来 7 天暂无待复习单词。</p>{/if}{/if}
</section>
<style>.forecast{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:18px;}.forecast h2{font-size:17px;}.forecast>p{font-size:12px;margin-top:6px;}ol{list-style:none;padding:0;display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:8px;margin:18px 0 10px;}li{display:flex;flex-direction:column;gap:5px;align-items:center;font-size:12px;}.track{height:72px;width:100%;max-width:38px;background:var(--surface-secondary);border-radius:5px;display:flex;align-items:end;}.track span{background:var(--accent);width:100%;border-radius:5px;min-height:0;}.value{font-weight:650;}time{white-space:nowrap;font-size:11px;}</style>
