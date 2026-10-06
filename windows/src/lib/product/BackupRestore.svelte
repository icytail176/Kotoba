<script lang="ts">
import { onDestroy } from 'svelte';
import StudyDialog from '../study/StudyDialog.svelte';
import { productService } from './service.ts';
import { FileActions, type FileState } from './actions.ts';
let { onchanged = () => { } }: {
    onchanged?: () => void;
} = $props();
let policy = $state<'merge' | 'skipExisting' | 'overwrite'>('merge');
let view = $state<FileState>({ pending: false, preview: null, summary: null, exported: null, error: null });
const action = new FileActions(productService, v => { view = v; });
onDestroy(() => action.dispose());
async function confirm() {
    await action.confirm(true, 'skip', policy);
    if (action.state.summary)
        onchanged();
}
</script>
<section><h2>Windows 本地备份</h2><p class="muted">保存词书、词条、学习进度和复习记录。此格式用于 Windows 客户端，不能恢复 Mac Backup V3 文件。</p><div class="actions"><button onclick={()=>{void action.export('backup',null);}} disabled={view.pending}>导出本地备份…</button><button onclick={()=>{void action.pick('backup',null);}} disabled={view.pending}>选择备份恢复…</button></div>{#if view.pending}<p role="status">正在处理备份…</p>{/if}{#if view.error}<p role="alert">{view.error}</p>{/if}{#if view.exported}<p role="status">已导出：{view.exported}</p>{/if}{#if view.summary?.backup}{@const s=view.summary.backup}<p role="status">恢复完成：新增 {s.inserted} · 更新 {s.updated} · 跳过 {s.skipped} 条记录</p>{/if}</section>
<StudyDialog open={view.preview!==null} title="确认恢复本地备份" onclose={()=>{if(!view.pending)void action.cancel();}}>{#if view.preview}{@const p=view.preview}<p>{p.fileName}</p><p>{p.books} 本词书 · {p.words} 个词条 · {p.progress} 条学习进度 · {p.logs} 条复习记录</p><label>恢复方式<select bind:value={policy} disabled={view.pending}><option value="merge">合并：只更新较新的词条与进度</option><option value="skipExisting">跳过已存在的记录</option><option value="overwrite">覆盖备份中的同身份记录</option></select></label><p class="muted">恢复不会清空整个数据库。内置词将通过 canonical ID 对应到本机词条，保留本机 ID。覆盖模式会替换备份中同身份的词条、学习进度和复习记录，请确认已保存当前备份。</p>{#if view.error}<p role="alert">{view.error}</p>{/if}<div class="actions"><button onclick={()=>{void action.cancel();}} disabled={view.pending}>取消</button><button onclick={()=>{void confirm();}} disabled={view.pending}>{view.pending?'正在恢复…':'确认恢复'}</button></div>{/if}</StudyDialog>
<style>section{display:flex;flex-direction:column;gap:12px;}h2{font-size:17px;}p{font-size:13px;overflow-wrap:anywhere;}.actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:12px;}label{display:flex;flex-direction:column;gap:5px;margin:14px 0;}select{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:8px;max-width:100%;}[role=alert]{color:var(--danger);}</style>
