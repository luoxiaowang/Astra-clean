import { computed, onBeforeUnmount, onMounted, ref, type ComputedRef, type Ref } from 'vue';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { disable, enable, isEnabled } from '@tauri-apps/plugin-autostart';
import type { AwakeStatus } from '../types';

interface AwakeControls {
  status: Ref<AwakeStatus>;
  duration: Ref<number | null>;
  isBusy: Ref<boolean>;
  isReady: Ref<boolean>;
  isAutostart: Ref<boolean>;
  error: Ref<string>;
  remaining: ComputedRef<string>;
  setAwake: (enabled: boolean) => Promise<void>;
  setDuration: (seconds: number | null) => Promise<void>;
  toggleAutostart: () => Promise<void>;
  hidePanel: () => Promise<void>;
  quitApp: () => Promise<void>;
}

/** Rust 是实际状态来源；读取请求过期时丢弃，避免覆盖刚完成的开关操作。 */
export const useAwake = (): AwakeControls => {
  const status = ref<AwakeStatus>({ enabled: false, expiresAt: null, durationSeconds: null, error: null });
  const duration = ref<number | null>(null);
  const isBusy = ref(false);
  const isReady = ref(false);
  const isAutostart = ref(false);
  const error = ref('');
  const now = ref(Date.now());
  let revision = 0;
  let isReading = false;
  let isDisposed = false;
  let timer: ReturnType<typeof setInterval> | undefined;

  const remaining = computed((): string => {
    if (!status.value.enabled) { return '跟随系统设置'; }
    if (status.value.expiresAt === null) { return '直到手动关闭'; }
    const seconds = Math.max(0, status.value.expiresAt - Math.floor(now.value / 1000));
    if (seconds === 0) { return '正在恢复系统设置…'; }
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return [hours, minutes, seconds % 60].map((value) => String(value).padStart(2, '0')).join(':');
  });

  const readStatus = async (): Promise<void> => {
    if (isBusy.value || isReading || isDisposed) { return; }
    isReading = true;
    const requestRevision = revision;
    try {
      const value = await invoke<AwakeStatus>('get_status');
      if (requestRevision !== revision || isDisposed) { return; }
      status.value = value;
      if (value.enabled) { duration.value = value.durationSeconds; }
      isReady.value = true;
      if (value.error) { error.value = value.error; }
    } catch (cause) {
      if (requestRevision === revision && !isDisposed) {
        isReady.value = false;
        error.value = String(cause);
      }
    } finally { isReading = false; }
  };

  const perform = async (action: () => Promise<void>): Promise<void> => {
    if (isBusy.value || !isReady.value) { return; }
    revision += 1;
    isBusy.value = true;
    error.value = '';
    try { await action(); }
    catch (cause) { error.value = String(cause); }
    finally { isBusy.value = false; }
  };

  const setAwake = async (enabled: boolean): Promise<void> => {
    await perform(async (): Promise<void> => {
      status.value = await invoke<AwakeStatus>('set_awake', { enabled, durationSeconds: duration.value });
      now.value = Date.now();
    });
  };

  const setDuration = async (seconds: number | null): Promise<void> => {
    if (isBusy.value || !isReady.value) { return; }
    if (!status.value.enabled) { duration.value = seconds; return; }
    await perform(async (): Promise<void> => {
      status.value = await invoke<AwakeStatus>('set_awake', { enabled: true, durationSeconds: seconds });
      duration.value = seconds;
      now.value = Date.now();
    });
  };

  const toggleAutostart = async (): Promise<void> => {
    await perform(async (): Promise<void> => {
      if (isAutostart.value) { await disable(); }
      else { await enable(); }
      isAutostart.value = await isEnabled();
    });
  };

  const hidePanel = async (): Promise<void> => { await perform(async (): Promise<void> => { await invoke('hide_panel'); }); };
  const quitApp = async (): Promise<void> => {
    // 即使状态读取失败，仍允许退出应用。
    try { await invoke('quit_app'); } catch (cause) { error.value = String(cause); }
  };
  const handleFocus = (): void => { void readStatus(); };
  const handleKey = (event: KeyboardEvent): void => { if (event.key === 'Escape') { void hidePanel(); } };

  onMounted(async (): Promise<void> => {
    if (!isTauri()) { error.value = '当前为浏览器预览。请使用桌面应用控制常亮。'; return; }
    await readStatus();
    try { isAutostart.value = await isEnabled(); } catch (cause) { error.value = String(cause); }
    if (isDisposed) { return; }
    window.addEventListener('focus', handleFocus);
    window.addEventListener('keydown', handleKey);
    timer = setInterval((): void => {
      now.value = Date.now();
      if (document.visibilityState === 'visible') { void readStatus(); }
    }, 1000);
  });
  onBeforeUnmount((): void => {
    isDisposed = true;
    if (timer) { clearInterval(timer); }
    window.removeEventListener('focus', handleFocus);
    window.removeEventListener('keydown', handleKey);
  });
  return { status, duration, isBusy, isReady, isAutostart, error, remaining,
    setAwake, setDuration, toggleAutostart, hidePanel, quitApp };
};
