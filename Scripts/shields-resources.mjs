#!/usr/bin/env node
// Builds Shields' resources.json from uBlock Origin's redirect resources and scriptlets.
//
// Usage: node Scripts/shields-resources.mjs <uBO source dir> <output resources.json> <version> [<release.json>]
//
// <version> is a whole number above every earlier release's: it is written beside the output as
// shields-resources.version (the bundled copy's version), and a downloaded release is used only
// while its version is higher. With <release.json>, the release to publish is written too:
// {"domain": "refrax-shields-resources", "version", "resources"}, to be signed whole with a
// release key (<release.json>.sig) and uploaded to the shields-resources release.
//
// <uBO source dir> is either an unpacked uBO release (the directory holding manifest.json,
// js/ and web_accessible_resources/, e.g. the unzipped Refrax/Resources/BundledExtensions xpi)
// or a uBlock git checkout's src/ directory. The output is a JSON array of adblock-rust
// `Resource` objects ({name, aliases, kind: {mime}, content (base64), dependencies,
// permission}) that `shields_engine_use_resources` reads.
//
// Scriptlets come from uBO's function-style registry (js/resources/scriptlets.js): each one is
// a named JavaScript function, its helpers are `fn/javascript` dependencies, and adblock-rust
// invokes it with the filter's arguments. Scriptlets uBO marks `requiresTrust` get permission
// bit 0, which only lists Refrax trusts (uBO's own) carry.
//
// Redirect resources come from js/redirect-resources.js and the files in
// web_accessible_resources/. Resources that need URL parameters (click2load.html) are skipped:
// a data: URL cannot carry them.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve, extname, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

const TRUSTED_PERMISSION = 1;

const MIME_BY_EXTENSION = new Map([
    ['.js', 'application/javascript'],
    ['.css', 'text/css'],
    ['.gif', 'image/gif'],
    ['.png', 'image/png'],
    ['.html', 'text/html'],
    ['.json', 'application/json'],
    ['.mp3', 'audio/mp3'],
    ['.mp4', 'video/mp4'],
    ['.xml', 'text/xml'],
    ['.txt', 'text/plain'],
    ['', 'text/plain'],
]);

const [, , sourceArgument, outputArgument, versionArgument, releaseArgument] = process.argv;
const version = Number(versionArgument);
if (!sourceArgument || !outputArgument || !Number.isInteger(version) || version < 1) {
    console.error('usage: node Scripts/shields-resources.mjs <uBO source dir> <output resources.json> <version> [<release.json>]');
    process.exit(64);
}

const source = resolve(sourceArgument);
const scriptletsModule = join(source, 'js', 'resources', 'scriptlets.js');
const redirectsModule = join(source, 'js', 'redirect-resources.js');
for (const required of [scriptletsModule, redirectsModule]) {
    if (!existsSync(required)) {
        console.error(`missing ${required}: pass an unpacked uBO release or a uBlock checkout's src/`);
        process.exit(66);
    }
}

const asList = (value) => (value === undefined ? [] : Array.isArray(value) ? value : [value]);
const base64 = (data) => Buffer.from(data).toString('base64');

const { builtinScriptlets } = await import(pathToFileURL(scriptletsModule).href);
const scriptlets = builtinScriptlets.map((details) => {
    if (typeof details.fn !== 'function' || typeof details.name !== 'string') {
        throw new Error(`malformed scriptlet entry ${JSON.stringify(details.name)}`);
    }
    const source = details.fn.toString();
    const isDependency = details.name.endsWith('.fn');
    // adblock-rust invokes a scriptlet by the name in its `function name(` header; a dependency
    // is pasted in front of the invocations, so a class declaration serves as well.
    const declaration = isDependency ? /^(function|class)\s+[^\s(){}]+/ : /^function\s+[^\s(){}]+\s*\(/;
    if (!declaration.test(source)) {
        throw new Error(`scriptlet ${details.name} is not a named declaration`);
    }
    return {
        name: details.name,
        aliases: asList(details.aliases),
        kind: { mime: isDependency ? 'fn/javascript' : 'application/javascript' },
        content: base64(source),
        dependencies: asList(details.dependencies).filter((name) => typeof name === 'string'),
        permission: details.requiresTrust ? TRUSTED_PERMISSION : 0,
    };
});

const { default: redirectTable } = await import(pathToFileURL(redirectsModule).href);
const scriptletNames = new Set(scriptlets.flatMap((resource) => [resource.name, ...resource.aliases]));
const redirects = [];
for (const [name, details] of redirectTable) {
    if (details.params) { continue; }
    const mime = MIME_BY_EXTENSION.get(extname(name));
    if (mime === undefined) {
        throw new Error(`no MIME type for redirect resource ${name}`);
    }
    const aliases = asList(details.alias).filter((alias) => !scriptletNames.has(alias));
    if (scriptletNames.has(name)) {
        console.warn(`skipping redirect ${name}: a scriptlet has the same name`);
        continue;
    }
    redirects.push({
        name,
        aliases,
        kind: { mime },
        content: base64(readFileSync(join(source, 'web_accessible_resources', name))),
        dependencies: [],
        permission: 0,
    });
}

const resources = [...redirects, ...scriptlets].sort((a, b) => a.name.localeCompare(b.name));
const names = new Set();
for (const resource of resources) {
    for (const name of [resource.name, ...resource.aliases]) {
        if (names.has(name)) { throw new Error(`duplicate resource name ${name}`); }
        names.add(name);
    }
}
for (const resource of resources) {
    for (const dependency of resource.dependencies) {
        if (!names.has(dependency)) { throw new Error(`${resource.name} depends on missing ${dependency}`); }
    }
}

writeFileSync(outputArgument, `${JSON.stringify(resources, null, 1)}\n`);
writeFileSync(join(dirname(outputArgument), 'shields-resources.version'), `${version}\n`);
if (releaseArgument) {
    writeFileSync(releaseArgument, `${JSON.stringify({ domain: 'refrax-shields-resources', version, resources })}\n`);
}
console.log(`${redirects.length} redirect resources, ${scriptlets.length} scriptlets, version ${version} → ${outputArgument}`);
