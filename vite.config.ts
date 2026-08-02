import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

const CSP_DEV = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'", // unsafe-eval required for Vite HMR
  "style-src 'self' 'unsafe-inline'",
  "connect-src 'self' http://127.0.0.1:54321 http://localhost:54321 ws://127.0.0.1:54321 ws://localhost:54321 https://*.supabase.co wss://*.supabase.co https://accounts.google.com https://oauth2.googleapis.com",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join('; ')

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    // Remote workspace port previews need the dev server to listen outside
    // localhost, and their forwarded Host headers vary by environment.
    host: '0.0.0.0',
    allowedHosts: true,
    // Proxy the local Supabase stack on the dev server's own origin. In a remote
    // workspace the browser cannot reach the container's 127.0.0.1:54321, and a
    // same-origin proxy avoids forwarding a second port, relaxing the CSP, or
    // exposing an API endpoint publicly. Set VITE_SUPABASE_URL=/supabase to use it.
    proxy: {
      '/supabase': {
        target: 'http://127.0.0.1:54321',
        changeOrigin: true,
        ws: true,
        rewrite: (p) => p.replace(/^\/supabase/, ''),
      },
    },
    headers: {
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      'Content-Security-Policy': CSP_DEV,
    },
  },
  preview: {
    host: '0.0.0.0',
    allowedHosts: true,
    headers: {
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
      'Content-Security-Policy': CSP_DEV,
    },
  },
})
