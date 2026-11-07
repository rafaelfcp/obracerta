import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// base relativa: o mesmo build funciona em https://<usuario>.github.io/<repo>/ ou na raiz de um domínio.
// As rotas usam HashRouter (#/etapas), então o GitHub Pages não precisa de reescrita de URL.
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/icon.svg', 'icons/icon-192.png'],
      manifest: {
        name: 'ObraCerta',
        short_name: 'ObraCerta',
        description: 'Controle da obra da Casa Villagio Tunis',
        lang: 'pt-BR',
        start_url: './',
        scope: './',
        display: 'standalone',
        background_color: '#f6f4ef',
        theme_color: '#1f3a2e',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // dados do Supabase nunca vão para o cache do service worker: sempre buscados na hora
        navigateFallbackDenylist: [/^\/rest\//, /^\/auth\//],
        runtimeCaching: [],
      },
    }),
  ],
})
