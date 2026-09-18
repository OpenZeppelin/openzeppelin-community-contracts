export const TYPES = Object.fromEntries(
  [
    { name: 'Uint', type: 'uint256', size: 0, memory: false },
    { name: 'String', type: 'string', size: 0, memory: true },
    { name: 'Bytes', type: 'bytes', size: 0, memory: true },
    { name: 'Bytes32x2', type: 'bytes32[2]', size: 2, memory: true, base: 'bytes32' },
  ].map(t => [t.name, { ...t, typeLoc: t.memory ? `${t.type} memory` : t.type }]),
);

export const SET_TYPES = [{ name: 'Bytes32x2Set', value: TYPES.Bytes32x2 }];

export const MAP_TYPES = [
  { name: 'BytesToUintMap', keySet: { name: 'BytesSet' }, key: TYPES.Bytes, value: TYPES.Uint },
  { name: 'StringToStringMap', keySet: { name: 'StringSet' }, key: TYPES.String, value: TYPES.String },
];
