<script lang="ts">
 import {onDestroy} from 'svelte';
 import type {VocabularyWordDetail} from '../types/vocabulary.ts';
 import {LatestRead,type ReadState} from './state.ts';
 import {learningStatusLabel} from './presentation.ts';
 import {confirmedAction} from '../product/actions.ts';
 import {productService} from '../product/service.ts';
 import {studyService} from '../services/study.ts';
 import {timeText,type ProductDetail,type ProductBook} from '../product/types.ts';
 import ReadStatus from '../components/ReadStatus.svelte';
 import StudyDialog from '../study/StudyDialog.svelte';
 import WordHistory from '../product/WordHistory.svelte';
 import WordEditor from '../product/WordEditor.svelte';
 import ConjugationForms from '../product/ConjugationForms.svelte';
 let {state:incoming,close,retry,onchanged=()=>{}}:{state:ReadState<VocabularyWordDetail|null>;close:()=>void;retry:()=>void;onchanged?:()=>void}=$props();
 let detail=$state<ReadState<ProductDetail|null>>({status:'loading',data:null});let currentId='';let books=$state<ProductBook[]>([]);let editor=$state(false);let confirm=$state<'reset'|'delete'|null>(null);let pending=$state(false);let error=$state('');let revision=$state(0);let alive=true;
 const resource=new LatestRead<ProductDetail|null>(v=>{detail=v;});
 function refresh(){if(currentId)void resource.run(()=>productService.detail(currentId));}
 $effect(()=>{const id=incoming.data?.id;if(incoming.status==='ready'&&id&&id!==currentId){currentId=id;error='';confirm=null;refresh();void productService.books().then(v=>{if(alive)books=v;}).catch(()=>{});}});
 onDestroy(()=>{alive=false;resource.dispose();});
 async function favorite(){const word=detail.data;if(!word||pending)return;pending=true;error='';try{await studyService.favorite(word.id,word.isFavorite);if(alive){refresh();onchanged();}}catch{if(alive)error='收藏状态保存失败，请重新加载后重试。';}finally{pending=false;}}
 async function mutate(){const word=detail.data;if(!word||pending||!confirm)return;const operation=confirm;pending=true;error='';try{await confirmedAction(confirm!==null,()=>operation==='reset'?productService.resetWord(word.id,true):productService.deleteWord(word.id,true));if(alive){confirm=null;revision++;onchanged();if(operation==='delete')close();else refresh();}}catch{if(alive)error='操作未完成，原数据已保留，请重试。';}finally{pending=false;}}
