import {test} from "node:test";
import assert from "node:assert/strict";
import {LatestRead,WordBrowser,rangeLabel} from "../src/lib/vocabulary/state.ts";
function deferred() {let resolve;let reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
function page(offset=0,total=120) {return {items:[],offset,total,limit:50};}
function clock() {const pending=new Map();let next=0;const scheduler={schedule:(work,delay)=>{assert.equal(delay,250);pending.set(++next,work);return next;},cancel:handle=>{pending.delete(handle);}};return {scheduler,flush:()=>{const work=[...pending.values()];pending.clear();work.forEach(fn=>fn());},size:()=>pending.size};}
const settle=()=>new Promise(resolve=>queueMicrotask(resolve));
test("old search cannot overwrite newer query, even during debounce",async()=>{
 const c=clock();const calls=[];let state={status:"loading",data:null};
 const browser=new WordBrowser(null,(query)=>{const wait=deferred();calls.push({query,wait});return wait.promise;},v=>{state=v;},c.scheduler);
 browser.search("高校");c.flush();browser.search(" 高中 ");calls[0].wait.resolve(page(0,2));await settle();assert.equal(state.status,"loading");assert.equal(state.data,null);
 c.flush();calls[1].wait.resolve(page(0,4));await settle();assert.equal(state.data?.total,4);assert.equal(calls[1].query,"高中");browser.dispose();
});
test("debounce coalesces typing, clearing uses browse contract, disposes pending work",async()=>{
 const c=clock();const calls=[];const browser=new WordBrowser(null,async query=>{calls.push(query);return page();},()=>{},c.scheduler);
 browser.search("a");browser.search("ab");browser.search("abc");assert.equal(c.size(),1);c.flush();await settle();assert.deepEqual(calls,["abc"]);
 browser.search("");c.flush();await settle();assert.deepEqual(calls,["abc",""]);browser.search("late");browser.dispose();c.flush();assert.equal(calls.length,2);
});
test("pagination transitions keep book, reset on query, never escape user text",async()=>{
 const c=clock();const calls=[];const browser=new WordBrowser("book",async(query,book,offset)=>{calls.push({query,book,offset});return page(offset);},()=>{},c.scheduler);
 await browser.refresh();await browser.page(50);browser.search("%_\\' OR 1=1 --");c.flush();await settle();
 assert.deepEqual(calls.map(v=>v.offset),[0,50,0]);assert.equal(calls[2].query,"%_\\' OR 1=1 --");assert.equal(calls[2].book,"book");assert.equal(browser.pageSize,50);
});
test("loading, empty and safe error states clear stale data; retry succeeds",async()=>{
 let state={status:"loading",data:null};const resource=new LatestRead(v=>{state=v;});
 await resource.run(async()=>page(0,0));assert.equal(state.status,"ready");assert.equal(state.data?.total,0);
 const wait=deferred();const run=resource.run(()=>wait.promise);assert.equal(state.status,"loading");assert.equal(state.data,null);wait.reject(new Error("SQLite secret path"));await run;assert.equal(state.status,"error");assert.equal(state.data,null);
 await resource.run(async()=>page());assert.equal(state.status,"ready");assert.equal("error" in state,false);
});
test("detail open switches safely, close invalidates pending result, missing is ready null",async()=>{
 let state={status:"loading",data:null};const resource=new LatestRead(v=>{state=v;});const a=deferred();const b=deferred();
 const first=resource.run(()=>a.promise);const second=resource.run(()=>b.promise);b.resolve("second");await second;a.resolve("first");await first;assert.equal(state.data,"second");
 const closed=deferred();const last=resource.run(()=>closed.promise);resource.dispose();closed.resolve("closed");await last;assert.equal(state.data,null);await resource.run(async()=>null);assert.equal(state.status,"ready");assert.equal(state.data,null);
});
test("page range handles empty and final page",()=>{assert.equal(rangeLabel(page(0,0)),"0 / 0");assert.equal(rangeLabel({...page(800,802),items:[{},{}]}),"801–802 / 802");});

import {learningStatusLabel} from "../src/lib/vocabulary/presentation.ts";
test("read-only learning status labels use the presentation DTO",()=>{
 assert.equal(learningStatusLabel("unlearned"),"未学习");
 assert.equal(learningStatusLabel("reviewing"),"复习中");
 assert.equal(learningStatusLabel("mastered"),"已熟练");
});
