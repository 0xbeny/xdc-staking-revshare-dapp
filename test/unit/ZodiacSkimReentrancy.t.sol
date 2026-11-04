// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ZodiacFeeModule} from "../../src/adapters/ZodiacFeeModule.sol";
import {Base} from "../Base.t.sol";
import {MockSafe} from "../mocks/MockSafe.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Token with a transfer hook, used to try every reentrancy path into `ZodiacFeeModule.skim`
///         while the fee Safe is mid-sweep (the window Slither's `reentrancy-balance` points at).
contract HookToken is ERC20 {
    enum Mode {
        None,
        ReenterSkim,
        DonateToSafe,
        DonateToModule
    }

    Mode public mode;
    address public module;
    address public safe;
    bool public reentryReverted;
    bytes4 public reentryError;
    bool private _inHook;

    constructor() ERC20("Hook", "HOOK") {}

    function configure(Mode mode_, address module_, address safe_) external {
        mode = mode_;
        module = module_;
        safe = safe_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (_inHook || mode == Mode.None || from != safe || to != module) {
            return;
        }
        _inHook = true;
        if (mode == Mode.ReenterSkim) {
            try ZodiacFeeModule(module).skim(address(this)) {}
            catch (bytes memory err) {
                reentryReverted = true;
                reentryError = bytes4(err);
            }
        } else if (mode == Mode.DonateToSafe) {
            _mint(safe, 1);
        } else if (mode == Mode.DonateToModule) {
            _mint(module, 1);
        }
        _inHook = false;
    }
}

contract ZodiacSkimReentrancyTest is Base {
    HookToken internal hook;
    MockSafe internal safe;
    ZodiacFeeModule internal module;

    function setUp() public override {
        super.setUp();
        hook = new HookToken();
        safe = new MockSafe();
        address[] memory tokens = new address[](1);
        tokens[0] = address(hook);
        module = new ZodiacFeeModule(dapp, address(distributor), dappTreasury, 2500, tokens, address(safe));
        safe.enableModule(address(module));
        hook.mint(address(safe), 10_000e18);
    }

    /// @dev A callback token re-entering `skim` mid-sweep is stopped by the guard; the outer sweep
    ///      still completes with the exact split and the Safe ends at zero.
    function test_reentrantSkimIsBlockedAndOuterSweepIsExact() public {
        hook.configure(HookToken.Mode.ReenterSkim, address(module), address(safe));

        module.skim(address(hook));

        assertTrue(hook.reentryReverted(), "nested skim must revert");
        assertEq(hook.reentryError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector, "guard blocks it");
        assertEq(hook.balanceOf(address(safe)), 0, "fee Safe swept to zero");
        assertEq(hook.balanceOf(dappTreasury), 7500e18, "dApp share paid once");
        assertEq(module.pendingCommitted(address(hook)), 2500e18, "locker share held once, not twice");
        assertEq(hook.balanceOf(address(module)), 2500e18, "module holds exactly the held share");
    }

    /// @dev Tokens landing in the Safe during the sweep make the pre-call balance stale; the
    ///      post-call check rejects the sweep instead of using the stale value. Nothing moves.
    function test_staleSafeBalanceRevertsWholeSweep() public {
        hook.configure(HookToken.Mode.DonateToSafe, address(module), address(safe));

        vm.expectRevert(ZodiacFeeModule.SweepIncomplete.selector);
        module.skim(address(hook));

        assertEq(hook.balanceOf(address(safe)), 10_000e18, "Safe untouched after revert");
        assertEq(hook.balanceOf(dappTreasury), 0);
        assertEq(module.pendingCommitted(address(hook)), 0);
    }

    /// @dev Extra tokens credited to the module during the sweep also trip the exact-amount check.
    function test_extraReceivedRevertsWholeSweep() public {
        hook.configure(HookToken.Mode.DonateToModule, address(module), address(safe));

        vm.expectRevert(ZodiacFeeModule.SweepIncomplete.selector);
        module.skim(address(hook));

        assertEq(hook.balanceOf(address(safe)), 10_000e18, "Safe untouched after revert");
        assertEq(hook.balanceOf(address(module)), 0);
    }

    /// @dev Unused-return check for `EnumerableSet.add/remove` in `SystemAccess`: the `_has` guard
    ///      makes the set result redundant, so member count tracks grants exactly.
    function test_roleSetStaysInSyncWithGrantFlag() public {
        bytes32 role = keccak256("TRIAGE_ROLE");
        address target = address(distributor);
        uint256 n0 = access.getRoleMemberCount(target, role);
        vm.startPrank(timelock);
        access.grantRole(target, role, alice);
        access.grantRole(target, role, alice);
        assertEq(access.getRoleMemberCount(target, role), n0 + 1, "duplicate grant is a no-op");
        access.revokeRole(target, role, alice);
        access.revokeRole(target, role, alice);
        vm.stopPrank();
        assertEq(access.getRoleMemberCount(target, role), n0, "duplicate revoke is a no-op");
    }
}
