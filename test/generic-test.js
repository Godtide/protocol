/* eslint-disable no-undef */
const hre = require("hardhat");
const { ethers, network } = require("hardhat");
const chai = require("chai");
const { BigNumber } = require("@ethersproject/bignumber");
const {increaseTime, overwriteTokenAmount, increaseBlock} = require("./utils/helpers");
const { expect } = chai;
const {setupSigners} = require("./utils/actors");


const doGenericTest = (name,assetAddr,snowglobeAddr,strategyAddr,globeABI,stratABI, txnAmt) => {

    const walletAddr = process.env.WALLET_ADDR;
    let assetContract,controllerContract;
    let governanceSigner, strategistSigner, controllerSigner, timelockSigner;
    let globeContract, strategyContract;
    let strategyBalance;

    describe("Folding Strategy tests for: "+name, async () => {

        before( async () => {
            await network.provider.send('hardhat_impersonateAccount', [walletAddr]);
            walletSigner = ethers.provider.getSigner(walletAddr);
            [timelockSigner,strategistSigner,controllerSigner,governanceSigner] = await setupSigners();

            await overwriteTokenAmount(assetAddr,walletAddr,txnAmt);
        
            assetContract = await ethers.getContractAt("ERC20",assetAddr,walletSigner);
            controllerContract = await ethers.getContractAt("ControllerV4", await controllerSigner.getAddress(),  governanceSigner);

            //If strategy address not supplied then we should deploy and setup a new strategy
            if (strategyAddr == ""){          
                globeContract = new ethers.Contract(snowglobeAddr, globeABI, governanceSigner);
                const stratFactory = await ethers.getContractFactory(stratABI);
                strategyAddr = await controllerContract.strategies(assetAddr);

                // Before we can setup new strategy we must deleverage from old one
                strategyContract = await stratFactory.attach(strategyAddr);
                console.log(name + " is being deleveraged before new contract is deployed");
                await strategyContract.connect(governanceSigner).deleverageToMin();

                // Now we can deploy the new strategy
                strategyContract = await stratFactory.deploy(governanceSigner._address, strategistSigner._address,controllerSigner._address,timelockSigner._address);
                strategyAddr = strategyContract.address;
                await controllerContract.connect(timelockSigner).approveStrategy(assetAddr,strategyAddr);
                await controllerContract.connect(timelockSigner).setStrategy(assetAddr,strategyAddr);
            } else {
                strategyContract = new ethers.Contract(strategyAddr, stratABI, governanceSigner);
                globeContract = new ethers.Contract(snowglobeAddr, globeABI, governanceSigner);
            }

            await strategyContract.connect(governanceSigner).whitelistHarvester(walletAddr);
        });
    
        it("user wallet contains asset balance", async () =>{
            let BNBal = await assetContract.balanceOf(await walletSigner.getAddress());
            const BN = ethers.BigNumber.from(txnAmt)._hex.toString();
            expect(BNBal).to.be.equals(BN);
        });
    
        it("Globe initialized with zero balance for user", async () =>{
            let BNBal = await globeContract.balanceOf(walletSigner._address);
            expect(BNBal).to.be.equals(BigNumber.from("0x0"));
        });
    
        it("Should be able to be configured correctly", async () => {
            expect(await controllerContract.globes(assetAddr)).to.be.equals(snowglobeAddr);
            expect(await controllerContract.strategies(assetAddr)).to.be.equals(strategyAddr);
        });
    
        it("Should be able to deposit/withdraw money into globe", async () => {
            await assetContract.approve(snowglobeAddr,"2500000000000000000000000000");
            let balBefore = await assetContract.connect(walletSigner).balanceOf(snowglobeAddr);
            await globeContract.connect(walletSigner).depositAll();
            
            let userBal = await assetContract.connect(walletSigner).balanceOf(walletAddr);
            expect(userBal).to.be.equals(BigNumber.from("0x0"));
    
            let balAfter = await assetContract.connect(walletSigner).balanceOf(snowglobeAddr);
            expect(balBefore).to.be.lt(balAfter);
    
            await globeContract.connect(walletSigner).withdrawAll();
            
            userBal = await assetContract.connect(walletSigner).balanceOf(walletAddr);
            expect(userBal).to.be.gt(BigNumber.from("0x0"));
        });
    
        it("Harvests should make some money!", async () => {
            let amt = await assetContract.connect(walletSigner).balanceOf(walletAddr);
            await assetContract.connect(walletSigner).approve(snowglobeAddr,"2500000000000000000000000000");
            await globeContract.connect(walletSigner).depositAll();
            await globeContract.connect(walletSigner).earn();
            await increaseTime(60 * 60 * 24 * 15);
    
            let initialBalance = await strategyContract.balanceOf();
    
            await strategyContract.connect(walletSigner).harvest();
            let newBalance = await strategyContract.balanceOf();
            expect(newBalance).to.be.gt(initialBalance);
        });

        it("Strategy loaded with initial balance", async () =>{
            strategyBalance = await strategyContract.balanceOf();
            expect(strategyBalance).to.not.be.equals(BigNumber.from("0x0"));
        });
    
        it("Users should earn some money!", async () => {
            await overwriteTokenAmount(assetAddr,walletAddr,txnAmt);
    
            let amt = await assetContract.connect(walletSigner).balanceOf(walletAddr);
            await assetContract.connect(walletSigner).approve(snowglobeAddr,amt);
            await globeContract.connect(walletSigner).deposit(amt);
            await globeContract.connect(walletSigner).earn();
            await increaseTime(60 * 60 * 24 * 15);
            await strategyContract.connect(walletSigner).harvest();
            console.log("Harvest successful");
            await globeContract.connect(walletSigner).withdrawAll();
            let newAmt = await assetContract.connect(walletSigner).balanceOf(walletAddr);
    
            expect(amt.mul(2)).to.be.lt(newAmt);
            newAmt = newAmt - amt.mul(2);
            console.log("The user just made "+newAmt+" in two weeks!");
        });
    
    });
    
}

module.exports = {doGenericTest};