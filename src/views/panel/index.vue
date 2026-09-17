<template>
  <main ref="panelElement" class="panel" aria-label="OneSwitch 快捷开关">
    <section class="setting-row" aria-labelledby="appearance-title">
      <span class="setting-row__icon" aria-hidden="true">☀️</span>
      <div class="setting-row__content"><h2 id="appearance-title">黑暗模式</h2><p v-if="isChanging">正在切换系统外观…</p></div>
      <ToggleSwitch :is-enabled="isDark" :is-disabled="isChanging || !isDesktop" label="系统黑暗模式" @toggle="toggleAppearance" />
    </section>
    <div class="separator" />
    <section class="setting-row setting-row--awake" aria-labelledby="awake-title">
      <span class="setting-row__icon" aria-hidden="true">☕️</span>
      <div class="setting-row__content"><h2 id="awake-title">保持亮屏</h2><p>{{ durationLabel }}<span v-if="status.enabled && status.expiresAt"> · {{ remaining }}</span></p></div>
      <button class="expand-button" :class="{ 'expand-button--open': isDurationOpen }" :aria-expanded="isDurationOpen"
        aria-controls="duration-menu" aria-label="选择亮屏时长" @click="isDurationOpen = !isDurationOpen">
        <svg viewBox="0 0 16 16" aria-hidden="true"><path :d="isDurationOpen ? 'M3 10l5-5 5 5z' : 'M3 6l5 5 5-5z'" /></svg>
      </button>
      <ToggleSwitch :is-enabled="status.enabled" :is-disabled="isBusy || !isReady" label="保持亮屏" @toggle="setAwake(!status.enabled)" />
    </section>
    <div v-if="isDurationOpen" id="duration-menu" class="duration-menu" role="group" aria-label="亮屏持续时间">
      <button v-for="option in DURATIONS" :key="option.label" class="duration-menu__item"
        :aria-pressed="duration === option.seconds" :disabled="isBusy || !isReady" @click="setDuration(option.seconds)">
        <span class="duration-menu__check" aria-hidden="true">{{ duration === option.seconds ? '✓' : '' }}</span>{{ option.label }}
      </button>
      <p class="duration-menu__note">{{ status.enabled ? '更改时长会从现在重新计时' : '开启后生效，退出应用时恢复' }}</p>
    </div>
    <div class="separator" />
    <section class="setting-row" aria-labelledby="activity-title">
      <span class="setting-row__icon" aria-hidden="true">🖱️</span>
      <div class="setting-row__content"><h2 id="activity-title">保持活跃</h2>
        <p>{{ activity.enabled ? '运行中 · 同时保持亮屏' : '闲置时模拟鼠标活动' }}</p>
        <button v-if="activityReady && !activity.permissionGranted" class="permission-button" :disabled="activityBusy" @click="requestPermission">授权辅助功能</button>
      </div>
      <ToggleSwitch :is-enabled="activity.enabled" :is-disabled="activityBusy || !activityReady" label="保持活跃" @toggle="toggleActivity" />
    </section>
    <div class="separator" />
    <section v-if="isSettingsOpen" class="settings" aria-label="应用设置">
      <div class="setting-row"><span class="setting-row__icon setting-row__icon--settings" aria-hidden="true">⚙</span>
        <div class="setting-row__content"><h2>登录时启动</h2><p>启动后亮屏、活跃默认关闭</p></div>
        <ToggleSwitch :is-enabled="isAutostart" :is-disabled="isBusy || !isReady" label="登录时启动" @toggle="toggleAutostart" />
      </div>
      <p class="settings__note">保持亮屏可防止闲置睡眠，合盖和手动睡眠仍遵循系统行为。保持活跃在闲置 45 秒后发送原位置鼠标事件，包含亮屏效果；关闭保持亮屏不会停止保持活跃。不会解锁电脑，企微在线状态需实际验证。黑暗模式会更改整个 Mac 的外观。</p>
      <div class="separator" />
    </section>
    <p v-if="visibleError" class="error-message" role="alert">{{ visibleError }}</p>
    <footer class="toolbar">
      <button class="toolbar__settings" :aria-expanded="isSettingsOpen" @click="isSettingsOpen = !isSettingsOpen">{{ isSettingsOpen ? '收起设置' : '设置' }}</button>
      <button class="toolbar__icon" title="退出 OneSwitch" aria-label="退出应用" @click="quitApp">
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2v10M7 5a9 9 0 1 0 10 0"/></svg>
      </button>
    </footer>
  </main>