</script>
<section class="detail-panel" aria-label="单词详情"><header><h2 id="detail-heading" tabindex="-1">单词详情</h2><button onclick={close} disabled={pending} aria-label="关闭单词详情">关闭 ×</button></header>
 <ReadStatus status={incoming.status==='ready'?detail.status:incoming.status} errorMessage="无法加载单词详情，请重试。" retry={()=>{retry();refresh();}} />
 {#if incoming.status==='ready'&&detail.status==='ready'}{#if detail.data}{@const word=detail.data}<div class="detail-content"><span class="badge">{word.bookName}</span><p class="muted">学习状态：{learningStatusLabel(word.learningStatus)}{word.isDifficult?' · 易错词（遗忘至少 2 次）':''}</p><h3 lang="ja">{word.expression}</h3><p class="reading" lang="ja">{word.reading}</p><p class="muted">{word.romaji}{#if word.pitch}<span class="pitch" aria-label={word.pitch.accessibilityText}>{word.pitch.displayText}</span>{/if}</p>
 <div class="actions"><button onclick={()=>{void favorite();}} disabled={pending}>{word.isFavorite?'★ 已收藏':'☆ 收藏'}</button><button onclick={()=>{editor=true;}} disabled={pending||!books.length}>编辑</button></div>
 <section class="block"><h4>中文释义</h4><p>{word.meaningChinese}</p>{#if word.partOfSpeech}<span class="badge">{word.partOfSpeech}</span>{/if}</section>
 {#if word.exampleJapanese||word.exampleChinese}<section class="block"><h4>例句</h4><p lang="ja">{word.exampleJapanese}</p><p class="muted translation">{word.exampleChinese}</p></section>{/if}
 {#if word.loanword}<section class="block"><h4>{word.loanword.isPartial?'部分词源':'外来语词源'}</h4><p>{word.loanword.sourceTerm}（{word.loanword.isWasei?word.loanword.languageName&&word.loanword.languageName!=='英语'?`和制${word.loanword.languageName}`:'和制英语':word.loanword.languageName??'词源'}{word.loanword.isPartial?' · 部分词源':''}）</p></section>{/if}
 {#if word.conjugation&&word.conjugation.forms.length>1}<section class="block"><h4>活用</h4><ConjugationForms value={word.conjugation} /></section>{/if}
 {#if word.tags.length}<section class="block"><h4>标签</h4><div class="tags">{#each word.tags as tag}<span>{tag}</span>{/each}</div></section>{/if}
 {#if word.progress}{@const p=word.progress}<section class="block"><h4>学习进度</h4><p>复习 {p.reviewCount} 次 · 遗忘 {p.lapseCount} 次</p>{#if p.lastReviewedAt}<p class="muted">上次学习：{timeText(p.lastReviewedAt)}</p>{/if}{#if ['learning','relearning','review'].includes(p.state)}<p class="muted">下次复习：{timeText(p.dueAt)}</p>{/if}</section>{/if}
 <div class="block"><WordHistory id={word.id} {revision} /></div>
 <div class="block actions"><button onclick={()=>{confirm='reset';}} disabled={pending||(word.learningStatus==='unlearned'&&!word.historyCount)}>重置为未学习</button><button onclick={()=>{confirm='delete';}} disabled={pending}>删除单词</button></div>{#if error}<p role="alert">{error}</p>{/if}
 </div><WordEditor open={editor} {books} {word} close={()=>{editor=false;}} saved={()=>{editor=false;refresh();onchanged();}} />{:else}<div class="missing" role="status">未找到该单词。<button onclick={close}>返回列表</button></div>{/if}{/if}
</section>
<StudyDialog open={confirm!==null} title={confirm==='delete'?'删除这个单词？':'重置为未学习？'} onclose={()=>{if(!pending)confirm=null;}}><p>{confirm==='delete'?'删除后，该词条及其学习进度和复习记录将被删除。':'此操作清空该词的学习进度与复习记录。词条内容和收藏状态会保留。'}</p>{#if error}<p role="alert">{error}</p>{/if}<div class="actions"><button onclick={()=>{confirm=null;}} disabled={pending}>取消</button><button onclick={()=>{void mutate();}} disabled={pending}>{pending?'正在处理…':'确认操作'}</button></div></StudyDialog>
<style>.detail-panel{min-width:0;min-height:0;height:100%;overflow:auto;border:1px solid var(--border);border-radius:var(--radius);background:var(--surface);}header{position:sticky;top:0;background:var(--surface);padding:16px 20px;border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;gap:12px;z-index:1;}header h2{font-size:15px;}header button{border:0;font-size:13px;}.detail-content{padding:22px;overflow-wrap:anywhere;}.badge{font-size:12px;color:var(--text-secondary);background:var(--surface-secondary);border-radius:5px;padding:3px 7px;display:inline-block;}h3{font-size:31px;margin:18px 0 5px;font-weight:600;line-height:1.3;}.reading{color:var(--text-secondary);font-size:17px;}.pitch{margin-left:12px;}.block{border-top:1px solid var(--border);padding-top:16px;margin-top:20px;}h4{margin:0 0 10px;font-size:12px;color:var(--text-secondary);font-weight:500;}.block p{font-size:15px;}.translation{margin-top:8px;}.tags,.actions{display:flex;flex-wrap:wrap;gap:7px;}.actions{margin-top:12px;}.tags span{background:var(--surface-secondary);padding:4px 8px;border-radius:5px;font-size:12px;}.missing{padding:30px;display:flex;flex-direction:column;gap:16px;}[role=alert]{color:var(--danger);margin-top:12px;}</style>
