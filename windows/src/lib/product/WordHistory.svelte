<script lang="ts">
import { onDestroy, untrack } from 'svelte';
import { LatestRead, type ReadState } from '../vocabulary/state.ts';
import { productService } from './service.ts';
import { timeText, type HistoryPage } from './types.ts';
import ReadStatus from '../components/ReadStatus.svelte';
let { id, revision = 0 }: {
    id: string;
    revision?: number;
} = $props();
let view = $state<ReadState<HistoryPage>>({ status: 'loading', data: null });
let offset = $state(0);
const read = new LatestRead<HistoryPage>(value => { view = value; });
const load = () => read.run(() => productService.history(id, offset));
$effect(() => { void id; void revision; untrack(() => { offset = 0; void load(); }); });
onDestroy(() => read.dispose());
</script>
<section aria-label="复习历史"><h4>复习历史</h4><ReadStatus status={view.status} empty={view.data?.items.length===0} emptyMessage="尚无正式复习记录" errorMessage="无法读取复习历史，请重试。" retry={()=>{void load();}} />
 {#if view.status==='ready'&&view.data}{#each view.data.items as item (item.log.id)}<article><time datetime={new Date(item.log.reviewedAt/1000).toISOString()}>{timeText(item.log.reviewedAt)}</time><p>{item.ratingLabel} · {item.transition}</p>{#if item.log.questionDirectionRawValue&&item.log.nextState!=='suspended'}<details><summary>拼写记录</summary><p>假名错误 {item.log.readingWrongCount} 次 · 表记错误 {item.log.spellingWrongCount} 次</p>{#if item.log.typedAnswer}<p lang="ja">输入：{item.log.typedAnswer}</p>{/if}{#if item.log.expectedAnswer}<p lang="ja">答案：{item.log.expectedAnswer}</p>{/if}</details>{/if}</article>{/each}{#if view.data.total>10}<div class="pages"><button disabled={offset===0} onclick={()=>{offset=Math.max(0,offset-10);void load();}}>更近记录</button><span>{offset+1}–{Math.min(offset+10,view.data.total)} / {view.data.total}</span><button disabled={offset+10>=view.data.total} onclick={()=>{offset+=10;void load();}}>更早记录</button></div>{/if}{/if}
</section>
<style>h4{font-size:12px;color:var(--text-secondary);margin:0 0 10px;}article{padding:10px 0;border-bottom:1px solid var(--border);overflow-wrap:anywhere;}time{color:var(--text-secondary);font-size:12px;}details{font-size:12px;margin-top:5px;}summary{cursor:pointer;}.pages{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:12px;font-size:12px;}.pages button{padding:5px;}</style>
