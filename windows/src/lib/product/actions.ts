import type { AppSettings, FileKind, ImportTarget, Preview, FileSummary } from './types.ts';
export interface FileService {
    pickImport: (kind: FileKind, target: ImportTarget | null) => Promise<Preview | null>;
    confirmImport: (token: string, duplicates: 'skip' | 'update' | null, restore: 'merge' | 'skipExisting' | 'overwrite' | null) => Promise<FileSummary>;
    cancelImport: () => Promise<void>;
    exportFile: (kind: FileKind, book: string | null) => Promise<string | null>;
}
export interface FileState {
    pending: boolean;
    preview: Preview | null;
    summary: FileSummary | null;
    exported: string | null;
    error: string | null;
}
export class FileActions {
    state: FileState = { pending: false, preview: null, summary: null, exported: null, error: null };
    private changed: (state: FileState) => void;
    private service: FileService;
    private alive = true;
    constructor(service: FileService, changed: (state: FileState) => void) { this.service = service; this.changed = changed; }
    private emit() {
        if (this.alive)
            this.changed({ ...this.state });
    }
    private async run(work: () => Promise<void>) {
        if (this.state.pending)
            return;
        this.state.pending = true;
        this.state.error = null;
        this.emit();
        try {
            await work();
        }
        catch {
            this.state.error = '文件操作未完成，原数据已保留，请检查文件格式或重试。';
        }
        finally {
            this.state.pending = false;
            this.emit();
        }
    }
    pick(kind: FileKind, target: ImportTarget | null) { return this.run(async () => { this.state.preview = null; this.state.summary = null; this.state.exported = null; this.state.preview = await this.service.pickImport(kind, target); }); }
    confirm(approved: boolean, duplicates: 'skip' | 'update', restore: 'merge' | 'skipExisting' | 'overwrite') {
        if (!approved || !this.state.preview)
            return Promise.resolve();
        const preview = this.state.preview;
        return this.run(async () => { this.state.summary = await this.service.confirmImport(preview.token, preview.kind === 'csv' ? duplicates : null, preview.kind === 'backup' ? restore : null); this.state.preview = null; });
    }
    cancel() { return this.run(async () => { await this.service.cancelImport(); this.state.preview = null; }); }
    export(kind: FileKind, book: string | null) { return this.run(async () => { this.state.exported = null; this.state.summary = null; this.state.exported = await this.service.exportFile(kind, book); }); }
    dispose() { this.alive = false; }
}
export interface SettingsState {
    loading: boolean;
    pending: boolean;
    value: AppSettings | null;
    error: string | null;
    saved: boolean;
}
export class SettingsController {
    state: SettingsState = { loading: true, pending: false, value: null, error: null, saved: false };
    private generation = 0;
    private service: {
        settings: () => Promise<AppSettings>;
        saveSettings: (value: AppSettings) => Promise<AppSettings>;
    };
    private changed: (state: SettingsState) => void;
    constructor(service: SettingsController['service'], changed: SettingsController['changed']) { this.service = service; this.changed = changed; }
    private emit() { this.changed({ ...this.state, value: this.state.value ? { ...this.state.value } : null }); }
    async load() {
        const gen = ++this.generation;
        this.state.loading = true;
        this.state.error = null;
        this.emit();
        try {
            const value = await this.service.settings();
            if (gen === this.generation)
                this.state.value = value;
        }
        catch {
            if (gen === this.generation)
                this.state.error = '无法加载设置，原文件已保留。';
        }
        finally {
            if (gen === this.generation) {
                this.state.loading = false;
                this.emit();
            }
        }
    }
    async save(value: AppSettings) {
        if (this.state.loading || this.state.pending)
            return;
        const gen = this.generation;
        this.state.pending = true;
        this.state.saved = false;
        this.state.error = null;
        this.emit();
        try {
            const saved = await this.service.saveSettings(value);
            if (gen === this.generation) {
                this.state.value = saved;
                this.state.saved = true;
            }
        }
        catch {
            if (gen === this.generation)
                this.state.error = '设置保存失败，原设置已保留。';
        }
        finally {
            if (gen === this.generation) {
                this.state.pending = false;
                this.emit();
            }
        }
    }
    dispose() { this.generation++; }
}
export async function confirmedAction(approved: boolean, work: () => Promise<void>): Promise<boolean> {
    if (!approved)
        return false;
    await work();
    return true;
}
