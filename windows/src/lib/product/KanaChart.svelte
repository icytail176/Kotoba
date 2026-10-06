<script lang="ts">
import { kanaGroups, kanaMove, type KanaGroup } from './kana.ts';
import { isSafeReferenceKey } from '../study/keyboard.ts';
let script = $state<'hiragana' | 'katakana'>('hiragana');
let focused = $state([0, 0, 0]);
function move(event: KeyboardEvent, group: KanaGroup, index: number, g: number) {
    if (!isSafeReferenceKey(event) || !event.key.startsWith('Arrow'))
        return;
    event.preventDefault();
    const next = kanaMove(group, index, event.key);
    focused[g] = next;
    document.getElementById(`kana-${g}-${next}`)?.focus();
}
</script>
<header><h1 tabindex="-1">五十音图</h1><p class="muted">清音、浊音、半浊音与拗音。方向键可在表格中移动。</p><label>字形<select bind:value={script}><option value="hiragana">平假名</option><option value="katakana">片假名</option></select></label></header>
<div class="scroll">{#each kanaGroups as group,g}<section aria-label={group.title}><h2>{group.title}</h2><table><thead><tr><th>行</th>{#each group.columns===5?['あ段','い段','う段','え段','お段']:['ゃ段','ゅ段','ょ段'] as label}<th scope="col">{label}</th>{/each}</tr></thead><tbody>{#each group.rows as row,r}<tr><th scope="row">{row.label}</th>{#each row.entries as entry,c}<td>{#if entry}<button id={`kana-${g}-${r*group.columns+c}`} tabindex={focused[g]===r*group.columns+c?0:-1} onfocus={()=>{focused[g]=r*group.columns+c;}} onkeydown={event=>move(event,group,r*group.columns+c,g)} aria-label={`${entry[script]}，${entry.romaji}${entry.historical?'，历史假名，现代日语通常不使用':''}`} title={entry.historical?'历史假名，现代日语通常不使用':entry.romaji}><strong lang="ja">{entry[script]}</strong><small>{entry.romaji}{entry.historical?' *':''}</small></button>{:else}<span aria-label="无对应假名">—</span>{/if}</td>{/each}</tr>{/each}</tbody></table></section>{/each}<p class="muted">* ゐ / ヰ 与 ゑ / ヱ 为历史假名，现代日语通常不使用。</p></div>
<style>header p{font-size:13px;margin-top:5px;}label{display:flex;align-items:center;gap:10px;margin:14px 0;}select{font:inherit;color:var(--text-primary);background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:7px;}.scroll{min-height:0;flex:1;overflow:auto;padding:4px;}section{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:16px;margin-bottom:18px;}h2{font-size:17px;margin-bottom:12px;}table{width:100%;table-layout:fixed;border-collapse:collapse;text-align:center;}th{font-size:11px;color:var(--text-secondary);font-weight:500;}th:first-child{width:50px;}td{padding:3px;}td button{width:100%;display:flex;flex-direction:column;align-items:center;gap:1px;padding:5px 2px;border:0;background:var(--surface-secondary);min-height:56px;}strong{font-size:23px;font-weight:500;}small{font-size:11px;color:var(--text-secondary);}.scroll>p{font-size:12px;padding-bottom:16px;}@media(max-width:800px){section{padding:10px;}th:first-child{width:34px;}td{padding:2px;}strong{font-size:20px;}}</style>
