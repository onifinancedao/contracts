// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract OFP is ERC721Enumerable {
    //variables
    
    uint public maxTotalSupply = 20_000;

    string public url;

    address public core;
    address public timelock;
    address public dev;

    bool public initialized;

    string Unautorized_Error = "unautorized";

    /// @notice A record of each accounts delegate
    mapping (address => address) public delegates;

    /// @notice A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping (address => uint) public numCheckpoints;

    //structs
    struct TokenWithData {
        uint Id;
        string Uri;
        address Owner;
    }

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint fromBlock;
        uint votes;
    }
    
    //events
    
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);
    
    modifier onlyCore() {
        require(msg.sender == core, Unautorized_Error);
        _;
    }

    //constructor
    constructor(
        string memory url_,
        address dev_
    ) 
    ERC721(
        "Onifinance Project",
        "OFP"
        )
    {   
        url = url_;
        dev = dev_;
    }

    function mintTokens(address to, uint amount) internal {
        for(uint i = 0; i < amount; i++){
            _mint(to, totalSupply() + 1);
        }
    }
   
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        _moveDelegates(delegates[from], delegates[to], 1);
    }

    function uint2str(uint256 _i)  internal pure returns (string memory str) {
        
        if (_i == 0) {return "0";}
        uint256 j = _i;
        uint256 length;
        while (j != 0){length++;j /= 10;}
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {bstr[--k] = bytes1(uint8(48 + j % 10));j /= 10;}
        str = string(bstr);
        
    }
    
    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint delegatorBalance = balanceOf(delegator);
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint srcRepNum = numCheckpoints[srcRep];
                uint srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint dstRepNum = numCheckpoints[dstRep];
                uint dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(address delegatee, uint nCheckpoints, uint oldVotes, uint newVotes) internal {
      uint blockNumber = block.number;

      if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
          checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
      } else {
          checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
          numCheckpoints[delegatee] = nCheckpoints + 1;
      }

      emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }
    
    function attributes() internal view returns (string memory) {
        if(Core(core).emergencyActive()){
            return '"attributes":[{"trait_type":"Votes","value":1},{"trait_type":"OFI","max_value":5000,"value":0}]';
        }
        return '"attributes":[{"trait_type":"Votes","value":1},{"trait_type":"OFI","max_value":5000,"value":5000}]';
    }

   
    //view functions
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory uri) {
        
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": "OFP #', uint2str(tokenId), '",',
                '"description": "Join the creation of [Onifinance DAO](https://project.onifinance.org) and claim OFI tokens.",',
                '"image": "', string(abi.encodePacked(url, "/", uint2str(tokenId), "/token.png")), '",',
                attributes(),
            '}'
        );
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
         
    }
    
    function tokensOfOwner(address owner) external view returns(uint[] memory){
        uint balance = balanceOf(owner);
        if(balance == 0){
            return new uint[](0);
        }else{
            uint[] memory result = new uint[](balance);
            for (uint index = 0; index < balance; index++){
                result[index] = tokenOfOwnerByIndex(owner, index);
            }
            return result;
        }

    }

    function getTokenWithData(uint tokenId) external view returns (TokenWithData memory data){
        return TokenWithData(tokenId, tokenURI(tokenId), ownerOf(tokenId));
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint) {
        uint nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber) public view returns (uint) {
        require(blockNumber < block.number, "OFP::getPriorVotes: not yet determined");

        uint nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }
    
    //user functions
    
    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(msg.sender, delegatee);
    }

    //restricted functions
    function initialize(address core_, address timelock_) public {
        require(msg.sender == dev, Unautorized_Error);
        require(!initialized, "initialized");
        initialized = true;
        core = core_;
        timelock = timelock_;
        mintTokens(dev, 10);
    }

    function mint(address to, uint amount) external onlyCore {
        mintTokens(to, amount);
    }

    function burn(uint token) external onlyCore {
        _burn(token);
    }

    function changeUrl(string memory url_ ) external {
        require(msg.sender == timelock, Unautorized_Error);
        url = url_;
        emit BatchMetadataUpdate(1, 20000);
    }
    
    function update() external {
        require(msg.sender == core || msg.sender == timelock, Unautorized_Error);
        emit BatchMetadataUpdate(1, 20000);
    }
    
}

interface Core {
    function emergencyActive() view external returns(bool);
}