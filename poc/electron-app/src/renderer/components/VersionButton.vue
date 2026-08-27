<template>
  <button class="version-btn" :disabled="checking" @click="check">
    <span class="ver">版本 v{{ currentVersion }}</span>
    <span class="hint">{{ hint }}</span>
  </button>
</template>
<script setup lang="ts">
import { computed } from 'vue';
const props = defineProps<{ currentVersion: string; checking: boolean; stateName: string }>();
const emit = defineEmits<{ check: [] }>();
const check = () => emit('check');
const hint = computed(() => {
  if (props.checking) return '正在检查更新';
  if (props.stateName === 'LATEST') return '当前已是最新版本';
  return '点击检查更新';
});
</script>
