// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RoleToken is ERC20, Ownable {
    bool public contractEnabled = true;

    enum Role { NONE, ADMIN, PRIMARY_GROUP_HEAD, SECONDARY_GROUP_HEAD, REGULAR_MEMBER }
    mapping(address => Role) private roles;

    struct Member {
        address memberAddress;
        string name;
        string memberType;
        string status; // benign, suspicious, malicious
        uint256 lastStatusUpdate; // Timestamp of the last status update
        Role role;
    }

    mapping(string => Member[]) public localResourceTable; // Maps type to their regular members and secondary group heads
    Member[] public globalResourceTable; // List of all primary heads
    mapping(string => Member) public typeSecondaryHead; // Maps type to their secondary group heads
    mapping(string => address) public typePrimaryHead; // Stores the address of the primary head for each type
    mapping(address => Member) public members; // keep all members' information

    event RoleAssigned(address indexed memberAddress, Role role, string memberType);

    constructor(address initialAdmin) ERC20("RoleToken", "RTK") Ownable(initialAdmin) {
        _mint(initialAdmin, 10000000 * 10 ** decimals());
        transferOwnership(initialAdmin);
        roles[initialAdmin] = Role.ADMIN;
    }

    modifier onlyAdmin() {
        require(roles[msg.sender] == Role.ADMIN, "Access denied: Not an Admin - RoleToken");
        _;
    }

    modifier onlyPrimaryGroupHeadOrAdmin() {
        require(roles[msg.sender] == Role.ADMIN || roles[msg.sender] == Role.PRIMARY_GROUP_HEAD, "Access denied: Not an Admin or Primary Group Head");
        _;
    }

    function mint(address to, uint256 amount) public onlyPrimaryGroupHeadOrAdmin {
        require(contractEnabled, "Contract is disabled");
        _mint(to, amount);
    }

    function assignAdminRole(address deployer, address contractAddress) public onlyAdmin {
        require(roles[deployer] == Role.ADMIN, "Creator is not admin");
        roles[contractAddress] = Role.ADMIN;
        mint(contractAddress, 10000000 * 10 ** decimals());
    }

    function disableContract() public onlyAdmin {
        require(contractEnabled, "Contract is already disabled");
        contractEnabled = false;
    }

    function enableContract() public onlyAdmin {
        require(!contractEnabled, "Contract is already enabled");
        contractEnabled = true;
    }

    function assignRole(address _memberAddress, string memory _name, string memory _memberType) external {
        require(roles[_memberAddress] == Role(0), "Member already has a role");

        if (typePrimaryHead[_memberType] == address(0)) {
            // If no primary head exists for this type, assign as PRIMARY_GROUP_HEAD
            roles[_memberAddress] = Role.PRIMARY_GROUP_HEAD;
            Member memory newPrimaryHead = Member(_memberAddress, _name, _memberType, "BENIGN", block.timestamp, Role.PRIMARY_GROUP_HEAD);
            globalResourceTable.push(newPrimaryHead); // Add to global resource table
            typePrimaryHead[_memberType] = _memberAddress; // Store the primary head's address for this type
            mint(_memberAddress, 1000000 * 10 ** decimals()); // Mint tokens for PRIMARY_GROUP_HEAD
            members[_memberAddress] = newPrimaryHead; // Update members mapping
            emit RoleAssigned(_memberAddress, Role.PRIMARY_GROUP_HEAD, _memberType);
        }
        else if (typeSecondaryHead[_memberType].memberAddress == address(0)) {
            // Assign as SECONDARY_GROUP_HEAD if no secondary group heads exist for this type
            roles[_memberAddress] = Role.SECONDARY_GROUP_HEAD;
            Member memory newSecondaryHead = Member(_memberAddress, _name, _memberType, "BENIGN", block.timestamp, Role.SECONDARY_GROUP_HEAD);
            localResourceTable[_memberType].push(newSecondaryHead); // Add to local resource table
            typeSecondaryHead[_memberType] = newSecondaryHead; // Set to secondary group heads mapping
            mint(_memberAddress, 500000 * 10 ** decimals()); // Mint tokens for SECONDARY_GROUP_HEAD
            members[_memberAddress] = newSecondaryHead; // Update members mapping
            emit RoleAssigned(_memberAddress, Role.SECONDARY_GROUP_HEAD, _memberType);
        } else {
            // Otherwise, assign as REGULAR_MEMBER under the existing primary head
            roles[_memberAddress] = Role.REGULAR_MEMBER;
            Member memory newMember = Member(_memberAddress, _name, _memberType, "BENIGN", block.timestamp, Role.REGULAR_MEMBER);
            localResourceTable[_memberType].push(newMember); // Add to local resource table
            mint(_memberAddress, 100000 * 10 ** decimals()); // Mint tokens for REGULAR_MEMBER
            members[_memberAddress] = newMember; // Update members mapping
            emit RoleAssigned(_memberAddress, Role.REGULAR_MEMBER, _memberType);
        }
    }

    function swapRole(address account1, address account2) external onlyAdmin {
        require(roles[account1] != Role.NONE && roles[account2] != Role.NONE, "Both accounts must have roles");
        require(roles[account1] != roles[account2], "Accounts must have different roles");

        // Retrieve the current roles and member types
        Role role1 = roles[account1];
        Role role2 = roles[account2];
        string memory memberType1 = members[account1].memberType;
        string memory memberType2 = members[account2].memberType;

        // Ensure both accounts are in the same member type
        require(keccak256(bytes(memberType1)) == keccak256(bytes(memberType2)), "Accounts must be in the same member type");

        // Remove account1's role
        removeRoleFromMappings(account1, memberType1);

        // Remove account2's role
        removeRoleFromMappings(account2, memberType2);

        // Swap roles
        roles[account1] = role2;
        roles[account2] = role1;

        // Update account1's and account2's member information
        members[account1].role = role2;
        members[account2].role = role1;

        // Add account1's new role
        assignRoleToMappings(account1, memberType2, role2);

        // Add account2's new role
        assignRoleToMappings(account2, memberType1, role1);

        emit RoleAssigned(account1, role2, memberType2);
        emit RoleAssigned(account2, role1, memberType1);
    }

    function removeRoleFromMappings(address account, string memory memberType) internal {
        Role role = roles[account];
        if (role == Role.PRIMARY_GROUP_HEAD) {
            // Remove from global resource table and typePrimaryHead
            for (uint256 i = 0; i < globalResourceTable.length; i++) {
                if (globalResourceTable[i].memberAddress == account) {
                    globalResourceTable[i] = globalResourceTable[globalResourceTable.length - 1];
                    globalResourceTable.pop();
                    break;
                }
            }
            if (typePrimaryHead[memberType] == account) {
                delete typePrimaryHead[memberType];
            }
        } else if (role == Role.SECONDARY_GROUP_HEAD) {
            if (typeSecondaryHead[memberType].memberAddress == account) {
                delete typeSecondaryHead[memberType];
            }

            // Remove from local resource table
            for (uint256 i = 0; i < localResourceTable[memberType].length; i++) {
                if (localResourceTable[memberType][i].memberAddress == account) {
                    localResourceTable[memberType][i] = localResourceTable[memberType][localResourceTable[memberType].length - 1];
                    localResourceTable[memberType].pop();
                    break;
                }
            }
        } else if (role == Role.REGULAR_MEMBER) {
            for (uint256 i = 0; i < localResourceTable[memberType].length; i++) {
                if (localResourceTable[memberType][i].memberAddress == account) {
                    localResourceTable[memberType][i] = localResourceTable[memberType][localResourceTable[memberType].length - 1];
                    localResourceTable[memberType].pop();
                    break;
                }
            }
        }
        delete roles[account];
    }

    function assignRoleToMappings(address account, string memory memberType, Role role) internal {
        if (role == Role.PRIMARY_GROUP_HEAD) {
            globalResourceTable.push(Member(account, members[account].name, memberType, members[account].status, members[account].lastStatusUpdate, role));
            typePrimaryHead[memberType] = account;
        } else if (role == Role.SECONDARY_GROUP_HEAD) {
            localResourceTable[memberType].push(Member(account, members[account].name, memberType, members[account].status, members[account].lastStatusUpdate, role));
            typeSecondaryHead[memberType] = Member(account, members[account].name, memberType, members[account].status, members[account].lastStatusUpdate, role);
        } else if (role == Role.REGULAR_MEMBER) {
            localResourceTable[memberType].push(Member(account, members[account].name, memberType, members[account].status, members[account].lastStatusUpdate, role));
        }
    }

    // Revoke roles and manage promotion logic for primary and secondary group heads
    function revokeRole(address account) external onlyAdmin {
        Role revokedRole = roles[account];
        string memory memberType = members[account].memberType;

        require(revokedRole == Role.PRIMARY_GROUP_HEAD || revokedRole == Role.SECONDARY_GROUP_HEAD || revokedRole == Role.REGULAR_MEMBER, "Account does not have a role");

        if (revokedRole == Role.PRIMARY_GROUP_HEAD) {
            _handlePrimaryHeadRevocation(memberType, account);
        } else if (revokedRole == Role.SECONDARY_GROUP_HEAD) {
            _handleSecondaryHeadRevocation(memberType, account);
        } else if (revokedRole == Role.REGULAR_MEMBER) {
            _removeFromLocalResourceTable(memberType, account);
        }

        roles[account] = Role.NONE;
        delete members[account]; // Remove from members
        _burn(account, balanceOf(account));
    }

    function _handlePrimaryHeadRevocation(string memory memberType, address account) internal {
        // Remove from globalResourceTable and typePrimaryHead
        _removeFromGlobalResourceTable(account);
        delete typePrimaryHead[memberType];

        // Promote Secondary Group Head to Primary Group Head if exists
        if (typeSecondaryHead[memberType].memberAddress != address(0)) {
            address secondaryHeadAddr = typeSecondaryHead[memberType].memberAddress;
            delete typeSecondaryHead[memberType];
            _promoteToPrimaryGroupHead(memberType, secondaryHeadAddr);

            // After promoting the Secondary Head to Primary, promote the Regular Member with highest token balance to Secondary Group Head
            address highestTokenMember = _findMemberWithHighestTokens(memberType);
            if (highestTokenMember != address(0)) {
                _promoteToSecondaryGroupHead(memberType, highestTokenMember);
            }
        }
    }

    function _handleSecondaryHeadRevocation(string memory memberType, address account) internal {
        // Remove from localResourceTable and typeSecondaryHead
        _removeFromLocalResourceTable(memberType, account);
        delete typeSecondaryHead[memberType];

        // Promote the Regular Member with the highest token balance to Secondary Group Head
        address highestTokenMember = _findMemberWithHighestTokens(memberType);
        if (highestTokenMember != address(0)) {
            _promoteToSecondaryGroupHead(memberType, highestTokenMember);
        }
    }

    // Promote Regular Member with highest token balance to Secondary Group Head
    function _promoteToSecondaryGroupHead(string memory memberType, address account) internal {
        roles[account] = Role.SECONDARY_GROUP_HEAD;
        _editFromLocalResourceTable(memberType, account, Role.SECONDARY_GROUP_HEAD); // Remove secondary head from local table
        members[account].role = Role.SECONDARY_GROUP_HEAD;
        typeSecondaryHead[memberType] = members[account]; // Set as secondary head for the resourceType
    }

    // Find the regular member with the highest token balance in the given resource type
    function _findMemberWithHighestTokens(string memory memberType) internal view returns (address) {
        uint256 highestBalance = 0;
        address highestMember = address(0);

        Member[] memory membersInResource = localResourceTable[memberType];

        for (uint256 i = 0; i < membersInResource.length; i++) {
            address memberAddr = membersInResource[i].memberAddress;
            if (roles[memberAddr] == Role.REGULAR_MEMBER) {
                uint256 balance = balanceOf(memberAddr);

                if (balance > highestBalance) {
                    highestBalance = balance;
                    highestMember = memberAddr;
                }
            }
        }
        return highestMember;
    }

    // Remove from global resource table (for Primary Group Head)
    function _removeFromGlobalResourceTable(address account) internal {
        for (uint256 i = 0; i < globalResourceTable.length; i++) {
            if (globalResourceTable[i].memberAddress == account) {
                globalResourceTable[i] = globalResourceTable[globalResourceTable.length - 1];
                globalResourceTable.pop();
                break;
            }
        }
    }

    // Promote Secondary to Primary Group Head
    function _promoteToPrimaryGroupHead(string memory memberType, address account) internal {
        roles[account] = Role.PRIMARY_GROUP_HEAD;
        members[account].role = Role.PRIMARY_GROUP_HEAD;
        _removeFromLocalResourceTable(memberType, account); // Remove secondary head from local table
        globalResourceTable.push(members[account]); // Add to global resource table
        typePrimaryHead[memberType] = account; // Set as primary head for the memberType
    }

    // Remove from local resource table (for Secondary Group Head or Regular Members)
    function _removeFromLocalResourceTable(string memory memberType, address account) internal {
        Member[] storage membersInResource = localResourceTable[memberType];
        
        for (uint256 i = 0; i < membersInResource.length; i++) {
            if (membersInResource[i].memberAddress == account) {
                membersInResource[i] = membersInResource[membersInResource.length - 1];
                membersInResource.pop();
                break;
            }
        }
    }

    // Remove from local resource table (for Secondary Group Head or Regular Members)
    function _editFromLocalResourceTable(string memory memberType, address account, Role role) internal {
        Member[] storage membersInResource = localResourceTable[memberType];
        
        for (uint256 i = 0; i < membersInResource.length; i++) {
            if (membersInResource[i].memberAddress == account) {
                membersInResource[i].role = role;
            }
        }
    }

    function getRole(address account) public view returns (Role) {
        return roles[account];
    }

    function getLocalResourceTable(string memory memberType) external view returns (Member[] memory) {
        return localResourceTable[memberType];
    }

    function getGlobalResourceTable() external view onlyPrimaryGroupHeadOrAdmin returns (Member[] memory) {
        return globalResourceTable;
    }

    // Function to get the Member struct for a specific address
    function getMember(address _memberAddress) public view returns (Member memory) {
        return members[_memberAddress];
    }

    function updateMemberStatus(address _memberAddress, string memory _newStatus) external onlyAdmin {
        members[_memberAddress].status = _newStatus;
        members[_memberAddress].lastStatusUpdate = block.timestamp;
    }

    function penalizeMember(address _memberAddress, uint256 _amount) external onlyAdmin {
        _burn(_memberAddress, _amount * 10 ** decimals());
    }

    function rewardMember(address _memberAddress, uint256 _amount) external onlyAdmin {
        _mint(_memberAddress, _amount * 10 ** decimals());
    }

    // Function to get the address of the primary head for a regular member
    function getPrimaryHeadAddress(address memberAddress) public view returns (address) {
        Member memory member = members[memberAddress];
    
        // Ensure the provided address is either a regular member or a secondary group head
        require(member.role == Role.REGULAR_MEMBER || member.role == Role.SECONDARY_GROUP_HEAD, "Address does not have a valid role");

        // Retrieve the primary head associated with the member's type
        address primaryHead = typePrimaryHead[member.memberType];
        
        return primaryHead;
    }
}