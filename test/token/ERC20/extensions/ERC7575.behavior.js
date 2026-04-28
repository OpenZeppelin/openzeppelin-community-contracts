const { expect } = require('chai');
const { shouldSupportInterfaces, INTERFACE_IDS } = require('../../../utils/introspection/SupportsInterface.behavior');

function shouldBehaveLikeERC7575({ selfAsset } = {}) {
  selfAsset ??= true;

  describe('Should behave like ERC7575', function () {
    describe('supports ERC-7575 operator interface', function () {
      expect(INTERFACE_IDS.ERC7575).to.equal('0x2f0a18c5');
      expect(INTERFACE_IDS.ERC7575Share).to.equal('0xf815c03d');
      shouldSupportInterfaces(['ERC7575']);
    });

    it('get share address', async function () {
      if (selfAsset) {
        await expect(this.mock.share()).to.eventually.equal(this.mock);
      } else {
        await expect(this.mock.share()).to.eventually.not.equal(this.mock);
      }
    });
  });
}

module.exports = {
  shouldBehaveLikeERC7575,
};
