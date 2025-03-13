const { capitalize, mapValues } = require('@openzeppelin/contracts/scripts/helpers');

const typeDescr = ({ type, size = 0, memory = false }) => {
  memory |= size > 0;

  const name = [type == 'uint256' ? 'Uint' : capitalize(type), size].filter(Boolean).join('x');
  const base = size ? type : undefined;
  const typeFull = size ? `${type}[${size}]` : type;
  const typeLoc = memory ? `${typeFull} memory` : typeFull;
  return { name, type: typeFull, typeLoc, base, size, memory };
};

const toSetTypeDescr = value => ({
  name: value.name + 'Set',
  value,
});

const toMapTypeDescr = ({ key, value }) => ({
  name: `${key.name}To${value.name}Map`,
  keySet: toSetTypeDescr(key),
  key,
  value,
});

const SET_TYPES = [
  // { type: 'bytes32' }, // part of the vanilla repo
  // { type: 'address' }, // part of the vanilla repo
  // { type: 'uint256' }, // part of the vanilla repo
  { type: 'bytes32', size: 2 },
  { type: 'string', memory: true },
  { type: 'bytes', memory: true },
]
  .map(typeDescr)
  .map(toSetTypeDescr);

const MAP_TYPES = [
  // { key: { type: 'uint256' }, value: { type: 'uint256' } }, // part of the vanilla repo
  // { key: { type: 'uint256' }, value: { type: 'address' } }, // part of the vanilla repo
  // { key: { type: 'uint256' }, value: { type: 'bytes32' } }, // part of the vanilla repo
  // { key: { type: 'address' }, value: { type: 'uint256' } }, // part of the vanilla repo
  // { key: { type: 'address' }, value: { type: 'address' } }, // part of the vanilla repo
  // { key: { type: 'address' }, value: { type: 'bytes32' } }, // part of the vanilla repo
  // { key: { type: 'bytes32' }, value: { type: 'uint256' } }, // part of the vanilla repo
  // { key: { type: 'bytes32' }, value: { type: 'address' } }, // part of the vanilla repo
  { key: { type: 'bytes', memory: true }, value: { type: 'uint256' } },
  { key: { type: 'string', memory: true }, value: { type: 'string', memory: true } },
]
  .map(entry => mapValues(entry, typeDescr))
  .map(toMapTypeDescr);

/// Sanity - Disabled because some types might be provided by the vanilla repository.
// MAP_TYPES.forEach(entry => {
//   if (!SET_TYPES.some(set => set.structName == entry.key.structName))
//     throw new Error(`${entry.structName} requires a "${entry.key.structName}" set of "${entry.key.type}"`);
// });

module.exports = {
  SET_TYPES,
  MAP_TYPES,
  typeDescr,
  toSetTypeDescr,
  toMapTypeDescr,
};
