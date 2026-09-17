import { onBeforeUnmount, onMounted, ref, useTemplateRef, type Ref } from 'vue';
import { invoke, isTauri } from '@tauri-apps/api/core';

/** 菜单展开、收起和错误提示出现时，窗口高度跟随实际内容。 */
export const usePanelSize = (): { sizeError: Ref<string> } => {
  const panelElement = useTemplateRef<HTMLElement>('panelElement');
  const sizeError = ref('');
  let observer: ResizeObserver | undefined;
  let pendingHeight = 0;
  let appliedHeight = 0;
  let isApplying = false;
  let isDisposed = false;
  const applyHeight = async (): Promise<void> => {
    if (isApplying || isDisposed || pendingHeight === appliedHeight) { return; }
    isApplying = true;
    const height = pendingHeight;
    try {
      await invoke('resize_panel', { height });
      appliedHeight = height;
    } catch (cause) {
      sizeError.value = `调整面板失败：${String(cause)}`;
      appliedHeight = pendingHeight;
    } finally {
      isApplying = false;
      if (!isDisposed && pendingHeight !== appliedHeight) { void applyHeight(); }
    }
  };
  onMounted((): void => {
    if (!isTauri() || !panelElement.value) { return; }
    observer = new ResizeObserver((): void => {
      pendingHeight = Math.ceil(panelElement.value?.getBoundingClientRect().height ?? 0) + 1;
      void applyHeight();
    });
    observer.observe(panelElement.value);
  });
  onBeforeUnmount((): void => { isDisposed = true; observer?.disconnect(); });
  return { sizeError };
};
