<script lang="ts">
import { onDestroy } from 'svelte';
import StudyDialog from '../study/StudyDialog.svelte';
import { productService } from './service.ts';
import { FileActions, type FileState } from './actions.ts';
import type { ProductBook } from './types.ts';
let { books, onchanged = () => { } }: {
    books: ProductBook[];
    onchanged?: () => void;
} = $props();
let selected = $state('');
let newName = $state('');
let newBook = $state(false);
let qualityPending = $state(false);
let qualityMessage = $state("");
let duplicates = $state<'skip' | 'update'>('skip');
let view = $state<FileState>({ pending: false, preview: null, summary: null, exported: null, error: null });
const action = new FileActions(productService, v => { view = v; });
$effect(() => {
    if (!selected && books.length)
        selected = books[0].id;
});
onDestroy(() => action.dispose());
async function exportQuality() {
    if (qualityPending || !view.preview)
        return;
    qualityPending = true;
    qualityMessage = "";
    try {
        const name = await productService.exportQuality(view.preview.token);
        if (name)
            qualityMessage = `已导出：${name}`;
    }
    catch {
        qualityMessage = "质量报告导出失败，请重试。";
    }
    finally {
        qualityPending = false;
    }
}
async function confirm() {
    await action.confirm(true, duplicates, 'merge');
    if (action.state.summary)
        onchanged();
}
</script>
<section class="file-section"><h2>CSV 导入与导出</h2><p class="muted">UTF-8 词库文件。CSV 包含词条内容，不包含学习进度。</p><label>现有词书<select bind:value={selected} disabled={view.pending}><option value="">请选择词书</option>{#each books as book}<option value={book.id}>{book.name}</option>{/each}</select></label><label class="check"><input type="checkbox" bind:checked={newBook} disabled={view.pending} />导入到新词书</label>{#if newBook}<label>新词书名称<input bind:value={newName} disabled={view.pending} /></label>{/if}
 <div class="actions"><button onclick={()=>{void action.pick('csv',newBook?{bookId:null,newBookName:newName}:{bookId:selected,newBookName:null});}} disabled={view.pending||(newBook?!newName.trim():!selected)}>选择 CSV 导入…</button><button onclick={()=>{void action.export('csv',selected);}} disabled={view.pending||!selected}>导出当前词书…</button></div>
 {#if view.pending}<p role="status">正在处理文件…</p>{/if}{#if view.error}<p role="alert">{view.error}</p>{/if}{#if view.exported}<p role="status">已导出：{view.exported}</p>{/if}{#if view.summary?.csv}{@const summary=view.summary.csv}<p role="status">导入 {summary.imported} · 更新 {summary.updated} · 跳过 {summary.skipped} · 无效行 {summary.errors}</p>{/if}
</section>
<StudyDialog open={view.preview!==null} title="确认 CSV 导入" onclose={()=>{if(!view.pending)void action.cancel();}}>{#if view.preview}{@const preview=view.preview}<p>{preview.fileName}</p><p>有效行 {preview.validRows} · 重复词 {preview.duplicateRows} · 无效行 {preview.errorCount}</p><p class="muted">确认后只导入有效行，无效行将被跳过。更新重复词只更新 CSV 中提供的词条字段，保留收藏、词源、canonical 身份和学习记录。</p><label>重复词处理<select bind:value={duplicates} disabled={view.pending}><option value="skip">跳过现有单词</option><option value="update">更新词条内容</option></select></label>{#if preview.quality}<details><summary>质量报告：严重错误 {preview.quality.criticalCount} · 警告 {preview.quality.warningCount} · 提示 {preview.quality.infoCount}</summary><ul>{#each preview.quality.issues as issue}<li>第 {issue.lineNumber} 行 · {issue.severity==='critical'?'严重错误':issue.severity==='warning'?'警告':'提示'}：{issue.reason}</li>{/each}</ul><p>最多显示 100 条；可导出完整报告。</p></details><button onclick={()=>{void exportQuality();}} disabled={view.pending||qualityPending}>导出质量报告…</button>{#if qualityMessage}<p role="status">{qualityMessage}</p>{/if}{/if}
 {#if preview.errorCount}<details open><summary>无效行（最多显示 100 条）</summary><ul>{#each preview.errors as error}<li>第 {error.row} 行：{error.reason}</li>{/each}</ul></details>{/if}{#if preview.sample.length}<details><summary>预览前 {preview.sample.length} 行</summary><ul>{#each preview.sample as row}<li><span lang="ja">{row.expression}（{row.reading}）</span> · {row.meaningChinese}</li>{/each}</ul></details>{/if}
 {#if view.error}<p role="alert">{view.error}</p>{/if}<div class="actions"><button onclick={()=>{void action.cancel();}} disabled={view.pending}>取消</button><button onclick={()=>{void confirm();}} disabled={view.pending||qualityPending||!preview.validRows}>{view.pending?'正在导入…':'确认导入有效行'}</button></div>{/if}</StudyDialog>
<style>.file-section{display:flex;flex-direction:column;gap:12px;}h2{font-size:17px;}p{font-size:13px;}label{display:flex;flex-direction:column;gap:4px;max-width:400px;}select{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:8px;}.check{flex-direction:row;align-items:center;gap:8px;}.actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:10px;}li{overflow-wrap:anywhere;margin-bottom:5px;}[role=alert]{color:var(--danger);}summary{cursor:pointer;margin-top:12px;}</style>
