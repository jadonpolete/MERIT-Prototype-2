// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RoleToken.sol";  // Import RoleToken for role management

contract RoleBasedAccessControl {
    RoleToken public roleTokenContract;  // Use RoleToken for role management functions
    address public admin;

    constructor(address _roleTokenContract, address _admin) {
        roleTokenContract = RoleToken(_roleTokenContract);  // Initialize with RoleToken contract
        admin = _admin;
    }

    modifier onlyAdmin() {
        require(roleTokenContract.getRole(msg.sender) == RoleToken.Role.ADMIN, "Access denied: Not an Admin - RoleBasedAccessControl");
        _;
    }

    modifier onlyPrimaryGroupHeadOrAdmin() {
        require(roleTokenContract.getRole(msg.sender) == RoleToken.Role.ADMIN || 
        (roleTokenContract.getRole(msg.sender) == RoleToken.Role.PRIMARY_GROUP_HEAD), "Access denied: Not an Admin or Primary Group Head");
        _;
    }

    modifier onlyMembers() {
        require(roleTokenContract.getRole(msg.sender) != RoleToken.Role.NONE, "Access denied: Not a Member");
        _;
    }

    function printBalances() external view returns (address, uint256) {
        return (msg.sender, roleTokenContract.balanceOf(msg.sender));
    }

    function requireRole(address account, RoleToken.Role role) public view {
        require(roleTokenContract.getRole(account) == role, "Access denied: incorrect role");
    }

    function assignRole(address _memberAddress, string memory _name, string memory _memberType) public onlyAdmin {
        roleTokenContract.assignRole(_memberAddress, _name, _memberType);
    }

    // Function to swap roles between two addresses
    function swapRole(address _address1, address _address2) public onlyPrimaryGroupHeadOrAdmin {
        roleTokenContract.swapRole(_address1, _address2);
    }

    function revokeRole(address account) public onlyPrimaryGroupHeadOrAdmin {
        roleTokenContract.revokeRole(account);
    }

    function getRole(address account) public view onlyMembers returns (RoleToken.Role) {
        return roleTokenContract.getRole(account);
    }

    function getMember(address account) public view onlyMembers returns (RoleToken.Member memory) {
        return roleTokenContract.getMember(account);
    }

    // Function to check if two accounts have the same member type or are both Primary Group Heads (PGHs)
    function areSameOrGlobalMembers(address account1, address account2) public view onlyMembers returns (bool) {
        // Fetch roles for the accounts
        RoleToken.Role role1 = roleTokenContract.getRole(account1);
        RoleToken.Role role2 = roleTokenContract.getRole(account2);
        
        // Check if both accounts are Primary Group Heads (PGHs)
        bool bothGlobal = (role1 == RoleToken.Role.PRIMARY_GROUP_HEAD) && (role2 == RoleToken.Role.PRIMARY_GROUP_HEAD);
        
        // Fetch member types for both accounts
        string memory memberType1 = roleTokenContract.getMember(account1).memberType;
        string memory memberType2 = roleTokenContract.getMember(account2).memberType;
        
        // Check if both member types are the same
        bool sameMemberType = keccak256(abi.encodePacked(memberType1)) == keccak256(abi.encodePacked(memberType2));
        
        return bothGlobal || sameMemberType;
    }

    function getLocalResourceTable(string memory memberType) public view onlyMembers returns (RoleToken.Member[] memory) {
        return roleTokenContract.getLocalResourceTable(memberType);
    }

    function getGlobalResourceTable() public view onlyPrimaryGroupHeadOrAdmin returns (RoleToken.Member[] memory) {
        return roleTokenContract.getGlobalResourceTable();
    }

    // New function to call getPrimaryHeadAddress from RoleToken
    function getPrimaryHeadAddress(address regularMember) public view onlyMembers returns (address) {
        return roleTokenContract.getPrimaryHeadAddress(regularMember);
    }

    // Forward the updateMemberStatus call to RoleToken contract
    function updateMemberStatus(address _memberAddress, string memory _newStatus) external onlyAdmin {
        roleTokenContract.updateMemberStatus(_memberAddress, _newStatus);
    }

    // Forward the penalizeMember call to RoleToken contract
    function penalizeMember(address _memberAddress, uint256 _amount) external onlyAdmin {
        roleTokenContract.penalizeMember(_memberAddress, _amount);
    }

    // Forward the rewardMember call to RoleToken contract
    function rewardMember(address _memberAddress, uint256 _amount) external onlyAdmin {
        roleTokenContract.rewardMember(_memberAddress, _amount);
    }
}
