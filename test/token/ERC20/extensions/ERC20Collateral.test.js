const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
    const [holder, recipient, approved] = await ethers.getSigners();

    const token = await ethers.deployContract('$ERC20CollateralMock', [0, name, symbol]);
    await token.$_mint(holder, initialSupply);

    return { holder, recipient, approved, token };
}

describe('ERC20Collateral', function () {
    beforeEach(async function () {
        Object.assign(this, await loadFixture(fixture));
    });

    describe('amount', function () {
        it('mint all of collateral amount', async function () {
            await expect(this.token.$_mint(this.holder, (2n ** 128n - 1n) - initialSupply)).to.changeTokenBalance(this.token, this.holder, (2n ** 128n - 1n) - initialSupply);
        });

        it('reverts when minting more than collateral amount', async function () {
            await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
                this.token,
                [this.holder, this.recipient],
                [-initialSupply, initialSupply],
            );
        });
    });

    // describe('expiration', function () {
    //     it('mint before expiration', async function () {
    //         await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
    //             this.token,
    //             [this.holder, this.recipient],
    //             [-initialSupply, initialSupply],
    //         );
    //     });

    //     it('reverts when minting after expiration', async function () {
    //         await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
    //             this.token,
    //             [this.holder, this.recipient],
    //             [-initialSupply, initialSupply],
    //         );
    //     });
    // });
});