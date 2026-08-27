import { ref, onMounted, onUnmounted } from 'vue';
import type { UpdateState } from '../../shared/types/update';

export interface ByclawAPI {
  getCurrentVersion: () => Promise<string>;
  checkForUpdates: () => Promise<UpdateState>;
  getUpdateState: () => Promise<UpdateState>;
  restartApplication: () => Promise<void>;
  onUpdateStateChanged: (cb: (s: UpdateState) => void) => () => void;
}

declare global {
  interface Window { byclawAPI: ByclawAPI }
}

export function useUpdateState() {
  const state = ref<UpdateState | null>(null);
  const checking = ref(false);
  let unsub: (() => void) | null = null;

  onMounted(async () => {
    const api = window.byclawAPI;
    state.value = await api.getUpdateState();
    unsub = api.onUpdateStateChanged((s: UpdateState) => { state.value = s; });
  });
  onUnmounted(() => { unsub?.(); });

  async function check() {
    if (checking.value) return; // dedup (spec §18.1 case 9)
    checking.value = true;
    try { state.value = await window.byclawAPI.checkForUpdates(); }
    finally { checking.value = false; }
  }

  async function restart() {
    state.value = { ...(state.value as UpdateState), state: 'RESTARTING' } as UpdateState;
    await window.byclawAPI.restartApplication(); // dedup handled by UI disable (spec §18.1 case 10)
  }

  return { state, checking, check, restart };
}
