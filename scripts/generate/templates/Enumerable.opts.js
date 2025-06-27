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

const SET_TYPES = [{ type: 'bytes32', size: 2 }].map(typeDescr).map(toSetTypeDescr);

const MAP_TYPES = [
  { key: { type: 'bytes', memory: true }, value: { type: 'uint256' } },
  { key: { type: 'string', memory: true }, value: { type: 'string', memory: true } },
]
  .map(entry => mapValues(entry, typeDescr))
  .map(toMapTypeDescr);

module.exports = {
  SET_TYPES,
  MAP_TYPES,
  typeDescr,
  toSetTypeDescr,
  toMapTypeDescr,
};
