import eslint from "@eslint/js";
import globals from "globals";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import jsxA11y from "eslint-plugin-jsx-a11y";
import prettier from "eslint-config-prettier";

// Flat config, scoped to the dashboard package. Stack per TECH-STACK: ESLint with
// typescript-eslint, React Hooks, and JSX accessibility rules. eslint-config-prettier
// is applied last so ESLint never fights Prettier over formatting.
export default tseslint.config(
  {
    ignores: [
      "dist/**",
      "coverage/**",
      "playwright-report/**",
      "test-results/**",
      "**/*.tsbuildinfo"
    ]
  },
  // Base JS + typed-syntax rules for every source file (no type-aware rules: those
  // require a full program build per lint run and are deferred until CI cost is known).
  {
    files: ["**/*.{ts,tsx,mjs}"],
    extends: [eslint.configs.recommended, tseslint.configs.recommended],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module"
    },
    rules: {
      // Allow intentionally-unused args/vars when prefixed with an underscore.
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" }
      ]
    }
  },
  // Browser-facing app and its unit tests: React Hooks + a11y rules, browser globals.
  {
    files: ["src/**/*.{ts,tsx}"],
    languageOptions: {
      globals: { ...globals.browser }
    },
    plugins: {
      "react-hooks": reactHooks,
      "jsx-a11y": jsxA11y
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      ...jsxA11y.configs.recommended.rules
    }
  },
  // Vitest unit-test globals (describe/it/expect/vi) live on the src test files.
  {
    files: ["src/**/*.test.{ts,tsx}", "src/test/**/*.{ts,tsx}"],
    languageOptions: {
      globals: { ...globals.node }
    }
  },
  // Node tooling: build config, scripts, and the Playwright specs/config.
  {
    files: ["*.{mjs,ts}", "scripts/**/*.{js,mjs}", "tests/**/*.ts", "playwright.config.ts"],
    languageOptions: {
      globals: { ...globals.node }
    }
  },
  prettier
);
