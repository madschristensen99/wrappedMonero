import adapter from "@sveltejs/adapter-static";
// svelte.config.js
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/kit').Config} */
const config = {
    kit: {
        adapter: adapter({ fallback: "200.html" }),
    },
    preprocess: [vitePreprocess()],
};

export default config;
