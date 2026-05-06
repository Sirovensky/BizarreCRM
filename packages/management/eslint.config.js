import js from '@eslint/js';
import globals from 'globals';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'coverage/**',
      'src/renderer/dist/**',
      'src/renderer/src/assets/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        ...globals.es2022,
      },
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    plugins: {
      'jsx-a11y': jsxA11y,
      react,
      'react-hooks': reactHooks,
    },
    settings: {
      react: {
        version: 'detect',
      },
    },
    rules: {
      ...react.configs.flat.recommended.rules,
      ...react.configs.flat['jsx-runtime'].rules,
      ...jsxA11y.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
      'jsx-a11y/click-events-have-key-events': 'warn',
      'jsx-a11y/label-has-associated-control': 'warn',
      'jsx-a11y/no-autofocus': 'warn',
      'jsx-a11y/no-noninteractive-element-interactions': 'warn',
      'jsx-a11y/no-static-element-interactions': 'warn',
      'no-control-regex': 'off',
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-undef': 'off',
      'no-useless-escape': 'off',
      'react-hooks/exhaustive-deps': 'warn',
      'react-hooks/rules-of-hooks': 'error',
      'react/no-unescaped-entities': 'off',
      'react/prop-types': 'off',
    },
  },
  {
    files: ['src/main/**/*.ts', 'src/preload/**/*.ts'],
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
  },
  {
    files: ['src/renderer/**/*.{ts,tsx}'],
    languageOptions: {
      globals: {
        ...globals.browser,
      },
    },
  },
  {
    files: ['src/preload/**/*.ts'],
    rules: {
      '@typescript-eslint/no-require-imports': 'off',
    },
  },
  {
    files: ['src/renderer/src/components/shared/ConfirmDialog.tsx'],
    rules: {
      'react-hooks/rules-of-hooks': 'off',
    },
  },
);
