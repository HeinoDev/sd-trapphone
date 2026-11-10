/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  // The handset is hand-written CSS driven by custom properties (shell and wallpaper themes).
  // Preflight is off so Tailwind's reset never touches it; Tailwind only supplies utilities.
  corePlugins: { preflight: false },
  theme: {
    extend: {
      fontFamily: {
        lcd: ['"Pixelify Sans"', 'system-ui', 'sans-serif'],
        brand: ['Michroma', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
