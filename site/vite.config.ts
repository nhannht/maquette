import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Custom domain at maquette.nhannht.io.vn - base is root.
export default defineConfig({
  base: "/",
  plugins: [react()],
  build: {
    target: "es2020",
    assetsInlineLimit: 0,
  },
});
