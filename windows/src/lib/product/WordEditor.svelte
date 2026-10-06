<script lang="ts">
import StudyDialog from '../study/StudyDialog.svelte';
import ConjugationForms from "./ConjugationForms.svelte";
import { onDestroy } from "svelte";
import { LatestRead, type ReadState } from "../vocabulary/state.ts";
import type { ProductBook, ProductDetail, WordEdit, EditorPreview } from './types.ts';
import { productService } from './service.ts';
let { open, books, preferredBook = null, word = null, close, saved }: {
    open: boolean;
    books: ProductBook[];
    preferredBook?: string | null;
    word?: ProductDetail | null;
    close: () => void;
    saved: () => void;
} = $props();
let fields = $state<WordEdit>({ id: null, bookId: '', expression: '', reading: '', meaningChinese: '', partOfSpeech: '', jlptLevel: '', exampleJapanese: '', exampleChinese: '', tags: [], isFavorite: false });
let tags = $state('');
let pending = $state(false);
let error = $state('');
let previousOpen = false;
$effect(() => {
    if (open && !previousOpen) {
        fields = { id: word?.id ?? null, bookId: word?.bookId ?? preferredBook ?? books[0]?.id ?? '', expression: word?.expression ?? '', reading: word?.reading ?? '', meaningChinese: word?.meaningChinese ?? '', partOfSpeech: word?.partOfSpeech ?? '', jlptLevel: word?.jlptLevel ?? '', exampleJapanese: word?.exampleJapanese ?? '', exampleChinese: word?.exampleChinese ?? '', tags: word?.editingTags ?? [], isFavorite: word?.isFavorite ?? false };
        tags = fields.tags.join(';');
        error = '';
    }
    previousOpen = open;
});
let preview = $state<ReadState<EditorPreview>>({ status: "loading", data: null });
const previewRead = new LatestRead<EditorPreview>(value => { preview = value; });
$effect(() => {
    const expression = fields.expression, reading = fields.reading, pos = fields.partOfSpeech;
    if (!open)
        return;
    previewRead.pending();
    const timer = setTimeout(() => { void previewRead.run(() => productService.editorPreview(expression, reading, pos)); }, 200);
    return () => clearTimeout(timer);
});
onDestroy(() => previewRead.dispose());
async function save() {
    if (pending)
        return;
    pending = true;
    error = '';
    try {
        await productService.editWord({ ...fields, tags: tags.split(';') });
        saved();
    }
    catch {
        error = '保存未完成。请检查必需字段和同词书重复词条后重试。';
    }
    finally {
        pending = false;
    }
}
</script>
<StudyDialog {open} title={word?'编辑单词':'新增单词'} onclose={()=>{if(!pending)close();}}><form onsubmit={e=>{e.preventDefault();void save();}}>
 <label>词书<select bind:value={fields.bookId} disabled={!!word||pending} required>{#each books as book}<option value={book.id}>{book.name}</option>{/each}</select></label>
 <label>日语单词<input lang="ja" bind:value={fields.expression} required disabled={pending} /></label><label>假名读音<input lang="ja" bind:value={fields.reading} required disabled={pending} /></label><label>中文释义<textarea bind:value={fields.meaningChinese} required disabled={pending}></textarea></label>
 <label>词性<input bind:value={fields.partOfSpeech} placeholder="名词 / 一段动词" disabled={pending} /></label><p class="muted">词性可用 / 分隔。活用仅使用明确词性与本地规则。</p>
 <label>JLPT 等级<select bind:value={fields.jlptLevel} disabled={pending}><option value="">未指定</option>{#each ['N5','N4','N3','N2','N1'] as level}<option value={level}>{level}</option>{/each}</select></label><label>日语例句<textarea lang="ja" bind:value={fields.exampleJapanese} disabled={pending}></textarea></label><label>中文例句<textarea bind:value={fields.exampleChinese} disabled={pending}></textarea></label><label>标签<input bind:value={tags} placeholder="用分号分隔" disabled={pending} /></label>
 <label><input type="checkbox" bind:checked={fields.isFavorite} disabled={pending} />收藏</label>
 <section aria-label="即时预览"><h3>即时预览</h3>{#if preview.status==="ready"&&preview.data}{#if preview.data.conjugation&&preview.data.conjugation.forms.length}<ConjugationForms value={preview.data.conjugation} />{/if}{#each preview.data.warnings as warning}<p class="muted">{warning}</p>{/each}{:else if preview.status==="error"}<p>暂时无法生成预览。</p>{:else}<p class="muted">正在生成预览…</p>{/if}</section>
 {#if error}<p role="alert">{error}</p>{/if}<div class="actions"><button type="button" onclick={close} disabled={pending}>取消</button><button type="submit" disabled={pending}>{pending?'正在保存…':'保存单词'}</button></div>
 </form></StudyDialog>
<style>form{display:flex;flex-direction:column;gap:10px;min-width:min(400px,calc(100vw - 105px));}label{display:flex;flex-direction:column;gap:4px;}select,textarea{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:8px;max-width:100%;}textarea{resize:vertical;min-height:55px;}.actions{display:flex;justify-content:flex-end;gap:10px;margin-top:12px;}[role=alert]{color:var(--danger);}</style>
