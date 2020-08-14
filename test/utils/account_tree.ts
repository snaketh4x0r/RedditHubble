import { Tree } from "./tree";
import { BlsAccountRegistryInstance } from "../../types/truffle-contracts";

export class AccountRegistry {
    treeLeft: Tree;
    treeRight: Tree;
    // TODO: must be big int
    leftIndex: number = 0;
    rigthIndex: number = 0;
    setSize: number;

    public static async new(
        registry: BlsAccountRegistryInstance
    ): Promise<AccountRegistry> {
        const depth = (await registry.DEPTH()).toNumber();
        const batchDepth = (await registry.BATCH_DEPTH()).toNumber();
        return new AccountRegistry(registry, depth, batchDepth);
    }
    constructor(
        private readonly registry: BlsAccountRegistryInstance,
        private readonly depth: number,
        private readonly batchDepth: number
    ) {
        this.treeLeft = Tree.new(depth);
        this.treeRight = Tree.new(depth);
        this.setSize = 1 << depth;
    }

    public async register(pubkey: string[]): Promise<number> {
        const accountID = (await this.registry.leafIndexLeft()).toNumber();
        await this.registry.register(pubkey);
        const leaf = this.pubkeyToLeaf(pubkey);
        this.treeLeft.updateSingle(accountID, leaf);
        const _witness = this.witness(accountID);
        assert.isTrue(
            await this.registry.exists(accountID, pubkey, _witness.slice(0, 31))
        );
        return accountID;
    }

    public witness(accountID: number): string[] {
        // TODO: from right
        const witness = this.treeLeft.witness(accountID).nodes;
        witness.push(this.treeRight.root);
        return witness;
    }

    public root() {
        const hasher = this.treeLeft.hasher;
        return hasher.hash2(this.treeLeft.root, this.treeRight.root);
    }

    public pubkeyToLeaf(uncompressed: string[]) {
        const leaf = web3.utils.soliditySha3(
            { t: "uint256", v: uncompressed[0] },
            { t: "uint256", v: uncompressed[1] },
            { t: "uint256", v: uncompressed[2] },
            { t: "uint256", v: uncompressed[3] }
        );
        return leaf;
    }
}
