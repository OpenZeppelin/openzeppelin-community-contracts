const { version } = require('../../package.json');
const fs = require('fs');

const PATH_PREFIX = '/community-contracts/api/';

module.exports['oz-version'] = () => version;

module.exports['readme-path'] = opts => {
  const pageId = opts.data.root.id;
  const basePath = pageId.replace(/\.(adoc|mdx)$/, '');
  return 'contracts/' + basePath + '/README.mdx';
};

module.exports.readme = readmePath => {
  try {
    if (fs.existsSync(readmePath)) {
      const readmeContent = fs.readFileSync(readmePath, 'utf8');
      return processMdxContent(readmeContent);
    }
  } catch (error) {
    console.warn(`Warning: Could not process README at ${readmePath}:`, error.message);
  }
  return '';
};

module.exports.names = params => params?.map(p => p.name).join(', ');

// Simple function counter for unique IDs
const functionNameCounts = {};

module.exports['simple-id'] = function (name) {
  if (!functionNameCounts[name]) {
    functionNameCounts[name] = 1;
    return name;
  } else {
    functionNameCounts[name]++;
    return `${name}-${functionNameCounts[name]}`;
  }
};

module.exports['reset-function-counts'] = function () {
  Object.keys(functionNameCounts).forEach(key => delete functionNameCounts[key]);
  return '';
};

module.exports.eq = (a, b) => a === b;
module.exports['starts-with'] = (str, prefix) => str && str.startsWith(prefix);

// Process natspec content with {REF} and link replacement
module.exports['process-natspec'] = function (natspec, opts) {
  if (!natspec) return '';

  const currentPage = opts.data.root.__item_context?.page || opts.data.root.id;
  const links = getAllLinks(opts.data.site.items, currentPage);

  return processReferences(natspec, links);
};

module.exports['typed-params'] = params => {
  return params?.map(p => `${p.type}${p.indexed ? ' indexed' : ''}${p.name ? ' ' + p.name : ''}`).join(', ');
};

const slug = (module.exports.slug = str => {
  if (str === undefined) {
    throw new Error('Missing argument');
  }
  return str.replace(/\W/g, '-');
});

// Link generation and caching
const linksCache = new WeakMap();

function getAllLinks(items, currentPage) {
  if (currentPage) {
    const cacheKey = currentPage;
    let cache = linksCache.get(items);
    if (!cache) {
      cache = new Map();
      linksCache.set(items, cache);
    }

    if (cache.has(cacheKey)) {
      return cache.get(cacheKey);
    }
  }

  const res = {};
  const currentPagePath = currentPage ? currentPage.replace(/\.mdx$/, '') : '';

  for (const item of items) {
    const pagePath = item.__item_context.page.replace(/\.mdx$/, '');
    const linkPath = generateLinkPath(pagePath, currentPagePath, item.anchor);

    res[slug(item.fullName)] = `[\`${item.fullName}\`](${linkPath})`;
  }

  if (currentPage) {
    let cache = linksCache.get(items);
    if (!cache) {
      cache = new Map();
      linksCache.set(items, cache);
    }
    cache.set(currentPage, res);
  }

  return res;
}

function generateLinkPath(pagePath, currentPagePath, anchor) {
  if (
    currentPagePath &&
    (pagePath === currentPagePath || pagePath.split('/').pop() === currentPagePath.split('/').pop())
  ) {
    return `#${anchor}`;
  }

  if (currentPagePath) {
    const currentParts = currentPagePath.split('/');
    const targetParts = pagePath.split('/');

    // Find common base
    let i = 0;
    while (i < currentParts.length && i < targetParts.length && currentParts[i] === targetParts[i]) {
      i++;
    }

    const upLevels = Math.max(0, currentParts.length - 1 - i);
    const downPath = targetParts.slice(i);

    if (upLevels === 0 && downPath.length === 1) {
      return `${PATH_PREFIX}${downPath[0]}#${anchor}`;
    } else if (upLevels === 0) {
      return `${PATH_PREFIX}${downPath.join('/')}#${anchor}`;
    } else {
      const relativePath = downPath.join('/');
      return `${PATH_PREFIX}${relativePath}#${anchor}`;
    }
  }

  return `${PATH_PREFIX}${pagePath}#${anchor}`;
}

