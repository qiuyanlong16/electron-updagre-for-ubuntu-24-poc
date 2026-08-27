import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import electron from 'vite-plugin-electron';
import renderer from 'vite-plugin-electron-renderer';

export default defineConfig({
  // Renderer source is its own Vite project root so its index.html builds flat to
  // dist/renderer/index.html (matching main.ts's path.join(__dirname, 'renderer/index.html')).
  // Without this, Vite picks up the stale root-level index.html (pre-Vue3 "Nanobot" prototype)
  // as the default entry and/or nests the output under dist/renderer/src/renderer/.
  root: 'src/renderer',
  plugins: [
    vue(),
    electron([
      // Main + preload build into the flat dist/ dir (so __dirname-relative preload.js resolves).
      // Per-entry root: '.' overrides the inherited 'src/renderer' root so the lib entries
      // (src/main/main.ts, src/preload/preload.ts) resolve from the project root, not src/renderer.
      { entry: 'src/main/main.ts', vite: { root: '.', build: { outDir: 'dist', rollupOptions: { output: { entryFileNames: 'main.js', format: 'cjs' } } } } },
      { entry: 'src/preload/preload.ts', vite: { root: '.', build: { outDir: 'dist', rollupOptions: { output: { entryFileNames: 'preload.js', format: 'cjs' } } } } },
    ]),
    renderer(),
  ],
  // Relative to root (src/renderer) -> resolves to <project>/dist/renderer.
  build: { outDir: '../../dist/renderer', emptyOutDir: true },
});
