import fs from 'node:fs';
import path from 'node:path';
import { version } from '../../package.json';

export const ozVersion = () => version;

// `@openzeppelin/contracts` is documented as a separate Antora component. It assigns pages the same
// way we do -- the closest `README.adoc` above the source file -- so the page an item is documented
// on can be derived from the submodule layout. Resolving against the submodule rather than guessing
// guarantees we never emit an xref to a page that does not exist.
const CORE_COMPONENT = 'contracts';
const CORE_MODULE = 'api';
const CORE_SOURCES = path.resolve(import.meta.dirname, '../../lib/@openzeppelin-contracts/contracts');
// Hardhat 3 keys dependency sources as `npm/<package>@<version>/...`; the core package resolves
// through `file:lib/@openzeppelin-contracts`, so it appears under its own name (`openzeppelin-solidity`).
const CORE_SOURCE_RE = /^npm\/(?:openzeppelin-solidity|@openzeppelin\/contracts)@[^/]+\/contracts\/(.+)$/;

const corePageCache = new Map();

// Page id an item defined in `absolutePath` is documented on, or undefined when it is not a core
// source or no README covers it.
function corePage(absolutePath) {
  const match = CORE_SOURCE_RE.exec(absolutePath);
  if (!match) return undefined;
  if (corePageCache.has(match[1])) return corePageCache.get(match[1]);

  let page;
  for (let dir = path.dirname(match[1]); dir !== '.' && dir !== path.sep; dir = path.dirname(dir)) {
    if (fs.existsSync(path.join(CORE_SOURCES, dir, 'README.adoc'))) {
      page = `${CORE_COMPONENT}::${CORE_MODULE}:${dir}.adoc`;
      break;
    }
  }
  corePageCache.set(match[1], page);
  return page;
}

export const readmePath = opts => {
  return 'contracts/' + opts.data.root.id.replace(/\.adoc$/, '') + '/README.adoc';
};

export const names = params => params?.map(p => p.name).join(', ');

export const typedParams = params => {
  return params?.map(p => `${p.type}${p.indexed ? ' indexed' : ''}${p.name ? ' ' + p.name : ''}`).join(', ');
};

export const slug = str => {
  if (str === undefined) {
    throw new Error('Missing argument');
  }
  return str.replace(/\W/g, '-');
};

const linksCache = new WeakMap();

// Members `contract.hbs` renders an anchor for, and which can therefore be linked to. Anything else
// (structs, enums, private members) has no target on the page, so linking to it would be a dead link.
function isLinkable(member) {
  switch (member.nodeType) {
    case 'ErrorDefinition':
    case 'EventDefinition':
    case 'ModifierDefinition':
      return true;
    case 'FunctionDefinition':
      return member.visibility !== 'private';
    case 'VariableDeclaration':
      return member.visibility === 'public' || member.visibility === 'internal';
    default:
      return false;
  }
}

function getAllLinks(items) {
  if (linksCache.has(items)) {
    return linksCache.get(items);
  }
  const res = {};
  linksCache.set(items, res);

  const byBareName = new Map();

  const register = (item, page) => {
    const link = `pass:normal[xref:${page}#${item.anchor}[\`${item.fullName}\`]]`;
    res[`xref-${item.anchor}`] = `xref:${page}#${item.anchor}`;
    res[slug(item.fullName)] = link;
    // Only collect a bare name when the item is actually rendered with an anchor. `items` also
    // carries structs and enums, which `contract.hbs` does not emit a target for.
    if (item.name && (item.nodeType === 'ContractDefinition' || isLinkable(item))) {
      if (!byBareName.has(item.name)) byBareName.set(item.name, new Set());
      byBareName.get(item.name).add(link);
    }
  };

  // Items of the core component first, so that a local item always wins a name collision.
  // `build.output.sources` holds every source the compilation saw, dependencies included.
  const build = items[0]?.__item_context?.build;
  for (const { ast } of Object.values(build?.output?.sources ?? {})) {
    const page = corePage(ast.absolutePath);
    if (page === undefined) continue;
    for (const contract of ast.nodes) {
      if (contract.nodeType !== 'ContractDefinition') continue;
      register(contract, page);
      for (const member of contract.nodes) {
        if (isLinkable(member)) register(member, page);
      }
    }
  }

  for (const item of items) {
    register(item, item.__item_context.page);
  }

  // Natspec inherited from a base contract refers to its members by bare name (`{CallScheduled}`),
  // which resolves in the component that documents the base but not once the text is rendered here.
  // Register those too, but only where the name has a single candidate across everything we know
  // about: an ambiguous one (`{transfer}`) would otherwise become a link to an arbitrary contract.
  for (const [name, targets] of byBareName) {
    const [only] = targets;
    if (targets.size === 1 && !(name in res)) res[name] = only;
  }
  return res;
}

export const withPrelude = opts => {
  const links = getAllLinks(opts.data.site.items);
  // Index entries are rendered as `{xref-<anchor>}[<text>]`, which requires the attribute to be
  // defined in the prelude below. Only items documented in this component have one: members
  // inherited from another component (@openzeppelin/contracts) have no page here, and asciidoctor
  // would drop the reference. Strip the xref from those and keep the plain link text.
  const contents = opts
    .fn()
    .replace(/^(\* )\{(xref-[^}]+)\}\[(.*)\]$/gm, (entry, bullet, key, text) => (key in links ? entry : bullet + text));
  const neededLinks = contents
    .match(/\{[-._a-z0-9]+\}/gi)
    .map(m => m.replace(/^\{(.+)\}$/, '$1'))
    .filter(k => k in links);
  const prelude = neededLinks.map(k => `:${k}: ${links[k]}`).join('\n');
  return prelude + '\n' + contents;
};
