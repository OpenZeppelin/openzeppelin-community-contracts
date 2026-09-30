import { capitalize, mapValues } from '@openzeppelin/contracts/scripts/helpers.js';

export const typeDescr = ({ type, size = 0, memory = false }) => {
  memory |= size > 0;

  const name = [type == 'uint256' ? 'Uint' : capitalize(type), size].filter(Boolean).join('x');
  const base = size ? type : undefined;
  const typeFull = size ? `${type}[${size}]` : type;
  const typeLoc = memory ? `${typeFull} memory` : typeFull;
  return { name, type: typeFull, typeLoc, base, size, memory };
};

export const toSetTypeDescr = value => ({
  name: value.name + 'Set',
  value,
});

export const toMapTypeDescr = ({ key, value }) => ({
  name: `${key.name}To${value.name}Map`,
  keySet: toSetTypeDescr(key),
  key,
  value,
});

export const SET_TYPES = [{ type: 'bytes32', size: 2 }].map(typeDescr).map(toSetTypeDescr);

export const MAP_TYPES = [
  { key: { type: 'bytes', memory: true }, value: { type: 'uint256' } },
  { key: { type: 'string', memory: true }, value: { type: 'string', memory: true } },
]
  .map(entry => mapValues(entry, typeDescr))
  .map(toMapTypeDescr);
