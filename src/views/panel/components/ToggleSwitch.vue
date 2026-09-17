<template>
  <button class="toggle" :class="{ 'toggle--enabled': isEnabled }" role="switch"
    :aria-checked="isEnabled" :aria-label="label" :disabled="isDisabled" @click="$emit('toggle')">
    <span class="toggle__thumb"><span /></span>
  </button>
</template>
<script setup lang="ts">
defineProps<{ isEnabled: boolean; isDisabled?: boolean; label: string }>();
defineEmits<{ toggle: [] }>();
</script>
<style scoped>
.toggle { display: inline-flex; align-items: center; flex-shrink: 0; width: 50px; height: 25px; padding: 4px; border: 0; border-radius: 20px; background: var(--switch-track); cursor: pointer; transition: background .16s; }
.toggle__thumb { display: grid; place-items: center; width: 17px; height: 17px; border-radius: 50%; background: #fafafa; transition: transform .16s; }
.toggle__thumb > span { width: 9px; height: 9px; border-radius: 50%; background: var(--switch-track); }
.toggle--enabled { background: #087fff; }
.toggle--enabled .toggle__thumb { transform: translateX(25px); }
.toggle--enabled .toggle__thumb > span { background: #087fff; }
.toggle:disabled { cursor: wait; opacity: .5; }
.toggle:focus-visible { outline: 2px solid #087fff; outline-offset: 3px; }
@media (prefers-reduced-motion: reduce) { .toggle, .toggle__thumb { transition: none; } }
</style>
