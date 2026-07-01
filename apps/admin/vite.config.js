import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
// console 服务把 SPA 挂在 /console/ 前缀下（StaticDir=./consoleweb，见 services/console）。
// 因此 base 设为 /console/，构建产物拷进 consoleweb 后即可被直接托管。
export default defineConfig({
    base: '/console/',
    plugins: [react()],
    resolve: {
        alias: {
            '@': fileURLToPath(new URL('./src', import.meta.url)),
        },
    },
    server: {
        port: 5180,
        proxy: {
            // 开发期把 /console/api 代理到本地 console 服务（:8080）
            '/console/api': {
                target: 'http://127.0.0.1:8080',
                changeOrigin: true,
            },
        },
    },
    build: {
        outDir: 'dist',
        chunkSizeWarningLimit: 1500,
    },
});
