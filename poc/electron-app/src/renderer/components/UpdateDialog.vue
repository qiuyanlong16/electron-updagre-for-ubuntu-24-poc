<template>
  <div v-if="visible" class="overlay" :class="{ frozen: force }">
    <div class="dialog">
      <template v-if="state === 'UPDATE_AVAILABLE'">
        <h2>发现新版本 {{ latestVersion }}</h2>
        <p>Ubuntu 正在后台准备更新，整个过程不需要输入密码。<br />更新完成后，Byclaw 会通知你重启应用。</p>
        <ul v-if="releaseNotes.length" class="notes"><li v-for="n in releaseNotes" :key="n">{{ n }}</li></ul>
        <div class="actions"><button @click="$emit('close')">知道了</button></div>
      </template>
      <template v-else-if="state === 'READY_OPTIONAL'">
        <h2>Byclaw {{ installedVersion }} 已经安装完成</h2>
        <p>重启应用后即可使用新版本。</p>
        <ul v-if="releaseNotes.length" class="notes"><li v-for="n in releaseNotes" :key="n">{{ n }}</li></ul>
        <div class="actions"><button @click="$emit('close')">稍后重启</button><button class="primary" @click="$emit('restart')">立即重启</button></div>
      </template>
      <template v-else-if="state === 'READY_FORCE'">
        <h2>必须更新 Byclaw</h2>
        <p>新版本已经安装完成，需要重启后继续使用。</p>
        <ul v-if="releaseNotes.length" class="notes"><li v-for="n in releaseNotes" :key="n">{{ n }}</li></ul>
        <div class="actions"><button class="primary" @click="$emit('restart')">立即重启</button></div>
      </template>
      <template v-else-if="state === 'RESTARTING'">
        <h2>正在重启…</h2>
      </template>
    </div>
  </div>
</template>
<script setup lang="ts">
import type { UpdateStateName } from '../../shared/types/update';
// spec §5.2 item 7: the popup shows the new version + upgrade type (optional/force, via the
// `force` prop / which template renders) + simple release notes. The §5.3 verbatim wording is
// preserved; the release-notes list is additive (rendered beneath it).
defineProps<{ visible: boolean; state: UpdateStateName; force: boolean; latestVersion: string; installedVersion: string; releaseNotes: string[] }>();
defineEmits<{ close: []; restart: [] }>();
</script>
<style scoped>
.overlay { position: fixed; inset: 0; background: rgba(0,0,0,.5); display: flex; align-items: center; justify-content: center; z-index: 9999; }
.dialog { background: #16213e; color: #e8e8f0; border-radius: 12px; padding: 32px; max-width: 440px; }
.actions { display: flex; gap: 12px; justify-content: flex-end; margin-top: 20px; }
button.primary { background: #00d4ff; color: #001020; font-weight: 700; }
.frozen { } /* force: no close on overlay/Esc (handled by no close button) */
.notes { margin: 12px 0 0; padding-left: 20px; color: #b8c4e0; font-size: .9em; }
</style>
