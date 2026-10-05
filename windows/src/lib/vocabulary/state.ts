import type { PagedResult } from "../types/vocabulary";
export type ReadState<T> = { status: "loading" | "ready" | "error"; data: T | null };
/** Sequence is invalidated before debounce, so old responses never flash as current. */
export class LatestRead<T> {
  private sequence = 0;
  private publish: (state: ReadState<T>) => void;
  constructor(publish: (state: ReadState<T>) => void) { this.publish = publish; }
  pending() { this.sequence++; this.publish({ status: "loading", data: null }); }
  async run(load: () => Promise<T>) {
    const current = ++this.sequence;
    this.publish({ status: "loading", data: null });
    try { const data = await load(); if (current === this.sequence) this.publish({ status: "ready", data }); }
    catch { if (current === this.sequence) this.publish({ status: "error", data: null }); }
  }
  dispose() { this.sequence++; }
}
export interface Scheduler { schedule: (work: () => void, delay: number) => unknown; cancel: (handle: unknown) => void }
const timers: Scheduler = { schedule: (work, delay) => setTimeout(work, delay), cancel: handle => clearTimeout(handle as ReturnType<typeof setTimeout>) };
export class WordBrowser {
  readonly pageSize = 50;
  offset = 0;
  query = "";
  private timer: unknown;
  private read: LatestRead<PagedResult>;
  private book: string | null;
  private load: (query: string, book: string | null, offset: number) => Promise<PagedResult>;
  private scheduler: Scheduler;
  constructor(book: string | null, load: (query: string, book: string | null, offset: number) => Promise<PagedResult>, publish: (state: ReadState<PagedResult>) => void, scheduler: Scheduler = timers) { this.book = book; this.load = load; this.scheduler = scheduler; this.read = new LatestRead(publish); }
  refresh() { this.cancel(); const {query,book,offset} = this; return this.read.run(() => this.load(query,book,offset)); }
  search(value: string) {
    this.cancel(); this.query = Array.from(value.trim()).slice(0,200).join(""); this.offset = 0;
    this.read.pending(); this.timer = this.scheduler.schedule(() => { this.timer = undefined; void this.refresh(); },250);
  }
  page(offset: number) { this.offset = Math.max(0,offset); return this.refresh(); }
  private cancel() { if (this.timer !== undefined) this.scheduler.cancel(this.timer); this.timer = undefined; }
  dispose() { this.cancel(); this.read.dispose(); }
}
export const rangeLabel = (page: PagedResult) => page.total === 0 ? "0 / 0" : `${Math.min(page.offset + 1,page.total)}–${Math.min(page.offset + page.items.length,page.total)} / ${page.total.toLocaleString("zh-CN")}`;
