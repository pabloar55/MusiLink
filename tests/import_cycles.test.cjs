const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');

function sourceFiles(directory, extension, excluded = []) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    if (excluded.includes(file)) return [];
    if (entry.isDirectory()) return sourceFiles(file, extension, excluded);
    return entry.name.endsWith(extension) ? [file] : [];
  });
}

function dartPackageName() {
  const pubspec = fs.readFileSync(path.join(root, 'pubspec.yaml'), 'utf8');
  return pubspec.match(/^name:\s*(\S+)/m)[1];
}

// Covers multi-line directives and conditional imports (`if (...) 'b.dart'`).
function dartImports(file, packageName) {
  const source = fs.readFileSync(file, 'utf8');
  const packagePrefix = `package:${packageName}/`;
  const imports = [];
  for (const [directive] of source.matchAll(/^\s*(?:import|export)\s[^;]*;/gm)) {
    for (const [, uri] of directive.matchAll(/['"]([^'"]+)['"]/g)) {
      if (uri.startsWith(packagePrefix)) {
        imports.push(path.join(root, 'lib', uri.slice(packagePrefix.length)));
      } else if (!/^[a-z]+:/.test(uri)) {
        imports.push(path.resolve(path.dirname(file), uri));
      }
    }
  }
  return imports;
}

function typeScriptImports(file) {
  const source = fs.readFileSync(file, 'utf8');
  const pattern = /^\s*(?:import|export)\s(?:[^'";]*?\sfrom\s)?\s*['"](\.{1,2}\/[^'"]+)['"]/gm;
  return [...source.matchAll(pattern)].map(([, specifier]) => {
    const target = path.resolve(path.dirname(file), specifier);
    return fs.existsSync(`${target}.ts`) ? `${target}.ts` : path.join(target, 'index.ts');
  });
}

function importGraph(files, importsOf) {
  const graph = new Map();
  for (const file of files) {
    const imports = importsOf(file);
    for (const target of imports) {
      assert.ok(
        fs.existsSync(target),
        `${path.relative(root, file)} importa ${path.relative(root, target)}, que no existe`,
      );
    }
    graph.set(file, new Set(imports.filter((target) => files.includes(target))));
  }
  return graph;
}

function edgeCount(graph) {
  return [...graph.values()].reduce((count, targets) => count + targets.size, 0);
}

// Tarjan: each strongly connected component with an internal edge is a cycle.
function importCycles(graph) {
  const index = new Map();
  const lowLink = new Map();
  const stack = [];
  const onStack = new Set();
  const cycles = [];

  function visit(node) {
    index.set(node, index.size);
    lowLink.set(node, index.get(node));
    stack.push(node);
    onStack.add(node);
    for (const target of graph.get(node) ?? []) {
      if (!index.has(target)) {
        visit(target);
        lowLink.set(node, Math.min(lowLink.get(node), lowLink.get(target)));
      } else if (onStack.has(target)) {
        lowLink.set(node, Math.min(lowLink.get(node), index.get(target)));
      }
    }
    if (lowLink.get(node) !== index.get(node)) return;
    const component = [];
    let member;
    do {
      member = stack.pop();
      onStack.delete(member);
      component.push(member);
    } while (member !== node);
    if (component.length > 1 || graph.get(node)?.has(node)) {
      cycles.push(cyclePath(graph, new Set(component)));
    }
  }

  for (const node of graph.keys()) {
    if (!index.has(node)) visit(node);
  }
  return cycles;
}

// One concrete loop inside a component, so the failure names the imports to break.
function cyclePath(graph, component) {
  const [start] = [...component].sort();
  const previous = new Map([[start, null]]);
  const queue = [start];
  while (queue.length > 0) {
    const node = queue.shift();
    for (const target of graph.get(node)) {
      if (target === start) {
        const loop = [start];
        for (let step = node; step !== start; step = previous.get(step)) loop.splice(1, 0, step);
        return [...loop, start];
      }
      if (component.has(target) && !previous.has(target)) {
        previous.set(target, node);
        queue.push(target);
      }
    }
  }
  throw new Error('A strongly connected component always contains a loop.');
}

function describeCycles(cycles) {
  return cycles
    .map((cycle) => cycle.map((file) => path.relative(root, file)).join(' -> '))
    .join('\n');
}

test('the detector reports every loop with a readable path', () => {
  const graph = new Map([
    ['a', new Set(['b'])],
    ['b', new Set(['c'])],
    ['c', new Set(['a'])],
    ['d', new Set(['d'])],
    ['e', new Set(['a'])],
  ]);

  assert.deepEqual(importCycles(graph), [['a', 'b', 'c', 'a'], ['d', 'd']]);
  assert.deepEqual(importCycles(new Map([['a', new Set(['b'])], ['b', new Set()]])), []);
});

test('the Flutter app has no import cycles', () => {
  const packageName = dartPackageName();
  // gen-l10n output imports itself by design and is never edited by hand.
  const files = sourceFiles(path.join(root, 'lib'), '.dart', [path.join(root, 'lib', 'l10n')]);
  const graph = importGraph(files, (file) => dartImports(file, packageName));

  assert.ok(edgeCount(graph) > 0, 'No se ha detectado ningún import interno en lib/');
  const cycles = importCycles(graph);
  assert.equal(cycles.length, 0, `Ciclos de importación en lib/:\n${describeCycles(cycles)}`);
});

test('Cloud Functions have no import cycles', () => {
  const files = sourceFiles(path.join(root, 'functions', 'src'), '.ts');
  const graph = importGraph(files, typeScriptImports);

  assert.ok(edgeCount(graph) > 0, 'No se ha detectado ningún import interno en functions/src/');
  const cycles = importCycles(graph);
  assert.equal(
    cycles.length,
    0,
    `Ciclos de importación en functions/src/:\n${describeCycles(cycles)}`,
  );
});
