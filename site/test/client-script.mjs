// Runs one of the site's browser scripts in plain Node so a test can drive it with fakes:
// the TypeScript (or the <script> of an .astro component) is transpiled with the site's own
// typescript package, every import is swapped for a stub the test supplies, and the code
// runs as a function body whose free variables are the test's `globals`. Dynamic imports go
// through `globals.__import(specifier)`, so a test decides when a lazy chunk arrives or fails.
import { readFileSync } from 'node:fs';
import ts from 'typescript';

/**
 * @param {string} path  file under site/src, e.g. 'components/search/loader.ts'
 * @param {{ imports?: Record<string, object>, globals?: Record<string, unknown> }} [env]
 * @returns {any} the script's default export, else an object of its named exports
 */
export function runClientScript(path, { imports = {}, globals = {} } = {}) {
  let source = readFileSync(new URL(`../src/${path}`, import.meta.url), 'utf8');
  if (path.endsWith('.astro')) source = source.match(/<script>([\s\S]*?)<\/script>/)[1];
  const { outputText } = ts.transpileModule(source, {
    fileName: path.replace(/\.astro$/, '.ts'),
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, jsx: ts.JsxEmit.ReactJSX },
  });

  let defaultName = null;
  const named = [];
  const body = outputText
    .replace(/^export (const|let|function|async function) (\w+)/gm, (_, kind, name) => (named.push(name), `${kind} ${name}`))
    .replace(/^import\s*\{([^}]*)\}\s*from\s*['"]([^'"]+)['"];?$/gm, (_, names, spec) => {
      if (!(spec in imports)) throw new Error(`${path} imports ${spec}: pass a stub in imports`);
      return `const {${names.replace(/\s+as\s+/g, ': ')}} = __imports[${JSON.stringify(spec)}];`;
    })
    .replace(/^import\s*['"]([^'"]+)['"];?$/gm, '')
    .replace(/\bimport\((['"])([^'"]+)\1\)/g, (_, _q, spec) => `__import(${JSON.stringify(spec)})`)
    .replace(/^export default function (\w+)/m, (_, name) => ((defaultName = name), `function ${name}`))
    .replace(/^export default (\w+);$/m, (_, name) => ((defaultName = name), ''))
    .replace(/^export \{\};$/m, '');
  if (/^\s*(import|export)\b/m.test(body)) throw new Error(`${path}: an import or export the harness does not handle`);

  const names = Object.keys(globals);
  // the default export when there is one, else the named exports as an object
  const result = defaultName ?? (named.length ? `{ ${named.join(', ')} }` : 'undefined');
  const run = new Function('__imports', ...names, `'use strict';\n${body}\nreturn ${result};`);
  return run(imports, ...names.map((n) => globals[n]));
}

/** An event target with DOM listener rules: one entry per (listener, capture), removal is idempotent. */
export function fakeTarget(extra = {}) {
  const listeners = [];
  const capture = (options) => (typeof options === 'boolean' ? options : Boolean(options?.capture));
  return Object.assign(
    {
      listeners,
      addEventListener(type, fn, options) {
        const c = capture(options);
        if (!listeners.some((l) => l.type === type && l.fn === fn && l.capture === c)) listeners.push({ type, fn, capture: c });
      },
      removeEventListener(type, fn, options) {
        const c = capture(options);
        const i = listeners.findIndex((l) => l.type === type && l.fn === fn && l.capture === c);
        if (i >= 0) listeners.splice(i, 1);
      },
      /** calls the listeners for `type`, capturing ones first, until one stops propagation */
      fire(type, init = {}) {
        const event = {
          type,
          defaultPrevented: false,
          stopped: false,
          preventDefault() {
            this.defaultPrevented = true;
          },
          stopPropagation() {
            this.stopped = true;
          },
          ...init,
        };
        for (const phase of [true, false]) {
          for (const l of listeners.filter((x) => x.type === type && x.capture === phase)) {
            if (event.stopped) return event;
            l.fn.call(this, event);
          }
        }
        return event;
      },
    },
    extra,
  );
}

/** A promise the test settles by hand. */
export function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

/** Lets every queued promise callback run. */
export const settle = () => new Promise((resolve) => setImmediate(resolve));
