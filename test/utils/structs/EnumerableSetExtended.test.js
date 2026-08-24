import { network } from 'hardhat';
import { mapValues } from '@openzeppelin/contracts/test/helpers/iterate';
import * as random from '@openzeppelin/contracts/test/helpers/random';
import { shouldBehaveLikeSet } from '@openzeppelin/contracts/test/utils/structs/EnumerableSet.behavior';

import { SET_TYPES } from '../../../scripts/generate/templates/Enumerable.opts';

const {
  ethers,
  networkHelpers: { loadFixture },
} = await network.create();

// Chai matchers expect hexadecimal data when dealing with bytes
const randomOf = type => random[type === 'bytes' ? 'hexBytes' : type];

async function fixture() {
  const mock = await ethers.deployContract('$EnumerableSetExtended');

  const env = Object.fromEntries(
    SET_TYPES.map(({ name, value }) => [
      name,
      {
        value,
        values: Array.from(
          { length: 3 },
          value.size ? () => Array.from({ length: value.size }, randomOf(value.base)) : randomOf(value.type),
        ),
        methods: mapValues(
          {
            add: `$add(uint256,${value.type})`,
            remove: `$remove(uint256,${value.type})`,
            contains: `$contains(uint256,${value.type})`,
            clear: `$clear(uint256)`, // `$clear_EnumerableSetExtended_${name}(uint256)` when more types are added
            length: `$length(uint256)`, // `$length_EnumerableSetExtended_${name}(uint256)` when more types are added
            at: `$at(uint256,uint256)`, // `$at_EnumerableSetExtended_${name}(uint256,uint256)` when more types are added
            values: `$values(uint256)`, // `$values_EnumerableSetExtended_${name}(uint256)` when more types are added
            valuesPage: `$values(uint256,uint256,uint256)`, // `$values_EnumerableSetExtended_${name}(uint256,uint256,uint256)` when more types are added
          },
          fnSig =>
            (...args) =>
              mock.getFunction(fnSig)(0, ...args),
        ),
        events: {
          addReturn: 'return$add', // `return$add_EnumerableSetExtended_${name}_${value.type.replace(/[[\]]/g, '_')}`,
          removeReturn: 'return$remove', // `return$remove_EnumerableSetExtended_${name}_${value.type.replace(/[[\]]/g, '_')}`,
        },
      },
    ]),
  );

  return { mock, env };
}

describe('EnumerableSetExtended', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  for (const { name, value } of SET_TYPES) {
    describe(`${name} (enumerable set of ${value.type})`, function () {
      beforeEach(function () {
        Object.assign(this, this.env[name]);
        [this.valueA, this.valueB, this.valueC] = this.values;
      });

      shouldBehaveLikeSet();
    });
  }
});
