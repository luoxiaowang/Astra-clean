import { onBeforeUnmount, onMounted, ref } from 'vue';
import { invoke, isTauri } from '@tauri-apps/api/core';

interface ActivityStatus {
  enabled: boolean;
  permissionGranted: boolean;
  error: string | null;
}

/** 后台 Rust 定时器负责活动；面板关闭后仍持续运行。 */
export const useActivity = () => {
  const activity = ref<ActivityStatus>({ enabled: false, permissionGranted: false, error: null });
  const activityBusy = ref(false);
  const activityReady = ref(false);
  const activityError = ref('');
  let disposed = false;
  let reading = false;
  let revision = 0;
  let timer: ReturnType<typeof setInterval> | undefined;

  const read = async (): Promise<void> => {
    if (disposed || reading || activityBusy.value) { return; }
    reading = true;
    const version = revision;
    try {
      const value = await invoke<ActivityStatus>('get_activity_status');
      if (disposed || version !== revision) { return; }
      activity.value = value;
      activityReady.value = true;
      activityError.value = value.error ?? '';
    } catch (error) {
      if (!disposed && version === revision) {
        activityReady.value = false;
        activityError.value = String(error);
      }
    } finally { reading = false; }
  };
  const toggleActivity = async (): Promise<void> => {
    if (!activityReady.value || activityBusy.value) { return; }
    revision += 1;
    activityBusy.value = true;
    try {
      activity.value = await invoke<ActivityStatus>('set_activity', { enabled: !activity.value.enabled });
      activityError.value = activity.value.error ?? '';
    } catch (error) { activityError.value = String(error); }
    finally { activityBusy.value = false; }
  };
  const requestPermission = async (): Promise<void> => {
    if (activityBusy.value) { return; }
    revision += 1;
    activityBusy.value = true;
    try {
      await invoke<boolean>('request_activity_permission');
      activityError.value = '在系统设置 → 隐私与安全性 → 辅助功能中允许 OneSwitch，然后返回开启保持活跃。';
    } catch (error) { activityError.value = String(error); }
    finally { activityBusy.value = false; }
  };
  onMounted((): void => {
    if (!isTauri()) { return; }
    void read();
    window.addEventListener('focus', read);
    timer = setInterval((): void => { void read(); }, 1000);
  });
  onBeforeUnmount((): void => {
    disposed = true;
    if (timer) { clearInterval(timer); }
    window.removeEventListener('focus', read);
  });
  return { activity, activityBusy, activityReady, activityError, toggleActivity, requestPermission };
};
