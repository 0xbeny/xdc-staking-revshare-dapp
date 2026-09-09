// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {FeeSplitter} from "../../src/adapters/FeeSplitter.sol";
import {PushAdapter} from "../../src/adapters/PushAdapter.sol";
import {RevenueAdapterBase} from "../../src/adapters/RevenueAdapterBase.sol";
import {ZodiacFeeModule} from "../../src/adapters/ZodiacFeeModule.sol";
import {Base} from "../Base.t.sol";
import {MockSafe} from "../mocks/MockSafe.sol";

contract AdaptersTest is Base {
    function setUp() public override {
        super.setUp();
        vm.warp(_epochStart(_currentEpoch() + 1));
        _lock(alice, 100_000 ether, 52 weeks);
        _nextEpoch();
    }

    /*//////////////////////////////////////////////////////////////
                              MODE A — PUSH
    //////////////////////////////////////////////////////////////*/

    function test_pushAdapterForwardsWholeAmount() public {
        vm.startPrank(dapp);
        usdc.approve(address(pusher), 1000e6);
        pusher.commitRevenue(address(usdc), 1000e6);
        vm.stopPrank();

        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 1000e6);
        assertEq(usdc.balanceOf(address(pusher)), 0, "adapters never accumulate a balance");
    }

    function test_pushAdapterIsRestrictedToTheRegisteredSource() public {
        vm.startPrank(alice);
        usdc.approve(address(pusher), 1000e6);
        vm.expectRevert(PushAdapter.NotSource.selector);
        pusher.commitRevenue(address(usdc), 1000e6);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            MODE B — SPLITTER
    //////////////////////////////////////////////////////////////*/

    function test_splitterSplitsByImmutableBpsAndEmptiesItself() public {
        deal(address(usdc), address(splitter), 10_000e6);

        uint256 dappBefore = usdc.balanceOf(dappTreasury);
        splitter.skim(address(usdc)); // permissionless

        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 3000e6, "30% committed");
        assertEq(usdc.balanceOf(dappTreasury) - dappBefore, 7000e6, "70% to the dApp");
        assertEq(usdc.balanceOf(address(splitter)), 0, "zero balance after sweep");
    }

    function test_doubleSkimMovesZero() public {
        deal(address(usdc), address(splitter), 10_000e6);
        splitter.skim(address(usdc));
        vm.expectRevert(RevenueAdapterBase.NothingToSkim.selector);
        splitter.skim(address(usdc));
    }

    function test_adapterRejectsUnsupportedTokens() public {
        vm.expectRevert(abi.encodeWithSelector(RevenueAdapterBase.UnsupportedToken.selector, address(0xBEEF)));
        splitter.skim(address(0xBEEF));
    }

    function test_adapterTermsAreImmutable() public {
        assertEq(splitter.COMMITTED_BPS(), 3000);
        assertEq(splitter.DISTRIBUTOR(), address(distributor));
        assertEq(splitter.DAPP_TREASURY(), dappTreasury);
        assertEq(splitter.SOURCE(), dapp);

        string[3] memory sigs = ["setCommittedBps(uint16)", "setDistributor(address)", "setDappTreasury(address)"];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(splitter).call(abi.encodeWithSignature(sigs[i], uint256(1)));
            assertFalse(ok, "adapters have no setters");
        }
    }

    function test_adapterConstructorValidatesTerms() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.expectRevert(RevenueAdapterBase.InvalidBps.selector);
        new FeeSplitter(dapp, address(distributor), dappTreasury, 0, tokens);
        vm.expectRevert(RevenueAdapterBase.InvalidBps.selector);
        new FeeSplitter(dapp, address(distributor), dappTreasury, 10_001, tokens);

        address[] memory none = new address[](0);
        vm.expectRevert(RevenueAdapterBase.NoTokens.selector);
        new FeeSplitter(dapp, address(distributor), dappTreasury, 3000, none);

        vm.expectRevert(RevenueAdapterBase.ZeroAddress.selector);
        new FeeSplitter(address(0), address(distributor), dappTreasury, 3000, tokens);
    }

    /*//////////////////////////////////////////////////////////////
                     MODE B2 / B3 — DEDICATED FEE SAFE
    //////////////////////////////////////////////////////////////*/

    function test_pullAdapterSweepsTheFeeSafeToZero() public {
        deal(address(usdc), address(feeSafe), 10_000e6);
        uint256 dappBefore = usdc.balanceOf(dappTreasury);

        puller.skim(address(usdc));

        assertEq(usdc.balanceOf(address(feeSafe)), 0, "B2 invariant: fee Safe balance == 0");
        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 2500e6);
        assertEq(usdc.balanceOf(dappTreasury) - dappBefore, 7500e6);
        assertEq(usdc.balanceOf(address(puller)), 0);
    }

    function test_zodiacModuleSweepsTheFeeSafeToZero() public {
        deal(address(usdc), address(feeSafeB3), 10_000e6);
        uint256 dappBefore = usdc.balanceOf(dappTreasury);

        zodiac.skim(address(usdc));

        assertEq(usdc.balanceOf(address(feeSafeB3)), 0, "B3 invariant: fee Safe balance == 0");
        assertEq(distributor.epochRevenue(address(usdc), _currentEpoch()), 2500e6);
        assertEq(usdc.balanceOf(dappTreasury) - dappBefore, 7500e6);
        assertEq(usdc.balanceOf(address(zodiac)), 0);
    }

    /// @dev The module's power comes entirely from the Safe having enabled it.
    function test_zodiacModuleFailsIfNotEnabledOnTheSafe() public {
        MockSafe otherSafe = new MockSafe();
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        ZodiacFeeModule rogue =
            new ZodiacFeeModule(dapp, address(distributor), dappTreasury, 2500, tokens, address(otherSafe));

        deal(address(usdc), address(otherSafe), 1000e6);
        vm.expectRevert(MockSafe.NotAModule.selector);
        rogue.skim(address(usdc));
    }

    function test_doubleSweepOfAFeeSafeMovesZero() public {
        deal(address(usdc), address(feeSafe), 10_000e6);
        puller.skim(address(usdc));
        vm.expectRevert(RevenueAdapterBase.NothingToSkim.selector);
        puller.skim(address(usdc));
    }

    function test_adapterExposesItsFixedTokenSet() public view {
        address[] memory supported = splitter.supportedTokens();
        assertEq(supported.length, 2);
        assertEq(supported[0], address(wxdc));
        assertEq(supported[1], address(usdc));
        assertTrue(splitter.isSupported(address(usdc)));
        assertFalse(splitter.isSupported(address(0xBEEF)));
    }

    function test_adapterConstructorDeduplicatesTokens() public {
        address[] memory dup = new address[](3);
        dup[0] = address(usdc);
        dup[1] = address(usdc);
        dup[2] = address(wxdc);
        FeeSplitter s = new FeeSplitter(dapp, address(distributor), dappTreasury, 3000, dup);
        assertEq(s.supportedTokens().length, 2);
    }
}