</template>
<script setup lang="ts">
import { computed, ref } from 'vue';
import { isTauri } from '@tauri-apps/api/core';
import { DURATIONS } from './constants';
import ToggleSwitch from './components/ToggleSwitch.vue';
import { useActivity } from './composables/useActivity';
import { useAwake } from './composables/useAwake';
import { useAppearance } from './composables/useAppearance';
import { usePanelSize } from './composables/usePanelSize';
const { status, duration, isBusy, isReady, isAutostart, error, remaining,
  setAwake, setDuration, toggleAutostart, quitApp } = useAwake();
const { isDark, isChanging, appearanceError, toggleAppearance } = useAppearance();
const { activity, activityBusy, activityReady, activityError, toggleActivity, requestPermission } = useActivity();
const { sizeError } = usePanelSize();
const isDesktop = isTauri();
const isDurationOpen = ref(true);
const isSettingsOpen = ref(false);
const durationLabel = computed((): string => DURATIONS.find((item) => item.seconds === duration.value)?.label ?? '永久');
const visibleError = computed((): string => appearanceError.value || activityError.value || error.value || sizeError.value);
</script>
<style scoped>
.permission-button { border: 0; padding: 3px 0; background: transparent; color: #087fff; font-size: 11px; }
.panel { padding: 4px 16px 6px 10px; }
.setting-row { display: flex; align-items: center; gap: 12px; min-height: 64px; padding: 2px 6px 2px 0; }
.setting-row--awake { min-height: 70px; }
.setting-row__icon { display: grid; place-items: center; flex: 0 0 28px; font-size: 25px; line-height: 1; }
.setting-row__icon--settings { color: var(--secondary); }
.setting-row__content { flex: 1; min-width: 0; }
.setting-row h2 { margin: 0; font-size: 16px; font-weight: 550; line-height: 1.5; }
.setting-row p { margin: 0; color: var(--secondary); font-size: 12px; font-weight: 500; line-height: 1.4; font-variant-numeric: tabular-nums; }
.separator { height: 1px; margin-left: 30px; background: var(--separator); }
.expand-button { display: grid; place-items: center; flex-shrink: 0; width: 19px; height: 19px; padding: 3px; border: 0; border-radius: 5px; background: var(--button-bg); color: var(--secondary); }
.expand-button--open { background: #087fff; color: #fff; }
.expand-button svg { width: 100%; height: 100%; fill: currentColor; }
.duration-menu { padding: 0 0 8px 20px; }
.duration-menu::before { display: block; height: 1px; margin: 0 0 1px 17px; background: var(--separator); content: ''; }
.duration-menu__item { display: flex; align-items: center; width: 100%; min-height: 32px; padding: 3px 6px; border: 0; border-radius: 5px; background: transparent; color: var(--foreground); text-align: left; font-size: 15px; }
.duration-menu__check { display: inline-block; width: 25px; color: var(--secondary); font-size: 20px; font-weight: 600; }
.duration-menu__item:hover:not(:disabled) { background: var(--hover); }
.duration-menu__item:disabled { opacity: .5; }
.duration-menu__note { margin: 6px 0 0 25px; padding-top: 8px; border-top: 1px solid var(--separator); color: var(--secondary); font-size: 10px; }
.settings__note { margin: 0 4px 12px 40px; color: var(--secondary); font-size: 11px; line-height: 1.6; }
.error-message { margin: 10px 5px 4px 40px; color: var(--error); font-size: 11px; line-height: 1.6; overflow-wrap: anywhere; }
.toolbar { display: flex; align-items: center; justify-content: space-between; gap: 20px; min-height: 57px; padding: 0 6px 0 30px; }
.toolbar__icon { display: grid; place-items: center; width: 28px; height: 30px; padding: 1px; border: 0; background: none; color: var(--secondary); }
.toolbar__icon svg { width: 24px; height: 24px; stroke: currentColor; stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; fill: none; }
.toolbar__settings { flex: 1; height: 30px; margin: 0; padding: 0 10px; border: 0; border-radius: 11px; background: var(--button-bg); color: var(--foreground); font-size: 14px; }
button { font-family: inherit; cursor: pointer; }
button:disabled { cursor: wait; }
button:focus-visible { outline: 2px solid #087fff; outline-offset: 2px; }
</style>
