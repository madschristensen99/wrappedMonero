import adapter from "@sveltejs/adapter-auto";
// svelte.config.js
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/kit').Config} */
const config = {
    kit: {
        adapter: adapter(),
    },
    preprocess: [vitePreprocess()],
};

export default config;
