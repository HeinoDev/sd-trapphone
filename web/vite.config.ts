import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';

// Build the handset into web/build with relative asset paths so the FiveM NUI
// (nui://sd-trapphone/web/build/index.html) resolves them. Filenames are unhashed to match
// the lean fxmanifest files{} globs. The NUI browser is Chromium 103.
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  base: './',
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    // `--mode demo` is the browser demo for the website: same page, its own folder, so it
    // never lands in the build the game serves.
    outDir: mode === 'demo' ? 'build-demo' : 'build',
    emptyOutDir: true,
    assetsDir: 'assets',
    target: 'chrome103',
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      },
    },
  },
}));
