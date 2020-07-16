import * as utils from "../scripts/helpers/utils";
import { ethers } from "ethers";
import * as walletHelper from "../scripts/helpers/wallet";
import { Transaction, ErrorCode, CreateAccount } from "../scripts/helpers/interfaces";
const RollupCore = artifacts.require("Rollup");
const TestToken = artifacts.require("TestToken");
const DepositManager = artifacts.require("DepositManager");
const IMT = artifacts.require("IncrementalTree");
const RollupUtils = artifacts.require("RollupUtils");
const EcVerify = artifacts.require("ECVerify");
const createAccount = artifacts.require("CreateAccount");


contract("Reddit", async function () {
    let wallets: any;
    let Reddit: any;
    let User: any;
    let testTokenInstance;
    let depositManagerInstance;
    before(async function () {
        depositManagerInstance = await DepositManager.deployed();
        wallets = walletHelper.generateFirstWallets(walletHelper.mnemonics, 10);
        Reddit = {
            Address: wallets[0].getAddressString(),
            Pubkey: wallets[0].getPublicKeyString(),
            Amount: 50,
            TokenType: 1,
            AccID: 2,
            Path: "2",
            nonce: 0,
        };
        User = {
            Address: wallets[1].getAddressString(),
            Pubkey: wallets[1].getPublicKeyString(),
            Amount: 10,
            TokenType: 1,
            AccID: 3,
            Path: "3",
            nonce: 0,
        };
        testTokenInstance = await utils.registerToken(wallets[0]);
        await testTokenInstance.transfer(Reddit.Address, 100);
        await depositManagerInstance.depositFor(
            Reddit.Address,
            Reddit.Amount,
            Reddit.TokenType,
            Reddit.Pubkey
        );

    })
    it("Should Create Account for the User", async function () {
        const createAccountInstance = await createAccount.deployed();
        // Call to see what's the accountID
        const accountId = await createAccountInstance.createPublickeys.call([User.Pubkey]);
        assert.equal(accountId.toString(), "3");
        // Actual execution
        await createAccountInstance.createPublickeys([User.Pubkey]);

        const tx: CreateAccount = {
            toIndex: 3,
            tokenType: 1
        };
        const RollupUtilsInstance = await RollupUtils.deployed();
        const signBytes = await RollupUtilsInstance.getCreateAccountSignBytes(tx.toIndex, tx.tokenType);
        tx.signature = utils.sign(signBytes, wallets[0]);
        // createAccountInstance.processTx()
    })

})