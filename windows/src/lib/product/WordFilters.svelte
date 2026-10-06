<script lang="ts">
import type { Filters, ProductBook } from "./types.ts";
let { value, books, options, onchange }: {
    value: Filters;
    books: ProductBook[];
    options: {
        partsOfSpeech: string[];
        tags: string[];
    };
    onchange: (value: Filters) => void;
} = $props();
const statuses = [['all', '全部'], ['new', '未学习'], ['review', '复习中'], ['mastered', '已熟练'], ['favorite', '收藏'], ['difficult', '易错词']] as const;
const sorts = [['defaultOrder', '默认'], ['recentlyStudied', '最近学习'], ['nextDue', '下次复习'], ['lapseCount', '遗忘次数']] as const;
function change(key: keyof Filters, event: Event) { const field = event.target as HTMLSelectElement | HTMLInputElement; onchange({ ...value, [key]: key === 'favoritesOnly' ? (field as HTMLInputElement).checked : field.value || null }); }
</script>
<div class="filters">
 <label>学习状态<select value={value.status} onchange={e=>change('status',e)}>{#each statuses as [id,label]}<option value={id}>{label}</option>{/each}</select></label>
 <label>排序<select value={value.sort} onchange={e=>change('sort',e)}>{#each sorts as [id,label]}<option value={id}>{label}</option>{/each}</select></label>
 <label>词书<select value={value.bookId??''} onchange={e=>change('bookId',e)}><option value="">全部词书</option>{#each books as book}<option value={book.id}>{book.name}</option>{/each}</select></label>
 <details><summary>更多筛选{value.jlpt||value.partOfSpeech||value.tag||value.favoritesOnly?' · 已启用':''}</summary><div class="extra"><label>等级<select value={value.jlpt??''} onchange={e=>change('jlpt',e)}><option value="">全部等级</option>{#each ['N5','N4','N3','N2','N1'] as level}<option value={level}>{level}</option>{/each}</select></label><label>词性<select value={value.partOfSpeech??''} onchange={e=>change('partOfSpeech',e)}><option value="">全部词性</option>{#each options.partsOfSpeech as pos}<option value={pos}>{pos}</option>{/each}</select></label><label>标签<select value={value.tag??''} onchange={e=>change('tag',e)}><option value="">全部标签</option>{#each options.tags as tag}<option value={tag}>{tag}</option>{/each}</select></label><label class="check"><input type="checkbox" checked={value.favoritesOnly} onchange={e=>change('favoritesOnly',e)} />仅收藏</label></div></details>
</div>
<style>.filters{display:flex;flex-wrap:wrap;align-items:end;gap:10px;margin-bottom:12px;flex-shrink:0;}.filters label{display:flex;flex-direction:column;gap:3px;font-size:12px;color:var(--text-secondary);min-width:100px;max-width:180px;}select{width:100%;padding:6px;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;font:inherit;}.extra{display:flex;flex-wrap:wrap;gap:8px;padding:8px 0;}summary{cursor:pointer;padding:6px;}.filters .check{flex-direction:row;align-items:center;}.filters details[open]{flex-basis:100%;}</style>
