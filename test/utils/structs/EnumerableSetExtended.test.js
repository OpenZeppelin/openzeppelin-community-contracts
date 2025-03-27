const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { mapValues } = require('@openzeppelin/contracts/test/helpers/iterate');
const { generators } = require('@openzeppelin/contracts/test/helpers/random');
const { SET_TYPES } = require('../../../scripts/generate/templates/Enumerable.opts');

const { shouldBehaveLikeSet } = require('@openzeppelin/contracts/test/utils/structs/EnumerableSet.behavior');

async function fixture() {
  const mock = await ethers.deployContract('$EnumerableSetExtended');

  const env = Object.fromEntries(
    SET_TYPES.map(({ name, value }) => [
      name,
      {
        value,
        values: Array.from(
          { length: 3 },
          value.size ? () => Array.from({ length: value.size }, generators[value.base]) : generators[value.type],
        ),
        methods: mapValues(
          {
            add: `$add(uint256,${value.type})`,
            remove: `$remove(uint256,${value.type})`,
            contains: `$contains(uint256,${value.type})`,
            clear: `$clear_EnumerableSetExtended_${name}(uint256)`,
            length: `$length_EnumerableSetExtended_${name}(uint256)`,
            at: `$at_EnumerableSetExtended_${name}(uint256,uint256)`,
            values: `$values_EnumerableSetExtended_${name}(uint256)`,
          },
          fnSig =>
            (...args) =>
              mock.getFunction(fnSig)(0, ...args),
        ),
        events: {
          addReturn: `return$add_EnumerableSetExtended_${name}_${value.type.replace(/[[\]]/g, '_')}`,
          removeReturn: `return$remove_EnumerableSetExtended_${name}_${value.type.replace(/[[\]]/g, '_')}`,
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
