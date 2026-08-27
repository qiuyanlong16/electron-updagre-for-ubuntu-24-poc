// @vitest-environment happy-dom
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h } from 'vue';
import { useUpdateState } from '../src/renderer/composables/useUpdateState';
import type { UpdateState } from '../src/shared/types/update';

// Non-null UpdateState so restart()'s `if (!state.value) return` guard does not short-circuit.
const fakeState: UpdateState = {
  state: 'READY_OPTIONAL',
  runningVersion: '1.0.0',
  installedVersion: '1.0.0',
  latestVersion: '1.0.0',
  mode: 'optional',
  releaseNotes: [],
  stateSource: 'update-state.json',
};

describe('restart() dedup (spec §18.1 case 10: 重复点击立即重启 -> 去重，仅 relaunch 一次)', () => {
  let restartApplication: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    // Mock the full ByclawAPI surface on the existing (happy-dom) window — do NOT replace
    // window itself (mount needs document). onUpdateStateChanged returns an unsubscribe fn.
    restartApplication = vi.fn(async () => {});
    (window as unknown as { byclawAPI: unknown }).byclawAPI = {
      getCurrentVersion: vi.fn(async () => '1.0.0'),
      checkForUpdates: vi.fn(async () => fakeState),
      getUpdateState: vi.fn(async () => fakeState),
      restartApplication,
      onUpdateStateChanged: vi.fn(() => () => {}),
    };
  });

  afterEach(() => {
    delete (window as unknown as { byclawAPI?: unknown }).byclawAPI;
  });

  it('calling restart() twice relaunches exactly once', async () => {
    // useUpdateState() uses onMounted/onUnmounted, so it needs a component lifecycle.
    let api!: ReturnType<typeof useUpdateState>;
    const Comp = defineComponent({
      setup() {
        api = useUpdateState();
        return {};
      },
      render: () => h('div'),
    });
    const wrapper = mount(Comp);
    await flushPromises(); // let onMounted (getUpdateState + subscribe) settle

    api.state.value = { ...fakeState }; // ensure non-null state
    await api.restart();
    await api.restart();

    expect(restartApplication).toHaveBeenCalledTimes(1);

    wrapper.unmount();
  });
});
