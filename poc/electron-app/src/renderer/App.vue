<template>
  <div class="app" :class="{ frozen: force }">
    <header><h1>Byclaw</h1></header>
    <main>
      <VersionButton :current-version="runningVersion" :checking="checking" :state-name="stateName" @check="check" />
      <p v-if="upgradedBanner" class="banner">Byclaw 已更新到 {{ runningVersion }}</p>
    </main>
    <UpdateDialog
      :visible="dialogVisible"
      :state="stateName"
      :force="force"
      :latest-version="latestVersion"
      :installed-version="installedVersion"
      @close="onClose"
      @restart="restart" />
  </div>
</template>
<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import VersionButton from './components/VersionButton.vue';
import UpdateDialog from './components/UpdateDialog.vue';
import { useUpdateState } from './composables/useUpdateState';
import type { UpdateStateName } from '../shared/types/update';

const { state, checking, check, restart } = useUpdateState();
const runningVersion = computed(() => state.value?.runningVersion ?? '');
const stateName = computed<UpdateStateName>(() => state.value?.state ?? 'CHECKING');
const latestVersion = computed(() => state.value?.latestVersion ?? '');
const installedVersion = computed(() => state.value?.installedVersion ?? '');
const force = computed(() => stateName.value === 'READY_FORCE');

// States that show the modal dialog. READY_FORCE has no close button (force cannot be dismissed).
const VISIBLE_STATES: UpdateStateName[] = ['UPDATE_AVAILABLE', 'READY_OPTIONAL', 'READY_FORCE', 'RESTARTING'];
// "稍后重启"/"知道了" sets dismissed=true so the dialog hides without the 5s tick re-showing it.
// Reset when stateName transitions to a different value (e.g. UPDATE_AVAILABLE -> READY_OPTIONAL).
const dismissed = ref(false);
watch(stateName, () => { dismissed.value = false; });
const dialogVisible = computed(() => VISIBLE_STATES.includes(stateName.value) && !dismissed.value);

// First-run-after-upgrade banner (spec §11): main attaches upgradedFrom (the prior version) to
// every pushed state when getVersion() > lastSeenVersion; banner shows "已更新到 <runningVersion>".
const upgradedBanner = computed(() => !!state.value?.upgradedFrom);

function onClose() { dismissed.value = true; }
</script>
<style scoped>
.app { min-height: 100vh; background: linear-gradient(135deg, #1a1a2e, #16213e); color: #e8e8f0; }
.frozen main { pointer-events: none; opacity: .45; filter: grayscale(.4); }
.banner { color: #00d4ff; }
</style>
