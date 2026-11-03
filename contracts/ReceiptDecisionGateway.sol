// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "./original/RoleBasedAccessControl.sol";

/// New prototype adapter. Not the inherited MERIT AccessControlContract or Judge.
contract ReceiptDecisionGateway {
    RoleBasedAccessControl public immutable roles;
    address public immutable target;
    address public immutable admin;
    bool public enabled = true;
    uint256 public constant requestLimit = 5;
    uint256 public constant windowSeconds = 10;
    uint256 public constant blockSeconds = 8;
    struct Window { uint256 started; uint256 count; uint256 blockedUntil; }
    mapping(address => Window) public windows;
    event Decision(bytes32 indexed requestId, address indexed requester, address indexed target,
                   bool allowed, string reason, uint256 count, uint256 blockedUntil);
    event EnabledChanged(bool enabled);
    constructor(address roleBased, address sensorOwner) {
        roles = RoleBasedAccessControl(roleBased); target = sensorOwner; admin = msg.sender;
    }
    function setEnabled(bool value) external {
        require(msg.sender == admin, "Only demo admin"); enabled = value; emit EnabledChanged(value);
    }
    function requestRead(bytes32 requestId) external {
        require(enabled, "Prototype gateway disabled");
        Window storage w = windows[msg.sender];
        if (block.timestamp < w.blockedUntil) {
            emit Decision(requestId, msg.sender, target, false, "TEMPORARILY_BLOCKED", w.count, w.blockedUntil);
            return;
        }
        if (w.started == 0 || block.timestamp >= w.started + windowSeconds || w.blockedUntil != 0) {
            w.started = block.timestamp; w.count = 0; w.blockedUntil = 0;
        }
        w.count++;
        if (w.count > requestLimit) {
            w.blockedUntil = block.timestamp + blockSeconds;
            emit Decision(requestId, msg.sender, target, false, "EXCESSIVE_REQUESTS", w.count, w.blockedUntil);
            return;
        }
        bool allowed = roles.getRole(msg.sender) != RoleToken.Role.NONE &&
                       roles.areSameOrGlobalMembers(msg.sender, target);
        emit Decision(requestId, msg.sender, target, allowed,
                      allowed ? "APPROVED_ROLE_POLICY" : "NO_ROLE_POLICY_PERMISSION", w.count, 0);
    }
}