// Process {REF} and other references
function processReferences(content, links) {
  let result = content;

  // Handle {REF:Contract.method} patterns
  result = result.replace(/\{REF:([^}]+)\}/g, (match, refId) => {
    const resolvedRef = resolveReference(refId, links);
    return resolvedRef || match;
  });

  // Replace {link-key} placeholders with markdown links
  result = result.replace(/\{([-._a-z0-9]+)\}/gi, (match, key) => {
    const replacement = findBestMatch(key, links);
    return replacement || `\`${key}\``;
  });

  // Handle standalone contract names on their own line (e.g., "ERC7579Executor")
  // This matches lines with just a contract name (starts with capital letter)
  result = result.replace(/^([A-Z][a-zA-Z0-9]+)$/gm, (match, contractName) => {
    const replacement = findBestMatch(contractName, links);
    return replacement || match;
  });

  return cleanupContent(result);
}

function resolveReference(refId, links) {
  // Try fuzzy matching for fullName keys
  const matchingKeys = Object.keys(links).filter(key => {
    const normalizedKey = key.toLowerCase();
    const normalizedRef = refId.replace(/\./g, '-').toLowerCase();
    return normalizedKey.includes(normalizedRef) || normalizedRef.includes(normalizedKey);
  });

  if (matchingKeys.length > 0) {
    const bestMatch = matchingKeys[0];
    const parts = refId.split('.');
    const displayText = parts.length > 1 ? `${parts[0]}.${parts[1]}` : refId;
    return `[\`${displayText}\`](${links[bestMatch]})`;
  }

  return null;
}

function findBestMatch(key, links) {
  let replacement = links[key];

  if (!replacement) {
    // Strategy 1: Look for keys that end with this key
    let matchingKeys = Object.keys(links).filter(linkKey => {
      const parts = linkKey.split('-');
      return parts.length >= 2 && parts[parts.length - 1] === key;
    });

    // Strategy 2: Try with different separators
    if (matchingKeys.length === 0) {
      const keyWithDashes = key.replace(/\./g, '-');
      matchingKeys = Object.keys(links).filter(linkKey => linkKey.includes(keyWithDashes));
    }

    // Strategy 3: Try partial matches
    if (matchingKeys.length === 0) {
      matchingKeys = Object.keys(links).filter(linkKey => {
        return linkKey === key || linkKey.endsWith('-' + key) || linkKey.includes(key);
      });
    }

    if (matchingKeys.length > 0) {
      replacement = links[matchingKeys[0]];
    }
  }

  return replacement;
}

function cleanupContent(content) {
  return content
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&#x60;/g, '`')
    .replace(/&#x3D;/g, '=')
    .replace(/&amp;/g, '&')
    .replace(/\{(\[`[^`]+`\]\([^)]+\))\}/g, '$1')
    .replace(/https?:\/\/[^\s[]+\[[^\]]+\]/g, match => {
      const urlMatch = match.match(/^(https?:\/\/[^[]+)\[([^\]]+)\]$/);
      return urlMatch ? `[${urlMatch[2]}](${urlMatch[1]})` : match;
    });
}

function processMdxContent(content) {
  try {
    // Process MDX content - strip frontmatter and cleanup
    let mdxContent = content
      // Remove frontmatter (--- ... ---)
      .replace(/^---\s*\n[\s\S]*?\n---\s*\n/, '')
      // Remove "better viewed at" callouts
      .replace(
        /<Callout>\s*This document is better viewed at https:\/\/docs\.openzeppelin\.com[^\n]*\s*<\/Callout>\s*/g,
        '',
      )
      // Ensure relative image paths start with /
      .replace(/!\[([^\]]*)\]\(([^/)][^)]*\.(png|jpg|jpeg|gif|svg|webp))\)/g, '![$1](/$2)')
      // Remove any title headers (they're in frontmatter now)
      .replace(/^#+\s+.+$/m, '')
      // Clean up leading newlines
      .replace(/^\n+/, '');

    return mdxContent;
  } catch (error) {
    console.warn('Warning: Failed to process MDX content:', error.message);
    return content;
  }
}

module.exports.title = opts => {
  const pageId = opts.data.root.id;
  const basePath = pageId.replace(/\.(adoc|mdx)$/, '');
  const parts = basePath.split('/');
  const dirName = parts[parts.length - 1] || 'Contracts';
  return dirName
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
};

module.exports.description = opts => {
  const pageId = opts.data.root.id;
  const basePath = pageId.replace(/\.(adoc|mdx)$/, '');
  const parts = basePath.split('/');
  const dirName = parts[parts.length - 1] || 'contracts';
  return `Smart contract ${dirName.replace('-', ' ')} utilities and implementations`;
};

module.exports['with-prelude'] = opts => {
  const currentPage = opts.data.root.id;
  const links = getAllLinks(opts.data.site.items, currentPage);
  const contents = opts.fn();

  const processed = processReferences(contents, links);
  return processed;
};
