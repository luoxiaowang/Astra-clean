import { onBeforeUnmount, onMounted, ref, type Ref } from 'vue';
import { invoke, isTauri } from '@tauri-apps/api/core';

interface AppearanceControls {
  isDark: Ref<boolean>;
  isChanging: Ref<boolean>;
  appearanceError: Ref<string>;
  toggleAppearance: () => Promise<void>;
}

/** 读取 WebKit 跟随系统的外观；写入则通过 Rust 切换 macOS 全局外观。 */
export const useAppearance = (): AppearanceControls => {
  const isDark = ref(false);
  const isChanging = ref(false);
  const appearanceError = ref('');
  let media: MediaQueryList | undefined;
  const syncAppearance = (): void => { isDark.value = media?.matches ?? false; };
  const toggleAppearance = async (): Promise<void> => {
    if (isChanging.value || !isTauri()) { return; }
    isChanging.value = true;
    appearanceError.value = '';
    try { isDark.value = await invoke<boolean>('set_dark_mode', { enabled: !isDark.value }); }
    catch (cause) { appearanceError.value = String(cause); syncAppearance(); }
    finally { isChanging.value = false; }
  };
  onMounted((): void => {
    media = window.matchMedia('(prefers-color-scheme: dark)');
    syncAppearance();
    media.addEventListener('change', syncAppearance);
    window.addEventListener('focus', syncAppearance);
  });
  onBeforeUnmount((): void => {
    media?.removeEventListener('change', syncAppearance);
    window.removeEventListener('focus', syncAppearance);
  });
  return { isDark, isChanging, appearanceError, toggleAppearance };
};
